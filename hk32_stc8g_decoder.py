"""
hk32_stc8g_decoder.py - Decode the HK32F->STC8G custom UART protocol.

Replaces pelco_decoder.py (which assumed standard Pelco-D 2400 baud / 7-byte
frames with 0xFF sync). The real protocol on the white wire between the HK32F
lens MCU and the STC8G distro MCU is:

    Line:     HK32F (lens board) TX  ->  white wire  ->  Diode D3  ->  STC8G P3.0 (RxD)
    Baud:     66,666 8N1 (non-standard; HK32F STM32F0-clone USART at 48 MHz / BRR 720)
    Framing:  6-byte frames, recurring "51 01 04 78 01 0D" observed in baseline captures

    Hypothesized layout (refine as we get more variation under triggered actions):
        Byte 0: 0x51       - likely sync / start byte
        Byte 1: 0x01       - device address or sub-command
        Byte 2: 0x04       - command class (could be opcode for "status update" baseline)
        Byte 3: 0x78       - data1 (varies with motor speed?  pan/tilt position?)
        Byte 4: 0x01       - data2
        Byte 5: 0x0D       - delimiter (CR character) OR checksum

    The "0D" trailer is suspicious - it's the ASCII <CR>, common in line-oriented protocols.
    If it's a fixed delimiter, then the 5 preceding bytes carry the data.  If it's a sum
    checksum, then 0x51+0x01+0x04+0x78+0x01 = 0xCF, NOT 0x0D, so a simple sum is ruled
    out.  Could still be XOR, CRC-8, or a position-dependent function - tested below.

Usage:
    python hk32_stc8g_decoder.py <input.bin> [<input2.bin> ...]
    python hk32_stc8g_decoder.py session_*/*.bin

Outputs per file:
    <input>.frames.txt    - one line per identified frame, hex + decode
    <input>.summary.txt   - frame counts, per-byte variance, checksum tests
"""

import sys
import os
import glob
from collections import Counter

# --------------------------------------------------------------------
# Tunables - update as protocol understanding firms up
# --------------------------------------------------------------------
SYNC_BYTE = 0x51         # observed start byte on every baseline frame
DELIMITER = 0x0D         # observed end byte on every baseline frame
FRAME_LEN = 6            # observed length
MIN_FRAME = 4            # don't even bother with frames shorter than this
MAX_FRAME = 12           # don't search above this

# --------------------------------------------------------------------
# Frame finder - sync-based
# --------------------------------------------------------------------
def find_frames(data: bytes, frame_len=FRAME_LEN, sync=SYNC_BYTE, delim=DELIMITER):
    """Yield (offset, frame_bytes) for each frame matching sync+...+delim pattern."""
    pos = 0
    n = len(data)
    while pos <= n - frame_len:
        if data[pos] == sync and data[pos + frame_len - 1] == delim:
            yield pos, data[pos:pos + frame_len]
            pos += frame_len
        else:
            pos += 1


def find_frames_loose(data: bytes, frame_len=FRAME_LEN, sync=SYNC_BYTE):
    """Yield (offset, frame_bytes) for each frame starting with sync, regardless of trailer.
    Useful when a checksum byte at the end varies and we're not sure of structure yet."""
    pos = 0
    n = len(data)
    while pos <= n - frame_len:
        if data[pos] == sync:
            yield pos, data[pos:pos + frame_len]
            pos += frame_len
        else:
            pos += 1


# --------------------------------------------------------------------
# Checksum / CRC trial functions - run all of them per frame and see if any match B[5]
# --------------------------------------------------------------------
def csum_sum(frame: bytes) -> int:
    return sum(frame[:-1]) & 0xFF


def csum_sum_minus_sync(frame: bytes) -> int:
    return sum(frame[1:-1]) & 0xFF


def csum_xor(frame: bytes) -> int:
    x = 0
    for b in frame[:-1]:
        x ^= b
    return x


def csum_xor_minus_sync(frame: bytes) -> int:
    x = 0
    for b in frame[1:-1]:
        x ^= b
    return x


def csum_2complement(frame: bytes) -> int:
    return ((~sum(frame[:-1])) + 1) & 0xFF


CHECKSUM_TESTS = [
    ("sum_all",              csum_sum),
    ("sum_minus_sync",       csum_sum_minus_sync),
    ("xor_all",              csum_xor),
    ("xor_minus_sync",       csum_xor_minus_sync),
    ("twos_complement_sum",  csum_2complement),
]


def test_checksums(frames):
    """For each known checksum function, count how often it matches B[last]."""
    if not frames:
        return {}
    results = {}
    for name, fn in CHECKSUM_TESTS:
        matches = 0
        for _, f in frames:
            if fn(f) == f[-1]:
                matches += 1
        results[name] = (matches, len(frames))
    return results


# --------------------------------------------------------------------
# Frame discovery (when default 6-byte assumption fails)
# --------------------------------------------------------------------
def discover_frame_size(data: bytes, sync=SYNC_BYTE):
    """Find inter-sync byte distances to suggest frame length."""
    positions = [i for i, b in enumerate(data) if b == sync]
    if len(positions) < 3:
        return None, []
    deltas = [positions[i+1] - positions[i] for i in range(len(positions) - 1)]
    counter = Counter(deltas)
    return counter.most_common(8), positions


# --------------------------------------------------------------------
# Per-byte variance analysis
# --------------------------------------------------------------------
def per_byte_variance(frames):
    """For each position in the frame, list the unique byte values observed."""
    if not frames:
        return []
    frame_len = len(frames[0][1])
    cols = []
    for i in range(frame_len):
        values = Counter(f[1][i] for f in frames)
        cols.append(values)
    return cols


# --------------------------------------------------------------------
# Main per-file processing
# --------------------------------------------------------------------
def parse_file(path: str):
    with open(path, 'rb') as fh:
        data = fh.read()

    base = os.path.splitext(path)[0]
    frames_path = base + ".frames.txt"
    summary_path = base + ".summary.txt"

    # First pass: assume default 6-byte 0x51...0x0D frame
    frames = list(find_frames(data, FRAME_LEN, SYNC_BYTE, DELIMITER))
    discovery = None
    if not frames:
        # Try sync-only, no delimiter check
        frames = list(find_frames_loose(data, FRAME_LEN, SYNC_BYTE))
        if not frames:
            # Sync byte itself may differ - discover candidate frame size
            discovery = discover_frame_size(data, SYNC_BYTE)

    cols = per_byte_variance(frames)
    checks = test_checksums(frames)

    # ---- frames.txt: one line per frame ----
    with open(frames_path, 'w', encoding='utf-8') as out:
        out.write(f"Source:        {path}\n")
        out.write(f"File size:     {len(data)} bytes\n")
        out.write(f"Frame length:  {FRAME_LEN}\n")
        out.write(f"Sync byte:     0x{SYNC_BYTE:02X}\n")
        out.write(f"Frames found:  {len(frames)}\n\n")

        if not frames:
            out.write("(no frames found at default sync/delim - see summary for discovery hints)\n")
        else:
            for idx, (offset, f) in enumerate(frames):
                hex_str = ' '.join(f"{b:02X}" for b in f)
                ascii_str = ''.join(chr(b) if 32 <= b < 127 else '.' for b in f)
                out.write(f"[{idx:5d}] off=0x{offset:08X}  {hex_str}   |{ascii_str}|\n")

    # ---- summary.txt: stats + checksum tests + discovery ----
    with open(summary_path, 'w', encoding='utf-8') as out:
        out.write(f"Source: {path}\n")
        out.write(f"Size:   {len(data)} bytes\n")
        out.write(f"Frames: {len(frames)}\n")
        out.write(f"Coverage: {len(frames) * FRAME_LEN}/{len(data)} = "
                  f"{(len(frames) * FRAME_LEN) / max(1, len(data)) * 100:.1f}%\n\n")

        # Unique frame patterns
        if frames:
            unique = Counter(bytes(f[1]) for f in frames)
            out.write(f"=== Unique frame patterns ({len(unique)}) ===\n")
            for f, count in sorted(unique.items(), key=lambda kv: -kv[1])[:50]:
                hex_str = ' '.join(f"{b:02X}" for b in f)
                out.write(f"  {hex_str}  ({count}x)\n")
            if len(unique) > 50:
                out.write(f"  ... and {len(unique) - 50} more\n")
            out.write("\n")

        # Per-byte variance
        if cols:
            out.write("=== Per-byte variance ===\n")
            for i, col in enumerate(cols):
                if len(col) == 1:
                    val, count = next(iter(col.items()))
                    out.write(f"  B{i}: constant 0x{val:02X}  ({count}x)\n")
                else:
                    top = sorted(col.items(), key=lambda kv: -kv[1])[:8]
                    items = ', '.join(f"0x{v:02X}={c}" for v, c in top)
                    suffix = f" ...{len(col)-8} more" if len(col) > 8 else ""
                    out.write(f"  B{i}: {len(col)} unique [{items}{suffix}]\n")
            out.write("\n")

        # Checksum hypothesis tests
        if checks:
            out.write("=== Checksum hypothesis tests (last byte) ===\n")
            for name, (matches, total) in sorted(checks.items(), key=lambda kv: -kv[1][0]):
                pct = matches / max(1, total) * 100
                out.write(f"  {name:25s}: {matches}/{total} ({pct:.0f}%)\n")
            out.write("\n")
            if all(v[0] == 0 for v in checks.values()):
                out.write("NOTE: none of the standard checksums match.  Last byte is likely a\n")
                out.write("      fixed delimiter (0x0D = CR) rather than a checksum.\n\n")

        # Frame size discovery (if default failed)
        if discovery is not None:
            common_deltas, positions = discovery
            out.write("=== Frame size discovery (default sync/delim found nothing) ===\n")
            out.write(f"Sync byte 0x{SYNC_BYTE:02X} appears at {len(positions)} positions\n")
            if common_deltas:
                out.write("Most common inter-sync distances (likely frame length):\n")
                for delta, count in common_deltas:
                    out.write(f"  {delta} bytes  ({count}x)\n")

    print(f"  {path}")
    print(f"    -> {frames_path}  ({len(frames)} frames)")
    print(f"    -> {summary_path}")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        sys.exit(1)
    inputs = []
    for arg in argv[1:]:
        if any(c in arg for c in '*?['):
            inputs.extend(glob.glob(arg))
        else:
            inputs.append(arg)
    if not inputs:
        print("No input files matched.")
        sys.exit(1)
    print(f"Decoding {len(inputs)} file(s)...\n")
    for inp in inputs:
        if os.path.exists(inp):
            try:
                parse_file(inp)
            except Exception as e:
                print(f"  {inp}: ERROR - {e}")
        else:
            print(f"  {inp}: NOT FOUND")


if __name__ == "__main__":
    main(sys.argv)
