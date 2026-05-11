"""
aj_diff_visualizer.py — compare two AJ frame captures, identify bytes
that change between them.

Usage:
    python aj_diff_visualizer.py <baseline.csv> <action.csv>
    python aj_diff_visualizer.py <session_dir>          # auto-diff all _RX.csv vs idle baseline

Goal: pinpoint which bytes encode each command. After running the diff campaign,
this surfaces the byte positions that distinguish, say, zoom-in from zoom-out.

Output for each pair:
    - Side-by-side comparison: byte position, baseline value range, action value range
    - Highlighting:
        STABLE    : same byte values in both captures (sync, fixed protocol bits)
        TELEMETRY : varies within each but overlaps (camera state noise)
        COMMAND   : differs deterministically between baseline and action  ← 🎯
"""

import csv
import os
import sys
import glob
from collections import Counter

FRAME_LEN = 20


def load_csv(path: str):
    """Returns list of frames (each frame = list of 20 ints)."""
    frames = []
    with open(path, 'r', encoding='utf-8', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            frame = []
            for i in range(FRAME_LEN):
                key = f"B{i:02d}"
                frame.append(int(row[key], 16))
            frames.append(frame)
    return frames


def byte_value_set(frames, byte_idx):
    """Returns set of values seen at byte_idx across all frames."""
    return set(f[byte_idx] for f in frames)


def byte_distribution(frames, byte_idx):
    """Returns Counter of values at byte_idx."""
    return Counter(f[byte_idx] for f in frames)


def categorize(baseline_set, action_set):
    """Return 'stable', 'telemetry', or 'command'."""
    if baseline_set == action_set:
        if len(baseline_set) == 1:
            return 'stable'
        else:
            return 'telemetry-stable'  # both vary identically
    overlap = baseline_set & action_set
    if not overlap:
        return 'command'  # disjoint sets — clean command bit
    if baseline_set.issubset(action_set) or action_set.issubset(baseline_set):
        return 'partial-command'  # action introduces new values
    return 'telemetry'  # overlap but different distributions


def format_set(s, max_show=6):
    """Format a set of byte values as hex."""
    sorted_vals = sorted(s)
    shown = ' '.join(f"{v:02X}" for v in sorted_vals[:max_show])
    if len(sorted_vals) > max_show:
        shown += f" +{len(sorted_vals) - max_show}"
    return f"{{{shown}}}"


def diff_pair(baseline_path: str, action_path: str, out_path: str = None):
    """Compare two parsed frame CSVs."""
    baseline = load_csv(baseline_path)
    action = load_csv(action_path)

    bn = os.path.basename(baseline_path).replace('.csv', '')
    an = os.path.basename(action_path).replace('.csv', '')

    out_lines = []
    out_lines.append(f"DIFF: {bn}  vs  {an}")
    out_lines.append(f"  baseline: {len(baseline)} frames  ({baseline_path})")
    out_lines.append(f"  action:   {len(action)} frames  ({action_path})")
    out_lines.append("")

    if not baseline or not action:
        out_lines.append("!!! one capture is empty — cannot diff")
        result = '\n'.join(out_lines)
        if out_path:
            with open(out_path, 'w', encoding='utf-8') as f:
                f.write(result)
        print(result)
        return

    # Header
    out_lines.append(f"{'Byte':>4}  {'Category':<18}  {'Baseline':<28}  {'Action':<28}  Notes")
    out_lines.append('-' * 100)

    command_bytes = []
    for i in range(FRAME_LEN):
        b_set = byte_value_set(baseline, i)
        a_set = byte_value_set(action, i)
        cat = categorize(b_set, a_set)

        b_str = format_set(b_set)
        a_str = format_set(a_set)

        # Highlight command bytes
        marker = ''
        if cat == 'command':
            marker = '*** COMMAND ***'
            command_bytes.append(i)
        elif cat == 'partial-command':
            marker = '!  partial'
            command_bytes.append(i)

        out_lines.append(f"  B{i:02d}  {cat:<18}  {b_str:<28}  {a_str:<28}  {marker}")

    out_lines.append('')
    if command_bytes:
        out_lines.append(f"COMMAND-LIKE BYTES: {', '.join(f'B{i:02d}' for i in command_bytes)}")
        out_lines.append("These bytes either change values entirely between baseline and action,")
        out_lines.append("or the action introduces new values not seen in baseline.")
        out_lines.append("They are the most likely candidates for action-encoding bytes.")
    else:
        out_lines.append("No command-distinguishing bytes found.")
        out_lines.append("Either action didn't generate distinct frames, or the protocol")
        out_lines.append("encodes commands in a non-byte-position way (timing? sequence?).")

    # Sample frames for inspection
    out_lines.append('')
    out_lines.append("Sample baseline frames (first 3):")
    for f in baseline[:3]:
        out_lines.append('  ' + ' '.join(f"{b:02X}" for b in f))
    out_lines.append("Sample action frames (first 3):")
    for f in action[:3]:
        out_lines.append('  ' + ' '.join(f"{b:02X}" for b in f))

    result = '\n'.join(out_lines)
    print(result)
    print()

    if out_path:
        with open(out_path, 'w', encoding='utf-8') as f:
            f.write(result)
        print(f"Saved diff to {out_path}")
        print()


def auto_diff_session(session_dir: str):
    """Find idle_baseline_RX.csv and diff every other *_RX.csv against it."""
    rx_csvs = glob.glob(os.path.join(session_dir, '*_RX.csv'))
    if not rx_csvs:
        print(f"No *_RX.csv files in {session_dir}. Did you run aj_frame_parser.py first?")
        return

    # Find baseline
    baseline = None
    for c in rx_csvs:
        if 'idle_baseline' in os.path.basename(c) and '01' in os.path.basename(c):
            baseline = c
            break
    if not baseline:
        # Fall back to first idle_baseline anywhere
        for c in rx_csvs:
            if 'idle_baseline' in os.path.basename(c):
                baseline = c
                break

    if not baseline:
        print(f"No idle_baseline_RX.csv found in {session_dir}.")
        print("Available CSVs:")
        for c in rx_csvs:
            print(f"  {c}")
        return

    print(f"Baseline: {baseline}")
    print()

    diff_dir = os.path.join(session_dir, 'diffs')
    os.makedirs(diff_dir, exist_ok=True)

    for action in rx_csvs:
        if action == baseline:
            continue
        action_name = os.path.basename(action).replace('_RX.csv', '')
        out_path = os.path.join(diff_dir, f"{action_name}_vs_idle.txt")
        diff_pair(baseline, action, out_path)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        sys.exit(1)

    if len(argv) == 2:
        # Single argument — must be a session dir
        if os.path.isdir(argv[1]):
            auto_diff_session(argv[1])
        else:
            print("Single argument must be a session directory.")
            print(__doc__)
            sys.exit(1)
    elif len(argv) >= 3:
        baseline_path = argv[1]
        action_path = argv[2]
        out_path = argv[3] if len(argv) >= 4 else None
        diff_pair(baseline_path, action_path, out_path)
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main(sys.argv)
