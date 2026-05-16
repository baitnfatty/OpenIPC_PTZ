"""
wf_compressed_uart.py - Decode UART from WaveForms Compressed Binary events.

The format (inferred from inspection):
- 4 bytes per event
- Bytes 0-1: uint16 LE packed DIO state after this transition
- Bytes 2-3: uint16 LE sample-count delta since the previous event
- (First delta is the offset from t=0, or pre-trigger window)

Equivalent to the Raw Events CSV but binary-packed, ~4-10x smaller files.

Usage:
    python wf_compressed_uart.py <input.bin> --samplerate 6250000 \
        --target BIT BAUD OUTFILE [--target ...]

Example:
    python wf_compressed_uart.py dwnclick.bin --samplerate 6250000 \
        --target 1 115200 dwn_click_b1.bin
"""
import sys
import os
import argparse
import struct


def parse_events(path, samplerate):
    """Read compressed-bin events. Yield (sample_idx, packed_state)."""
    with open(path, 'rb') as f:
        data = f.read()
    if len(data) % 4 != 0:
        print(f"WARNING: file size {len(data)} not multiple of 4", file=sys.stderr)
    n_events = len(data) // 4
    sample_idx = 0
    events = []
    for i in range(n_events):
        off = i * 4
        state = struct.unpack_from('<H', data, off)[0]
        delta = struct.unpack_from('<H', data, off + 2)[0]
        sample_idx += delta
        events.append((sample_idx, state))
    return events


def bit_transitions(events, bit):
    mask = 1 << bit
    prev = None
    for idx, d in events:
        cur = 1 if (d & mask) else 0
        if cur != prev:
            yield (idx, cur)
            prev = cur


def uart_decode(transitions, samplerate, baud):
    """8N1 LSB-first UART decode using transition list with sample indices.

    For each falling edge, sample the line at the center of each data bit using
    the rest of the transition timeline to determine line state at that exact
    sample index.
    """
    import bisect
    events = list(transitions)
    if not events:
        return []
    # Build sorted (sample_idx -> value) for state_at lookup
    idxs = [e[0] for e in events]
    vals = [e[1] for e in events]

    def state_at(sample_idx):
        i = bisect.bisect_right(idxs, sample_idx) - 1
        return vals[i] if i >= 0 else 1  # idle high before first event

    samples_per_bit = samplerate / baud
    bytes_out = []

    i = 0
    while i < len(events):
        t_sample, v = events[i]
        if v == 0:  # falling edge = start bit
            value = 0
            for bit_n in range(8):
                t = t_sample + (1.5 + bit_n) * samples_per_bit
                if state_at(t):
                    value |= (1 << bit_n)
            bytes_out.append(value)
            # Skip to end of byte
            t_end = t_sample + 10 * samples_per_bit
            while i < len(events) and events[i][0] < t_end:
                i += 1
            continue
        i += 1
    return bytes_out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="WaveForms compressed-bin events file")
    ap.add_argument("--samplerate", type=float, required=True,
                    help="capture sample rate in Hz (e.g., 6250000 for 6.25 MS/s)")
    ap.add_argument("--target", action="append", nargs=3,
                    metavar=("BIT", "BAUD", "OUTFILE"),
                    help="decode bit N at baud B to outfile")
    args = ap.parse_args()
    if not args.target:
        ap.error("need at least one --target")

    events = parse_events(args.input, args.samplerate)
    print(f"Source:      {args.input}")
    print(f"File size:   {os.path.getsize(args.input)} bytes")
    print(f"Events:      {len(events)}")
    if events:
        span_samples = events[-1][0] - events[0][0]
        print(f"Span:        {span_samples / args.samplerate:.3f} s ({span_samples} samples)")

    # Active bit summary
    print(f"\nActive bits:")
    for bit in range(16):
        mask = 1 << bit
        states = set()
        trans = 0
        prev = None
        for _, d in events:
            cur = 1 if (d & mask) else 0
            states.add(cur)
            if prev is not None and cur != prev:
                trans += 1
            prev = cur
        if len(states) > 1:
            print(f"  bit{bit}: {trans} transitions")

    print()
    for bit_s, baud_s, outfile in args.target:
        bit = int(bit_s)
        baud = int(baud_s)
        trans = list(bit_transitions(events, bit))
        bytes_out = uart_decode(trans, args.samplerate, baud)
        with open(outfile, 'wb') as f:
            f.write(bytes(bytes_out))
        preview = ' '.join(f'{b:02X}' for b in bytes_out[:30])
        print(f"  bit{bit} @ {baud} -> {outfile}: {len(bytes_out)} bytes")
        if bytes_out:
            print(f"    preview: {preview}")


if __name__ == "__main__":
    main()
