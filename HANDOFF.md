# MC800S PTZ Reverse-Engineering — Handoff Document

**Last updated:** 2026-05-20 (Repo cleaned up, glitch parameters documented for public reproducibility)
**Project:** Reverse-engineer the JideTech MC800S PTZ camera so OpenIPC can drive
zoom, focus, pan, tilt, IR LEDs, and the IR-cut filter without the stock proprietary
firmware.

This document is a self-contained snapshot of the project state so any human or LLM
session can pick up where this one left off.

> **Public repo — fork-friendly.** This repo is designed so anyone with an MC800S
> (or similar JideTech AJ-protocol PTZ camera) can clone it, hand `HANDOFF.md` to
> their AI assistant, and pick up right where we left off. All scripts, decode tools,
> and protocol findings are included. The HK32F debug lock bypass is fully
> reproducible — see the [Glitch attack details](#glitch-attack-details-for-reproducibility)
> section for exact hardware and parameters.

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

## 0.5 Getting started (for someone cloning this repo)

If you're here because you have an MC800S (or similar JideTech AJ-protocol camera)
and want to build an OpenIPC PTZ driver, here's the fastest path:

1. **Read this file top-to-bottom.** It's the single source of truth for what's been
   figured out and what's still open.

2. **Read `MC800S-system-map.md`** for the full hardware pinout, signal traces, and
   connector mappings. Everything is traced wire-by-wire.

3. **If your HK32F is still debug-locked** (which it will be from the factory):
   - Build the glitch hardware (P2N2222A + 560Ω + AD3 — see [Glitch attack details](#glitch-attack-details-for-reproducibility))
   - Run `hk32_glitch_and_dump.dwf3script` in WaveForms — it sweeps automatically
   - The **400–700 µs delay range** is where hits concentrate
   - Once unlocked, run `hk32_swd_dump.dwf3script` to extract SRAM + peripheral regs

4. **For AF protocol capture** (SoC ↔ MCU UART at 115200):
   - Hook a logic analyzer onto R2 RED (SoC→MCU) and R2 BLACK (MCU→SoC)
   - Capture while sending PTZ commands through the stock web UI
   - Decode with: `python wf_events_uart.py <capture>.csv --target 1 115200 out.bin`
   - Parse frames: `python aj_frame_parser.py out.bin`

5. **Hand this file to your AI.** It's structured so Claude, ChatGPT, or any LLM can
   understand the full project context and help you continue from here.

---

## 1. What the camera is

| Subsystem | Part | Role |
|---|---|---|
| **SoC** | SigmaStar SSC338Q (IMA80S15 reference board) | Main processor — runs OpenIPC or stock; handles video, web UI, sends AF UART commands |
| **Sensor** | Sony IMX415 (1/2.8", 8.4 MP, 4K UHD) | Image sensor on MIPI-CSI ribbon |
| **Lens MCU** | Hangshun **HK32F030MF4P6** (Cortex-M0, debug lock **permanently destroyed** 2026-05-20, RDP Level 1 still active) | Receives 115200-baud AF protocol (software bit-bang) from SoC, drives BA6208G for zoom/focus DC motors. SRAM + peripheral regs readable via SWD; flash returns 0xAA (RDP). |
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

## 🔥 BREAKTHROUGH 2026-05-20 — Debug lock permanently destroyed + SRAM dumped

Voltage glitch attack on the HK32F030MF4P6 using an AD3 Patterns instrument
(P2N2222A NPN crowbar, 560Ω base resistor, DIO3 trigger) permanently corrupted
the `DBG_CLK_CTL` EEPROM option byte at `0x1FFFF814` from `0x12DE` (locked) to
`0xFFFF` (any value ≠ 0x12DE = unlocked). **Debug access is now permanent —
survives power cycles. No more glitching needed.**

However, **RDP Level 1 remains active** (RDP byte at `0x1FFFF800[7:0]` = 0x00,
FLASH_IF OBR bit 1 = 1). Flash reads return `0xAAAAAAAA`. EEPROM reads also
return `0xAA` — same RDP protection.

### What we extracted

| Region | Bytes | Result |
|--------|-------|--------|
| **SRAM** | **4096 / 4096** | ✅ **Complete** (intermittent bus contention at 0x20000C00 on some runs; succeeded on final run) |
| **EEPROM** | 448 / 448 | Read succeeded but all 0xAA — RDP-protected like flash |
| **Peripheral regs** | All readable | ✅ GPIO A-D, USART1, TIM1/3/14/16/17, SPI1, I2C1, ADC, RCC, SYSCFG, EXTI, IWDG, FLASH_IF, DBGMCU |
| **DMA** | 0 | ❌ Clock disabled (AHBENR bit 0 = 0) — firmware doesn't use DMA |
| **Flash** | 0 useful | All 0xAA (RDP Level 1) |

### Key findings from peripheral registers

- **PA3 = USART1_TX (AF1)** — white wire 9600 baud console. BRR = 0x022C → 5.33 MHz / 556 = 9585 baud
- **PA0 = Input with pull-up** — likely USART1_RX or button
- **PB4 = AF1** — possibly timer or secondary UART-related
- **PC3-PC7 = GPIO Output** — motor control (BA6208G + IR-cut via S5756-A2)
- **PD1-PD4 = GPIO Output** — more motor/control pins
- **PD5 = Alternate Function with pull-up** — possibly SWD or secondary function
- **APB2ENR = 0x4000** → only USART1 clocked. **No second hardware UART exists.**
- **The 115200 AF UART to the SoC is software bit-banged** — confirmed by absence of any other UART peripheral clock. Uses tight delay loops (~46 CPU cycles per bit at 5.33 MHz), NOT timer interrupts.
- **TIM2 is the ONLY active timer**: PSC=0, ARR=3333 → **1600 Hz** interrupt. This is the **motor step base timer**. Combined with step profile (8,8,8,6,6,6,4,4,4): slowest = 200 steps/sec, fastest = 400 steps/sec — ideal range for 24BYJ48 steppers.
- **Only 2 NVIC interrupts enabled**: IRQ 15 (TIM2) + IRQ 27 (USART1). All default priority. Extremely simple interrupt structure.
- **SysTick running at 333 Hz** (RVR=15999, 3ms period). General-purpose tick for delay functions.
- **VTOR = 0x00000000** — vector table at flash base (not relocated to SRAM). CPUID = ARM Cortex-M0 r0p0.
- **IWDG not configured** (default values: RLR = 0x0FFF, KR = 0). Firmware's "Watch Dog :Enable" banner refers to software watchdog logic, not hardware IWDG.
- **No SPI, I2C, ADC, or DMA active** — firmware is very simple
- **Clock: HSI 32 MHz / 6 = 5.33 MHz**, zero flash wait states, no PLL

### Key findings from SRAM

- **Motor step profile at 0x2000008C**: `08 08 08 06 06 06 04 04 04` — 9-byte acceleration ramp (step delays decrease: 8→6→4) for stepper motor control
- **Stack frames with flash pointers** (0x2000044C-0x200004C4): Contains EXC_RETURN values (0xFFFFFFF1, 0xFFFFFFF9) proving nested interrupt execution. Flash function addresses extracted: `0x080005FB`, `0x08003358` (appears 4×, hot path), `0x08000883` (2×), `0x080007CB`, `0x08001BB0`, `0x080024A7`, `0x08002F0E`. USART1 base `0x40013800` on stack confirms UART handler was active.
- **AF protocol buffer** (0x200004C4-0x20000BFC): ~1.8 KB of high-entropy data — almost certainly the TX/RX buffer for the 115200 AF protocol to/from the SoC
- **Timer values**: 0x3E8 (1000) and 0x3E3 (995) suggest a 1-second tick timer

### Glitch attack details (for reproducibility)

**Hardware setup:**
- **Glitch transistor**: P2N2222A NPN, collector → HK32F VDD (pin 9), emitter → GND
- **Base resistor**: 560Ω from AD3 DIO3 to base
- **Mechanism**: DIO3 HIGH → transistor saturates → VDD crowbarred to GND → supply
  collapses for the glitch duration → DIO3 LOW → VDD recovers via LDO
- **AD3 connections**: DIO0 → SWDIO, DIO1 → SWCLK, DIO2 → NRST, DIO3 → 560Ω → base
- **Monitoring**: Scope Ch1 on VDD to verify glitch depth (should dip below 1.8V POR threshold)

**Attack parameters (what actually worked):**
- **Pattern rate**: 10 MHz (100 ns/sample resolution) for fine timing control
- **Delay sweet spot: 400–700 microseconds** after NRST release — this is when the
  HK32F reads the `DBG_CLK_CTL` option byte from flash. Hits were concentrated here.
  First confirmed single-point success was at **750 µs delay, 1.5 µs width** (found
  by `hk32_glitch_unlock.dwf3script`), with the automated 2D sweep
  (`hk32_glitch_and_dump.dwf3script`) showing dense hits across 400–700 µs.
- **Glitch widths**: Both narrow (100–500 ns, corrupts the flash bus read) and wide
  (1.0–2.5 µs, pulls VDD below POR threshold) produced unlocks. The narrow pulses
  corrupt the data on the bus during the option byte read; the wide pulses trigger a
  partial POR that resets the debug-lock latch without fully resetting the CPU.
- **Sweep strategy**: 3-phase approach:
  1. **Phase 1** — narrow pulses (100–500 ns) across 400–900 µs delay, 15 µs steps, 3 reps
  2. **Phase 2** — wide pulses (1.0–2.5 µs) across same delay range
  3. **Phase 3** — full range 0–4500 µs with mixed widths, 50 µs steps (catches outliers)
- **Reset timing**: 120 µs NRST hold (low), then release. 1300 ms boot wait before SWD probe.

**Why it became permanent:**
- VDD overshoot on crowbar release hit **~4.5 V** (absolute max rating is 4.0 V).
  The repeated over-voltage spikes during the sweep permanently corrupted the
  `DBG_CLK_CTL` EEPROM byte at `0x1FFFF814` from `0x12DE` → `0xFFFF`.
  Any value ≠ `0x12DE` = debug clock enabled. **Survives power cycles permanently.**
- A **10Ω series resistor on the collector** would damp the overshoot and keep it
  within spec if you want a temporary (per-boot) bypass without permanent damage.
  We didn't install one — the permanent unlock was a happy accident.

**Known issues during development:**
- A JavaScript **signed-integer comparison bug** in the dump script (`if (stat >= 0xF0000000)`)
  caused all dumps to fail silently — JS treats `0xF0000000` as negative in 32-bit.
  Fixed by using `>>> 28` unsigned right shift instead. All scripts in the repo have this fix.
- **SWD probe connections are fragile** — intermittent ACK=5 or ACK=0 errors.
  Retry and reseat probes if SWD reads fail.

### Scripts

- **`hk32_glitch_and_dump.dwf3script`** — all-in-one 3-phase voltage glitch sweep + SWD dump. 10 MHz pattern rate, auto-detects unlock, attempts full memory dump.
- **`hk32_swd_dump.dwf3script`** — standalone SWD dump script. Reads SRAM first (most valuable), then EEPROM, then all peripheral registers. Includes AP reinit between regions to prevent accumulated AHB-AP state corruption.
- Output files: `sram_periph_dump.txt`, `flash_dump.txt`, `glitch_log.txt`

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

### 2.2 HK32F silicon lock (Phase 1) — BYPASSED [SUPERSEDED 2026-05-20 — see "BREAKTHROUGH 2026-05-20" above]

> ~~**[CORRECTED 2026-05-20]**~~ — superseded by breakthrough section above. Preserved for traceability:
>
> HK32F030MF4P6 has `DBG_CLK_CTL = 0x12DE` set, which gates the debug clock at
> silicon level. Confirmed unreachable via CubeProgrammer (8 frequencies), OpenOCD
> (3 configs), and HLA-mode SWD. **No software-only path to dump the firmware
> exists.** Plan B: hot-air swap a fresh chip with our own firmware (dev boards
> already on order).

**2026-05-20 update:** Voltage glitch attack permanently destroyed the debug lock
(DBG_CLK_CTL now reads 0xFFFF). SWD access is fully functional. However, RDP
Level 1 (flash readout protection) remains active — flash and EEPROM return 0xAA.
SRAM and peripheral registers are readable. See breakthrough section above for
full details.

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
| 0x80 | Boot idle, low % in active captures | **Idle heartbeat / motor-stopped** |
| 0x86 | utd 100%, dlr 100%, zoom 11%, zoomIn+AF 27% | **Pan/Tilt motor command** (also AF auto-firing concurrently during zoom) |
| 0x60 | zoom-in-HOLD 70%, zoom+AF 22% | **Zoom motor command (sustained drive)** |
| **0x1E** | **iris0004 = 100%, iris0005 = 100%** *(corrected 2026-05-16)* | **🎯 IRIS adjustment** (previously misclassified as "init/start" — iris commands appear at boot AND during zoom for lighting compensation, seeding the confusion) |
| **0x9E** | **focus0002 = 45%, focus0003 present, zoom+AF mixed** *(new 2026-05-16)* | **🎯 FOCUS motor command** |
| 0x98 | Focus & zoom+AF captures only | Focus settling / sub-state |
| 0x66, 0x78, 0x7E | Click follow-throughs, zoom transitions | Decel/settle/transition states (or end-of-travel — TBD) |
| 0xE0 | Rare home-seek substate | Boot/home-seek only |

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

### Glitch attack + SWD dump (AD3 WaveForms scripts)
- **`hk32_glitch_and_dump.dwf3script`** — 3-phase 2D voltage-glitch sweep (delay × width × repeats) + SWD bit-bang dump. Fires patterns at 10 MHz via DIO2 (NRST) and DIO3 (glitch). On unlock detection, attempts full memory dump. Includes incremental chunk-per-glitch mode.
- **`hk32_swd_dump.dwf3script`** — standalone SWD dump via StaticIO bit-bang. Reads SRAM first, then EEPROM, then all peripheral registers with AP reinit between each region. Output → `sram_periph_dump.txt`.
- **`hk32_glitch_sweep_v3.dwf3script`** — earlier glitch sweep variant (reference only)

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
| 1a | HK32F debug lock bypass | ✅ **DONE** — lock permanently destroyed via voltage glitch (DBG_CLK_CTL = 0xFFFF) |
| 1b | HK32F memory extraction | ✅ done — **full 4KB SRAM** + all peripheral registers dumped. Flash/EEPROM blocked by RDP Level 1 (returns 0xAA). Enough data extracted for OpenIPC integration. |
| 2a | AF UART command capture (R2 RED) | ✅ working — clean frames |
| 2b | AF UART telemetry capture (R2 BLACK) | ❌ hardware issue (line at mid-rail) |
| 2c | White-wire capture | ✅ corrected — line is 9600 ASCII |
| 3 | IR LED PWM path | ✅ resolved (STC8G P1.7 → PT4115 DIM via 1 kΩ) |
| 4a | AF opcode dictionary | 🚧 partial — 0x86, 0x80, 0x1E, 0x18 mapped; **next: full protocol capture with AD3 logic analyzer** |
| 4b | White-wire ASCII command syntax | ⏳ TBD (need longer capture with commanded actions to see post-boot traffic) |
| 5 | OpenIPC `mc800s-ptzd` daemon | ⏳ blocked on Phase 4 |
| 6 | End-to-end PTZ verification under OpenIPC | ⏳ blocked on Phase 5 |
| 7 | IR LED board respin (940 nm) | 🚧 LEDs chosen; MCPCB design pending |

---

## 7. The next ~2 hours of work, prioritized

**Context (2026-05-20):** Debug lock is permanently gone. We have the full MCU
peripheral configuration and 3KB of SRAM. The AF UART is confirmed as 115200 baud,
software bit-banged on the MCU side. The missing piece is the **AF protocol frame
format** — we need live captures of actual PTZ commands.

1. **AF protocol capture with AD3 logic analyzer.** Hook the AD3's logic channels
   onto the AF UART lines (R2 RED = SoC→MCU, R2 BLACK = MCU→SoC). Use the stock
   camera web UI to send PTZ commands while recording. Save as Raw Events CSV.
   Key captures needed:
   - Idle (30 sec, no action)
   - Pan left hold, pan right hold
   - Tilt up hold, tilt down hold
   - Zoom in hold, zoom out hold
   - IR toggle (cover/uncover CDS)

2. **Decode captured frames** with the existing pipeline:
   ```
   python wf_events_uart.py <capture>.csv --target 1 115200 <output>.bin
   python aj_frame_parser.py <output>.bin
   ```

3. **Cross-correlate** to build the full byte-by-byte command dictionary.

4. **Fix the AF telemetry line** — try probing at HK32F's TX pad directly
   instead of mid-cable. The R2 BLACK line reads 1.48V mid-rail.

5. **Test sending a frame** to the camera via USB-serial adapter into R2 BLACK.
   If the HK32F drives a motor, that's the proof-of-concept for the OpenIPC daemon.

**Deferred (low priority):**
- CPU halt to read last 1KB of SRAM (0x20000C00-0x20000FFF) — marginal value,
  risk of motor driver damage if outputs are HIGH when halted
- RDP removal (write RDP=0xA5 to option bytes) — triggers mass erase, destroys
  firmware. Only useful if we plan to write replacement firmware from scratch.
- Install 10Ω collector damping resistor on glitch transistor (prevents 4.5V
  overshoot, but glitching is no longer needed)

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
| 2026-05-20 | **Repo cleanup + public reproducibility.** Removed 118 capture data files (4.3 MB) from tracking — all regeneratable, findings documented here. Added comprehensive .gitignore. Updated glitch attack section with accurate parameters: **400–700 µs delay sweet spot**, both narrow (100–500ns) and wide (1–2.5µs) widths worked, 4.5V overshoot is what permanently killed the lock. Added "Getting started" section for public repo users. Fixed Phase 1b status to reflect full 4KB SRAM dump. | *(this commit)* |
| 2026-05-20 | **🔥 Debug lock permanently destroyed + SRAM/peripheral dump complete.** Voltage glitch attack (AD3 Patterns, P2N2222A crowbar, 10 MHz) permanently corrupted DBG_CLK_CTL from 0x12DE→0xFFFF. SWD now works after power cycle. RDP Level 1 still active (flash/EEPROM return 0xAA). Extracted 3KB/4KB SRAM (active stack area blocked last 1KB), all peripheral registers. Key findings: AF UART is software bit-banged (no second hardware USART), motor step profile found in SRAM (08-08-08-06-06-06-04-04-04), flash function addresses recovered from stack frames, IWDG not used, no DMA/SPI/I2C/PWM. Fixed critical JS signed-integer comparison bug in SWD scripts. Added AP reinit between memory regions to fix TAR write failures. Phase 1 complete. Shifting to AF protocol capture. | *(this commit)* |
| 2026-05-16 | **Corrected `DBG_CLK_CTL` address** + bootloader-dead conclusion authoritatively confirmed. User provided the actual HK32F030M datasheet (Rev 1.2.0, 2021-11-23) which corrects two things: **(1)** `DBG_CLK_CTL[15:0]` lives at flash option word `0x1FFF_F814`, not `0x1FFF_F810` as previously stated (the `_F810` slot is actually `IWDG_INI_KEY[15:0] / IWDG_RL_IV[11:0]`).  Glitch attack target updated to the correct address. **(2)** The previous research conclusion that the M-variant has no ROM bootloader is now confirmed end-to-end from the authoritative Hangshun document: no "Boot mode" section, no BOOT0 pin, no system memory region in the memory map, only USART1 (no USART2). The "boot message" we see on the white wire at 9600 baud ASCII is the **application firmware's** printf banner ("version :1.20 / lens :LH3X / Watch Dog :Enable"), not a ROM bootloader protocol. System map updated with non-destructive correction markers per CLAUDE.md Rule 2. Also added M-variant peculiarities section (only USART1, separate EEPROM region, 64-bit UID, four available packages SON8/TSSOP16/TSSOP20/QFN20). | *(this commit)* |
| 2026-05-16 | **B15 = direction byte (confirmed)** + opcode hypothesis revision. New batch of 13 isolated captures (panL/R, tiltU/D, speeds, zoom variants, iris) shows: B15=0x06 → LEFT/UP, B15=0x60 → RIGHT/DOWN (same encoding across both axes). **However the previous "B8 = subsystem opcode" theory is wrong** — short isolated captures show 0x98 dominant in pan/tilt/iris captures (which earlier theory called "focus settling state"). Revised hypothesis: **B8 = motor phase / frame type** (not subsystem), with previous "100% 0x86" captures being only the sustained-continuous-motion phase. User clarified focus0002/0003 from prior batch were focus NEAR vs focus FAR (focus near has more motor travel → 0x9E dominant; focus far has more iris compensation → 0x1E dominant). User confirmed no probe changes between batches. | *(this commit)* |
| 2026-05-16 | **🎯 Iris=0x1E + Focus=0x9E discovered** — batch of 9 isolated captures (focus×3, iris×2, zoom+AF×4) decoded. Both iris captures are 100% opcode 0x1E, proving 0x1E is the IRIS opcode (not "init/start" as previously thought — that was just because iris fires at boot). Focus captures dominated by new opcode 0x9E (44.6% in focus0002). 0x98 also appears in focus/zoom+AF combos as a focus sub-state. Full subsystem opcode map: pan/tilt=0x86, zoom=0x60, iris=0x1E, focus=0x9E, idle=0x80. **0x86 reclassified back from "general lens motor" to "pan/tilt specific"** — the AF-during-zoom traffic is actually B8=0x9E (focus), not B8=0x86. Section 2.5 + system map updated. **NOTE 2026-05-16 evening**: subsequent batch revised this — B8 is more likely motor PHASE not subsystem. | [`cbe3c6d`](https://github.com/baitnfatty/openipc_ptz/commit/cbe3c6d) |
| 2026-05-16 | **Refined 0x86 interpretation** — user observed that during continuous zoom, AF never gets time to settle and keeps re-firing. (Note: subsequent capture analysis showed the 0x86 frames in zoom were ALSO pan/tilt — likely incidental motion. The TRUE AF opcode is 0x9E, discovered separately.) | [`eaa65a6`](https://github.com/baitnfatty/openipc_ptz/commit/eaa65a6) |
| 2026-05-16 | **Flagged 0x78/0x7E interpretation as ambiguous** — user noted the zoom-click capture might have been at the telephoto endstop, in which case 0x78/0x7E are limit-reached codes, not generic decel. Added discriminator test (zoom click from wide end). Updated both Section 2.5 and system map breakthrough #5. | [`64160c7`](https://github.com/baitnfatty/openipc_ptz/commit/64160c7) |
| 2026-05-16 | **Zoom click vs hold structurally different** — `zoominclick.csv` shows click introduces opcodes 0x78 (decel) and 0x7E (settle); HOLD is sustained 0x60, CLICK is brief 0x60 burst bracketed by 0x78/0x7E. Also: B9=0x80 (hold) vs B9=0x00 (click) on 0x60 frames suggests B9 is the press-type sub-opcode. | [`d6b6306`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/d6b6306) |
| 2026-05-16 | **Zoom opcode 0x60 discovered** — `zoominhold.csv` decode shows zoom uses a different opcode than pan/tilt (0x86). Opcode dictionary expanded in Section 2.5 + system map breakthrough #4. New tool `wf_rawdata_uart.py` added for streaming Raw Data format. | [`574bb22`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/574bb22) |
| 2026-05-16 | Added Section 0 (amendment process) and Section 10 (this change log); created CLAUDE.md with project-wide rules for keeping HANDOFF.md current across sessions | [`1f6c7f4`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/1f6c7f4) |
| 2026-05-16 | Initial HANDOFF.md creation — captured project state through opcode 0x86 mapping, white-wire 9600 ASCII discovery, and the two single-action captures (`utd`, `dlr`) | [`abe16fa`](https://github.com/baitnfatty/OpenIPC_PTZ/commit/abe16fa) |

---

*Document maintained per the amendment rules in [CLAUDE.md](CLAUDE.md).*
