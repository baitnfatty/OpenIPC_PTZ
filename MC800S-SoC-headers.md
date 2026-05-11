# MC800S SoC Board — Header Pinout (with voltages)

Board: SSC338Q_V2.1, dated 20210604.

**Pin numbering convention:** for each header, "closest" = closest to the SoC chip side. Voltages with camera fully booted into OpenIPC, idle.

**Important note:** the brown wire on L1 is **separate** from the R1 (NET cable) connector — it gets bundled with the NET cable externally but isn't one of the 7 R1 pins.

---

## T1 — 3-pin top-center

**No voltages currently present** (when we ran the earlier GPIO-toggle scan, this is where PAD_GPIO0 / sysfs gpio 59 surfaced as 3.3V — but only when driven as output HIGH; in idle/input mode it floats to 0V).

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (left)   | _bare_ — **GND** | 0 | ground |
| 2 (middle) | _bare_ | 0 (floating) | likely PAD_GPIO0 (sysfs gpio 59) — surfaces as 3.3V when driven output HIGH |
| 3 (right)  | _bare_ | 0 (floating) | unknown — possibly second pin of UART0 (RX?) or another GPIO |

---

## L1 — 2-pin top-left

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (closest)  | _bare_ — **GND** | 0 | ground |
| 2 (furthest) | **brown** | **3.18V steady** | bundled with NET cable, hits SoC pad PM_GPIO4 (sysfs gpio 10) — slight drop from 3.3V suggests pull-up via series resistor |

---

## L2 — 4-pin middle-left

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (closest)  | **black** — **GND** | 0 | ground |
| 2            | _bare_ | 0 | (likely GPIO unconfigured / floating) |
| 3            | _bare_ | 0 | (likely GPIO unconfigured / floating) |
| 4 (furthest) | _bare_ | 0 | (likely GPIO unconfigured / floating) |

---

## L3 — 4-pin bottom-left

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (closest)  | _bare_ — **GND** | 0 | ground |
| 2 (closest red, "Red2") | **red #2** | **1.42V steady** | electret mic bias |
| 3 (further red, "Red1") | **red #1** | **~0.5V bouncy** (AC content) | active audio signal — could be mic OUT (post-amp) or a separate audio line |
| 4 (furthest) | **black** — **GND** | 0 | ground |

---

## R1 — 8-pin top-right (NET cable to distribution board)

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (closest)  | **red** | **11V** | PoE-derived power → IO board |
| 2            | **black** — **GND** | 0 | ground |
| 3            | **green** | **0** | signal (no voltage at idle) |
| 4            | **blue** | **0** | signal (no voltage at idle) |
| 5            | **white** | **0** | signal (no voltage at idle) |
| 6            | **orange** | **0** | signal (no voltage at idle) |
| 7            | **purple** | **0** | signal (no voltage at idle) |
| 8 (furthest) | _empty_ |  |  |

---

## R2 — 4-pin bottom-right

Two wires in middle positions cross horizontally above the heatsink.

| Pin | Color | Voltage | Destination |
|-----|-------|---------|-------------|
| 1 (closest)  | _bare_ — **GND** | 0 | ground |
| 2            | **red** (crossing wire) | **0V** | crosses board → ? (likely audio GND given color reversal pattern) |
| 3            | **black** (crossing wire) | **1.48V** | crosses board → ? (likely mic bias, color convention reversed) |
| 4 (furthest) | _empty_ — **GND** | 0 | ground |

---

## B1 — 2-pin underside header (unpopulated)

Bottom side of SoC board, both pins exposed.

| Pin | Voltage | Notes |
|-----|---------|-------|
| 1 (closest)  | **3.3V** | bare — **silent on USB-serial RX at all bauds tested** — could be passive 3.3V tap, internal pull-up, or idle UART with no OpenIPC traffic |
| 2 (furthest) | 0 (presumed GND) | bare |

---

## FFC ribbon (bottom edge)

To 2nd board (sensor / microSD daughterboard). **Do not probe.**

---

# Summary & Key Findings

## Power and ground
- **R1 pin 1 (red)** = 11V PoE feed to IO board
- **R1 pin 2 (black)**, **L1 pin 1**, **L2 pin 1 (black)**, **L3 pin 1 + pin 4 (black)**, **R2 pin 1 + pin 4** = all GND
- **B1 (underside) pin 1 (closest)** = 3.3V (silent on USB-serial — passive tap or unused UART)

## Wire #1 (brown — known)
- L1 pin 2 → PM_GPIO4 (sysfs gpio 10) → bundled with NET cable externally
- Idles at 3.18V (pull-up suggests passive control signal, not driven UART)

## Wire #2 (the second 3.3V wire on NET — STATUS REVISED)
- **Not on R1.** All R1 signal pins (green/blue/white/orange/purple) read 0V at idle.
- **Likely candidate: B1 (underside) at 3.3V.** Need to trace its destination — does it route into the NET bundle externally like the brown wire does?

## Audio
- L3 (4-pin) and R2 (4-pin) both have a pin at ~1.4-1.5V — classic electret mic bias.
- Color convention is **reversed** (black = signal/bias, red = GND) — common Chinese OEM quirk.
- L3 likely = mic input header. R2 likely = also audio (second mic? speaker? to lens module?).

## R1 signal pins (5 wires green/blue/white/orange/purple)
- All 0V at idle. These are likely:
  - Stepper motor coil drive returns from STC8G (idle low when no motor command)
  - OR control signals from STC8G to SoC (status / limit switches / etc.)
- They don't carry UART data (UART idles HIGH at Vcc, not 0V).

## Critical reframing
- We were told "two 3.3V wires on NET" but **there is only ONE** (the brown wire on L1, externally bundled). The second 3.3V we've been hunting may have been the **underside header pin** mis-attributed to the NET bundle.

# Next steps to investigate

1. **Trace B1 closest pin (3.3V)** — continuity to any R1 pin / brown wire / known GND? Identify which SoC pad it routes to (run the GPIO toggle scan with probe on B1 to find the pad).
2. **Drive bytes from every OpenIPC ttyS<n> at 2400/9600/115200** while listening on B1 — see if any combo makes B1 dance.
3. **L2 voltages** confirmed all 0V on bare pins (defaulted from "any not listed = 0").
4. **R2 destination** — find where the crossing wires (red/black) terminate on the other side of the board.
