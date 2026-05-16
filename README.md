# MC800S PTZ Camera Reverse Engineering

Reverse-engineering the JideTech MC800S PTZ camera (also branded as Anjvision /
Topsee) to enable full PTZ control under OpenIPC firmware. Video works on
OpenIPC; this work focuses on getting zoom, focus, pan, tilt, IR LEDs, and
IR-cut filter all operating without the stock proprietary firmware.

## Hardware

- **SoC**: SigmaStar SSC380 / SSC338Q (CCDCAM IMA80S15 reference design)
- **Image sensor**: Sony IMX415 (1/2.8", 4K UHD)
- **Lens MCU**: Hangshun HK32F030MF4P6 (Cortex-M0, debug-fused via `DBG_CLK_CTL = 0x12DE`)
- **Distro MCU**: STC8G2K325A (8051, drives pan/tilt steppers via ULN2803A)
- **Motor driver**: BA6208G (DC) + ULN2803A (steppers)
- **LED driver**: PT4115 constant-current buck regulator
- **PoE**: SDaPo PM3812TV7 PD module
- **Motors**: 2× 24BYJ48 (12V) steppers + 2× DC motors (zoom + focus)

## Architecture summary

```
ONVIF/Hikvision client
   │
   ▼ (Ethernet/TCP)
SoC SSC380 main board (IMA80S15)
   ├─ J1 (NET cable) ────→ PoE board + Ethernet
   ├─ J2 (AF UART R2)   ──→ HK32F lens MCU (zoom/focus via AF protocol @ 115200 8N1)
   ├─ J6 (PWM IR)       ──→ Distro PT4115 DIM pin (IR LED brightness)
   ├─ J7 (CDS_IN)       ←── Ambient light sensor (via STC8G)
   └─ J8 (IR-cut H-bridge) ──→ Sensor board IR-cut actuator coil

HK32F lens board
   ├─ Receives AF protocol from SoC
   ├─ Drives BA6208G (zoom/focus DC motors)
   └─ Outputs custom protocol @ ~66666 baud to STC8G via white wire + diode D3

STC8G distro board
   ├─ Receives commands from HK32F via white wire (Pelco-D-like protocol)
   ├─ Drives ULN2803A inputs 1-8 (4-phase stepper sequencing)
   └─ Reads CDS ambient light, may forward day/night state
```

See `MC800S-system-map.md` for the full board and signal map.

## Key findings

- **HK32F030M is silicon-debug-locked** via the Hangshun `DBG_CLK_CTL = 0x12DE`
  option byte. SWD never responds; no software path to dump firmware. Confirmed
  across CubeProgrammer (8 frequencies), OpenOCD (3 configs), HLA-mode SWD.
- **The chip is the central PTZ relay** — receives AF protocol from SoC, translates
  to Pelco-D-style protocol for the STC8G, drives zoom/focus DC motors directly.
- **AF protocol** is 115200 8N1, 20-byte frames, sync header `06 66 00 60 80 66 E6 80`.
- **HK32F→STC8G protocol** runs at non-standard **66,666 baud** with recurring
  6-byte frame `51 01 04 78 01 0D`.
- The chip can be **replaced** with a fresh HK32F030MF4P6 (~$0.30) running our
  own firmware if needed — this defeats Hangshun's lock permanently. Dev boards
  on order to enable this path.

## Project status

Pre-camera tooling complete. Live capture campaign in progress.

| Stage | Status |
|---|:-:|
| Hardware mapped + datasheets gathered | ✅ |
| Capture/parse/diff tooling written | ✅ |
| Nucleo F411RE as SUMP LA built | ✅ |
| Initial captures decoded | ✅ |
| Multi-action diff campaign | 🚧 in progress |
| OpenIPC `mc800s-ptzd` daemon | ⏳ pending |
| Hot-air chip swap (if needed) | ⏳ pending |

## Tools in this repo

### Capture tools (PowerShell)
- `aj_diff_campaign.ps1` — dual-port UART capture, AF protocol on R2 RED/BLACK (115200 8N1)
- `pelco_capture.ps1` — white-wire capture, HK32F→STC8G custom protocol (66666 8N1, NOT actually Pelco-D)
- `go.ps1` — one-shot workflow runner (capture → parse → diff → CRC-solve)
- `sd_setup.ps1` — preps SD card with stock-firmware RCE script

### Analysis tools (Python)
- `aj_frame_parser.py` — extracts 20-byte AF frames from raw captures (sync `06 66 00 60 80 66 E6 80`)
- `aj_diff_visualizer.py` — side-by-side capture comparison, flags command bytes
- `aj_crc_solver.py` — brute-forces CRC polynomial against captured frames
- `hk32_stc8g_decoder.py` — decodes the HK32F→STC8G 6-byte custom protocol (sync `0x51`, delim `0x0D`)
- `sr_uart_extract.py` — extracts UART bytes from a PulseView `.sr` file at any channel/baud
- `pelco_decoder.py` — **DEPRECATED** stub; the white wire turned out NOT to be Pelco-D. Use `hk32_stc8g_decoder.py` instead.

### Logic analyzer (Nucleo F411RE)
- `nucleo_la/logicalrust.bin` — Rust-based SUMP firmware (native F411 timing)
- `nucleo_la/flash_logicalrust.ps1` — flash via STM32CubeProgrammer
- `nucleo_la/check_la.py` — sanity-check the LA via SUMP ID query
- `nucleo_la/pinout.md`, `pulseview_setup.md` — wiring + PulseView setup

### Reference documents
- `MC800S-system-map.md` — master board/signal map (constantly updated)
- `MC800S-PTZ-STATE.md` — current PTZ debugging state
- `MC800S-SoC-headers.md`, `MC800S-IO-headers.md` — connector pinouts

## Building tools from source

The Rust LA firmware (`nucleo_la/logicalrust/`) requires:
```
rustup toolchain install stable-x86_64-pc-windows-gnu
rustup target add thumbv7em-none-eabihf
cargo install flip-link
cd nucleo_la/logicalrust && cargo build --release --bin logicalrust
```

(Source repo: <https://github.com/westrup/logicalrust>)

## License / disclaimer

Personal reverse engineering of a consumer surveillance device for
interoperability with OpenIPC. Not for distribution of proprietary firmware
or trademarked materials. Use at your own risk.
