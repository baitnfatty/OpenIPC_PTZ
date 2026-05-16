"""
decode_summary.py - Run AF + HK32F-STC8G decoders on extracted .bin files
and produce a one-page summary of findings.

Usage:
    python decode_summary.py [--af-cmd af_cmd.bin] [--af-tlm af_tlm.bin] [--white whitewire.bin]
"""
import os
import sys
import argparse
import subprocess
import csv
from collections import Counter


def af_summary(bin_path):
    if not os.path.isfile(bin_path) or os.path.getsize(bin_path) == 0:
        return f"  {bin_path}: empty or missing"
    # Run aj_frame_parser
    subprocess.run([sys.executable, "aj_frame_parser.py", bin_path],
                   capture_output=True, check=False)
    csv_path = os.path.splitext(bin_path)[0] + ".csv"
    summary_path = os.path.splitext(bin_path)[0] + ".summary.txt"

    if not os.path.isfile(csv_path):
        return f"  {bin_path}: parser produced no CSV"

    # Read CSV and gather stats
    with open(csv_path) as f:
        reader = csv.DictReader(f)
        rows = list(reader)
    n_frames = len(rows)

    # Unique frame patterns
    unique = Counter(tuple(row[f'B{i:02d}'] for i in range(20)) for row in rows)
    state_dist = Counter(row['state'] for row in rows)

    lines = [
        f"  {bin_path}: {os.path.getsize(bin_path)} bytes, {n_frames} frames parsed",
        f"    Unique 20-byte patterns: {len(unique)}",
        f"    State byte distribution: " + ", ".join(f"0x{s}={c}" for s, c in state_dist.most_common(5)),
        f"    Top 3 frames:",
    ]
    for frame, count in unique.most_common(3):
        hex_str = ' '.join(frame)
        lines.append(f"      {hex_str}  ({count}x)")
    return '\n'.join(lines)


def white_summary(bin_path):
    if not os.path.isfile(bin_path) or os.path.getsize(bin_path) == 0:
        return f"  {bin_path}: empty or missing"
    # Run hk32_stc8g_decoder
    subprocess.run([sys.executable, "hk32_stc8g_decoder.py", bin_path],
                   capture_output=True, check=False)
    frames_path = os.path.splitext(bin_path)[0] + ".frames.txt"
    summary_path = os.path.splitext(bin_path)[0] + ".summary.txt"

    lines = [f"  {bin_path}: {os.path.getsize(bin_path)} bytes"]
    if os.path.isfile(summary_path):
        with open(summary_path) as f:
            lines.append("    " + f.read().replace('\n', '\n    '))
    return '\n'.join(lines)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--af-cmd", default="af_cmd.bin")
    ap.add_argument("--af-tlm", default="af_tlm.bin")
    ap.add_argument("--white", default="whitewire.bin")
    args = ap.parse_args()

    print("="*70)
    print("MC800S protocol decode summary")
    print("="*70)
    print()
    print("=== AF UART command line (SoC -> HK32F, 115200 8N1) ===")
    print(af_summary(args.af_cmd))
    print()
    print("=== AF UART telemetry line (HK32F -> SoC, 115200 8N1) ===")
    print(af_summary(args.af_tlm))
    print()
    print("=== HK32F -> STC8G white wire (66666 8N1) ===")
    print(white_summary(args.white))


if __name__ == "__main__":
    main()
