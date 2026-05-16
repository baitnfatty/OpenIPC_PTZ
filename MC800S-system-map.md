# MC800S System Map — All Boards (Master Reference)

**Updated 2026-05-04** — incorporated phonehome report findings + offline RE results.

---

## ⚠️ CRITICAL FINDINGS (Don't Overlook These!)

### 1. STOCK SUPPORTS TWO MOTOR CONTROL METHODS

This is the biggest insight. Stock can drive pan/tilt steppers in two completely different ways:

**Method 1: Direct SoC GPIO/PWM bit-banging via kernel driver** ← MAY BE OUR ACTUAL PATH
- `/dev/motor` (char device, major 99)
- `/sys/devices/virtual/mstar/motor/group_{begin,end,enable,period,polarity,round,round_get,stop}`
- Selected by flag file: `/opt/ch/motor_ctrl_use_pwm.flag`
- **Bypasses STC8G MCU entirely** — drives ULN2803A inputs directly from SoC GPIOs
- Source: phonehome report Section 12

**Method 2: External MCU via UART (Pelco-D 2400 to STC8G)**
- `/dev/ttyS1` for pan/tilt UART
- Used when PWM flag is NOT present

**ACTION ITEM:** When camera is back on stock, check `ls /opt/ch/motor_ctrl_use_pwm.flag`. Presence determines which method is active. **If Method 1 is active, the entire "PM_GPIO4 brown wire UART pinmux" path is unnecessary** — we just need OpenIPC's existing `sigmastar-motors` package configured for the right GPIOs.

### 2. ZOOM/FOCUS PROTOCOL: VISCA (per phonehome report) NOT custom "AJ"

Phonehome report Section 12 explicitly states:
```
/dev/ttyS2 — Zoom/focus motor MCU (VISCA, 9600 baud)
```

We tried VISCA at 9600 with no response. Possible reasons:
- HK32F not currently powered (verify SS24-jumpered red wire on HK32F 2p-top has 3.3V)
- HK32F needs hardware reset before responding
- Address byte different from standard VISCA 0x81 (try 0x82, 0x83, 0x88 broadcast)
- Stock has additional init we haven't replicated

### 3. SD CARD AUTO-UPDATE FILENAME (NOT TFTP)

IPL string: `anjvision_autoupdate::MC800S2_V0`

This is the **SD card** firmware update filename (corrected by user 2026-05-04). When an SD card is inserted with a file matching this prefix, the IPL/U-Boot will load and flash it. **Not** the TFTP recovery path.

**Actual TFTP recovery filename: still TBD** — the project memory note "MC800S_V2: Send upgrade request, ready to receive..." suggests TFTP is also supported, but the exact filename would need UART capture during a boot attempt while TFTPd32 is running. Could be `MC800S2_V0`, `update.bin`, or something else.

### 4. KERNEL CONSOLE BAUD = 38400 (NOT 115200)

Stock DTS bootargs: `console=ttyS0,38400n8r` (38400 baud, 8N1, RTS/CTS hw flow control)

The trailing `r` requires RTS/CTS! PuTTY config must include hardware flow control to receive cleanly.

U-Boot itself runs at 115200 (its env says `baudrate=115200`). So during boot you see:
- Brief 115200 burst (U-Boot)
- Long 38400 stream (kernel)

### 5. STOCK ASSERTED GPIOs (extracted from binary)

```
echo out > /sys/class/gpio/gpio16/direction
echo out > /sys/class/gpio/gpio17/direction
echo out > /sys/class/gpio/gpio61/direction
echo out > /sys/class/gpio/gpio80/direction

# Toggle patterns:
echo 1/0 > /sys/class/gpio/gpio36/value   # IR LED?
echo 0   > /sys/class/gpio/gpio37/value   # IR LED enable LOW?
echo 1/0 > /sys/class/gpio/gpio53/value   # IR-cut H-bridge half
echo 1/0 > /sys/class/gpio/gpio61/value   # IR-cut H-bridge half  
echo 1/0 > /sys/class/gpio/gpio80/value   # ??? (sensor pin per gpio.h)
```

Plus PWM-based control on `/sys/class/pwm/pwmchip0/pwm{0,1,5,8,9}/duty_cycle`.

---

## SoC board is generic — IMA80S15 reference design

The MC800S SoC main board is **CCDCAM IMA80S15** (per their datasheet). This is a generic
camera module with NO native PTZ support. All PTZ functionality is delegated to
subordinate MCUs:

- **Zoom + focus** = HK32F030M lens MCU (via AF UART on J2 = R2 RED/BLACK)
- **Pan + tilt** = STC8G2K325A distro MCU (via Pelco-D UART on a CUSTOM header not
  in the IMA80S15 datasheet — uses PM_GPIO4 brown wire to L1, then through NET cable
  to distro board)

The SoC just provides:
- Ethernet (J1) for network
- AF UART (J2) for lens MCU
- Audio I/O (J3)
- USB (J4 — unused on MC800S, only GND wired as ref to lens board)
- Reset (J5)
- PWM dimming for IR + warm LEDs (J6)
- CDS ambient light ADC input (J7)
- IR-cut H-bridge output (J8)
- Custom add-on tap for Pelco-D UART to STC8G (PM_GPIO4 → L1 brown wire)

**Implication for OpenIPC daemon**: must drive BOTH /dev/ttyS2 (AF protocol to HK32F)
AND /dev/ttyS1 (Pelco-D to STC8G) to control zoom/focus AND pan/tilt respectively.

## Board inventory (7 PCBs + 2 motors)

| # | Board | Location | Key ICs | Function |
|---|-------|----------|---------|----------|
| 1 | **SoC Main Board** | gimbal housing | SSC338Q | Main processor, runs OpenIPC |
| 2 | **Sensor Board** | gimbal housing | IMX415 (1/2.8" format, 6.46mm diagonal, 5.6×3.2mm active area, 3864×2192 / 8.4MP, 1.45μm pixel pitch, 4K UHD output) | 4K image sensor, MIPI-CSI ribbon to SoC |
| 3 | **IR LED Board** | gimbal housing | 4× 850nm IR LEDs (SMD, amber/yellow lens, faint red glow), CdS photoresistor | Night vision illumination + ambient light sensing. **Dumb board** — no driver onboard, just LEDs + sensor. CDS connects to STC8G on distro board, NOT directly to SoC. |
| 4 | **SD Card Board** | gimbal housing | TF100/AJ/HX markings | microSD slot, ribbon to SoC top |
| 5 | **HK32F030 Board** | gimbal housing | HK32F030MF4P6 (Cortex-M0, debug-fused via DBG_CLK_CTL=0x12DE), BA6208G (DC motor driver), S5756-A2 (IR-cut filter actuator coil) | Zoom/focus DC motor control via 115200 8N1 AJ protocol on /dev/ttyS2. Has J3 5-pin SWD header (effectively bricked due to debug fuse). |
| 6 | **Distribution Board** (round) | gimbal base | STC8G2K325A (8051 MCU, also reads CDS ambient light), ULN2803A (Darlington array), PT4115 (LED driver), SS24 (Schottky power diode) | Pan/tilt stepper control + IR LED driver. PT4115 drives LED string with constant current; ULN2803A pin 17 (output 2C) is the LED on/off switch from SoC. STC8G handles CDS → ambient light reading; day/night decision likely flows back to SoC via Pelco-D UART or autonomously controlled by STC8G. |
| 7 | **PoE Board** | gimbal base | SDaPo PM3812R | PoE 48V → 12V/5V/3.3V rails |

Plus: 2× 24BYJ48 12V stepper motors (pan + tilt).

---

## SoC Board Header Pinout (from in-camera probing + photo analysis)

### T1 — 3-pin top-center
| Pin | Color | Voltage | Notes |
|-----|-------|---------|-------|
| 1 (left)   | bare GND | 0 | ground |
| 2 (middle) | bare | 0 (floating) | likely PAD_GPIO0 (sysfs gpio 59) — surfaces as 3.3V when driven HIGH |
| 3 (right)  | bare | 0 (floating) | unknown |

### T1 — 3-pin top-center (= IMA80S15 datasheet J6 — PWM header) — CONFIRMED via photo
| Pin | Label (silkscreen) | Function | Status on MC800S |
|-----|---|---|---|
| 1 (left)   | GND | ground | **unpopulated — no wire** |
| 2 (middle) | PWM1 | SoC PWM1 output (IR LED dimming in IMA80S15 ref design) | **unpopulated — no wire** |
| 3 (right)  | PWM0 | SoC PWM0 output (warm LED dimming in IMA80S15 ref design) | **unpopulated — no wire** |

**MC800S does not use the SoC's PWM peripheral for any LED control.** All IR LED
control (on/off + brightness) is delegated to the STC8G on the distro board.

### L1 — 2-pin top-left (= IMA80S15 datasheet J5 — RESET) — FULLY TRACED
| Pin | Color | Datasheet name | Voltage | Notes |
|-----|-------|---------------|---------|-------|
| 1 (closest)  | bare | GND | 0 | ground |
| 2 (furthest) | brown | RESET | 3.18V | **SoC NRST line** — hardware reset button signal |

**Full trace**:
```
SoC J5 Pin 1 (RESET) ─→ brown wire ─→ Distro board NET connector Pin 6
                                          │
                                          └→ Distro POE connector (white wire)
                                                │
                                                └→ POE board ─→ brown wire on POE board
                                                                 │
                                                                 └→ HARDWARE RESET BUTTON
                                                                    (camera body pinhole)
```

So pressing the camera's external reset button propagates back through POE → distro → SoC J5,
pulling the SoC's NRST low and rebooting the camera.

**Method 2 (UART Pelco-D to STC8G via brown wire) is officially RULED OUT**. The brown wire
is purely a reset signal pass-through, not data.

**STILL OPEN**: how does pan/tilt control actually reach the STC8G?
- Method 1 (direct GPIO bit-bang) via undocumented pads is the leading hypothesis
- OR a different wire in the NET cable that we haven't traced yet
- OR the STC8G is more autonomous than we thought
- Phase 1 SD card RCE will resolve this definitively

### L2 — 4-pin middle-left
| Pin | Color | Voltage |
|-----|-------|---------|
| 1 (closest, black GND) | black | 0 |
| 2-4 | bare | 0 |

L2 black wire goes to HK32F 2p-top "Black" position.

### L3 — 4-pin bottom-left (= IMA80S15 datasheet J3 — Audio)
| Pin | Color | Datasheet name | Voltage | Notes |
|-----|-------|---------------|---------|-------|
| 1 (closest) | bare GND | GND | 0 | ground |
| 2 (closest red) | red | AUDIO_OUT | 1.42V steady | External speaker drive (DC bias for power amp) |
| 3 (further red) | red | AUDIO_IN | ~0.5V bouncy | Mic pickup (active/passive mic input) |
| 4 (furthest, black GND) | black | GND | 0 | ground |

**Source**: CCDCAM IMA80S15 datasheet J3.

### R1 — 8-pin NET cable connector (= IMA80S15 datasheet J1)
| Pin | Color | Datasheet name | Voltage | Function |
|-----|-------|---------------|---------|----------|
| 1 (closest)  | red    | DC12V+   | **11-12V** | DC power input to SoC board |
| 2            | black  | GND      | 0 | Ground |
| 3            | green  | RJ45_6   | 0 | Ethernet differential signal (one of the 4 RJ45 pairs) |
| 4            | blue   | RJ45_3   | 0 | Ethernet differential signal |
| 5            | white  | RJ45_2   | 0 | Ethernet differential signal — **NOT IR-cut as previously thought** |
| 6            | orange | RJ45_1   | 0 | Ethernet differential signal |
| 7            | purple | LED_+    | activity during boot | Network connection indicator LED positive — boot activity = network/DHCP traffic, not a data protocol |
| 8 (furthest) | empty  | LED_+    | — | Network status indicator LED (unpopulated) |

**Source**: CCDCAM IMA80S15 datasheet — same board as MC800S SoC main, page 3 pinout. The IR-cut control signal is NOT on this connector (lives on J8 instead — separate 2-pin header).

### R2 — 4-pin bottom-right (= IMA80S15 datasheet J2 — AF UART)
| Pin | Color | Datasheet name | Voltage | Function |
|-----|-------|---------------|---------|----------|
| 1 (closest)  | bare GND | GND    | 0 | ground |
| 2 | red    | AF_TX | 3.32V steady (idle) | **PAD_FUART_TX = sysfs gpio 47 → HK32F RX (silkscreen "RX") — SoC outgoing AF commands** |
| 3 | black  | AF_RX | 1.48V mid-rail | **PAD_FUART_RX = sysfs gpio 46 ← HK32F TX (silkscreen "TX") — HK32F outgoing AF telemetry** |
| 4 (furthest) | empty | SPK_EN | 0 | Speaker amplifier enable IO (unpopulated) |

**Source**: CCDCAM IMA80S15 datasheet J2. The "AJ protocol" we've been capturing is actually the **AF (AutoFocus) protocol** — naming clarified.

R2 red+black cross above heatsink, terminate at **HK32F 3p-top** with white wire from distro NET (silkscreen labels: Red=RX, Black=TX, White=IR).

### B1 — 2-pin underside header (unpopulated)
| Pin | Voltage | Notes |
|-----|---------|-------|
| 1 (closest) | 3.3V | silent on USB-serial — passive 3.3V tap or unused UART |
| 2 (furthest) | 0 | likely GND |

---

## Distribution Board — silkscreen labels (from IMG_5746.jpeg)

The distro board has full silkscreen labels on every connector. Verified labels:

### Top center connector (NET cable from SoC main board)
| Pin label | Function |
|---|---|
| 12V | power input |
| GND | ground |
| LNK | network link LED |
| RX+ / RX- | Ethernet RX differential pair |
| TX+ / TX- | Ethernet TX differential pair |
| **RST** | reset signal (= brown wire from SoC L1/J5) |

### LEFT external interface connector (multi-pin, exposed for users)
| Pin label | Function |
|---|---|
| RCUT | IR-cut filter signal passthrough |
| RX1 | secondary UART RX |
| **PTZ** | external PTZ control |
| **485A / 485B** | **RS-485 differential pair — Pelco-D PTZ bus** |
| RST | second reset pad |
| LNK | secondary network LED |
| RX± / TX± | backup ethernet pair |

### Top edge — LED board connector
| Pin label | Function |
|---|---|
| LED+ / LED- | IR LED string drive (from PT4115) |
| CDS+ / CDS- | ambient light sensor (CdS photoresistor) |

### Right side — H_MOTOR connector (horizontal pan motor + audio)
| Pin label | Function |
|---|---|
| AN | analog (audio related?) |
| AGND | analog ground |
| AOUT | audio output |
| GND | digital ground |
| 12V | power |
| RX / TX | UART pair (function TBD — audio? lens MCU passthrough?) |
| H_MOTOR | horizontal stepper drive |

### Center — V_MOTOR
Vertical stepper motor connector.

## REVISED ARCHITECTURE — HK32F is a CENTRAL PTZ RELAY

User's tracing (2026-05-09) revealed:

1. **ULN2803A inputs 1-8 all connect to STC8G2K325A GPIOs** → STC8G drives the steppers
2. **White wire (NET cable Pin 9) goes from distro to HK32F lens board** — does NOT touch SoC
3. **On distro side**: white wire → Diode D3 → STC8G Pin 1 (P3.0 RxD)
4. **On HK32F side**: enters at "IR" pin of 3-pin header; doesn't appear to touch HK32F MCU
   directly — but a more careful trace through small ICs/transistors on the HK32F board may
   reveal the actual MCU connection

**HYPOTHESIS — HK32F is the central command relay**:

```
SoC ──── AF UART (115200 8N1, R2 RED/BLACK) ────→ HK32F lens MCU
                                                       │
                                                       ├─→ Drives BA6208G (zoom/focus DC motors)
                                                       │
                                                       └─→ Generates Pelco-D 2400 8N1 on white wire
                                                                  │
                                                                  ▼
                                                        Distro Pin 9 ──→ Diode D3 ──→ STC8G Pin 1 (RxD)
                                                                                            │
                                                                                            ▼
                                                                                      STC8G drives
                                                                                      8× ULN2803A inputs
                                                                                            │
                                                                                            ▼
                                                                                      Stepper coils
```

This means the **AF protocol is actually a multi-subsystem command protocol**, not just AF.
It carries:
- Zoom commands (HK32F → BA6208G → zoom motor)
- Focus commands (HK32F → BA6208G → focus motor)
- Pan/tilt commands (HK32F → Pelco-D translator → white wire → STC8G → steppers)
- Possibly status, AF data, and other camera-side info

This would explain why:
- The 20-byte AF frame format is more complex than needed for just zoom/focus
- HK32F is debug-fused (OEM protects this multi-purpose protocol)
- We can't find any direct SoC→STC8G UART path — there isn't one

## OPEN: confirm the relay hypothesis

To confirm:
1. Capture white wire @ 2400 8N1 simultaneously with AF UART @ 115200 during a pan command
2. If white wire shows Pelco-D bytes correlated with AF UART activity → relay confirmed
3. If white wire is silent during AF UART pan command → there's another path we haven't found

Also need to re-trace the white wire's connection on the HK32F board PCB: does it pass through
a small chip/transistor before reaching the HK32F MCU? The "doesn't touch MCU" finding may
have missed an indirect path.

## IR LED PWM path — RESOLVED 2026-05-15 (double-confirmed via photo)

**Visual proof from SoC main board photo**: The IMA80S15 J6 PWM header
(top edge of board, labeled `GND | PWM1 | PWM0`) is physically present on
the PCB but **the 3-pin connector is unpopulated — no wires attached**.

The SoC's SSC338Q PWM peripheral is exposed on this header but not wired
to anything in the MC800S assembly. The phonehome report's references to
`/sys/class/pwm/pwmchip0/pwm0/duty_cycle` describe SoC kernel capability,
not actual wired functionality on this camera.

The PT4115 DIM signal originates **locally on the distro board**, NOT from the SoC:

```
STC8G2K325A pin 28 (P1.7 / hardware PWM6)
    │
    └─→ 47 Ω series resistor
            │
            └─→ PT4115 pin 3 (DIM)
                    │
                    └─→ controls IR LED brightness via PWM duty cycle
```

User confirmed via continuity trace 2026-05-15: PT4115 DIM goes to STC8G pin 28
via a single **1 kΩ series resistor** (silkscreen "102") and 4 vias for routing.
Pin 28 on STC8G2K325A LQFP-32 is P1.7, which has hardware PWM6 peripheral
(verify against official STC8G2K datasheet for the exact part variant).

**STC8G VCC = 5 V** (confirmed 2026-05-15 by measuring 5 V at DIM with camera
powered and in daylight mode). STC8G pin 28 actively drives HIGH = 5 V CMOS,
which means STC8G is running on the 5 V rail (not 3.3 V). Implications:
- All STC8G GPIO outputs are 0 V / 5 V CMOS
- White wire signal (HK32F TX → STC8G RxD) is 5 V CMOS at idle high
- ULN2803A inputs from STC8G are 0 V / 5 V CMOS
- Diode D3 on white wire likely handles the 3.3 V (HK32F) → 5 V (STC8G) level
  difference via either forward-drop level shifting or protection against
  back-feed
- AD3 digital inputs are 5 V tolerant, so probing is safe without level shifters

**LED on/off vs brightness control architecture** (refined):
- DIM = brightness setpoint (continuous HIGH 5 V observed in daylight = "100% max")
- ULN2803A pin 17 (output 2C, open-collector sink to GND) = master on/off gate for
  LED chain return path. In daylight, this gate is open (no LED current flow).
- The two are controlled by separate STC8G GPIOs
- Open question: does the camera actually PWM the DIM in night mode, or is DIM held
  constant HIGH and only the ULN2803A gate switches? Will be answered by the next
  capture (cover CDS, watch DIM waveform)

**Implication for OpenIPC daemon**:
- No need to claim a SoC PWM channel or patch DTS for IR
- IR brightness control is via "set brightness" command sent through the existing
  HK32F→STC8G white-wire protocol (66666 baud, custom 6-byte frames)
- STC8G may also be fully autonomous on IR (using its own ADC on CDS sensor) —
  needs verification with AD3 capture during night-mode toggle

The SoC's exposed `/sys/class/pwm/pwmchip0/pwm0` from the phonehome report is for
something else (warm LEDs, fan, or unused) — not the IR LEDs.

### Verification plan (next AD3 session)

1. Scope 1 → PT4115 DIM pin (47 Ω side)
2. Scope 2 → STC8G pin 28
3. Cover CDS photoresistor → IR comes on
4. Both channels should show identical PWM waveforms — confirms direct trace
5. With white wire + AF UART also captured (DIO 0/1/2), cover/uncover CDS while
   watching all four signals to determine whether IR is STC8G-autonomous or
   commanded via the protocol relay

## Distribution Board — 9 connectors

| # | Label | Pin Count | Wire colors (closest → furthest) | Goes to |
|---|-------|-----------|----------------------------------|---------|
| 1 | **NET** | 10-pin, 8 populated | mirrors SoC R1 (red, black, green, blue, white, orange, purple) PLUS the brown wire from SoC L1 — total 8 used, 2 empty | SoC main board |
| 2 | **PoE-in** | 8-pin | white, brown, green, blue, orange, yellow, black, red | PoE board |
| 3 | **V-MOT** | 5-pin | Blue, Brown, Yellow, Black, Red(closest) | Vertical (tilt?) stepper motor |
| 4 | **H-MOT** | 5-pin | Red, Black, Yellow, Brown, Blue(closest) | Horizontal (pan?) stepper motor |
| 5 | **LED** | 5-pin (4 wires) | white, yellow, black, red | IR LED board |
| 6 | **HK32F** | single red wire | red (jumpered through SS24 schottky) | HK32F board's 2p-top "Red" — power feed |
| 7 | **Speaker** | 2-pin | +SPK- | Speaker |
| 8 | **Microphone** | 2-pin | +MIC- | Microphone |
| 9 | **UNLABELED 7-pin** | 7-pin, 5 populated | open, open, red(11V), black(GND), red(audio), black, red(audio) | HK32F audio routing |

**Note:** 11V from R1 pin 1 is tied to V-MOT red + H-MOT red + HK32F R1 red — single power rail for ALL motors.

---

## HK32F030 Board

Connectors:
| Label | Pin Count | Wire colors | Notes |
|-------|-----------|-------------|-------|
| **3p (Top)** | 3-pin | Red=RX, Black=TX, White=IR | **🎯 SILKSCREEN labeled.** Red+Black come from SoC R2 (VISCA UART pair). White from distro NET (IR control signal). NO GND on this connector — chassis ground. |
| **8p (Leftmost)** | 8-pin | White, red, purple, yellow, orange, green, black, blue | Likely goes to lens module — VISCA UART pair + DC motor drives (zoom + focus + IR-cut filter actuator) |
| **2p (Top)** | 2-pin | Black, Red | Black from SoC L2. Red from distro board (jumpered off SS24 schottky) — **3.3V/5V power** |
| **J3** | 5-pin SWD | — | ARM SWD programming header — **could dump HK32F firmware via ST-Link** |

---

## PoE Board (SDaPo PM3812R)

Connectors:
| Label | Pin Count | Wire colors |
|-------|-----------|-------------|
| **8p** | 8-pin | yellow, orange, blue, green, brown, white, red, black(closest) |
| **4p** | 4-pin | white, yellow, black, red(closest) |
| **6 (RJ45)** | 6 wires (3 twisted pairs) | brown, brown-white, blue, blue-white, green, green-white(closest) |

---

## IR LED Board

Connectors:
| Label | Pin Count | Wire colors |
|-------|-----------|-------------|
| 2p | 2-pin | yellow, white |
| 2p | 2-pin | black, red |

---

## Stock Firmware UART Configuration (CONFIRMED)

```
SoC (SSC338Q)
  ├─ /dev/ttyS0  (uart0 @ 0x1F221000)  → kernel console      → 38400 8N1 RTS/CTS  → dedicated round copper pads near FFC ribbon
  ├─ /dev/ttyS1  (uart1 @ 0x1F221200)  → STC8G pan/tilt MCU  → 2400 8N1          → brown wire (PM_GPIO4) via NET → distro board
  └─ /dev/ttyS2  (uart2 @ 0x1F220400)  → HK32F lens MCU      → 9600 8N1 (VISCA)  → R2 red+black via crossing wires → HK32F 3p-top
```

**Stock also exposes:**
- /dev/ttyAMA1, /dev/ttyAMA2 — AMBA UART driver names (registered by mhal.ko, alias for ttyS1/ttyS2)
- /dev/sercom0 — serial-over-network bridge to TCP via remserial

**OpenIPC currently:**
- ttyS0/1/2 work but uart1 muxed to PAD_GPIO0 (dead 3-pin header pin), not brown wire
- ttyS2 muxed correctly to FUART (R2 red/black) — verified by loopback test
- Kernel console works via the round copper pads (per OpenIPC build)

---

## TFTP Recovery / Firmware Flashing

**IPL string found:** `anjvision_autoupdate::MC800S2_V0` — **this is the SD card auto-update filename, NOT TFTP** (corrected 2026-05-04)

**Stock backup:** `C:\Users\matth\ipcamera\backups\stock_backup_20260501_MC800S_SSC338Q.bin` (MD5 `c405df984c9d3a2692e2b5b99f74fd1a`)

**Flash methods:**
1. **CH341A SOIC-8 clip + flashrom** (verified working — used to install OpenIPC) ← preferred for reliability
2. **SD card auto-update** — place stock firmware on SD card with `MC800S2_V0` filename prefix, insert, boot — IPL flashes from SD
3. **TFTP recovery via U-Boot** — possibly works at boot, exact filename TBD (need UART capture)

**Partition map (NOR 16 MB):**
- 0x000000-0x020000 (128 KB): BOOT (IPL — has the `anjvision_autoupdate::MC800S2_V0` string)
- 0x020000-0x040000 (128 KB): UBOOT (env: `bootcmd=sf probe 0;sf read 0x22000000 0x00040000 0x00200000;bootm 0x22000000`)
- 0x040000-0x240000 (2 MB): KERNEL (uImage XZ-compressed)
- 0x240000-0xF60000: SYSTEM (squashfs)
- 0xF60000-0x1000000: DATA (JFFS2)

---

## Phone-Home / Cloud / Security (per phonehome report)

Stock firmware has extensive cloud connectivity that OpenIPC entirely removes. Key items:
- **Alibaba IoT** (ac18pro_server, 832KB) — full P2P, MQTT, OTA push capability
- **Anjvision device binding** (dev_bind, 682KB) — talks HTTP to ac18pro.icamra.com
- **Skyworth IoT** — secondary cloud platform
- **Hikvision emulator** on port 8000 (auth disabled by default)
- **Dahua emulator** on port 37777 (auth disabled by default)
- **Hardcoded MD5-crypt root password** `$1$yFuJ6yns$33Bk0I91Ji0QMujkR/DPi1`
- **SD card RCE** — `/mnt/mmc0/upt_exec` runs as root if present
- **8+ cloud P2P backends** ready to activate via flag file
- Full details in `C:\Users\matth\OneDrive\Desktop\MC800S_stock_firmware_phonehome_report.md`

---

## Reverse-Engineered Function Locations

### `/opt/ch/comm_server` (UART daemon, 175KB, ARM EABI5)
- `ttl_init` @ 0x1f164 — opens /dev/ttyS2, sets 9600 baud
- `ttl_init2` @ 0x26ae8 — opens /dev/ttyS1, sets 2400 baud
- `write_tottl2` @ 0x26b50 — writes bytes to ttyS2
- `ttl_upgrade_proc` @ 0x1f554 — HK32F firmware upgrade interface
- `AdvanceCMD_D` @ 0x26fd8 — main command dispatch
- Command names: zoomtele, zoomwide, focusfar, focusnear, FocusFarAutoOff, FocusNearAutoOff
- Confirmed: 9600 8N1, 7-byte command frames (printf format `%02x,%02x,%02x,%02x,%02x,%02x,%02x`)
- Limitation: literal byte arrays built in RAM, not extractable from .rodata

### `/opt/ch/mainctrl` (PTZ controller, 375KB, ARM EABI5, dynamically linked)
- gpio_init/gpio_write/GetResetGpioPort/GetLedBrGpioPort are UND symbols → live in libtools.so
- References to /dev/gpiopwm, /sys/class/pwm/pwmchip0/pwm{0,1,5,8,9}/duty_cycle
- Strings: motor_ctrl_use_pwm.flag, calculate_step_use_pwm_period.flag, new_pwm.flag — flags determine motor control mode
- Bauds referenced: 460800, 921600 (likely for ttl_upgrade_proc HK32F firmware update)

### `/opt/ch/libtools.so` (utility library, 543KB, ARM EABI5, stripped)
- `gpio_init` @ 0x413d8 (Thumb) — calls InitGpioThread() then product_type-based GPIO config
- `GetResetGpioPort` @ 0x417f8 — iterates 52-byte config table, returns gpio at offset 32 of entry where type==3
- `GetLedBrGpioPort` @ 0x4185c — similar pattern
- MC800S product_type in 0xb200 range (45568-45586 dec)
- Limitation: config table data uses PC-relative addressing, not statically extractable

### `/config/modules/4.9.84/mhal.ko` (kernel module, 1.6MB, ARM EABI5)
- DELEGATES PM padmux to external kernel symbols: `mdrv_padmux_active`, `mdrv_padmux_getmode`, `mdrv_padmux_getpad`
- Reads `padmux.dtsi` config at boot
- Creates /dev/gpiopwm (major 95)
- PM domain base: 0xFD000000 + (0x003F * 0x0200) = 0xFD007E00
- The actual register-write code for PM_GPIO4 → PM_UART_TX1 is in another module we haven't located

---

## Implementation Strategy (UPDATED with new findings)

### Path A — Direct GPIO motor control (NEW PRIMARY PATH if Method 1 confirmed)

If `/opt/ch/motor_ctrl_use_pwm.flag` exists in stock when running:
1. **Skip the entire PT UART problem** — STC8G is bypassed
2. Identify the 4 SoC GPIOs that drive ULN2803A inputs (probe with multimeter against ULN2803A pins 1-4 / 5-8 on distro board)
3. Configure OpenIPC's `general/package/legacy/sigmastar-motors/` package with the right GPIO numbers
4. Pan/tilt via direct GPIO bit-bang
5. **Way simpler than DTS/pinmux approach**

### Path B — UART pinmux approach (FALLBACK if Method 2 is what stock uses)

1. DTS patch: dual-reg uart1 with `pad = <PAD_PM_UART_TX1>`
2. Userspace devmem write to PM PADTOP register at 0xFD007E?? to mux PM_GPIO4 → PM_UART_TX1
3. Specific register/bit values: TBD — need to disassemble the actual mhal padmux module (not in mhal.ko itself, in a separate module we haven't located)

### Phase 2 — HK32F VISCA UART (already correctly muxed in OpenIPC)
1. Verify HK32F is powered (3.3V on SS24 jumper red wire)
2. Capture stock's actual VISCA exchange via USB-serial during boot/operation
3. Replicate exact byte sequences in OpenIPC
4. The protocol IS VISCA per phonehome report; "AJ protocol" reference may be a false flag

### Phase 3 — IR-cut + IR LEDs
- Configure OpenIPC's IR-cut driver to toggle GPIO 53 + 61 (H-bridge pattern)
- IR LED PWM control via `/sys/class/pwm/pwmchip0/pwm0` or pwm1
- GPIO 36 toggle for LED on/off

---

## Open Questions — Live Capture Needed

To answer definitively, boot stock briefly with USB-serial probes attached:

1. **Is `/opt/ch/motor_ctrl_use_pwm.flag` present?** (Determines Method 1 vs Method 2 — single biggest unknown)
2. **What does stock send to /dev/ttyS2 during zoom command?** Capture R2 black wire while zooming via web UI
3. **What baud is purple wire actually at?** Capture during boot, look at line transitions
4. **Which 4 SoC GPIOs drive ULN2803A inputs on distro board?** Probe ULN2803A pins 1-4 / 5-8 while stock is bit-banging steppers

Once these are answered (~30 min of capture), we have full understanding to port everything.

---

## File References

| File | Purpose |
|------|---------|
| `C:\Users\matth\investigate\MC800S-system-map.md` | This file — master reference |
| `C:\Users\matth\investigate\MC800S-PTZ-STATE.md` | Working state of PTZ debugging session |
| `C:\Users\matth\investigate\MC800S-SoC-headers.md` | SoC board pinout details |
| `C:\Users\matth\investigate\MC800S-IO-headers.md` | Distribution board pinout (older, partial) |
| `C:\Users\matth\OneDrive\Desktop\MC800S_stock_firmware_phonehome_report.md` | **CRITICAL** — phone-home + Method 1/2 motor finding |
| `C:\Users\matth\.claude\plans\calm-singing-dongarra.md` | Implementation plan |
| `C:\Users\matth\ipcamera\backups\stock_backup_20260501_MC800S_SSC338Q.bin` | Stock firmware backup (MD5 c405df984c9d3a2692e2b5b99f74fd1a) |
| `/mnt/c/tftp/_stock_backup_20260501.bin-0.extracted/squashfs-root/` | Extracted stock filesystem (in WSL) |
| `/mnt/c/tftp/stock_dts_work/stock.dts` | Decompiled stock device tree |

---

## Final Pre-Sleep TL;DR (SUPERSEDED — see Current Findings below)

The two biggest things to remember:

1. **Stock probably uses direct GPIO motor control (Method 1) not the STC8G UART (Method 2).** This means the entire "PM_GPIO4 brown wire pinmux" struggle may be unnecessary — we just need to copy the right GPIO assignments. **Verify by checking `/opt/ch/motor_ctrl_use_pwm.flag` when stock is running.**

2. **VISCA at 9600 IS correct for HK32F** per phonehome report — but our tests got no response. Either HK32F isn't powered (check 3.3V on SS24 jumper) or stock has a wake/init we haven't replicated.

---

## 🔥🔥🔥🔥🔥🔥🔥 BREAKTHROUGH 2026-05-16 (#7) — B15 = DIRECTION BYTE + OPCODE HYPOTHESIS REVISION

Batch of 13 isolated single-action captures (panL, panR, tiltU, tiltD, multiple
speed variations, zoom variants, iris) decoded.  User confirmed no probe changes
between batches.

### B15 is the direction encoding byte ✅

The 0x98-dominant frames in this batch cleanly differentiate direction via B15:

| Capture | B15=0x06 count | B15=0x60 count | Interpretation |
|---|---|---|---|
| panL | 104 (33%) | 1 (0%) | **0x06 = LEFT** |
| panR | 7 (2%) | 57 (18%) | **0x60 = RIGHT** |
| tiltU | 168 (54%) | 0 (0%) | **0x06 = UP** |
| tiltD | 18 (6%) | 56 (18%) | **0x60 = DOWN** |

Same encoding values used for both pan and tilt axes.  This is what the daemon
will set when issuing motor commands.

### B14 also contributes to direction encoding (secondary axis)

| Capture | Top B14 values | Pattern |
|---|---|---|
| panL | 0x66 (33%), 0x98 (15%), 0x60 (13%) | 0x66 = LEFT (with 0x98 marker) |
| panR | 0x60 (18%), 0x00 (14%), 0x66 (12%) | 0x60 = RIGHT |
| tiltU | 0x60 (33%), 0x98 (19%), 0x66 (15%) | 0x60 = UP (different from pan!) |
| tiltD | 0x06 (17%), 0x60 (15%), 0x00 (13%) | mixed |

Note: B14 = 0x60 means "UP" for tilt but "RIGHT" for pan.  B15 is the cleaner
direction encoding (consistent value across axes).

### OPCODE HYPOTHESIS REVISION

The previous batch led to "B8 = subsystem opcode" — pan/tilt=0x86, zoom=0x60,
iris=0x1E, focus=0x9E.  That worked for the long sustained captures (utd, dlr,
iris0004/5) but **fails for shorter isolated captures** in this new batch.

Observations that broke the prior theory:

| Earlier capture | Length | Dominant B8 | New capture (same action) | Length | Dominant B8 |
|---|---|---|---|---|---|
| utd_tilt (tilt up+down) | 43 s | 100% 0x86 | TiltU0003 | ~6 s | 78% 0x98 |
| dlr_pan_tilt (pan+tilt) | 43 s | 100% 0x86 | panL0001 | ~6 s | 52% 0x98 |
| iris0004 (iris only) | ~8 s | 100% 0x1E | IrisSpeed100013 | ~6 s | 76% 0x98 |

With user confirming **no probe changes**, the cause must be one of:
1. **Different command-issue mechanism** (web UI continuous PTZ vs single-step API call)
2. **Camera mode / firmware state difference**
3. **B8 actually encodes motor PHASE, not subsystem** — with the previous "100% 0x86"
   being just the "sustained motion" phase

**Revised opcode interpretation** (hypothesis #2):

| B8 | Likely phase / type | When dominant |
|---|---|---|
| 0x80 | Idle / no-op | When motor is stopped |
| 0x86 | Sustained-motion telemetry | Long held actions (utd, dlr captures) |
| 0x98 | Transition / brief-action status | Short isolated captures, transitions |
| 0x9E | Position-update / completion phase | Action ending; also focus motor |
| 0x60 | Zoom-specific phase | Zoom captures specifically (still distinct) |
| 0x1E | Iris-specific phase OR command-start | Iris adjustments |
| 0x66, 0x78, 0x7E | Other sub-states | Transitions |

Zoom remains distinct (0x60 still dominant in zoom captures), so zoom has its
own opcode family.  Pan/tilt/focus/iris may share opcodes that vary by phase.

The cleanest direction encoding (B15) is more useful for the daemon than B8 anyway.

### Focus NEAR vs Focus FAR (user clarification)

User clarified focus0002 and focus0003 from prior batch were two different focus
actions: one near, one far.

| Capture | Dominant B8 | Interpretation |
|---|---|---|
| focus0002 | 0x9E (45%) + 0x1E (36%) | **Focus NEAR** — lens travels significantly, requires iris compensation for depth-of-field at close range |
| focus0003 | 0x1E (49%) + others | **Focus FAR** — lens already near infinity, minimal motor travel; iris adjusts more for far-scene exposure |

The 0x9E vs 0x1E split is a function of HOW MUCH the focus motor needs to move
relative to the iris.  Both ARE focus actions; the direction determines the
opcode emphasis.

### Speed encoding (TBD)

Captures named "PanSpeed10005" through "tiltSpeed10009" suggest the user tested
different motor speeds.  B14 values shift between captures but the exact speed
encoding byte hasn't been isolated yet.  Need to know the user's speed values
mapped to each filename to correlate.

---

## 🔥🔥🔥🔥🔥🔥 BREAKTHROUGH 2026-05-16 (#6) — IRIS = 0x1E, FOCUS = 0x9E

Batch of 9 isolated single-action captures decoded (3× focus, 2× iris, 4× zoom+AF):

| Capture | Frames | Top opcodes (B8) | Interpretation |
|---|---|---|---|
| iris0004 | 125 | **0x1E = 100%** | Pure iris adjustment |
| iris0005 | 136 | **0x1E = 100%** | Pure iris adjustment |
| focus0002 | 130 | 0x9E=58 (45%), 0x1E=47 (36%), 0x60=10 | Focus + iris (focus changes light, iris compensates) |
| focus0003 | 130 | 0x1E=64 (49%), 0x60=20, 0x66=11 | Mostly iris with some zoom (likely focus action triggered iris/zoom too) |
| zoomoutandfocus0006 | 152 | 0x9E=56, 0x98=35, 0x1E=33 | Focus + iris + focus sub-state |
| zoomoutandfocus0007 | 154 | 0x1E=36, 0x80=30, 0x60=25, 0x86=22 | Mixed: iris + idle + zoom + pan/tilt |
| zoomoutandfocus0008 | 310 | 0x98=68, 0x60=66, 0x9E=54 | Heavy zoom + focus settling |
| zoominandfocus0009 | 304 | 0x86=81, 0x9E=41, 0x7E=38 | Pan/tilt and focus active concurrently |

### Major corrections to opcode dictionary

**0x1E is NOT "init / command start" as previously believed.** It's the **iris adjustment opcode**. The reason iris commands appear at boot (which seeded the misclassification) is that the camera adjusts iris during startup as part of normal initialization.  Same reason iris fires during zoom: changing focal length changes apparent scene brightness, and the iris compensates.

**0x9E is the FOCUS motor opcode** (new).

**0x86 stays as pan/tilt motor** (corrects the earlier "general lens motor" interpretation — the AF-during-zoom traffic was actually 0x9E focus frames, not 0x86 pan/tilt frames).

### Final subsystem opcode map

```
Sync header (B0–B7):  06 66 00 60 80 66 E6 80

Opcode (B8):
  0x80  Idle / no-op
  0x86  Pan/Tilt motor
  0x60  Zoom motor
  0x1E  Iris
  0x9E  Focus motor
  0x98  Focus sub-state (settling? transition?)

Sub-opcode (B9):
  0x80  Continuous / hold
  0x00  Single step / click
```

### Focus frame structure example (B8 = 0x9E)

```
06 66 00 60 80 66 E6 80 | 9E 80 86 E6 00 E6 66 00 00 1E 00 00 7E
                          ^^opcode = focus  ^^                    ^^B17=0x1E
                                                                     (motor active flag in different position than pan/tilt!)
```

For pan/tilt frames (0x86), the motor-active flag is at **B16=0x1E**.
For focus frames (0x9E), the motor-active flag appears to be at **B17=0x1E**.

This is a useful pattern: the byte position of the active flag depends on which subsystem.  The daemon should know each opcode's flag-position.

### Implication for OpenIPC daemon

```python
OPCODES = {
    'idle':      0x80,
    'pan_tilt':  0x86,
    'zoom':      0x60,
    'iris':      0x1E,
    'focus':     0x9E,
}

SUB_OPCODES = {
    'hold':   0x80,
    'click':  0x00,
}

def build_motor_frame(subsystem, press_type, payload):
    """Build a 20-byte AF UART frame for a motor command."""
    sync = b'\x06\x66\x00\x60\x80\x66\xE6\x80'
    b8 = OPCODES[subsystem]
    b9 = SUB_OPCODES[press_type]
    # payload (B10-B19) is subsystem-specific — needs cross-correlation with
    # tilt/pan direction captures to finalize byte assignments
    return sync + bytes([b8, b9]) + payload
```

---

## 🔥🔥🔥🔥🔥 BREAKTHROUGH 2026-05-16 (#5) — ZOOM CLICK vs HOLD STRUCTURALLY DIFFERENT

`zoominclick.csv` (10.5-s isolated zoom-in single click, Raw Events, 194 frames)
vs `zoominhold.csv` (12-s held zoom, 239 frames) reveals **click and hold use
different opcodes**, not just different frame counts:

### Opcode distribution

| B8 | zoom HOLD | zoom CLICK | Inferred role |
|---|---|---|---|
| **0x60** | 168 (70%) | 22 (11%) | Zoom motor active (sustained or pulse) |
| **0x1E** | 40 (17%) | 0 | Command start / motor enable (HOLD only) |
| **0x78** | 3 (1%) | **74 (38%)** | **Motor decelerating / coast-down** |
| **0x7E** | 0 | **46 (24%)** | **Motor settling state** |
| 0x80 | 1 | 25 (13%) | Idle / motor stopped |
| 0x66 | 1 | 20 (10%) | Sub-state during transition |
| 0x86 | 26 (11%) | 2 (1%) | Pan/tilt (probably AF-triggered) |

**Click action sequence (inferred from opcode timeline)**:
1. Send brief 0x60 burst (22 frames) — the actual "move zoom one step" command
2. Switch to 0x78 (decel?) — 74 frames of coast-down/limit telemetry
3. Settle through 0x7E (46) → 0x80 (idle, 25) → done

> ⚠️ **Alternative hypothesis (user-flagged 2026-05-16)**: 0x78/0x7E might NOT be
> generic decel codes — they could be **end-of-travel / limit-reached** notifications.
> The zoom click capture may have been done when the lens was at or near the
> telephoto limit, in which case:
> - The 22 frames of 0x60 = HK32F tried to move the motor
> - The 74 frames of 0x78 = motor refused / hit endstop / telemetry reporting
>   "can't move further in this direction"
> - 0x7E = related limit-state code
>
> **Discriminating test**: do a zoom click capture starting from the WIDE end
> (well away from the telephoto limit), and another starting MID-RANGE.  If
> 0x78/0x7E still dominate at mid-range, they're generic decel codes.  If they
> only appear at the limit (telephoto), they're limit-detection codes.

**Hold action sequence**:
1. Send 0x1E init frames (40)
2. Send continuous 0x60 motor commands (168) while button is held
3. (Capture ended while button was still held — no decel phase visible)

### Press-type sub-opcode (B9)

Comparing 0x60 (zoom) frames between HOLD and CLICK:

```
HOLD,  B8=0x60:  ... | 60 80 9E 00 FE 98 66 00 1E 00 00 00
                        ^^ B9=0x80
CLICK, B8=0x60:  ... | 60 00 06 60 18 00 00 1E 00 00 E0 06
                        ^^ B9=0x00
```

**B9 distinguishes press type**:
- **B9 = 0x80**: continuous-drive sub-opcode (hold)
- **B9 = 0x00**: single-step sub-opcode (click)

This is independent of B8 (the subsystem opcode), so the encoding pattern is:
- `B8 = subsystem` (pan/tilt vs zoom vs focus)
- `B9 = press type` (continuous hold vs single click)
- `B10–B19` = direction / speed / position

This needs verification against pan/tilt isolated click/hold captures (in flight —
user will re-export the 4 tilt captures as Raw Events).

### New zoom-click bytes appearing (B17 in particular)

B17 in zoom-CLICK has 6 unique values {0x00, 0x06, 0x18, 0x1E, 0x66, 0x80} —
much more variance than HOLD ({0x00, 0x1E}).  Likely encodes the click-progression
state (start/move/decel/settle).

### Refined transmit-side daemon design

```
def tx_zoom_click(direction):
    # Pulse: brief 0x60 with B9=0x00, then 0x78 decel, then 0x80 idle
    send_frame(opcode=0x60, sub=0x00, dir=direction, count=N_pulse)
    send_frame(opcode=0x78, ...)   # automatic? or commanded?
    send_frame(opcode=0x80, ...)

def tx_zoom_hold(direction):
    # Continuous: 0x1E init, then sustained 0x60 with B9=0x80 while held
    send_frame(opcode=0x1E, ...)
    while button_held:
        send_frame(opcode=0x60, sub=0x80, dir=direction)
    # Decel sequence sent automatically by HK32F? Or daemon needs to send it?
```

The "automatic" question — whether the HK32F auto-generates the decel sequence
when the SoC stops sending 0x60 frames, or whether the SoC must explicitly send
0x78/0x7E/0x80 — is critical for the daemon and TBD.  Best test: when the
daemon is built, try one approach first; if motor doesn't decelerate gracefully,
add the explicit decel sequence.

---

## 🔥🔥🔥🔥 BREAKTHROUGH 2026-05-16 (#4) — ZOOM USES OPCODE 0x60, NOT 0x86

`zoominhold.csv` (12-s isolated zoom-in-hold capture, 239 AF frames decoded) reveals
that **zoom is commanded with a completely different opcode** than pan/tilt:

| Opcode B8 | Function | Frames in zoom capture |
|---|---|---|
| **0x60** | **ZOOM motor command** | 168 (70%) |
| 0x1E | Init / command-start | 40 (17%) |
| 0x86 | Pan/tilt motor (rare here — possibly AF-triggered) | 26 (11%) |
| 0x78 | Sub-state | 3 |
| 0x80 | Idle | 1 |
| 0x66 | Sub-state | 1 |

**Shared structure across pan/tilt (0x86) and zoom (0x60) motor commands**:

| Byte | Pan/tilt (0x86) | Zoom (0x60) | Role |
|---|---|---|---|
| B0–B7 | sync `06 66 00 60 80 66 E6 80` | same | sync header |
| B8 | 0x86 | **0x60** | **opcode = which subsystem to drive** |
| B9 | 0x80 (constant) | 0x80 (constant) | sub-opcode (common) |
| B10–B14 | variable | variable | payload (direction/speed/position) |
| B15 | 0x00 | **{0x00, 0x06, 0x1E, 0x80}** ← new in zoom | zoom-specific flag |
| B16 | 0x1E (motor moving) | {0x00, 0x1E} | motor-active flag (zoom toggles) |
| B17 | 0x00 | **{0x00, 0x1E}** ← new in zoom | unknown zoom flag |
| B18 | 0x00 | **{many values}** ← high variance only in zoom | zoom position counter? |
| B19 | variable | variable | position/state |

### Example frames

```
utd  (tilt up/down):    06 66 00 60 80 66 E6 80 | 86 80 F8 78 00 00 06 00 1E 00 00 80
dlr  (pan right):       06 66 00 60 80 66 E6 80 | 86 80 66 9E 00 E6 66 00 1E 00 00 E0
zoom-op-0x60 (zoom in): 06 66 00 60 80 66 E6 80 | 60 80 9E 00 FE 98 66 00 1E 00 00 00
zoom-op-0x86 (during zoom):
                        06 66 00 60 80 66 E6 80 | 86 80 F8 7E 00 78 78 06 00 1E 00 00
```

### Updated full opcode dictionary

| B8 opcode | Seen where | Inferred role |
|---|---|---|
| **0x80** | Boot phases 1-4 (steady idle), zoom (1×) | **Idle heartbeat / no-op** |
| **0x86** | utd 100%, dlr 100%, zoom 11% | **Lens-side motor command** — pan/tilt OR auto-focus motor (camera fires AF during zoom to track focal length; user obs: continuous zoom prevents AF from settling, so AF re-fires throughout the hold). B9 or payload bytes distinguish pan/tilt vs AF. |
| **0x60** | Zoom-in 70% | **Zoom motor command** |
| **0x1E** | Boot init, zoom 17% | **Command start / motor enable / init** |
| 0x18 | Home seek (boot) | Boot motor command |
| 0x06, 0x00, 0xE0, 0xE6, 0xF8, 0x66, 0x78, 0x9E | Boot home-seek sub-phases, rare in motion | Sub-state / specific motor steps |

> ⚙️ **Insight 2026-05-16 (user)**: When zooming continuously, the camera's
> auto-focus system can't converge because each new focal length requires a
> new focus position but the lens never sits still.  The HK32F nonetheless
> keeps firing 0x86 commands at the AF motor during the entire zoom, which is
> why we see 11% of zoom-capture frames as 0x86.  This is consistent with the
> earlier observation that IR-cut toggle also triggers an AF cycle (each
> mechanical IR-cut switch changes the optical path requiring refocus).
>
> **Implication for the OpenIPC daemon**: when issuing a zoom command, the
> daemon does NOT need to issue separate AF commands — the HK32F handles
> auto-focus autonomously.  The daemon only needs to send the zoom opcode.

### What this means for the OpenIPC daemon

Implementing the daemon now requires TWO command families (not one):
- `tx_pan_tilt(direction, speed)` → emits opcode-0x86 frames
- `tx_zoom(direction, speed)` → emits opcode-0x60 frames
- Optional `tx_focus(...)` → opcode unknown yet — will be revealed by focus captures

Plus the protocol probably needs an init/start sequence using opcode 0x1E before
the actual motor command frames flow.

### Next captures to disambiguate further

The 4 isolated tilt captures (uphold/upclick/downhold5sec/downclick) were exported
as Raw Data (GB-sized) and didn't decode in this session.  When re-exported as
Raw Events, those will pin down which byte = direction vs which = click-vs-hold.

Plus the previously-listed: zoom out, focus near, focus far, idle 30 sec, IR toggle.

---

## 🔥🔥🔥 BREAKTHROUGH 2026-05-16 (#3) — MULTI-CAPTURE COMPARATIVE DECODE

After two single-action captures (`upthendown.csv` = ups-then-downs sequence;
`Downleftright.csv` = downs+lefts+rights), and user clarification on capture
content, the opcode 0x86 frame structure is mapped:

### Captures compared

| Capture | Actions | Frames | Bits 4-7 (ULN_1-4)? | Implication |
|---|---|---|---|---|
| `upthendown.csv` (utd) | ups then downs | 859 | **idle** (no transitions) | Tilt uses ULN_5-8, NOT probed here |
| `Downleftright.csv` (dlr) | downs + lefts + rights (mix of holds + clicks) | 858 | **active** (~800 trans each) | Pan uses ULN_1-4 = bits 4-7 |

### Frame structure for opcode 0x86 (motor command, refined)

```
06 66 00 60 80 66 E6 80 | 86 80 [B10] [B11] [B12] [B13] [B14] 00 1E 00 00 [B19]
```

| Byte | utd values | dlr values | Interpretation |
|---|---|---|---|
| B8 | 0x86 (100%) | 0x86 (100%) | Opcode: motor command |
| B9 | 0x80 (const) | 0x80 (const) | Sub-opcode |
| B10 | 16 distinct (00, 06, 18, 1E, 60, 66, FE, F8, E6, E0, 7E, 78, 86, 80, 98, 9E) | 16 distinct (similar set) | Magnitude / position |
| B11 | `0x78: 297, 0x9E: 562` (2 values) | `0x78: 55, 0x9E: 474, 0xE6: 329` (3 values, **0xE6 only in pan**) | Press-duration encoding × axis flag |
| B12 | 0x00 (const) | `0x00: 529, 0x06: 329` | **0x06 = pan axis active** |
| B13 | {00, 06, FE} | {00, 06, 18, E0, E6, F8, FE} | direction/quadrant flag |
| B14 | `06: 787, 66: 72` | `06: 491, 66: 367` | Speed or modifier flag (more 0x66 during pan) |
| B16 | 0x1E (const) | 0x1E (const) | **Motor-in-motion status flag** |
| B19 | 12 distinct | 16 distinct | Position counter / progress |

### Key takeaways

1. **B11 is NOT a simple direction byte** — it encodes press type (click vs hold)
   combined with axis selector.  Value 0xE6 appears ONLY when pan moves, suggesting
   `B11 in {0x78, 0x9E}` for tilt and `B11 = 0xE6` for pan (with internal flags).
2. **B12 = 0x06 marks pan-axis frames** (529 of 858 dlr frames had B12=0x00, the
   remaining 329 had 0x06 — and only dlr had any 0x06 because utd was tilt-only).
3. **ULN_1-4 (probed bits 4-7) is the PAN stepper drive**.  Tilt stepper drives
   the OTHER 4 ULN inputs (pins 5-8 on the ULN2803A, not in current probe set).
4. **Direction info is distributed** across B10, B11, B12, B13, B19 — no single
   byte cleanly says "up" vs "down" or "left" vs "right".  Need additional
   single-action captures to isolate each axis × direction.

### Next captures to fully resolve the dictionary

- `panLeft_hold.csv` — long-press pan left only
- `panRight_hold.csv` — long-press pan right only
- `tiltUp_click.csv` — short-press tilt up only
- `tiltDown_click.csv` — short-press tilt down only
- `zoomIn_hold.csv` — telephoto
- `zoomOut_hold.csv` — wide
- `idle_30sec.csv` — pure heartbeat baseline (should be opcode 0x80, not 0x86)

With those eight captures, the opcode 0x86 byte map will be unambiguous and we can
implement the OpenIPC daemon's motor command encoder.

## 🔥🔥 BREAKTHROUGH 2026-05-16 (#2) — TILT UP/DOWN AF FRAME STRUCTURE DECODED

User performed an "UP then DOWN" tilt action while AD3 captured `upthendown.csv`
(Raw Events).  Decoded bit 1 at 115200 baud — got 859 AF frames at 90.2% sync alignment.

**ALL 859 frames have opcode B8 = 0x86** (vs boot capture which had mixed opcodes).
This identifies 0x86 as the **"motor active / telemetry" opcode**.

Refined frame structure for opcode 0x86 (motor active):

| Byte | Value(s) | Role |
|---|---|---|
| B0–B7 | `06 66 00 60 80 66 E6 80` | Sync header (constant) |
| **B8** | `0x86` | **Opcode: motor active / position telemetry** |
| B9 | `0x80` | Constant in this capture (sub-opcode?) |
| **B10** | varies, correlated with B11 | High byte of signed position/velocity |
| **B11** | `0x78` (297×) or `0x9E` (562×) | **Direction: 0x78 = UP, 0x9E = DOWN** |
| B12 | `0x00` | Constant |
| B13 | mostly `0x06` | Flag |
| B14 | `0x06` dominant, occ. `0x66` | Flag |
| B15 | `0x00` | Constant |
| **B16** | `0x1E` | **Status flag: motor in motion** |
| B17–B18 | `0x00` | Constant |
| B19 | 12 unique | Position counter / progress field |

B10+B11 together encode direction and magnitude:
- B11 = 0x78 (UP): B10 in {FE, F8, E6, E0} — high-bit-set range (0xE0–0xFE)
- B11 = 0x9E (DOWN): B10 in {00, 06, 18, 1E, 60, 66} — low byte values (0x00–0x66)

Treating B10/B11 as signed 16-bit velocity:
- `FE 78` = -392 → UP at speed X
- `00 9E` = +158 → DOWN at speed Y

The 65.4% / 34.6% split (DOWN dominates) is consistent with user doing UP first
then DOWN, with DOWN action probably running when capture ended.

Frame transmission rate: **859 frames / 43 s ≈ 20 fps = 50 ms per frame** — that's
the motor telemetry refresh rate.

### Comparison to boot capture opcodes

| Opcode (B8) | Boot capture | Up/down capture | Meaning |
|---|---|---|---|
| 0x80 | 48.6% (dominant) | 0% | **Idle heartbeat** |
| 0x1E | 31.4% | 0% | **Boot / home seek**? |
| 0x18 | 3.3% | 0% | AF / zoom init? |
| 0x86 | 0% | **100%** | **Motor active (telemetry)** |
| 0x06, 0x00, 0x60, 0xE6, 0xE0, 0xF8, 0x66, 0x7E, 0x78, 0x9E | rare | 0% | Specific home-seek sub-commands |

### Next captures needed for opcode dictionary

Single-action clean captures of each motion type:
1. **Pan left only** → identify pan-L opcode/payload
2. **Pan right only** → identify pan-R opcode/payload
3. **Zoom in only** (telephoto) → zoom-in encoding
4. **Zoom out only** (wide) → zoom-out encoding
5. **Focus near** → focus-near
6. **Focus far** → focus-far
7. **IR-cut toggle** → identify IR enable/disable encoding
8. **Idle for 30 seconds** → pure heartbeat baseline

After collecting these, each opcode-byte position maps unambiguously to one
control function and we have the full PTZ command dictionary for the OpenIPC daemon.

---

## 🔥 BREAKTHROUGH 2026-05-16 (#1) — WHITE WIRE IS HK32F DEBUG CONSOLE AT 9600 BAUD

User's second AD3 capture (`newacq000{1,2,3}.csv`) captured at 6.25 MS/s with Raw
Events export format.  Decoding bit 9 (the white wire) at **9600 baud** reveals
clean ASCII boot banner from the HK32F lens MCU:

```
version   :1.20
build date:Aug  4 2022
build time:10:02:51
ip moudle :AJ       <-- "module" misspelled in firmware; "AJ" = camera family name
lens      :LH3X     <-- LH3X is the lens model
Watch Dog :Enable
```

The banner repeats at every HK32F reboot, identifying:
- **HK32F firmware version**: 1.20
- **Build timestamp**: Aug 4 2022, 10:02:51
- **Module identifier**: "AJ" — this is the origin of the "AJ protocol" name used
  throughout the project
- **Lens**: LH3X

**Major implication**: the previous hypothesis (white wire = HK32F→STC8G at 66666 baud
binary protocol with `51 01 04 78 01 0D` 6-byte frames) is **WRONG**.  The earlier
PulseView/Nucleo LA decode at 66666 baud was finding spurious repeating patterns from
*misinterpreting a 9600 baud ASCII signal at the wrong rate*.

The white wire is actually the **HK32F's serial debug/command console**:
- 9600 8N1 ASCII
- Boot banner identifying firmware/lens
- Probably accepts text commands (zoom/focus/pan/tilt) during operation
- Acts as the HK32F↔STC8G control link AND as a debug tap accessible to anyone with
  a USB-serial probe

**Tooling that needs updating** based on this correction:
- `hk32_stc8g_decoder.py` — the "6-byte frame + 0x0D delimiter" hypothesis was based
  on the wrong-baud misdecode.  Real protocol is line-oriented ASCII at 9600 baud.
- `pelco_capture.ps1` — already says "not Pelco-D", needs baud changed to 9600.
- `sr_uart_extract.py` — needs no change, just needs to be invoked with `--baud 9600`
  on the existing `.sr` captures to re-decode them.

**Open question (Phase 4b refined)**: what is the ASCII command vocabulary the
HK32F→STC8G console accepts during PTZ operation?  Need a longer capture with
commanded actions to see post-boot traffic.

## SECONDARY FINDING 2026-05-16 — bit 1 has a 115200 binary signal

bit 1 in the same capture shows ~248 transitions over 41 s, decoding at 115200 baud
to a repeating 5-6 byte pattern:

```
66 86 98 60 E6 E6 66 86 98 60 E6 E6 ... 78 66 06 86 98 66 FE
```

This is NOT the AF sync header (`06 66 00 60 80 66 E6 80`), so it's either:
- AF telemetry (HK32F→SoC) which we previously couldn't capture due to the dead
  black-wire connection — and the new tap may be picking up some but missing the
  sync header somehow
- A different protocol entirely on a wire we haven't fully traced yet
- The same signal as bit 9 but my decoder is failing to align at 115200

To resolve: re-run `aj_frame_parser.py` on `ev_b1_115200.bin` (already done — 0
frames found, so this is NOT clean AF data); and probe more wires.

## CURRENT FINDINGS (2026-05) — SUPERSEDES OLD HYPOTHESES

### Protocol architecture (confirmed via continuity tracing + LA captures)

The HK32F lens MCU is the **CENTRAL PTZ RELAY**, not just a zoom/focus controller:

```
SoC main board                    HK32F lens MCU                  STC8G distro MCU
    │                                  │                              │
    │── AF protocol on R2 RED/BLACK ──▶│                              │
    │   (115200 8N1, 20-byte frames)   │                              │
    │   Sync: 06 66 00 60 80 66 E6 80  │                              │
    │                                  │── 66666 baud 8N1 ───────────▶│ Pin 1 (P3.0 RxD)
    │                                  │   white wire via Diode D3    │   (decoded
    │                                  │   Recurring frame:           │    pattern)
    │                                  │   "51 01 04 78 01 0D"        │
    │                                  │                              │
    │── PWM on J6 PWM1 ────────────────────────────────────────────────▶ PT4115 DIM (IR LED brightness)
    │── H-bridge on J8 ────────────────────────────────────────────────▶ Sensor board IR-cut coil
    │── ADC on J7 ─────────────────────────────────────────────────────◀── CDS sensor (via STC8G monitoring)
```

### Connector mapping (IMA80S15 reference design ↔ MC800S labels)

| Datasheet | MC800S label | Function | Status |
|:-:|:-:|---|:-:|
| J1 | R1 (8-pin NET cable) | Ethernet + 12V + status LEDs | ✅ confirmed |
| J2 | R2 (4-pin) | AF UART pair + GND + SPK_EN | ✅ confirmed |
| J3 | L3 (4-pin) | Audio: GND + AUDIO_OUT + AUDIO_IN + GND | ✅ confirmed |
| J4 | L2 (4-pin) | USB header (only GND wired on MC800S) | ✅ confirmed |
| J5 | L1 (2-pin) | RESET (brown wire) + GND | ✅ confirmed |
| J6 | TBD | PWM0 warm + PWM1 IR + GND | ⏳ TBD (likely T1) |
| J7 | TBD | CDS_IN + GND | ⏳ TBD |
| J8 | TBD | IR-CUT × 2 (H-bridge) | ⏳ TBD |

### Brown wire (RESET) — fully traced

```
SoC J5 Pin 1 RESET ─→ brown wire ─→ Distro NET connector Pin 6
                                          │
                                          └→ Distro POE connector (white cable)
                                                │
                                                └→ POE board ─→ brown wire on POE board
                                                                 │
                                                                 └→ HARDWARE RESET BUTTON
                                                                    (camera body pinhole)
```

### Distribution board silkscreen labels (from IMG_5746.jpeg)

- **Top center NET connector**: `12V | GND | LNK | RX+ | RX- | TX+ | TX- | RST` (8 pins from SoC)
- **Left external interface**: `RCUT | RX1 | PTZ | 485A | 485B | RST | LNK | RX± | TX±` — generic silkscreen, 485A/B NOT POPULATED on MC800S
- **LED board connector**: `LED+ | LED- | CDS+ | CDS-`
- **H_MOTOR connector**: `AN | AGND | AOUT | GND | 12V | RX | TX | H_MOTOR`
- **V_MOTOR connector**: stepper for tilt

### IR LED driver chain (CONFIRMED via continuity probe)

```
12V supply ─→ SS24 schottky ─→ PT4115 buck driver ─→ inductor ─→ LED+ ─→ 4× 850nm IR LEDs (series) ─→ LED- ─→ R330 (0.33Ω sense) ─→ GND
                                    │
                                    │ DIM pin (PWM input from SoC J6 PWM1)
                                    │
                                    └─ ULN2803A pin 17 (output 2C) acts as on/off switch for LED chain
```

Current driven: **0.1V / 0.33Ω = 303mA constant current** through the LED string. Verified by measured 11.7V → 5.4V across the string (= 6.3V drop / 4 LEDs ≈ 1.58V/LED at 303mA, matching 850nm IR LED I-V curve).

### ULN2803A (TSSOP-18) — confirmed pin mapping

```
       ┌────────────┐
Pin 1  │1          18│ Pin 18 ← H_MOTOR blue   (OUT 1C)
Pin 2  │2          17│ Pin 17 ← H_MOTOR brown  (OUT 2C, also LED-)
Pin 3  │3          16│ Pin 16 ← H_MOTOR yellow (OUT 3C)
Pin 4  │4          15│ Pin 15 ← H_MOTOR black  (OUT 4C)
Pin 5  │5          14│ Pin 14 ← V_MOTOR        (OUT 5C)
Pin 6  │6          13│ Pin 13 ← V_MOTOR        (OUT 6C)
Pin 7  │7          12│ Pin 12 ← V_MOTOR        (OUT 7C)
Pin 8  │8          11│ Pin 11 ← V_MOTOR        (OUT 8C)
GND    │9          10│ COMMON (motor +12V supply, also LED+ path)
       └────────────┘
```

**Inputs 1-8 all wired to STC8G GPIOs** (confirmed via continuity probing).
**Outputs 11-18 drive H/V stepper coils** (4 per motor).

### HK32F030MF4P6 — silicon debug locked

`DBG_CLK_CTL = 0x12DE` option byte gates the debug clock at silicon level.
Confirmed unreachable via: CubeProgrammer (8 frequencies), OpenOCD HLA (3 configs).
**No software-only path to firmware exists.**

Replacement path: HK32F030MF4P6 dev boards on order ($18.99 5pcs, 8-day ship,
Amazon). With dev boards, we can write our own AF protocol firmware and hot-air
swap a programmed chip into the camera, defeating the lock permanently.

### Captured protocol byte patterns

From LA captures (LogicalRust SUMP firmware on Nucleo F411RE):
- **D5 white wire @ 66,666 baud** decodes to clean UART frames. Recurring 6-byte
  sequence `51 01 04 78 01 0D` appears in multiple captures. `0D` likely frame
  delimiter. Full sequence example:
  ```
  00 0D 51 01 04 78 01 0D 00 E2 00 42 0A 00 03 00 00 0D
  ```
- **D4 black (AF command SoC→HK32F) and D3 yellow** showed activity in some
  captures, no activity in others. Need multi-action diff campaign to decode.
- **D6 red wire dead** — wire connection issue, needs verification before
  proceeding with AF telemetry decode.

### Channel scan results 2026-05-15 (via sr_uart_extract.py)

Verified the captured data against fresh tool pipeline (`sr_uart_extract.py` → `hk32_stc8g_decoder.py`):

| Channel | Baud | capture2.sr | capture3.sr | Verdict |
|---|---|---|---|---|
| D0..D2 | any | 0–1 byte (start-edge noise) | 0–1 byte | unused / GND |
| D3 (yellow) | 66666 | none | 6 bytes garbage | not the right baud/channel for the yellow signal |
| D4 (AF cmd black) | 115200 | **0 bytes** | **0 bytes** | AF UART idle during both captures (no zoom/focus action commanded) |
| D5 (white wire) | 66666 | `51 01 04 78 01 0D` clean | leading FF junk then `51 01 04 78 01 0D` | **baseline heartbeat confirmed** |
| D5 (white wire) | 115200 | 20 bytes garbage | 8 bytes garbage | wrong baud — 66666 is right |
| D6 (AF tlm red) | 115200 | 1 byte (idle high) | 1 byte (idle high) | **wire/connection dead — verified** |
| D7 | any | 1 byte | 1 byte | unused |

Implications:
1. Both captures were **idle baselines** — only the HK32F heartbeat to STC8G is visible
2. Need stock-firmware boot + triggered PTZ commands to see real protocol data
3. D6 needs hardware repair before AF telemetry decode is possible
4. The `0D` trailer in white-wire frames is NOT any standard checksum (sum/XOR/2's-complement all fail) — it's a fixed delimiter (CR character), consistent with the longer-frame variant `00 E2 00 42 0A 00 03 00 00 0D` also seen in capture2.sr

### AD3 capture 2026-05-16 (`acq0001.csv`, 11.6 GB) — labeled boot timeline

User-reported sequence during the 134-second capture (in approximate boot order):

1. **PoE applied** — SoC NRST released, brown wire transitions LOW→HIGH
2. **Zoom reset to 0** — drives zoom motor toward wide-angle limit
3. **Auto-focus** — runs focus sweep, settles on best focus
4. **Pan sweep** (home seek, described as "up-down" by user — may be tilt-axis terminology
   inversion vs. convention)
5. **Tilt sweep** (home seek, described as "left-right")
6. **IR LEDs on** — activated for entire boot sequence and persisting after
7. **User toggled IR off, then back on** — this **retriggered auto-focus** automatically
   (consistent with the IR-cut filter switching causing focal-plane shift; firmware
   compensates by re-running AF)

Strong correlation targets for the decoded protocol bytes:
- AF UART (R2 RED): zoom-reset opcodes, AF-trigger opcodes, pan/tilt commands during seek
- White wire 66666: heartbeat baseline + (probably) commanded IR-state changes when the user
  manually toggled IR
- **IR autonomy answer is now in this capture**: if white wire shows new frames at the IR
  toggle moment, IR is commanded via the protocol relay; if silent (only DIM signal changes),
  STC8G is fully autonomous on IR

The IR-toggle-triggers-AF observation is a useful piece of firmware behavior to remember
when implementing the OpenIPC daemon — toggling IR-cut requires a follow-up AF cycle.



First multi-channel AD3 capture of the camera during boot + idle.  Initial activity
scan of a 1-second slice from -2 s to -1 s relative to trigger:

| Channel | Status | Count (per 1 s) |
|---|---|---|
| **red(HK)** (AF cmd, SoC→HK32F) | ✅ active | 689 falling edges, continuous UART traffic |
| **black(HK)** (AF tlm, HK32F→SoC) | ❌ **stuck LOW** | 1 edge in 1 s — same persistent issue as D6 in earlier captures |
| **whitewire(HK)** (HK32F→STC8G) | idle in this slice | 0 edges (may be active elsewhere — full file processing TBD) |
| **brown(net)** (RESET) | high (camera running) | 0 edges |
| **purple(net)** (LED activity) | mostly high, 2 falling edges | network status indicator |
| **yellow(net)** | stuck LOW | unused / unconnected wire |
| **ULN_1..4** (stepper drive) | all LOW | no stepper activity in this slice |

The persistent **black(HK) stuck LOW** is the same hardware issue from prior captures.
HK32F TX line reads at 1.48 V mid-rail per the earlier voltmeter check — below AD3 digital
threshold (1.65 V) so it always reads as 0.  Wire fix or buffer needed before AF telemetry
can be captured.

Decode of 1-second red(HK) slice produced 439 bytes with the canonical AF sync header
`06 66 00 60 80 66 E6 80` appearing at offsets 0, 22, 44, 65, 87.  **Frame stride is ~22 bytes**
(sync-to-sync), not 20 as previously hypothesized from older USB-serial capture.  Frames may
actually be 22 bytes, or the 20-byte hypothesis was based on captures missing 2 trailing bytes
per frame — to be resolved with full-file decode.

Tooling: `wf_csv_uart.py` (single-channel) and `wf_csv_multi_uart.py` (multi-channel,
one-pass) read the WaveForms CSV by streaming, no full-file load.

#### Full extraction results 2026-05-16

Extracted from full `acq0001.csv` (134 s, 268 M samples, 11.6 GB):

| Channel | Baud | Output | Result |
|---|---|---|---|
| red(HK) AF cmd | 115200 | af_cmd.bin (36,889 bytes) | ✅ **1,435 frames decoded, 77.8% sync-aligned** |
| black(HK) AF tlm | 115200 | af_tlm.bin (1 byte) | ❌ wire stuck low (known hardware issue) |
| whitewire(HK) HK→STC8G | 66666 | whitewire.bin (339 bytes) | ❌ glitch noise, line was idle entire capture middle |

The whitewire channel showed 1,000,000 consecutive HIGH samples in a middle slice with
zero edges — probe was effectively disconnected from real signal during this capture.
Re-verify clip on the actual HK32F 3p-top "IR" pin or distro NET pin 9 for the next run.

#### AF protocol structure refined (from 1435 live boot+idle frames)

Definitive 20-byte frame layout, verified across this capture:

| Bytes | Variance in this capture | Role |
|---|---|---|
| B0–B7 | constant `06 66 00 60 80 66 E6 80` | Sync header |
| **B8** | 16 unique (opcode space) | **Command/state opcode** |
| B9–B14 | 12–16 unique each | Payload (command parameters) |
| B15 | 9 unique | Sub-flag |
| B16 | 3 unique: `{0x00, 0x18, 0x80}` | Status/mode flag |
| B17–B19 | 16 unique each | Tail / response / position data |

Opcode distribution in this boot+idle capture (state byte B8):
- 0x80 (48.6%), 0x1E (31.4%), 0x18 (3.3%), 0x60 (3.0%), 0xE6 (2.3%), 0x66 (1.8%),
  0xE0 (1.7%), 0x78 (1.5%), 0xF8 (1.4%), 0x7E (1.3%), others <1%

Distinct from the historical `hk32115200_red.csv` capture (where B8 was 0x06 89% / 0x00 11%) —
those captures were during commanded actions, this one is mostly boot home-seek + idle.

First two frames at capture offset 59 and 79 have **identical payload** with B8=0x1E —
likely the **first command issued at boot start** (probably zoom-to-zero or AF-init).
Frames 2–30 settle into a B8=0x18 family with consistent payload skeleton — the
**home-seek loop** running.

### AF protocol structure (refined 2026-05-15 from historical hk32115200_red.csv)

USB-serial capture on D6 (red wire = HK32F TX, AF telemetry) from a prior
session captured 2937 frames at 95% sync alignment. Re-analysis confirms:

| Offset | Bytes | Variance | Interpretation |
|---|---|---|---|
| 0-7 | `06 66 00 60 80 66 E6 80` | constant | **sync header** |
| 8 | `0x06` (89%) / `0x00` (11%) | 2 values | **command/state byte** (was hypothesized 0xFE/0xE6 — wrong) |
| 9-13 | many values | 12-16 unique | **payload** (motor speed, action data) |
| 14 | `{00, 06, 80, 98}` | 4 unique | sub-header byte 1 |
| 15 | `{00, 1E, 80}` | 3 unique | sub-header byte 2 |
| 16 | `{00, 1E}` | 2 unique | sub-header flag |
| 17 | `{00, 1E}` | 2 unique | sub-header flag |
| 18-19 | many values | 16+ unique | **status/telemetry, NOT a CRC** (see analysis below) |

CRC hypothesis status (verified 2026-05-15 with `aj_crc_solver.py --auto` against the 2937-frame historical capture):
- No CRC-8 or CRC-16 polynomial matches at any partition tested
- Splitting by state byte (B8 = 0x06 vs 0x00) reveals B18 is overwhelmingly 0x00 in
  state=0x06 frames (~70% of them) — that distribution is inconsistent with a CRC
  (which would spread evenly across all 256 values)
- Top recurring (B18, B19) pairs in state=0x06: `00 00`, `00 FE`, `00 E6`, `00 F8`, `00 7E`...
  These look like **enumerated status codes / position telemetry** (e.g. "zoom position = 0xFE")
  rather than computed checksums
- **Working hypothesis**: the AF protocol has no checksum on this direction; integrity is
  implicit (frames are short, link is local, errors retried at application layer)

The original `aj_frame_parser.py` had a wrong "marker 06 00 1E 00 00" hypothesis
at offset 9-13 (0/2937 matched). Docstring updated 2026-05-15 to reflect actual
structure.

### Tool pipeline for next captures

```
# Offline analysis of PulseView .sr captures:
python sr_uart_extract.py capture.sr --channel 5 --baud 66666 --out white.bin
python hk32_stc8g_decoder.py white.bin

# Live capture via USB-serial during stock-firmware operation:
.\pelco_capture.ps1 -ComPort COM5         # white wire @ 66666 baud, all PTZ actions
.\aj_diff_campaign.ps1 -ComPortRx COM6 -ComPortTx COM7   # bidirectional AF @ 115200

# Then parse:
python hk32_stc8g_decoder.py whitewire_captures\session_*\*.bin
python aj_frame_parser.py aj_captures\session_*\*_RX.bin
python aj_diff_visualizer.py aj_captures\session_*\01_idle_baseline_RX.csv aj_captures\session_*\02_zoom_in_30_RX.csv
python aj_crc_solver.py aj_captures\session_*\*.csv
```

### IR LED upgrade plan (940nm covert)

Ordered: 940nm 3W IR LEDs, 400-700mA, 1.1-1.5V V_f (measured), 3535 SMD with thermal pad.

**Bench-measured I-V curve (single-die confirmed, 2026-05-14):**

| Current | V_f | Per-LED power |
|---|:-:|:-:|
| 50mA | 1.13V | 0.057W |
| 100mA | 1.17V | 0.117W |
| 200mA | 1.24V | 0.248W |
| 300mA | 1.31V | 0.393W |
| 400mA | 1.35V | 0.540W |
| 500mA | 1.39V | 0.695W |
| 600mA | 1.44V | 0.864W |
| 700mA | 1.50V | 1.05W |

Drop-in compatibility:
- Direct swap works at existing R330 (303mA) — but ~50% brightness of original
  850nm (sensor efficiency drops at 940nm).
- For brightness recovery:
  - **R220 (0.22Ω)** → 454mA, ~75% baseline brightness
  - **R150 (0.15Ω)** → 666mA, ~100% baseline brightness (recommended with new IR board thermal pad)

Upgrade to 6 LEDs in series:
- With R330 (303mA): comfortable headroom (3.5V), +50% total IR output
- With R220 (454mA): tight headroom (2.9V), workable
- With R150 (666mA): marginal headroom (2.1V), NOT recommended

### Phase status

| Phase | Status | Blocking |
|---|:-:|---|
| Phase 0 — Hardware mapping | ✅ done | — |
| Phase 1 — Method 1/2 determination | ✅ Method 2 confirmed via trace work | — |
| Phase 2a — AF protocol diff campaign (R2 RED/BLACK) | 🚧 partial captures; need D6 fix + multi-action runs | D6 red wire connectivity |
| Phase 2b — Pelco-D-style white wire capture | 🚧 single captures done at 66666 baud; need diff campaign | — |
| Phase 3 — IR LED PWM path identification | ✅ RESOLVED — STC8G pin 28 (P1.7/PWM6) drives DIM locally via 47Ω | — |
| Phase 4 — Protocol byte-mapping + CRC decode | ⏳ pending | More captures with known triggers |
| Phase 5 — OpenIPC mc800s-ptzd daemon | ⏳ pending | Phase 4 output |
| Phase 6 — End-to-end PTZ verification | ⏳ pending | Phase 5 output |
| Phase 7c — Chip swap fallback | ⏳ Plan B if protocol can't be cleanly replayed | Dev boards arriving (8 days) |

The path forward: brief stock-boot capture session via CH341A flash + USB-serial probes will resolve both unknowns in <30 min. Way more efficient than continued blind RE.
