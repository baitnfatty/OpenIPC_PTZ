"""
pelco_decoder.py — Decode Pelco-D 7-byte frames from white-wire captures.

Pelco-D protocol (well-documented standard):
    Byte 0: 0xFF  (sync)
    Byte 1: address (1-255, the device ID we're talking to)
    Byte 2: command 1 byte (focus, iris, sense, scan)
    Byte 3: command 2 byte (camera, IRIS, FOCUS, ZOOM, TILT, PAN bits)
    Byte 4: data 1 (pan speed, 0x00 stop, 0x3F max)
    Byte 5: data 2 (tilt speed, 0x00 stop, 0x3F max)
    Byte 6: checksum (sum of bytes 1-5 modulo 256)

Usage:
    python pelco_decoder.py <input.bin> [<input2.bin> ...]
"""
import sys
import os
import glob


def find_frames(data: bytes):
    """Yield (offset, frame_bytes) for every Pelco-D frame found."""
    pos = 0
    while pos <= len(data) - 7:
        if data[pos] == 0xFF:
            frame = data[pos:pos+7]
            if len(frame) == 7:
                # Verify checksum
                expected_csum = sum(frame[1:6]) & 0xFF
                if expected_csum == frame[6]:
                    yield pos, frame
                    pos += 7
                    continue
        pos += 1


def decode_command(c1: int, c2: int) -> str:
    """Decode Pelco-D command bits (well-documented protocol)."""
    parts = []

    # Byte 2 (command 1)
    if c1 & 0x80: parts.append("Sense")
    if c1 & 0x40: parts.append("R0")
    if c1 & 0x20: parts.append("R1")
    if c1 & 0x10: parts.append("AutoScan")
    if c1 & 0x08: parts.append("CameraOn")
    if c1 & 0x04: parts.append("IrisClose")
    if c1 & 0x02: parts.append("IrisOpen")
    if c1 & 0x01: parts.append("FocusNear")

    # Byte 3 (command 2)
    if c2 & 0x80: parts.append("FocusFar")
    if c2 & 0x40: parts.append("ZoomWide")
    if c2 & 0x20: parts.append("ZoomTele")
    if c2 & 0x10: parts.append("TiltDown")
    if c2 & 0x08: parts.append("TiltUp")
    if c2 & 0x04: parts.append("PanLeft")
    if c2 & 0x02: parts.append("PanRight")
    if c2 & 0x01: parts.append("Reserved")

    if not parts:
        if (c1 & 0xFF) == 0 and (c2 & 0xFF) == 0:
            return "STOP"
        return f"<unknown cmd1=0x{c1:02X} cmd2=0x{c2:02X}>"
    return " + ".join(parts)


def decode_frame(frame: bytes) -> str:
    """Decode a 7-byte Pelco-D frame to human-readable."""
    sync, addr, c1, c2, d1, d2, csum = frame
    cmds = decode_command(c1, c2)
    return f"addr=0x{addr:02X}  cmd=[{cmds}]  pan_speed=0x{d1:02X} tilt_speed=0x{d2:02X}  csum=0x{csum:02X}"


def parse_file(path: str):
    with open(path, 'rb') as f:
        data = f.read()
    base = os.path.splitext(path)[0]
    out_path = base + ".decoded.txt"

    frames = list(find_frames(data))
    print(f"  {path}: {len(data)} bytes, {len(frames)} valid Pelco-D frames")

    with open(out_path, 'w', encoding='utf-8') as out:
        out.write(f"Source: {path}\n")
        out.write(f"Size: {len(data)} bytes\n")
        out.write(f"Valid Pelco-D frames: {len(frames)}\n\n")

        if not frames:
            out.write("(no Pelco-D frames found — wrong baud, wrong wire, or no traffic)\n")
            return

        seen = {}
        for idx, (offset, frame) in enumerate(frames):
            hex_str = ' '.join(f"{b:02X}" for b in frame)
            decoded = decode_frame(frame)
            out.write(f"[{idx:4d}] off=0x{offset:08X}  {hex_str}   {decoded}\n")
            seen[hex_str] = seen.get(hex_str, 0) + 1

        out.write(f"\n=== Unique frames ({len(seen)}) ===\n")
        for f, count in sorted(seen.items(), key=lambda kv: -kv[1]):
            csum_byte = int(f.split()[-1], 16)
            decoded = decode_frame(bytes(int(b, 16) for b in f.split()))
            out.write(f"  {f}  ({count}x)   {decoded}\n")

    print(f"    -> {out_path}")


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
    print(f"Decoding {len(inputs)} file(s)...")
    print()
    for inp in inputs:
        if os.path.exists(inp):
            try:
                parse_file(inp)
            except Exception as e:
                print(f"  {inp}: ERROR — {e}")
        else:
            print(f"  {inp}: NOT FOUND")


if __name__ == "__main__":
    main(sys.argv)
