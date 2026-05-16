"""
pelco_decoder.py - DEPRECATED.  Use hk32_stc8g_decoder.py instead.

This file used to decode standard Pelco-D (2400 baud, 7-byte 0xFF-sync frames),
based on the original hypothesis that the white wire on the MC800S was carrying
SoC->STC8G Pelco-D for pan/tilt.

That hypothesis was WRONG.  The actual protocol on the white wire is:
  - Source: HK32F lens MCU TX  (NOT SoC)
  - Sink:   STC8G P3.0 RxD via diode D3
  - Baud:   66,666 8N1  (NOT 2400)
  - Frame:  6 bytes, recurring "51 01 04 78 01 0D" baseline  (NOT 7-byte Pelco-D)

The new decoder is `hk32_stc8g_decoder.py` - it handles the actual frame format,
runs multiple checksum hypotheses on the trailing byte, and falls back to frame-
size discovery when defaults don't match.

If you're absolutely sure your capture is standard Pelco-D from a different source
(e.g. an external RS-485 device probed via 485A/485B on the distro board), see git
history for the previous version of this script.
"""
import sys
import os

print(__doc__)
print()
print("ERROR: This decoder is deprecated.")
print()
print("To decode your white-wire capture, run:")
print()
print(f"  python hk32_stc8g_decoder.py {' '.join(sys.argv[1:]) if len(sys.argv) > 1 else '<input.bin>'}")
print()
sys.exit(1)
