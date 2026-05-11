"""
aj_frame_parser.py — extract 20-byte AJ protocol frames from raw UART captures.

Usage:
    python aj_frame_parser.py <input.bin> [<input2.bin> ...]
    python aj_frame_parser.py path/to/session/*.bin

Output: for each <input.bin>, writes <input.csv> alongside it with one row per frame:
    frame_idx, byte_offset, B00..B19 (hex), state_byte, marker_intact

Also writes <input>.summary.txt with stats:
    total bytes, total frames found, percent-aligned, state byte distribution.

Frame structure (hypothesis from prior analysis — refined as we go):
    Offset  0-7   : sync header `06 66 00 60 80 66 E6 80`
    Offset  8     : state byte (0xFE idle / 0xE6 active)
    Offset  9-13  : marker `06 00 1E 00 00`
    Offset  14-19 : payload (command + arguments + likely CRC)

If your capture's actual frame size is different from 20, change FRAME_LEN below.
"""

import sys
import os
import csv
import glob
from collections import Counter

SYNC_HEADER = bytes.fromhex("06 66 00 60 80 66 E6 80".replace(" ", ""))
MARKER = bytes.fromhex("06 00 1E 00 00".replace(" ", ""))
FRAME_LEN = 20
STATE_OFFSET = 8     # zero-indexed, so byte at frame[8]
MARKER_OFFSET = 9
PAYLOAD_START = 14


def find_frames(data: bytes):
    """Yield (byte_offset, frame_bytes) for every sync-aligned frame."""
    n = len(data)
    pos = 0
    while pos <= n - FRAME_LEN:
        if data[pos:pos+len(SYNC_HEADER)] == SYNC_HEADER:
            yield pos, data[pos:pos+FRAME_LEN]
            pos += FRAME_LEN
        else:
            pos += 1


def parse_file(input_path: str):
    with open(input_path, 'rb') as f:
        data = f.read()

    base = os.path.splitext(input_path)[0]
    csv_path = base + ".csv"
    summary_path = base + ".summary.txt"

    frames = list(find_frames(data))
    state_counts = Counter()
    marker_intact_count = 0

    # Sync alignment quality: how much of the file is covered by sync-aligned frames?
    aligned_bytes = len(frames) * FRAME_LEN

    with open(csv_path, 'w', newline='', encoding='utf-8') as csvfh:
        writer = csv.writer(csvfh)
        header = ['frame_idx', 'byte_offset'] + [f'B{i:02d}' for i in range(FRAME_LEN)] + ['state', 'marker_ok']
        writer.writerow(header)

        for idx, (offset, frame) in enumerate(frames):
            row = [idx, offset]
            row.extend(f"{b:02X}" for b in frame)
            state = frame[STATE_OFFSET]
            state_counts[state] += 1
            marker = frame[MARKER_OFFSET:MARKER_OFFSET+len(MARKER)]
            marker_ok = (marker == MARKER)
            if marker_ok:
                marker_intact_count += 1
            row.append(f"{state:02X}")
            row.append("1" if marker_ok else "0")
            writer.writerow(row)

    # Summary
    with open(summary_path, 'w', encoding='utf-8') as sfh:
        sfh.write(f"Source: {input_path}\n")
        sfh.write(f"File size: {len(data)} bytes\n")
        sfh.write(f"Frames found: {len(frames)}\n")
        sfh.write(f"Aligned coverage: {aligned_bytes}/{len(data)} = {aligned_bytes/max(1,len(data))*100:.1f}%\n")
        sfh.write(f"Marker intact: {marker_intact_count}/{len(frames)}\n")
        sfh.write("\nState byte distribution:\n")
        for state, count in sorted(state_counts.items(), key=lambda kv: -kv[1]):
            sfh.write(f"  0x{state:02X}: {count} ({count/max(1,len(frames))*100:.1f}%)\n")

        # Payload variance check — which bytes vary across frames?
        if frames:
            sfh.write("\nPer-byte variance (within this capture):\n")
            for i in range(FRAME_LEN):
                values = set(frame[i] for _, frame in frames)
                if len(values) == 1:
                    sfh.write(f"  B{i:02d}: constant 0x{next(iter(values)):02X}\n")
                else:
                    samples = ' '.join(f"0x{v:02X}" for v in sorted(values)[:8])
                    suffix = " ..." if len(values) > 8 else ""
                    sfh.write(f"  B{i:02d}: {len(values)} unique [{samples}{suffix}]\n")

    print(f"  {input_path}")
    print(f"    -> {csv_path}  ({len(frames)} frames)")
    print(f"    -> {summary_path}")
    if len(frames) == 0:
        print(f"    !!  NO FRAMES FOUND. Sync header `{SYNC_HEADER.hex()}` not present.")
        print(f"    !!  Check baud rate, parity, RTS/CTS — capture may be misaligned.")
    elif aligned_bytes / max(1, len(data)) < 0.5:
        print(f"    ?? low alignment ({aligned_bytes/len(data)*100:.0f}%) — frames present but lots of unframed bytes")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        sys.exit(1)

    inputs = []
    for arg in argv[1:]:
        # Glob expansion (Windows shell may not do this)
        if any(c in arg for c in '*?['):
            inputs.extend(glob.glob(arg))
        else:
            inputs.append(arg)

    if not inputs:
        print("No input files matched.")
        sys.exit(1)

    print(f"Parsing {len(inputs)} file(s)...")
    print()
    for inp in inputs:
        if not os.path.exists(inp):
            print(f"  {inp}: NOT FOUND")
            continue
        try:
            parse_file(inp)
        except Exception as e:
            print(f"  {inp}: ERROR — {e}")

    print()
    print("Done.")


if __name__ == "__main__":
    main(sys.argv)
