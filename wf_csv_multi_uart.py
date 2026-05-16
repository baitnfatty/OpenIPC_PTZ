"""
wf_csv_multi_uart.py - Multi-channel UART extractor for WaveForms CSV.

Streams through a WaveForms "Acquisition" CSV exactly once and writes one .bin
per (channel, baud) target.  Much faster than running wf_csv_uart.py three times
on the same 10 GB file.

Usage:
    python wf_csv_multi_uart.py <input.csv> \
        --target "whitewire(HK)" 66666 whitewire.bin \
        --target "red(HK)" 115200 af_cmd.bin \
        --target "black(HK)" 115200 af_tlm.bin

Each --target takes 3 args: channel_name, baud, output_bin.
"""
import sys
import os
import argparse
import re
import csv
import time


def parse_header(path):
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
                columns = next(csv.reader([line]))
                break
    return samplerate, columns


class UartDecoderState:
    """Per-channel UART decoder state, fed one bit at a time."""
    IDLE, START, DATA, STOP = range(4)

    def __init__(self, samplerate, baud, out_path):
        self.spb = samplerate / baud
        self.state = self.IDLE
        self.prev = 1
        self.sample_idx = 0
        self.bit_center = 0.0
        self.bit_n = 0
        self.value = 0
        self.byte_count = 0
        self.out_file = open(out_path, 'wb')
        self.buf = bytearray()

    def feed(self, s):
        if self.state == self.IDLE:
            if self.prev == 1 and s == 0:
                self.state = self.START
                self.bit_center = self.sample_idx + self.spb / 2.0
            self.prev = s
            self.sample_idx += 1
            return

        if self.state == self.START:
            if self.sample_idx >= self.bit_center:
                if s != 0:
                    self.state = self.IDLE
                else:
                    self.state = self.DATA
                    self.bit_n = 0
                    self.value = 0
                    self.bit_center += self.spb
            self.sample_idx += 1
            return

        if self.state == self.DATA:
            if self.sample_idx >= self.bit_center:
                if s:
                    self.value |= (1 << self.bit_n)
                self.bit_n += 1
                if self.bit_n == 8:
                    self.state = self.STOP
                self.bit_center += self.spb
            self.sample_idx += 1
            return

        if self.state == self.STOP:
            if self.sample_idx >= self.bit_center:
                self.buf.append(self.value)
                self.byte_count += 1
                if len(self.buf) >= 65536:
                    self.out_file.write(self.buf)
                    self.buf.clear()
                self.state = self.IDLE
            self.sample_idx += 1
            return

    def close(self):
        if self.buf:
            self.out_file.write(self.buf)
            self.buf.clear()
        self.out_file.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="WaveForms Logic Analyzer Acquisition CSV")
    ap.add_argument("--target", action="append", nargs=3,
                    metavar=("CHANNEL", "BAUD", "OUTFILE"),
                    help="add a UART decode target")
    ap.add_argument("--progress", type=int, default=20_000_000,
                    help="print progress every N samples")
    args = ap.parse_args()

    if not os.path.isfile(args.input):
        ap.error(f"Input not found: {args.input}")
    if not args.target:
        ap.error("at least one --target required")

    samplerate, columns = parse_header(args.input)
    if not samplerate or not columns:
        raise SystemExit("Failed to parse header")

    print(f"Source:       {args.input}")
    print(f"Samplerate:   {samplerate:.0f} Hz")
    print(f"Columns:      {len(columns)}")
    print()

    # Build decoder state, one per target
    decoders = []
    for ch, baud_str, out in args.target:
        if ch not in columns:
            print(f"ERROR: channel {ch!r} not in CSV")
            print(f"  Available: {columns}")
            sys.exit(1)
        idx = columns.index(ch)
        baud = int(baud_str)
        d = UartDecoderState(samplerate, baud, out)
        decoders.append((idx, d, ch, baud, out))
        print(f"  Target: {ch!r:<25} idx={idx:<2} baud={baud:<6}  ->  {out}")
    print()

    # Stream through file
    t_start = time.time()
    n_samples = 0
    with open(args.input, 'r') as f:
        # Skip header
        for line in f:
            if line.startswith('Time') or line.startswith('"Time'):
                break
        # Process data rows
        for line in f:
            # Fast manual parse - avoid csv module overhead
            # Format: "time,0,1,0,1,...,X,X,X\n"
            parts = line.rstrip().split(',')
            for idx, d, ch, baud, out in decoders:
                if idx < len(parts):
                    v = parts[idx]
                    if v == '0':
                        d.feed(0)
                    elif v == '1':
                        d.feed(1)
                    else:
                        d.feed(1)  # treat X as idle high
            n_samples += 1
            if n_samples % args.progress == 0:
                elapsed = time.time() - t_start
                rate = n_samples / elapsed if elapsed > 0 else 0
                pct = n_samples / 268435456 * 100
                print(f"  ... {n_samples:>12,} samples  ({pct:5.1f}%)  "
                      f"{elapsed:6.1f}s elapsed  {rate/1e6:5.2f} MS/s")
                for idx, d, ch, baud, out in decoders:
                    print(f"       {ch:<25} bytes={d.byte_count}")

    # Close all decoders
    for idx, d, ch, baud, out in decoders:
        d.close()

    elapsed = time.time() - t_start
    print()
    print(f"Done.  {n_samples:,} samples processed in {elapsed:.1f}s "
          f"({n_samples/elapsed/1e6:.2f} MS/s effective).")
    print(f"Outputs:")
    for idx, d, ch, baud, out in decoders:
        size = os.path.getsize(out)
        print(f"  {out}  -- {d.byte_count} bytes / {size} on disk")


if __name__ == "__main__":
    main()
