"""
wf_csv_uart.py - Extract UART-decoded bytes from a WaveForms Logic Analyzer CSV.

Streams through a WaveForms "Acquisition" CSV (one column per channel, 0/1 values)
without loading it into memory.  Pulls one named channel, software-decodes 8N1
UART at a given baud rate, writes the resulting bytes to .bin.

Handles huge files (10+ GB) by streaming line-by-line.

Usage:
    python wf_csv_uart.py <input.csv> --channel NAME --baud B [--out file.bin]

Example:
    python wf_csv_uart.py acq0001.csv --channel "whitewire(HK)" --baud 66666 --out whitewire.bin
    python wf_csv_uart.py acq0001.csv --channel "black(HK)"     --baud 115200 --out af_tlm.bin
    python wf_csv_uart.py acq0001.csv --channel "red(HK)"       --baud 115200 --out af_cmd.bin

The script auto-detects the sample rate from the header comment "#Sample rate: 2e+06Hz".
"""
import sys
import os
import argparse
import re
import csv


def parse_header(path):
    """Pull samplerate and column names from a WaveForms CSV.  Returns (samplerate_hz, columns_list)."""
    samplerate = None
    columns = None
    with open(path, 'r') as f:
        for line in f:
            line = line.rstrip('\n')
            if line.startswith('#Sample rate:'):
                m = re.search(r'([\d.eE+-]+)\s*Hz', line)
                if m:
                    samplerate = float(m.group(1))
            elif line.startswith('Time') or line.startswith('"Time'):
                # First non-comment row = column header
                columns = next(csv.reader([line]))
                break
            # Skip empty lines and continue
    return samplerate, columns


def stream_channel_bits(path, channel_idx):
    """Yield 0/1 ints for the given column index, streaming through file."""
    with open(path, 'r') as f:
        # Skip header (comments + column-name line)
        for line in f:
            if line.startswith('Time') or line.startswith('"Time'):
                break
        # Now yield channel values from data rows
        reader = csv.reader(f)
        for row in reader:
            if len(row) <= channel_idx:
                continue
            v = row[channel_idx].strip()
            if v == '0':
                yield 0
            elif v == '1':
                yield 1
            else:
                # 'X' or other - treat as idle high
                yield 1


def uart_decode(bit_stream, samplerate, baud):
    """Generic 8N1 LSB-first UART software decoder.  Yields decoded bytes."""
    spb = samplerate / baud  # samples per bit (may be fractional)

    IDLE, START, DATA, STOP = range(4)
    state = IDLE
    prev = 1
    sample_idx = 0
    bit_center = 0.0
    bit_n = 0
    value = 0

    for s in bit_stream:
        if state == IDLE:
            if prev == 1 and s == 0:
                state = START
                bit_center = sample_idx + spb / 2.0
            prev = s
            sample_idx += 1
            continue

        if state == START:
            if sample_idx >= bit_center:
                if s != 0:
                    state = IDLE
                else:
                    state = DATA
                    bit_n = 0
                    value = 0
                    bit_center += spb
            sample_idx += 1
            continue

        if state == DATA:
            if sample_idx >= bit_center:
                if s:
                    value |= (1 << bit_n)
                bit_n += 1
                if bit_n == 8:
                    state = STOP
                bit_center += spb
            sample_idx += 1
            continue

        if state == STOP:
            if sample_idx >= bit_center:
                yield value
                state = IDLE
            sample_idx += 1
            continue


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="WaveForms Logic Analyzer Acquisition CSV file")
    ap.add_argument("--channel", required=True,
                    help='exact column name, e.g. "whitewire(HK)" (quote it on shell)')
    ap.add_argument("--baud", type=int, required=True, help="UART baud rate")
    ap.add_argument("--out", help="output .bin filename (default: <channel>_baudB.bin)")
    ap.add_argument("--progress", type=int, default=10_000_000,
                    help="print progress every N samples (default 10M)")
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        ap.error(f"Input not found: {args.input}")

    samplerate, columns = parse_header(args.input)
    if not samplerate or not columns:
        raise SystemExit("Failed to parse header (samplerate / columns)")

    if args.channel not in columns:
        print(f"ERROR: column {args.channel!r} not found.")
        print(f"Available columns: {columns}")
        sys.exit(1)
    channel_idx = columns.index(args.channel)

    if args.out:
        out_path = args.out
    else:
        safe = re.sub(r'[^\w-]', '_', args.channel)
        out_path = f"{safe}_baud{args.baud}.bin"

    print(f"Source:       {args.input}")
    print(f"Samplerate:   {samplerate:.0f} Hz")
    print(f"Channel:      {args.channel!r}  (column {channel_idx})")
    print(f"Baud:         {args.baud}")
    print(f"Samples/bit:  {samplerate / args.baud:.2f}")
    print(f"Output:       {out_path}")
    print()

    # Stream
    n_samples = 0
    n_bytes = 0
    buf = bytearray()
    with open(out_path, 'wb') as out:
        bits = stream_channel_bits(args.input, channel_idx)
        # Need to count samples while still yielding to uart_decode.
        # Wrap with a counter generator:
        def counting():
            nonlocal n_samples
            for b in bits:
                n_samples += 1
                if n_samples % args.progress == 0:
                    pct = n_samples / 268435456 * 100 if n_samples <= 268435456 else 100
                    print(f"  ... {n_samples:>12,} samples processed ({pct:5.1f}%)  bytes decoded: {n_bytes}")
                yield b

        for byte in uart_decode(counting(), samplerate, args.baud):
            buf.append(byte)
            n_bytes += 1
            if len(buf) >= 65536:
                out.write(buf)
                buf.clear()
        if buf:
            out.write(buf)

    print()
    print(f"Done.  {n_samples:,} samples processed, {n_bytes:,} bytes decoded.")
    print(f"Wrote: {out_path}")
    if n_bytes == 0:
        print()
        print("WARNING: zero bytes decoded.  Possible causes:")
        print("  - Wrong channel name")
        print("  - Wrong baud rate")
        print("  - Channel never went active (idle high the whole time)")


if __name__ == "__main__":
    main()
