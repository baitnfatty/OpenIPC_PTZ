"""
wf_events_uart.py - Decode UART from a WaveForms "Raw Events" CSV.

The Raw Events format is much more compact than Raw Data / Acquisition.
Each row is a single transition event: (time_seconds, packed_data_int).
`packed_data_int` is the new state of all 16 DIO channels after the
transition.

This script:
- Reads the events file fully into memory (small)
- For each requested (bit, baud, outfile) triple, reconstructs that bit's
  time-series of transitions and software-decodes 8N1 UART.
- Writes one .bin file per target.

Usage:
    python wf_events_uart.py <events.csv> \
        --target BIT BAUD OUTFILE [--target ...]

Examples:
    # Decode AF UART pair (bits 0 and 1 at 115200)
    python wf_events_uart.py newacq0002.csv \
        --target 0 115200 ev_ch0.bin \
        --target 1 115200 ev_ch1.bin \
        --target 8 66666 ev_ch8.bin \
        --target 9 66666 ev_ch9.bin

    # Scan: try a bit at multiple bauds
    python wf_events_uart.py newacq0002.csv \
        --target 9 115200 ev_b9_115200.bin \
        --target 9 76800 ev_b9_76800.bin \
        --target 9 57600 ev_b9_57600.bin
"""
import sys
import os
import argparse
import csv


def parse_events(path):
    """Read events file, return (samplerate, list of (time_sec, data_int))."""
    samplerate = None
    events = []
    with open(path) as f:
        for line in f:
            line = line.rstrip()
            if line.startswith('#Sample rate:'):
                import re
                m = re.search(r'([\d.eE+-]+)\s*Hz', line)
                if m:
                    samplerate = float(m.group(1))
            elif line.startswith('Time'):
                break
        reader = csv.reader(f)
        for row in reader:
            if len(row) < 2: continue
            try:
                t = float(row[0])
                d = int(row[1])
                events.append((t, d))
            except ValueError:
                continue
    return samplerate, events


def bit_transitions(events, bit):
    """Yield (time_sec, value) for each transition on the given bit."""
    mask = 1 << bit
    prev = None
    for t, d in events:
        cur = 1 if (d & mask) else 0
        if cur != prev:
            yield (t, cur)
            prev = cur


def uart_decode_from_events(transitions, baud):
    """Software UART 8N1 LSB-first decode using transition list.

    For each falling edge (idle->start), sample the line state at the
    center of each subsequent bit using the next-transition timeline.
    """
    # Convert to a function: state_at(t) returns 0 or 1 at time t.
    # Easiest implementation: build a sorted list of (time, value) and
    # binary-search for each sample point.
    import bisect
    events = list(transitions)
    if not events:
        return []
    times = [e[0] for e in events]
    vals = [e[1] for e in events]

    def state_at(t):
        # Find the latest event with time <= t
        idx = bisect.bisect_right(times, t) - 1
        if idx < 0:
            return 1  # Assume idle high before first event
        return vals[idx]

    bit_period = 1.0 / baud
    bytes_out = []

    # Walk events looking for falling edges (start of UART frame)
    i = 0
    while i < len(events):
        t_edge, v = events[i]
        if v == 0:  # falling edge to 0 = start bit
            # Sample 8 data bits at center
            value = 0
            valid = True
            for bit_n in range(8):
                t_sample = t_edge + (1.5 + bit_n) * bit_period
                s = state_at(t_sample)
                if s:
                    value |= (1 << bit_n)
            # Stop bit center
            t_stop = t_edge + 9.5 * bit_period
            stop = state_at(t_stop)
            if stop == 1:  # valid frame
                bytes_out.append(value)
            else:
                # Frame error - still emit byte but flag could go here
                bytes_out.append(value)
            # Advance to end of stop bit
            t_end = t_edge + 10 * bit_period
            # Skip events that fall within this byte's window
            while i < len(events) and events[i][0] < t_end:
                i += 1
            continue
        i += 1
    return bytes_out


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="WaveForms Raw Events CSV")
    ap.add_argument("--target", action="append", nargs=3,
                    metavar=("BIT", "BAUD", "OUTFILE"),
                    help="decode bit N at baud B to outfile")
    args = ap.parse_args()

    if not args.target:
        ap.error("need at least one --target")

    samplerate, events = parse_events(args.input)
    print(f"Source:      {args.input}")
    print(f"Samplerate:  {samplerate:.0f} Hz")
    print(f"Events:      {len(events)}")
    if events:
        print(f"Time range:  {events[0][0]:.3f} to {events[-1][0]:.3f} s")
        print(f"Capture span: {events[-1][0] - events[0][0]:.3f} s")
    print()

    # Show which bits had any transitions
    from collections import Counter
    seen_data = Counter(d for _, d in events)
    print(f"Most common packed values:")
    for v, c in seen_data.most_common(8):
        bits_set = [str(i) for i in range(16) if v & (1 << i)]
        print(f"  0x{v:04X} = {v:>5}  bits[{','.join(bits_set)}]  ({c}x)")
    print()

    print(f"Active bits (with at least one transition):")
    for bit in range(16):
        mask = 1 << bit
        states = set()
        for _, d in events:
            states.add(1 if (d & mask) else 0)
        if len(states) > 1:
            n_trans = len(list(bit_transitions(events, bit)))
            print(f"  bit{bit:>2}: {n_trans} transitions")
    print()

    # Decode each target
    for bit_s, baud_s, outfile in args.target:
        bit = int(bit_s)
        baud = int(baud_s)
        print(f"Decoding bit {bit} @ {baud} baud -> {outfile}")
        trans = list(bit_transitions(events, bit))
        if not trans:
            print(f"  (no transitions on bit {bit})")
            continue
        bytes_out = uart_decode_from_events(trans, baud)
        with open(outfile, 'wb') as f:
            f.write(bytes(bytes_out))
        print(f"  decoded {len(bytes_out)} bytes")
        if bytes_out and len(bytes_out) < 1024:
            preview = ' '.join(f'{b:02X}' for b in bytes_out[:60])
            print(f"  preview: {preview}")
        elif bytes_out:
            preview = ' '.join(f'{b:02X}' for b in bytes_out[:30])
            print(f"  preview (first 30): {preview}")


if __name__ == "__main__":
    main()
