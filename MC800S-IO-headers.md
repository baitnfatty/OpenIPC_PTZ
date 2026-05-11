# MC800S IO / Distribution Board — Header Pinout

Round board in the dome base. Houses the STC 8G2K325A MCU (Pelco-D motor controller) + ULN2803A Darlington array + audio jacks. The other end of the NET cable plugs in here.

**Known components on this board** (from prior teardown):
- STC 8G2K325A 36I-LQFP32 MCU (Pelco-D motor controller, 8051-derivative)
- ULN2803A Darlington array (stepper coil driver)
- Audio jacks: silkscreen `+SPK-` / `+MIC-`
- Ethernet/power passthrough
- Hand-soldered red rework jumper near TVS1/RU10 = factory ECO (not a fault)

**Pin numbering convention:** for each header, "closest" = closest to the STC8G MCU (or specify reference per header).

---

## NET — 8-pin connector (mirror of SoC board's R1)

The same NET cable terminates here. Colors should match SoC R1.

| SoC R1 pos | Color | Voltage at IO board side | Lands on (chip pin / component) | Notes |
|------------|-------|--------------------------|-------------------------------|-------|
| 1 (closest)  | **red** | **11V** | **Tied to both motor 11V power inputs on distro board** (pan motor + tilt motor) | confirmed: this 11V feeds both steppers |
| 2            | **black** — GND | 0 | (ground plane) | |
| 3            | **green** |  | ? STC8G pin __ / ULN2803A input __ |  |
| 4            | **blue** |  | ? |  |
| 5            | **white** |  | ? |  |
| 6            | **orange** |  | ? |  |
| 7            | **purple** |  | ? |  |
| 8 (furthest) | _empty_ |  |  |  |

Plus the **separately-bundled brown wire** from SoC L1 — does it land on the IO board? Where? (Likely on a discrete pin or solder pad rather than an 8-pin connector position.)

| Wire | Voltage | Lands on | Notes |
|------|---------|----------|-------|
| brown (from SoC L1) |  |  | This wire travels with NET externally but enters the IO board separately |

---

## Audio jacks

### +MIC- (silkscreen)
| Pin (or terminal) | Wire | Voltage | Notes |
|---|---|---|---|
| MIC + | | | |
| MIC - (GND) | | | |

### +SPK- (silkscreen)
| Pin (or terminal) | Wire | Voltage | Notes |
|---|---|---|---|
| SPK + | | | |
| SPK - (GND) | | | |

---

## Ethernet pass-through / RJ45

Pins to RJ45 — typically 4 used (TX+, TX-, RX+, RX-) plus shielding.
| Pin | Function | Voltage / activity |
|-----|----------|--------------------|
|     |          |                    |

---

## Other headers / connectors on the IO board (TBD)

Add as discovered.

| Label | Pin count | Wires populated | Notes |
|-------|-----------|-----------------|-------|
|       |           |                 |       |

---

## STC 8G2K325A MCU pinout reference

LQFP-32 package. Datasheet pin functions:
- VCC / GND, OSC pins
- P0.0-P0.7, P1.0-P1.7, P2.0-P2.7, P3.0-P3.7 (4 ports × 8 pins)
- Some pins double as UART TX/RX (P3.0 = RX, P3.1 = TX on classic 8051)

When tracing NET wires to the STC8G, note which P-port pin each lands on. The two NET wires that end up on STC8G's UART pins (P3.0 / P3.1, or whichever the 8G2K325A uses) are the **Pelco-D communication lines** — these are the SoC↔MCU UART pair we've been hunting for from the SoC side.

---

## ULN2803A pinout reference

DIP-18 (or SOIC-18): 8 input/output pairs.
- Pins 1-8 = inputs (low-current, drive from MCU GPIO)
- Pins 11-18 = outputs (high-current, drive stepper coils)
- Pin 9 = GND, Pin 10 = COM (clamp diodes to motor supply)

Each output pin sinks current from a stepper motor coil. **The four inputs that feed the stepper coil pattern come from the STC8G's GPIO pins.** If any NET wires from the SoC land directly on ULN2803A inputs (bypassing the STC8G), that means stock fires steppers via GPIO bit-bang, not UART.

---

## Open questions to answer with this board

1. **Which two NET wires (of green/blue/white/orange/purple) land on the STC8G's UART pins?** Those are the Pelco-D TX/RX between SoC and MCU.
2. **Does the brown wire (from SoC L1, joins NET externally) land on the STC8G or on the ULN2803A?** That'd reveal what wire #1 actually does.
3. **Do any NET wires bypass the STC8G and go straight to ULN2803A inputs?** If yes, GPIO-direct stepper control is possible.
4. **Which audio jacks are mic vs speaker, and which NET wires (if any) carry their analog signal back to the SoC's audio codec?** R2's 1.48V crossing wire might be one of these.
