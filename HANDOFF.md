# MC800S PTZ Reverse-Engineering — Handoff Document

**Last updated:** 2026-05-16 (zoom click vs hold distinguished; new opcodes 0x78/0x7E found)
**Project:** Reverse-engineer the JideTech MC800S PTZ camera so OpenIPC can drive
zoom, focus, pan, tilt, IR LEDs, and the IR-cut filter without the stock proprietary
firmware.

This document is a self-contained snapshot of the project state so any human or LLM
session can pick up where this one left off.

---

## ⚠️ How to amend this document (READ BEFORE EDITING)

`HANDOFF.md` is the living source-of-truth for the project state across sessions.
The full rules live in [`CLAUDE.md`](CLAUDE.md) (auto-loaded by every Claude Code
session).  Quick version:

1. **Never silently delete information.**  Mark superseded content with a dated
   marker and add the new content alongside.  Mistakes stay easy to fix because
   the wrong content is still visible inline.
2. **Bump the `Last updated:` date** in the header above whenever you change
   substantive content.
3. **Add a one-line entry to the [Change log](#10-change-log)** at the bottom for
   every meaningful update.
4. **Commit each meaningful update** with a `HANDOFF:` prefix in the message.
   Git is the ultimate safety net — every prior version is recoverable.

### Quick correction template (copy/paste)

When fixing wrong content, wrap the old text like this:

```markdown
> ~~**[CORRECTED YYYY-MM-DD]**~~ — superseded.  Preserved for traceability:
>
> [old text indented in blockquote]
```

…then add the corrected info immediately below in a new paragraph.

### Quick supersede template (copy/paste)

When a whole section becomes outdated:

```markdown
## [Section title] [SUPERSEDED YYYY-MM-DD — see "[New section]" above]
> Kept for historical context.  Current understanding lives in the newer section.
```

### Rollback (if a HANDOFF edit goes wrong)

```bash
git log -p HANDOFF.md                       # see every prior edit
git checkout <old-sha> -- HANDOFF.md        # restore — only touches HANDOFF.md
```

---

## 1. What the camera is

| Subsystem | Part | Role |
|---|---|---|
| **SoC** | SigmaStar SSC338Q (IMA80S15 reference board) | Main processor — runs OpenIPC or stock; handles video, web UI, sends AF UART commands |
| **Sensor** | Sony IMX415 (1/2.8", 8.4 MP, 4K UHD) | Image sensor on MIPI-CSI ribbon |
| **Lens MCU** | Hangshun **HK32F030MF4P6** (Cortex-M0, **debug-fused via `DBG_CLK_CTL = 0x12DE`**) | Receives 115200-baud AF protocol from SoC, drives BA6208G for zoom/focus DC motors. **Cannot be read via SWD.** |
| **Distro MCU** | **STC8G2K325A** (8051 family) | Drives ULN2803A for pan/tilt steppers; drives PT4115 DIM for IR LED PWM. Receives commands from HK32F. |
| **Motor driver** | BA6208G (DC zoom/focus) + ULN2803A (steppers) | On lens board and distro board respectively |
| **IR LED driver** | PT4115 buck constant-current LED driver | DIM pin driven by STC8G pin 28 (P1.7 hardware PWM6) via 1 kΩ series |
| **PoE module** | SDaPo PM3812R | 48 V → 12 V/5 V/3.3 V |
| **Steppers** | 2× 24BYJ48 (12 V) | Pan + tilt |
| **DC motors** | 2× small | Zoom + focus |

### Architecture (current understanding)

```
ONVIF / Hikvision / TopSee client
    │
    ▼ Ethernet
SoC main board (SSC338Q on IMA80S15)
    │
    ├─ AF UART R2 RED+BLACK ── 115200 8N1 ── HK32F lens MCU (binary AJ protocol)
    │                                            │
    │                                            ├─ Drives BA6208G (zoom + focus DC)
    │                                            ├─ Drives S5756-A2 (IR-cut actuator)
    │                                            └─ Sends commands to STC8G via white wire (9600 ASCII)
    │                                                       │
    │                                                       ▼
    │                                                   STC8G distro MCU
    │                                                       │
    │                                                       ├─ Drives ULN2803A (pan + tilt steppers)
    │                                                       ├─ Reads CDS ambient via internal ADC
    │                                                       └─ Drives PT4115 DIM (IR LED PWM, P1.7 hardware PWM6)
    │
    └─ J6 PWM header (T1, 3-pin): UNPOPULATED — SoC does NOT drive any LED PWM
```

---

## 2. What is solved

### 2.1 Hardware mapping (Phase 0) — done

Every connector, every wire, every chip — fully traced. See
[MC800S-system-map.md](MC800S-system-map.md) for the master pinout reference.

Highlights:
- **R1 (NET cable, 8 pins)** = power + Ethernet pairs + LED indicators
- **R2 (4-pin)** = AF UART pair, ground, SPK_EN (red wire = SoC TX, black = SoC RX)
- **L1 (2-pin)** = RESET line (brown wire) — propagates back to camera body reset button
- **Distro board** = STC8G + ULN2803A + PT4115 + SS24 schottky for IR LED chain
- **HK32F lens board** = HK32F + BA6208G + S5756-A2 (IR-cut coil)
- The on-board SoC J6 PWM header (T1, top center, labeled `GND | PWM1 | PWM0`) is
  **physically unpopulated** — no SoC PWM is wired to anything.

### 2.2 HK32F silicon lock (Phase 1) — done (negative result)

HK32F030MF4P6 has `DBG_CLK_CTL = 0x12DE` set, which gates the debug clock at
silicon level. Confirmed unreachable via CubeProgrammer (8 frequencies), OpenOCD
(3 configs), and HLA-mode SWD. **No software-only path to dump the firmware
exists.** Plan B: hot-air swap a fresh chip with our own firmware (dev boards
already on order).

### 2.3 IR LED PWM path (Phase 3) — RESOLVED

```
STC8G P1.7 (pin 28, hardware PWM6) ─→ 1 kΩ series resistor ─→ PT4115 DIM pin
```

Confirmed by continuity tracing 2026-05-15. The IR LED PWM is generated locally
on the distro board by STC8G — NOT by the SoC. This means:

- No SoC PWM channel or DTS patch needed
- OpenIPC daemon controls IR brightness by sending a command to STC8G (probably
  through the HK32F relay), not by writing to `/sys/class/pwm/...`

### 2.4 White wire = HK32F debug/control console at 9600 baud ASCII

**This is the biggest correction in the project.** Earlier hypothesis (66666 baud,
6-byte binary frames `51 01 04 78 01 0D`) was WRONG — it was decoding a 9600-baud
ASCII signal at the wrong rate.

Real behavior: the white wire connects HK32F serial output to STC8G's RxD via
diode D3. At boot, HK32F emits this banner:

```
version   :1.20
build date:Aug  4 2022
build time:10:02:51
ip moudle :AJ          <-- "module" misspelled in firmware; "AJ" is the family
lens      :LH3X        <-- the lens model
Watch Dog :Enable
```

The "AJ" identifier is where the project's "AJ protocol" name came from. The
white wire is a **debug / command console**, not a custom binary protocol.

### 2.5 AF UART protocol partial decode

The AF UART (R2 RED/BLACK, 115200 8N1) carries 20-byte frames:

```
06 66 00 60 80 66 E6 80 | [opcode] [...12 payload bytes...]
└────── sync header ────┘   B8       B9..B19
```

**Opcodes observed so far** (B8 byte):

| B8 | When seen | Inferred role |
|---|---|---|
| 0x80 | Boot idle, zoom-click 13% | **Idle heartbeat / motor-stopped** |
| 0x86 | utd 100%, dlr 100%, zoom 11% | **Pan/tilt motor command** |
| 0x60 | zoom-in-HOLD 70%, zoom-in-CLICK 11% | **Zoom motor command (sustained drive)** |
| **0x78** | **zoom-click 38%** *(new 2026-05-16)* | **Motor decel/coast-down OR end-of-travel limit** ⚠ ambiguous — see note below |
| **0x7E** | **zoom-click 24%** *(new 2026-05-16)* | **Settling state OR limit-reached** ⚠ ambiguous |

> ⚠ **0x78/0x7E interpretation uncertain.**  The zoom-click capture may have
> been taken while the lens was at/near the telephoto endstop.  In that case,
> 0x78/0x7E would represent **"can't move further"** notifications rather than
> generic decel.  Discriminate by re-capturing zoom click from the wide end of
> travel (well away from limit) — if 0x78/0x7E still dominate, they're general
> decel codes; if not, they're limit-detection codes.
| 0x1E | Boot init, zoom-HOLD 17%, zoom-CLICK 0% | Command start / motor enable / init |
| 0x18 | Home seek loop | Boot motor command |
| 0x06, 0x00, 0xE0, 0xE6, 0xF8, 0x66, 0x9E, etc. | Boot home-seek phase, rare in motion | Specific sub-commands |

**B9 sub-opcode encodes press type for zoom**:
- **B9 = 0x80** in HOLD's 0x60 frames → continuous-drive sub-opcode
- **B9 = 0x00** in CLICK's 0x60 frames → single-step sub-opcode

(May also apply to pan/tilt opcode-0x86 frames — to be verified once isolated
tilt click/hold captures arrive as Raw Events.)

**For opcode 0x86 frames**:
- B8 = 0x86 (opcode)
- B9 = 0x80 (sub-opcode, constant)
- B10–B14, B19 = variable (encode axis × direction × magnitude × position)
- B15 = 0x00, B17 = 0x00, B18 = 0x00 (constant)
- **B16 = 0x1E** = "motor in motion" status flag
- B12 = 0x06 (and only 0x06) **only appears when PAN moves** — pan-axis indicator
- B11 = 0xE6 **only appears when PAN moves** — pan-axis indicator

### 2.6 940 nm IR LED upgrade selected

Chosen: **6 × Osram SFH 4722BS A01** (OSLON Black, 60° beam, 1320 mW/sr at 1 A
typical, 940 nm centroid). Drive plan: PT4115 with R200 sense → 500 mA constant
current through 6-LED series string (~15 V V_f total, well within PT4115's
30 V output ceiling on the camera's 12 V PoE rail).

IR LED board respin: custom aluminum-core MCPCB from JLCPCB, lead-free HASL,
2 W/m·K dielectric.

---

## 3. What's still open

### 3.1 OpenIPC daemon design (Phase 5)

Will need to:
- Open `/dev/ttyS2` at 115200 8N1
- Send 20-byte AF frames with the sync header + appropriate opcode + payload
- Listen for AF telemetry responses (once the AF telemetry hardware issue is fixed)
- Interpret responses (position feedback, status flags)
- Probably ALSO open `/dev/ttyS3` or whatever maps to the white wire at 9600 baud
  to send ASCII commands (if SoC has any direct connection there) — but more likely
  IR/STC8G commands are routed via the HK32F AF UART relay

Currently blocked on: completing the opcode dictionary (next captures listed below).

### 3.2 AF telemetry line is dead at the probe

The HK32F TX line (R2 BLACK, where HK32F sends responses back to SoC) reads
**1.48 V mid-rail** on a meter — below the AD3 digital input threshold of 1.65 V,
so it always reads as 0. Could be:
- A pull-down in the SoC that the HK32F's open-drain TX isn't fighting hard enough
- A bad probe contact
- A series resistor in the line we haven't identified

Until this is fixed, we only see SoC→HK32F commands (one-way visibility). The
HK32F's responses (which would tell us position feedback, ACKs, etc.) are missing.

**Workaround**: probe upstream — at the HK32F TX pin directly (3p-top "TX" pad) —
might give a stronger signal before the mid-rail clamp.

### 3.3 Stock-firmware login

User got the camera DHCPing again after the recent boot but can't log in to the
web UI. Default credentials to try (in order):

- `admin / admin`
- `admin / 123456`
- `admin / (blank)`
- `admin / 888888`
- `root / topsee`
- `root / cxlinux`
- `default / default`

If none work: 10–15 second reset-button hold on the camera body restores defaults.
Or the SD-card RCE path (`upt_exec` script on FAT32 SD card) can reset the password
file from inside the running stock firmware.

### 3.4 Opcode dictionary completion

Need single-action captures of each motion in isolation to unambiguously map each
byte position to its meaning. With the captures we have:

| Capture | Action | What it taught us |
|---|---|---|
| `newacq0002.csv` | Boot + home seek + early idle | Boot opcodes 0x80, 0x1E, 0x18, and home-seek sub-opcodes |
| `upthendown.csv` (utd) | Several UPs then several DOWNs (tilt) | Opcode 0x86 = motor command; B11=0x78 vs 0x9E (press type) |
| `Downleftright.csv` (dlr) | Mix of holds and clicks on DOWN, LEFT, RIGHT | B11=0xE6 + B12=0x06 only when pan moves; ULN_1-4 = pan stepper |

Captures still needed (each ~20 seconds, single action only):

1. **`panLeft_hold.csv`** — long-hold pan left
2. **`panRight_hold.csv`** — long-hold pan right
3. **`tiltUp_click.csv`** — single short click of tilt up
4. **`tiltDown_click.csv`** — single short click of tilt down
5. **`zoomIn_hold.csv`** — telephoto
6. **`zoomOut_hold.csv`** — wide
7. **`focusNear.csv`** — focus near
8. **`focusFar.csv`** — focus far
9. **`idle_30sec.csv`** — no action (confirms idle opcode = 0x80)
10. **`IRtoggle.csv`** — cover/uncover CDS or toggle via web UI

With these, the full PTZ command dictionary will be unambiguous.

---

## 4. Tooling inventory (in this repo)

### Capture
- **`aj_diff_campaign.ps1`** — dual-port USB-serial capture orchestrator (AF cmd + AF tlm at 115200), drives Hikvision API to trigger PTZ actions
- **`pelco_capture.ps1`** — white-wire capture at **9600 baud** (renamed protocol assumption; was 66666 → 9600 corrected 2026-05-16)
- **`sd_setup.ps1`** — preps a FAT32 SD card with stock-firmware RCE script `upt_exec`

### Extraction (from logic-analyzer captures)
- **`sr_uart_extract.py`** — extract UART bytes from a PulseView `.sr` capture at any channel/baud
- **`wf_csv_uart.py`** — extract UART bytes from a WaveForms "Acquisition" CSV (one column per channel)
- **`wf_csv_multi_uart.py`** — same but processes multiple channels in one pass through the file
- **`wf_events_uart.py`** — extract UART bytes from a WaveForms "Raw Events" CSV (compact, transition-only format)

### Decoding
- **`aj_frame_parser.py`** — extracts 20-byte AF frames using sync header `06 66 00 60 80 66 E6 80`; outputs CSV with per-byte columns
- **`aj_diff_visualizer.py`** — side-by-side capture comparison, flags varying bytes
- **`aj_crc_solver.py`** — brute-forces 50+ CRC polynomials against captured frames (used to disprove CRC hypothesis — trailer bytes are status/telemetry, not CRC)
- **`hk32_stc8g_decoder.py`** — *deprecated for current use* — was for the wrong 66666-baud binary hypothesis; needs to be rewritten for 9600-baud ASCII
- **`pelco_decoder.py`** — *deprecated*, redirect stub pointing at hk32_stc8g_decoder.py

### Analysis
- **`decode_summary.py`** — runs all decoders and produces a one-page summary

### LA hardware
- **`nucleo_la/`** — Nucleo F411RE flashed with LogicalRust (Rust-based SUMP firmware, 5 MS/s, 8 channels). Now superseded by the AD3 (Digilent Analog Discovery 3) at 6.25 MS/s × 16 channels for richer captures.

### Documentation
- **`MC800S-system-map.md`** — master reference (board pinouts, all signals, refined protocol findings) — KEEP UPDATED
- **`README.md`** — project overview, status, tool inventory
- **`HANDOFF.md`** — this file
- **`MC800S-PTZ-STATE.md`** — older state-of-debugging doc (may be stale)

---

## 5. Recent captures and decoded outputs

| File | Source | Channel | Baud | Output | Status |
|---|---|---|---|---|---|
| `capture2.sr`, `capture3.sr` | Nucleo LA boot+idle | D5 | 66666 | superseded — wrong rate | redo at 9600 if needed |
| `acq0001.csv` (11.6 GB) | AD3 134 s full boot | red(HK) | 115200 | `af_cmd.bin` (36,889 bytes, 1435 frames) | analyzed |
| `acq0001.csv` | AD3 | black(HK) | 115200 | `af_tlm.bin` (1 byte) | hardware issue |
| `acq0001.csv` | AD3 | whitewire(HK) | 66666 (wrong) | 339 bytes garbage | discard |
| `newacq0002.csv` (35 KB) | AD3 Raw Events, boot | bit 9 | 9600 | ASCII boot banner | decoded |
| `newacq0002.csv` | AD3 | bit 1 | 115200 | 60 bytes (sparse) | partial |
| `upthendown.csv` | AD3 Raw Events, ups-then-downs | bit 1 | 115200 | `utd_b1_115200.bin` (19,049 bytes, 859 frames, 100% opcode 0x86) | analyzed |
| `Downleftright.csv` | AD3 Raw Events, downs+lefts+rights | bit 1 | 115200 | `dlr_b1.bin` (19,484 bytes, 858 frames, 100% opcode 0x86) | analyzed |

---

## 6. Project status by phase

| Phase | Description | Status |
|---|---|---|
| 0 | Hardware mapping | ✅ done |
| 1 | HK32F SWD dump attempt | ✅ done (negative — chip is locked) |
| 2a | AF UART command capture (R2 RED) | ✅ working — clean frames |
| 2b | AF UART telemetry capture (R2 BLACK) | ❌ hardware issue (line at mid-rail) |
| 2c | White-wire capture | ✅ corrected — line is 9600 ASCII |
| 3 | IR LED PWM path | ✅ resolved (STC8G P1.7 → PT4115 DIM via 1 kΩ) |
| 4a | AF opcode dictionary | 🚧 partial — 0x86, 0x80, 0x1E, 0x18 mapped; full dictionary needs 8 more captures |
| 4b | White-wire ASCII command syntax | ⏳ TBD (need longer capture with commanded actions to see post-boot traffic) |
| 5 | OpenIPC `mc800s-ptzd` daemon | ⏳ blocked on Phase 4 |
| 6 | End-to-end PTZ verification under OpenIPC | ⏳ blocked on Phase 5 |
| 7 | IR LED board respin (940 nm) | 🚧 LEDs chosen; MCPCB design pending |

---

## 7. The next ~2 hours of work, prioritized

1. **Take the 8 remaining single-action captures listed above.** Each ~20 sec.
   Save each as Raw Events CSV (smallest, fastest to process).

2. **Run the wf_events_uart pipeline on each:**
   ```
   python wf_events_uart.py panLeft_hold.csv --target 1 115200 panLeft.bin
   python aj_frame_parser.py panLeft.bin
   ```
   Repeat for each capture.

3. **Cross-correlate the decoded frames** to build the full byte-by-byte
   meaning of opcode 0x86. Should be able to identify which byte = axis,
   which = direction, which = speed.

4. **Verify the idle baseline**: `idle_30sec.csv` should produce frames with
   B8 = 0x80, not 0x86.

5. **Test sending a frame back to the camera**: once we have a confirmed
   "pan right at speed X" frame, transmit it via a USB-serial adapter into
   the AF UART (R2 BLACK side, with the camera disconnected from its SoC).
   The HK32F should respond by driving the motor. This is the proof-of-concept
   for the OpenIPC daemon.

6. **Fix the AF telemetry line** — try probing at HK32F's TX pad directly
   instead of mid-cable.

---

## 8. Reference shortcuts

- Camera IP (DHCP from local network): **was 10.172.220.15 previously, but currently unknown after re-flash**
- Stock fw login: try **admin/admin** first
- Stock backup: `C:\Users\matth\ipcamera\backups\stock_backup_20260501_MC800S_SSC338Q.bin` (MD5 `c405df984c9d3a2692e2b5b99f74fd1a`)
- GitHub repo (current branch `main`): user has it pushed at https://github.com/baitnfatty/OpenIPC_PTZ

---

## 9. Key documents to read first if you're new to this project

1. **CLAUDE.md** — auto-loaded by Claude Code; defines rules for this repo
   including the HANDOFF.md amendment process
2. **MC800S-system-map.md** — read top-to-bottom, especially the "BREAKTHROUGH 2026-05-16"
   sections at the top which contain the most current findings
3. **README.md** — project overview and tool inventory
4. This file (HANDOFF.md)
5. The capture files themselves — try running `python aj_frame_parser.py af_cmd.bin`
   to see decoded protocol bytes

---

## 10. Change log

Append-only log of meaningful updates to this document.  Each entry: date,
short description, optional commit SHA.  Add a new row at the **top** so the
most recent change is always at the top of the log.

| Date | Change | Commit |
|---|---|---|
| 2026-05-16 | **Flagged 0x78/0x7E interpretation as ambiguous** — user noted the zoom-click capture might have been at the telephoto endstop, in which case 0x78/0x7E are limit-reached codes, not generic decel. Added discriminator test (zoom click from wide end). Updated both Section 2.5 and system map breakthrough #5. | *(this commit)* |
| 2026-05-16 | **Zoom click vs hold structurally different** — `zoominclick.csv` shows click introduces opcodes 0x78 (decel) and 0x7E (settle); HOLD is sustained 0x60, CLICK is brief 0x60 burst bracketed by 0x78/0x7E. Also: B9=0x80 (hold) vs B9=0x00 (click) on 0x60 frames suggests B9 is the press-type sub-opcode. | [`d6b6306`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/d6b6306) |
| 2026-05-16 | **Zoom opcode 0x60 discovered** — `zoominhold.csv` decode shows zoom uses a different opcode than pan/tilt (0x86). Opcode dictionary expanded in Section 2.5 + system map breakthrough #4. New tool `wf_rawdata_uart.py` added for streaming Raw Data format. | [`574bb22`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/574bb22) |
| 2026-05-16 | Added Section 0 (amendment process) and Section 10 (this change log); created CLAUDE.md with project-wide rules for keeping HANDOFF.md current across sessions | [`1f6c7f4`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/1f6c7f4) |
| 2026-05-16 | Initial HANDOFF.md creation — captured project state through opcode 0x86 mapping, white-wire 9600 ASCII discovery, and the two single-action captures (`utd`, `dlr`) | [`abe16fa`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/abe16fa) |

---

*Document maintained per the amendment rules in [CLAUDE.md](CLAUDE.md).*
