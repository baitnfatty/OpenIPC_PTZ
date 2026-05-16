"""
wf_rawdata_uart.py - Stream-decode UART from a WaveForms "Raw Data" CSV.

Raw Data format = one row per sample, columns are "Time (s), Sample"
where Sample is a packed 16-bit int holding all 16 DIO states.

Unlike Raw Events, Raw Data has a row for EVERY sample at full sample rate.
At 6.25 MS/s × 30 s, that's 187 million rows = multi-GB files.

This script streams through the file row by row (constant memory), tracking
the previous state of each target bit, and decodes UART per bit by sampling
at the expected bit centers using the sample rate from the header.

Usage:
    python wf_rawdata_uart.py <input.csv> \
        --target BIT BAUD OUTFILE [--target BIT BAUD OUTFILE ...]

Example:
    python wf_rawdata_uart.py tiltuphold0003.csv --target 1 115200 tilt_up_hold.bin
"""
import sys
import os
import argparse
import re
import time


def parse_header(path):
    samplerate = None
    with open(path, 'r') as f:
        for line in f:
            line = line.rstrip()
            if line.startswith('#Sample rate:'):
                m = re.search(r'([\d.eE+-]+)\s*Hz', line)
                if m:
                    samplerate = float(m.group(1))
            elif line.startswith('Time'):
                break
    return samplerate


class UartDecoderState:
    """Per-bit UART 8N1 LSB-first decoder.  Fed one (bit value, sample_idx) at a time."""
    IDLE, START, DATA, STOP = range(4)

    def __init__(self, samplerate, baud, out_path):
        self.spb = samplerate / baud
        self.state = self.IDLE
        self.prev = 1
        self.bit_center = 0.0
        self.bit_n = 0
        self.value = 0
        self.byte_count = 0
        self.out_file = open(out_path, 'wb')
        self.buf = bytearray()

    def feed(self, s, sample_idx):
        if self.state == self.IDLE:
            if self.prev == 1 and s == 0:
                self.state = self.START
                self.bit_center = sample_idx + self.spb / 2.0
            self.prev = s
            return

        if self.state == self.START:
            if sample_idx >= self.bit_center:
                if s != 0:
                    self.state = self.IDLE
                else:
                    self.state = self.DATA
                    self.bit_n = 0
                    self.value = 0
                    self.bit_center += self.spb
            return

        if self.state == self.DATA:
            if sample_idx >= self.bit_center:
                if s:
                    self.value |= (1 << self.bit_n)
                self.bit_n += 1
                if self.bit_n == 8:
                    self.state = self.STOP
                self.bit_center += self.spb
            return

        if self.state == self.STOP:
            if sample_idx >= self.bit_center:
                self.buf.append(self.value)
                self.byte_count += 1
                if len(self.buf) >= 65536:
                    self.out_file.write(self.buf)
                    self.buf.clear()
                self.state = self.IDLE
            return

    def close(self):
        if self.buf:
            self.out_file.write(self.buf)
        self.out_file.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="WaveForms Raw Data CSV")
    ap.add_argument("--target", action="append", nargs=3,
                    metavar=("BIT", "BAUD", "OUTFILE"),
                    help="decode bit N at baud B to outfile")
    ap.add_argument("--progress", type=int, default=20_000_000,
                    help="print progress every N samples")
    args = ap.parse_args()

    if not args.target:
        ap.error("need at least one --target")
    if not os.path.isfile(args.input):
        ap.error(f"input not found: {args.input}")

    samplerate = parse_header(args.input)
    if not samplerate:
        raise SystemExit("Failed to parse samplerate from header")
    print(f"Source:      {args.input}")
    print(f"Samplerate:  {samplerate:.0f} Hz")
    decoders = []
    for bit_s, baud_s, outfile in args.target:
        bit = int(bit_s)
        baud = int(baud_s)
        d = UartDecoderState(samplerate, baud, outfile)
        decoders.append((bit, d, baud, outfile))
        print(f"  Target: bit {bit} @ {baud} baud -> {outfile}")
    print()

    t_start = time.time()
    n_samples = 0
    with open(args.input, 'r') as f:
        # Skip header
        for line in f:
            if line.startswith('Time'):
                break
        # Process data rows.  Each row is "time,sample"
        for line in f:
            # Fast manual parse
            comma = line.find(',')
            if comma < 0: continue
            try:
                # We only need the sample value (skip the time string parse to be fast)
                sample = int(line[comma+1:].rstrip())
            except ValueError:
                continue
            # Feed each decoder
            for bit, d, baud, outfile in decoders:
                s = 1 if (sample & (1 << bit)) else 0
                d.feed(s, n_samples)
            n_samples += 1
            if n_samples % args.progress == 0:
                elapsed = time.time() - t_start
                rate = n_samples / elapsed if elapsed > 0 else 0
                print(f"  ... {n_samples:>12,} samples  {elapsed:6.1f}s  {rate/1e6:5.2f} MS/s")
                for bit, d, baud, outfile in decoders:
                    print(f"       bit{bit}: {d.byte_count} bytes")

    for bit, d, baud, outfile in decoders:
        d.close()

    elapsed = time.time() - t_start
    print()
    print(f"Done.  {n_samples:,} samples in {elapsed:.1f}s ({n_samples/elapsed/1e6:.2f} MS/s).")
    for bit, d, baud, outfile in decoders:
        size = os.path.getsize(outfile)
        print(f"  {outfile}: {d.byte_count} bytes")


if __name__ == "__main__":
    main()
