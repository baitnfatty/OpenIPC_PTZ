"""
aj_crc_solver.py — brute-force the AJ protocol's checksum/CRC algorithm.

Given multiple captured frames where we hypothesize:
    payload = bytes [start:end_exclusive]
    checksum = bytes [end:end+1] (CRC-8) or [end:end+2] (CRC-16) etc.

This tries every common CRC polynomial + init + reflect + xor combination
and tells you which (if any) produces matching values for ALL frames.

Usage:
    python aj_crc_solver.py <frames.csv> [--payload 0:18] [--crc 18:20]

Default: assumes the first 18 bytes are payload, last 2 bytes are CRC-16.
You can override with --payload START:END  --crc START:END (Python slice syntax).

If you want to try several payload/CRC partitions automatically, pass --auto.
"""

import sys
import csv
import argparse
import itertools
from typing import List, Tuple

# -------------------------------------------------------------------
# Generic CRC implementation
# -------------------------------------------------------------------

def crc_generic(data: bytes, width: int, poly: int, init: int,
                reflect_in: bool, reflect_out: bool, xor_out: int) -> int:
    """Bit-by-bit CRC. Slow but covers every parameter combination."""
    if reflect_in:
        # Reflect each byte
        data = bytes(reverse_bits(b, 8) for b in data)

    crc = init
    top_bit = 1 << (width - 1)
    mask = (1 << width) - 1

    for b in data:
        crc ^= (b << (width - 8)) & mask
        for _ in range(8):
            if crc & top_bit:
                crc = ((crc << 1) ^ poly) & mask
            else:
                crc = (crc << 1) & mask

    if reflect_out:
        crc = reverse_bits(crc, width)

    crc ^= xor_out
    crc &= mask
    return crc


def reverse_bits(value: int, width: int) -> int:
    """Reverse the bits of `value` within `width` bits."""
    out = 0
    for i in range(width):
        if value & (1 << i):
            out |= 1 << (width - 1 - i)
    return out


# -------------------------------------------------------------------
# Common polynomials to try
# -------------------------------------------------------------------

CRC8_POLYS = {
    'CRC-8 (CCITT)':       (8, 0x07,    0x00, False, False, 0x00),
    'CRC-8 (Maxim/Dallas)':(8, 0x31,    0x00, True,  True,  0x00),
    'CRC-8 (SAE J1850)':   (8, 0x1D,    0xFF, False, False, 0xFF),
    'CRC-8 (WCDMA)':       (8, 0x9B,    0x00, True,  True,  0x00),
    'CRC-8 (DVB-S2)':      (8, 0xD5,    0x00, False, False, 0x00),
    'CRC-8 (8H2F)':        (8, 0x2F,    0xFF, False, False, 0xFF),
    'CRC-8 (Bluetooth)':   (8, 0xA7,    0x00, True,  True,  0x00),
    'CRC-8 (DARC)':        (8, 0x39,    0x00, True,  True,  0x00),
    'CRC-8 (LTE)':         (8, 0x9B,    0x00, False, False, 0x00),
    'CRC-8 (ROHC)':        (8, 0x07,    0xFF, True,  True,  0x00),
    'CRC-8 (CDMA2000)':    (8, 0x9B,    0xFF, False, False, 0x00),
    'CRC-8 (I-CODE)':      (8, 0x1D,    0xFD, False, False, 0x00),
}

CRC16_POLYS = {
    'CRC-16 (CCITT-FALSE)':   (16, 0x1021, 0xFFFF, False, False, 0x0000),
    'CRC-16 (XMODEM)':        (16, 0x1021, 0x0000, False, False, 0x0000),
    'CRC-16 (KERMIT)':        (16, 0x1021, 0x0000, True,  True,  0x0000),
    'CRC-16 (CCITT-AUG)':     (16, 0x1021, 0x1D0F, False, False, 0x0000),
    'CRC-16 (IBM)':           (16, 0x8005, 0x0000, True,  True,  0x0000),
    'CRC-16 (MODBUS)':        (16, 0x8005, 0xFFFF, True,  True,  0x0000),
    'CRC-16 (USB)':           (16, 0x8005, 0xFFFF, True,  True,  0xFFFF),
    'CRC-16 (DECT-R)':        (16, 0x0589, 0x0000, False, False, 0x0001),
    'CRC-16 (DECT-X)':        (16, 0x0589, 0x0000, False, False, 0x0000),
    'CRC-16 (DNP)':           (16, 0x3D65, 0x0000, True,  True,  0xFFFF),
    'CRC-16 (T10-DIF)':       (16, 0x8BB7, 0x0000, False, False, 0x0000),
    'CRC-16 (TELEDISK)':      (16, 0xA097, 0x0000, False, False, 0x0000),
    'CRC-16 (GENIBUS)':       (16, 0x1021, 0xFFFF, False, False, 0xFFFF),
    'CRC-16 (DDS-110)':       (16, 0x8005, 0x800D, False, False, 0x0000),
    'CRC-16 (TMS37157)':      (16, 0x1021, 0x89EC, True,  True,  0x0000),
    'CRC-16 (RIELLO)':        (16, 0x1021, 0xB2AA, True,  True,  0x0000),
    'CRC-16 (CRC-A)':         (16, 0x1021, 0xC6C6, True,  True,  0x0000),
    'CRC-16 (PROFIBUS)':      (16, 0x1DCF, 0xFFFF, False, False, 0xFFFF),
    'CRC-16 (CDMA2000)':      (16, 0xC867, 0xFFFF, False, False, 0x0000),
    'CRC-16 (BUYPASS)':       (16, 0x8005, 0x0000, False, False, 0x0000),
    'CRC-16 (EN13757)':       (16, 0x3D65, 0x0000, False, False, 0xFFFF),
    'CRC-16 (MAXIM)':         (16, 0x8005, 0x0000, True,  True,  0xFFFF),
    'CRC-16 (CMS)':           (16, 0x8005, 0xFFFF, False, False, 0x0000),
}

CRC32_POLYS = {
    'CRC-32 (Ethernet/ZIP)': (32, 0x04C11DB7, 0xFFFFFFFF, True,  True,  0xFFFFFFFF),
    'CRC-32 (BZIP2)':        (32, 0x04C11DB7, 0xFFFFFFFF, False, False, 0xFFFFFFFF),
    'CRC-32C (Castagnoli)':  (32, 0x1EDC6F41, 0xFFFFFFFF, True,  True,  0xFFFFFFFF),
    'CRC-32D':               (32, 0xA833982B, 0xFFFFFFFF, True,  True,  0xFFFFFFFF),
    'CRC-32 (MPEG-2)':       (32, 0x04C11DB7, 0xFFFFFFFF, False, False, 0x00000000),
    'CRC-32 (POSIX)':        (32, 0x04C11DB7, 0x00000000, False, False, 0xFFFFFFFF),
}


# -------------------------------------------------------------------
# Simple checksums (non-CRC)
# -------------------------------------------------------------------

def checksum_sum8(data: bytes) -> int:
    return sum(data) & 0xFF


def checksum_sum16(data: bytes) -> int:
    return sum(data) & 0xFFFF


def checksum_xor8(data: bytes) -> int:
    out = 0
    for b in data:
        out ^= b
    return out


def checksum_2c8(data: bytes) -> int:
    """Two's complement of sum, as used in many Pelco-D-derived protocols."""
    return ((-sum(data)) & 0xFF)


def checksum_pelco_d(data: bytes) -> int:
    """Pelco-D specific: sum of bytes 1-5, mod 256."""
    return sum(data) & 0xFF


SIMPLE_CHECKSUMS_8 = {
    'SUM-8': checksum_sum8,
    'XOR-8': checksum_xor8,
    'TWO-COMPLEMENT-8 (sum negated)': checksum_2c8,
    'Pelco-D style sum': checksum_pelco_d,
}

SIMPLE_CHECKSUMS_16 = {
    'SUM-16': checksum_sum16,
}


# -------------------------------------------------------------------
# Solver
# -------------------------------------------------------------------

def load_frames_from_csv(csv_path: str) -> List[List[int]]:
    frames = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            frame = []
            for i in range(20):
                key = f"B{i:02d}"
                if key in row:
                    frame.append(int(row[key], 16))
            if frame:
                frames.append(frame)
    return frames


def try_crc_against_frames(frames: List[List[int]], payload_slice: slice,
                            crc_slice: slice, polys: dict, width: int,
                            verbose: bool = False) -> List[Tuple[str, tuple]]:
    """Returns list of (name, params) that match all frames."""
    matches = []
    for name, params in polys.items():
        all_match = True
        for i, frame in enumerate(frames):
            payload = bytes(frame[payload_slice])
            expected_bytes = bytes(frame[crc_slice])
            # Combine CRC bytes into integer (big-endian first, then little)
            # Try both endiannesses
            if width == 8:
                expected = expected_bytes[0]
                computed = crc_generic(payload, *params)
                if computed != expected:
                    all_match = False
                    break
            else:
                expected_be = int.from_bytes(expected_bytes, 'big')
                expected_le = int.from_bytes(expected_bytes, 'little')
                computed = crc_generic(payload, *params)
                if computed != expected_be and computed != expected_le:
                    all_match = False
                    break
        if all_match:
            matches.append((name, params))
            if verbose:
                print(f"  ✓ {name}")
    return matches


def try_simple_against_frames(frames: List[List[int]], payload_slice: slice,
                                crc_slice: slice, checksums: dict,
                                width: int) -> List[str]:
    matches = []
    for name, fn in checksums.items():
        all_match = True
        for frame in frames:
            payload = bytes(frame[payload_slice])
            expected_bytes = bytes(frame[crc_slice])
            computed = fn(payload)
            if width == 8:
                if computed != expected_bytes[0]:
                    all_match = False
                    break
            else:
                expected = int.from_bytes(expected_bytes, 'big')
                if computed != expected:
                    all_match = False
                    break
        if all_match:
            matches.append(name)
    return matches


def solve(frames: List[List[int]], payload_slice: slice, crc_slice: slice):
    """Run all CRC algorithms and simple checksums against the partition."""
    width_bytes = (crc_slice.stop or len(frames[0])) - (crc_slice.start or 0)
    width_bits = width_bytes * 8
    print(f"Testing {len(frames)} frames")
    print(f"  payload: bytes [{payload_slice.start or 0}:{payload_slice.stop or 20}] ({(payload_slice.stop or 20) - (payload_slice.start or 0)} bytes)")
    print(f"  CRC:     bytes [{crc_slice.start or 0}:{crc_slice.stop or 20}] ({width_bytes} bytes / {width_bits} bits)")
    print()

    if width_bits == 8:
        print(f"--- CRC-8 candidates ---")
        crc_matches = try_crc_against_frames(frames, payload_slice, crc_slice, CRC8_POLYS, 8, verbose=True)
        print(f"--- Simple 8-bit checksums ---")
        simple_matches = try_simple_against_frames(frames, payload_slice, crc_slice, SIMPLE_CHECKSUMS_8, 8)
        for m in simple_matches:
            print(f"  ✓ {m}")
    elif width_bits == 16:
        print(f"--- CRC-16 candidates ---")
        crc_matches = try_crc_against_frames(frames, payload_slice, crc_slice, CRC16_POLYS, 16, verbose=True)
        print(f"--- Simple 16-bit checksums ---")
        simple_matches = try_simple_against_frames(frames, payload_slice, crc_slice, SIMPLE_CHECKSUMS_16, 16)
        for m in simple_matches:
            print(f"  ✓ {m}")
    elif width_bits == 32:
        print(f"--- CRC-32 candidates ---")
        crc_matches = try_crc_against_frames(frames, payload_slice, crc_slice, CRC32_POLYS, 32, verbose=True)
    else:
        print(f"Unsupported CRC width: {width_bits} bits")
        return

    if not crc_matches:
        print("  (no CRC matches at this partition)")


def auto_search(frames: List[List[int]]):
    """Try every reasonable payload/CRC partition."""
    print("Auto-search: trying every (payload, CRC) partition...")
    print()

    # Try CRC widths of 1 byte and 2 bytes at the END of frame
    for crc_bytes in [1, 2]:
        for payload_start in [0, 8, 9]:  # try with or without sync header in payload
            payload_end = 20 - crc_bytes
            crc_start = payload_end
            crc_end = 20

            print(f"=== Partition: payload[{payload_start}:{payload_end}], crc[{crc_start}:{crc_end}] ===")
            solve(frames, slice(payload_start, payload_end), slice(crc_start, crc_end))
            print()


def main(argv):
    parser = argparse.ArgumentParser(description="Brute-force AJ protocol CRC")
    parser.add_argument('csv_path', help="Frame CSV from aj_frame_parser.py")
    parser.add_argument('--payload', help="Payload byte slice, e.g. 0:18", default="0:18")
    parser.add_argument('--crc', help="CRC byte slice, e.g. 18:20", default="18:20")
    parser.add_argument('--auto', action='store_true', help="Try all reasonable partitions")
    args = parser.parse_args(argv[1:])

    frames = load_frames_from_csv(args.csv_path)
    if not frames:
        print(f"No frames loaded from {args.csv_path}")
        sys.exit(1)

    print(f"Loaded {len(frames)} frames from {args.csv_path}")
    print()

    if args.auto:
        auto_search(frames)
    else:
        def parse_slice(s):
            parts = s.split(':')
            return slice(int(parts[0]) if parts[0] else None,
                         int(parts[1]) if parts[1] else None)
        solve(frames, parse_slice(args.payload), parse_slice(args.crc))


if __name__ == "__main__":
    main(sys.argv)
