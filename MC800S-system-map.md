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

### T2 — possibly CN2 (per IP Cam Talk thread!)
We thought "grouping of caps" but might be 6-pin debug header:
- Pins 1-2: UART1 TX/RX (Pelco-D 2400 to STC8G)
- Pins 3-4: UART2 TX/RX (VISCA 9600 to HK32F)
- Pin 5: GND
- Pin 6: 12V

**RE-INSPECT THIS AREA** — if 2x3 unpopulated solder pads, it's CN2.

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

## REVISED: IR LED PWM path is unknown

Earlier hypothesis that the white "IR" wire was IR LED PWM control was WRONG. The white
wire is Pelco-D UART (above). The IR LED PWM signal must travel on a different,
unidentified wire from SoC J6 PWM1 to PT4115 DIM pin on distro board.

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

### IR LED upgrade plan (940nm covert)

Ordered: 940nm 3W IR LEDs, 300-700mA, 1.2-1.6V V_f, 3535 form factor.

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
| Phase 3 — IR LED PWM path identification | ⏳ pending | Camera-on probe of T1 pin 3 during night mode |
| Phase 4 — Protocol byte-mapping + CRC decode | ⏳ pending | More captures with known triggers |
| Phase 5 — OpenIPC mc800s-ptzd daemon | ⏳ pending | Phase 4 output |
| Phase 6 — End-to-end PTZ verification | ⏳ pending | Phase 5 output |
| Phase 7c — Chip swap fallback | ⏳ Plan B if protocol can't be cleanly replayed | Dev boards arriving (8 days) |

The path forward: brief stock-boot capture session via CH341A flash + USB-serial probes will resolve both unknowns in <30 min. Way more efficient than continued blind RE.
