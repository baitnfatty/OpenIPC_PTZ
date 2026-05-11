# MC800S PTZ Motor Control — Current State & Plan

## What This Is
JideTech MC800S PTZ camera flashed to OpenIPC. Video works via SSH (192.168.1.10).
PTZ motors don't respond. We're finding which SoC GPIO pad routes through the 8-wire
NET cable to the STC8G motor MCU on the distribution board.

## Hardware Architecture (Short Version)
```
SoC (SSC338Q) --[UART1 Pelco-D 2400baud]--> NET cable (8 wires) --> STC8G MCU --> ULN2803A --> 24BYJ48 steppers
SoC (SSC338Q) --[UART2 VISCA 9600baud]----> NET cable -----------> HK32F030 --> BA6208G --> Zoom/Focus DC motors
```

## What We Know
- Stock firmware uses Pelco-D on /dev/ttyAMA1 (AMBA driver), NOT ttyS1 (ms_uart)
- Stock DTS: `pad = <0x01>` (PAD_PM_UART_TX1) with dual reg windows (0x1F221200 + 0x1F006A00)
- PM_UART hardware works (loopback confirmed)
- PAD_PM_UART_TX1 (GPIO 1) is **NOT** connected to NET cable
- PAD_GPIO0 (GPIO 59) is **NOT** on NET cable — goes to unpopulated 3-pin header on SoC board
- NET cable has two 3.3V wires on the distribution board side
- ~~One NET cable wire bounces 400mV to 1mV (possibly UART idle/traffic)~~ — **CORRECTED 2026-05-03: that wire is actually steady at 3.3V, not dancing. No active UART traffic observed on any NET cable wire while OpenIPC is silent.**

## GPIO Pad Scan — Current Progress
Method: Export GPIO as output, set LOW, user checks if 3.3V NET cable wire drops.
One pad at a time, wait for user confirmation.

### Completed (all NEGATIVE — no voltage change on NET cable):
| Pad Name | GPIO # | Result |
|----------|--------|--------|
| PM_UART_TX1 | 1 | No (separate test) |
| PM_GPIO0 | 6 | No |
| PM_GPIO1 | 7 | No |
| PM_GPIO2 | 8 | No |
| PM_GPIO3 | 9 | No |
| PM_GPIO5 | 11 | No (vs wire #2) |
| GPIO0 | 59 | No (found on unpopulated 3-pin header, not NET cable) |

### HITS:
| Pad Name | GPIO # | NET Wire | Notes |
|----------|--------|----------|-------|
| **PM_GPIO4** | **10** | **BROWN wire — 6th from left on back of NET connector** (from 2-pin header on SoC board, only one wire populated) | Confirmed by toggle (low→drop, high→3.3V). One of two 3.3V lines on the NET cable. Likely TX or RX of UART1 to STC8G. |

### Wire-#2 scan (starting from the top of GPIO numbering — prior negatives were vs wire #1 only, so retest needed):
Tested vs wire #2:
| Pad Name | GPIO # | Result |
|----------|--------|--------|
| PM_UART_RX1 | 0 | No |
| PM_UART_TX1 | 1 | No |
| PM_GPIO5 | 11 | No |
| PM_GPIO6 | 12 | unconfirmed (driven low but user reset before answering) |
| GPIO 2 | 2 | Skipped — wrote 0, read back 1 (pad muxed away from GPIO function or strongly held HIGH) |
| GPIO 4 | 4 | No |
| GPIO 3 | 3 | No (readback was 1 but user probe confirms no drop) |
| GPIO 5 | 5 | No |
| PM_GPIO0 | 6 | No |
| PM_GPIO1 | 7 | No |
| PM_GPIO2 | 8 | No |
| PM_GPIO3 | 9 | No |
| PM_GPIO6 | 12 | No |
| PM_GPIO9 | 15 | No |
| PM_GPIO10 | 16 | No |
| PM_SPI_CZ | 17 | No |
| PM_SPI_CK | 18 | No |
| FUART_RX | 46 | No |
| FUART_TX | 47 | No |
| FUART_CTS | 48 | No |
| FUART_RTS | 49 | No |
| PM_UART_RX | 2 | No (saw +20mV bump, not correlated on toggle — noise) |
| PM_SPI_DI | 19 | No |
| PM_SPI_DO | 20 | Skipped per user (jumped to GPIO 60) |
| GPIO1 | 60 | No |
| GPIO2 | 61 | No |
| GPIO3 | 62 | No |
| GPIO4 | 63 | No |
| GPIO5 | 64 | No |
| GPIO6 | 65 | No |
| GPIO7 | 66 | No |
| GPIO8 | 107 | No |
| GPIO9 | 108 | No |
| GPIO10 | 109 | No |
| GPIO11 | 110 | No |
| GPIO12 | 111 | No |
| GPIO13 | 112 | No |
| GPIO14 | 113 | No |
| **GPIO15** | **114** | **NEXT** |
| PM_GPIO6 | 12 | Pending |
| PM_GPIO9 | 15 | Pending |
| PM_GPIO10 | 16 | Pending |
| I2S0_BCK | 38 | Pending |
| I2S0_WCK | 39 | Pending |
| I2S0_DI | 40 | Pending |
| I2S0_DO | 41 | Pending |
| I2C0_SCL | 42 | Pending |
| I2C0_SDA | 43 | Pending |
| ETH_LED0 | 44 | Pending |
| ETH_LED1 | 45 | Pending |
| FUART_RX | 46 | Pending |
| FUART_TX | 47 | Pending |
| FUART_CTS | 48 | Pending |
| FUART_RTS | 49 | Pending |
| GPIO1 | 60 | Pending |
| GPIO2 | 61 | Pending |
| GPIO3 | 62 | Pending |
| GPIO4 | 63 | Pending |
| GPIO5 | 64 | Pending |
| GPIO6 | 65 | Pending |
| GPIO7 | 66 | Pending |
| GPIO8 | 107 | Pending |
| GPIO9 | 108 | Pending |
| GPIO10 | 109 | Pending |
| GPIO11 | 110 | Pending |
| GPIO12 | 111 | Pending |
| GPIO13 | 112 | Pending |
| GPIO14 | 113 | Pending |
| GPIO15 | 114 | Pending |

Note: PM_GPIO7 (13) and PM_GPIO8 (14) are in use by the system — skip these.

## How To Toggle A Pad (SSH commands)
```bash
# Set LOW:
echo N > /sys/class/gpio/export
echo out > /sys/class/gpio/gpioN/direction
echo 0 > /sys/class/gpio/gpioN/value

# Release (back to input):
echo in > /sys/class/gpio/gpioN/direction
echo N > /sys/class/gpio/unexport
```

## Once The Correct Pad Is Found
1. Route UART1 to that pad via DIGMUX registers (devmem writes)
2. Configure 2400 baud 8N1 on /dev/ttyS1
3. Send Pelco-D test commands
4. Update DTS patch if needed
5. Build OpenIPC firmware with corrected DTS

## Key Source Files (WSL)
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\drivers\sstar\serial\infinity6e\uart_pads.c` — pad mux functions
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\drivers\sstar\serial\infinity6e\ms_uart.h` — MUX defines
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\drivers\sstar\serial\ms_uart.c` — main UART driver
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\drivers\sstar\gpio\infinity6e\mhal_pinmux.c` — full pad mux register table
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\drivers\sstar\include\infinity6e\gpio.h` — pad numbering (PAD_PM_UART_RX1=0 through GPIO_NR=127)
- `\\wsl.localhost\Ubuntu\opt\openipc\linux-sigmastar\arch\arm\boot\dts\infinity6e-ssc012b-s01a.dts` — board DTS
- `\\wsl.localhost\Ubuntu\opt\openipc\firmware\general\package\all-patches\linux\0050-mc800s-uart1-pm-uart-pads.patch` — our DTS patch

## Key Register Info
- PM_PADTOP_BANK=0x003F00, PADTOP_BANK=0x103C00, BASE_RIU_PA=0xFD000000
- REG_UART_MODE=0x1F2079B4, REG_UART_SEL=0x1F203D4C
- PM_UART reg window: 0x1F006A00
- UART1 reg window: 0x1F221200

## Full Plan (if pad scan fails or after)
See the detailed plan in the CLAUDE.md plan file. Key phases:
1. **Phase 1 (NOW)**: GPIO pad scan to find NET cable UART wire
2. **Phase 2**: Direct pad mux register writes via devmem
3. **Phase 3**: Pelco-D test on correctly muxed UART
4. **Phase 4 (fallback)**: Direct GPIO stepper control bypassing STC8G
5. **Phase 5 (when logic analyzer arrives)**: Capture stock firmware signals

---

## 🔴 SESSION UPDATE 2026-05-04 — CRITICAL FINDINGS

**See master:** `C:\Users\matth\investigate\MC800S-system-map.md`

### Brief summary
- ✅ R2 red+black = VISCA UART pair (FUART_TX=47, FUART_RX=46) — SoC TX confirmed working
- ✅ Brown wire = PM_GPIO4 (sysfs gpio 10) confirmed via GPIO scan
- ❌ HK32F never responded to VISCA at 9600 (or any other baud) — protocol/wake unknown
- 🔴 **MAJOR:** Stock has Method 1 (kernel PWM motor driver) vs Method 2 (UART MCU). If MC800S uses Method 1, the entire PT UART struggle is unnecessary.
- 🔴 Stock console is 38400 8N1 with RTS/CTS hw flow control (not 115200)
- 🔴 SD card update filename = `MC800S2_V0` (TFTP filename TBD)
- ⏳ Purple wire on NET shows activity during boot but no clean baud match yet

### Recommended next action
Brief stock-flash via CH341A + USB-serial capture session (~30 min). Resolves 4 of 5 outstanding questions definitively.

### Key flag to check when stock is running
`ls /opt/ch/motor_ctrl_use_pwm.flag` — presence = Method 1 active = STC8G bypass possible.
