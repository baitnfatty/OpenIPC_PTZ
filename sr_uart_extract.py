"""
sr_uart_extract.py - Extract UART-decoded bytes from a sigrok .sr capture.

Takes a PulseView .sr file (or an already-extracted sr_extract/ dir), pulls one
channel's bit stream, software-decodes it as UART at a given baud, and writes
the resulting byte stream as a .bin file that can feed the existing decoders
(hk32_stc8g_decoder.py, aj_frame_parser.py, etc.).

Usage:
    python sr_uart_extract.py <input.sr> --channel N --baud B [--out file.bin]
    python sr_uart_extract.py sr_extract/  --channel N --baud B [--out file.bin]

Example:
    # Extract the white wire (D5) at 66666 baud from capture2.sr
    python sr_uart_extract.py capture2.sr --channel 5 --baud 66666 --out white_c2.bin

    # Extract the AF command line (D4) at 115200 baud
    python sr_uart_extract.py capture2.sr --channel 4 --baud 115200 --out af_cmd_c2.bin

UART parameters: 8N1, LSB-first, idle-high.
"""
import sys
import os
import argparse
import zipfile
import tempfile
import shutil
import re


def parse_samplerate(value: str) -> int:
    """Parse '5 MHz' / '500 kHz' / '125000000' into integer Hz."""
    s = value.strip()
    m = re.match(r"([\d.]+)\s*([kMG]?)Hz", s)
    if m:
        n = float(m.group(1))
        mult = {'': 1, 'k': 1e3, 'M': 1e6, 'G': 1e9}[m.group(2)]
        return int(n * mult)
    # Bare number
    return int(s)


def read_metadata(meta_path: str):
    """Return dict: {samplerate, total_probes, probe_names...}"""
    info = {}
    with open(meta_path, 'r') as f:
        for line in f:
            line = line.strip()
            if '=' not in line or line.startswith('['):
                continue
            k, _, v = line.partition('=')
            info[k.strip()] = v.strip()
    return info


def find_capture_files(dir_path: str):
    """Return sorted list of logic-N-M data files in directory."""
    files = []
    for name in os.listdir(dir_path):
        m = re.match(r"logic-(\d+)-(\d+)$", name)
        if m:
            files.append((int(m.group(1)), int(m.group(2)), os.path.join(dir_path, name)))
    files.sort()
    return [path for _, _, path in files]


def extract_channel_stream(data_files, channel: int):
    """Yield 0/1 samples for the given channel from all data files in order."""
    mask = 1 << channel
    for path in data_files:
        with open(path, 'rb') as f:
            chunk = f.read(65536)
            while chunk:
                for b in chunk:
                    yield 1 if (b & mask) else 0
                chunk = f.read(65536)


def uart_decode(bit_stream, samplerate: int, baud: int):
    """Generic 8N1 LSB-first UART software decode.

    Yields decoded bytes.  Frame errors (missing stop bit) are silently skipped
    after re-syncing on the next high->low transition.
    """
    spb = samplerate / baud  # samples per bit (may be fractional)

    # State machine
    IDLE, START, DATA, STOP = range(4)
    state = IDLE
    prev = 1
    sample_idx = 0
    bit_center = 0.0  # next sample index at which to sample current bit's center
    bit_n = 0
    value = 0

    for s in bit_stream:
        # Detect falling edge while idle = start of frame
        if state == IDLE:
            if prev == 1 and s == 0:
                state = START
                # We're at the very first low sample of the start bit.
                # Center of start bit is sample_idx + spb/2
                bit_center = sample_idx + spb / 2.0
            prev = s
            sample_idx += 1
            continue

        if state == START:
            if sample_idx >= bit_center:
                # Sample at start-bit center; must still be low to confirm
                if s != 0:
                    # False start - resync
                    state = IDLE
                else:
                    state = DATA
                    bit_n = 0
                    value = 0
                    bit_center += spb  # next center = first data bit center
            sample_idx += 1
            continue

        if state == DATA:
            if sample_idx >= bit_center:
                # Sample this data bit (LSB first)
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
                # Should be high - if not, frame error but emit byte anyway
                yield value
                state = IDLE
            sample_idx += 1
            continue


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help=".sr file OR extracted sr_extract/ directory")
    ap.add_argument("--channel", type=int, required=True, help="channel number 0..7 (D0..D7 in PulseView)")
    ap.add_argument("--baud", type=int, required=True, help="UART baud rate")
    ap.add_argument("--out", help="output .bin filename (default: <input-stem>_chN_baudB.bin)")
    args = ap.parse_args()

    # Resolve input - extract .sr if needed
    cleanup_dir = None
    if os.path.isdir(args.input):
        capture_dir = args.input
    elif args.input.endswith(".sr") and os.path.isfile(args.input):
        cleanup_dir = tempfile.mkdtemp(prefix="sr_extract_")
        with zipfile.ZipFile(args.input) as zf:
            zf.extractall(cleanup_dir)
        capture_dir = cleanup_dir
    else:
        ap.error(f"Input not found or not a .sr/dir: {args.input}")

    try:
        meta_path = os.path.join(capture_dir, "metadata")
        if not os.path.isfile(meta_path):
            raise SystemExit(f"No metadata file in {capture_dir}")
        info = read_metadata(meta_path)
        samplerate = parse_samplerate(info.get("samplerate", "0"))
        n_probes = int(info.get("total probes", 8))

        if not (0 <= args.channel < n_probes):
            raise SystemExit(f"Channel {args.channel} out of range (capture has {n_probes} probes)")

        data_files = find_capture_files(capture_dir)
        if not data_files:
            raise SystemExit(f"No logic-*-* data files in {capture_dir}")

        # Output filename
        if args.out:
            out_path = args.out
        else:
            stem = os.path.splitext(os.path.basename(args.input.rstrip(os.sep)))[0]
            out_path = f"{stem}_ch{args.channel}_baud{args.baud}.bin"

        print(f"Source:       {args.input}")
        print(f"Samplerate:   {samplerate} Hz")
        print(f"Channel:      D{args.channel}")
        print(f"Baud:         {args.baud}")
        print(f"Samples/bit:  {samplerate/args.baud:.2f}")
        print(f"Data files:   {len(data_files)}")
        print()

        stream = extract_channel_stream(data_files, args.channel)
        n_bytes = 0
        with open(out_path, 'wb') as out:
            buf = bytearray()
            for b in uart_decode(stream, samplerate, args.baud):
                buf.append(b)
                if len(buf) >= 4096:
                    out.write(buf)
                    n_bytes += len(buf)
                    buf.clear()
            if buf:
                out.write(buf)
                n_bytes += len(buf)

        print(f"Decoded:      {n_bytes} bytes")
        print(f"Wrote:        {out_path}")
        if n_bytes == 0:
            print()
            print("WARNING: zero bytes decoded.  Possible causes:")
            print("  - Wrong channel number (try D0..D7)")
            print("  - Wrong baud rate")
            print("  - Channel is idle (no UART activity in this capture)")
            print("  - Line is inverted (UART logic high should = 3.3V at rest)")

    finally:
        if cleanup_dir:
            shutil.rmtree(cleanup_dir, ignore_errors=True)


if __name__ == "__main__":
    main()
