"""
check_la.py — Verify the Nucleo LA firmware is responding before wiring.

Speaks the SUMP protocol's basic ID query. If the firmware is alive, we
get back a 4-byte identifier ("1ALS" for OLS, varies for clones).

Usage:
    python check_la.py --port COM5
    python check_la.py --port COM5 --baud 115200    # default
"""

import argparse
import time
import sys


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', required=True, help='COM port (e.g. COM5)')
    parser.add_argument('--baud', type=int, default=115200, help='Control baud (default 115200)')
    args = parser.parse_args()

    try:
        import serial
    except ImportError:
        print("ERROR: pyserial not installed. Run: pip install pyserial")
        sys.exit(1)

    print(f"Opening {args.port} at {args.baud} baud...")
    try:
        ser = serial.Serial(args.port, args.baud, timeout=2)
    except serial.SerialException as e:
        print(f"ERROR: {e}")
        print("Check that the Nucleo is plugged in and the COM port is correct.")
        sys.exit(1)

    print("Sending SUMP RESET (0x00) x5 to clear any pending state...")
    ser.write(b'\x00' * 5)
    time.sleep(0.2)
    ser.read(1024)  # discard

    print("Sending SUMP ID query (0x02)...")
    ser.write(b'\x02')

    print("Waiting for 4-byte ID response...")
    response = ser.read(4)

    if len(response) == 0:
        print()
        print("[FAIL] NO RESPONSE")
        print()
        print("Possible causes:")
        print("  - Wrong COM port (check Device Manager)")
        print("  - Firmware not flashed correctly — re-run flash.ps1")
        print("  - Nucleo needs to be reset (press B2 black button on the board)")
        print("  - USB cable is charge-only (try a different cable)")
        sys.exit(2)

    if len(response) < 4:
        print(f"⚠ PARTIAL response: {response.hex()} ({len(response)} bytes — expected 4)")
        sys.exit(2)

    id_str = response.decode('ascii', errors='replace')
    print()
    print(f"[OK] ID response: {response.hex()}  ('{id_str}')")
    print()

    if id_str == "1ALS":
        print("[OK] This is the standard OLS ID — firmware is alive and SUMP-compatible.")
    elif "1AL" in id_str:
        print("[OK] Looks like a SUMP-family ID. Firmware is alive.")
    else:
        print("? Unexpected ID, but at least we got 4 bytes back. Try PulseView anyway.")

    # Try metadata query (0x04) — gives more info
    print()
    print("Sending METADATA query (0x04)...")
    ser.write(b'\x04')
    meta = ser.read(256)  # metadata is variable length, ends with 0x00
    if meta:
        # Parse metadata key-value pairs
        i = 0
        print(f"Metadata raw ({len(meta)} bytes): {meta.hex()}")
        while i < len(meta):
            key = meta[i]
            i += 1
            if key == 0:
                break
            elif key == 1:  # Device name (string)
                end = meta.find(b'\x00', i)
                name = meta[i:end].decode('ascii', errors='replace')
                print(f"  Device name: {name}")
                i = end + 1
            elif key == 2:  # FPGA version
                end = meta.find(b'\x00', i)
                ver = meta[i:end].decode('ascii', errors='replace')
                print(f"  Version: {ver}")
                i = end + 1
            elif key == 0x21:  # Sample memory (32-bit)
                samples = int.from_bytes(meta[i:i+4], 'big')
                print(f"  Sample memory: {samples}")
                i += 4
            elif key == 0x23:  # Max sample rate (32-bit)
                rate = int.from_bytes(meta[i:i+4], 'big')
                print(f"  Max sample rate: {rate} Hz ({rate/1e6:.2f} MSPS)")
                i += 4
            elif key == 0x40:  # Probes (8-bit)
                probes = meta[i]
                print(f"  Channels: {probes}")
                i += 1
            elif key == 0x41:  # Protocol version (8-bit)
                proto = meta[i]
                print(f"  Protocol version: {proto}")
                i += 1
            else:
                # Unknown key — skip ahead heuristically
                # Keys 0x00-0x1F are strings, 0x20-0x2F are 32-bit, 0x30+ are 8-bit
                if key < 0x20:
                    end = meta.find(b'\x00', i)
                    if end == -1: break
                    print(f"  [unknown string key 0x{key:02X}]: {meta[i:end].decode('ascii', errors='replace')}")
                    i = end + 1
                elif key < 0x30:
                    print(f"  [unknown 32-bit key 0x{key:02X}]: {int.from_bytes(meta[i:i+4], 'big')}")
                    i += 4
                else:
                    print(f"  [unknown 8-bit key 0x{key:02X}]: {meta[i]}")
                    i += 1
    else:
        print("(no metadata response — that's OK, basic ID was good)")

    ser.close()
    print()
    print("[OK] All checks passed. Open PulseView, select the OLS driver, and capture.")


if __name__ == "__main__":
    main()
