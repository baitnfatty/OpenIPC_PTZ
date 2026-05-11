# Nucleo F411RE → SUMP Logic Analyzer

Turns the Nucleo F411RE into a SUMP-compatible logic analyzer that works with
[PulseView](https://sigrok.org/wiki/PulseView). Lets us capture multi-channel
digital signals (stepper GPIOs, PWM, UART) without buying dedicated LA hardware.

## What you need

- **Nucleo F411RE** (you have one)
- **USB cable** to plug the Nucleo into your PC (the Nucleo's own USB connector,
  not the STLINK V3 — the Nucleo's onboard ST-Link handles flash + USB CDC for us)
- **STM32CubeProgrammer** installed (already have it)
- **PulseView** — install separately, see "PulseView setup" section below

## Files in this folder

- `LogicAlNucleo.bin` — precompiled SUMP firmware (originally for F401RE,
  works on F411RE for our slow-signal needs)
- `source/` — full source if we ever need to rebuild for F411-specific timing
- `README.md` — this file
- `flash.ps1` — flashes the bin to the Nucleo via CubeProgrammer CLI
- `pinout.md` — channel-to-pin mapping with Morpho header locations
- `pulseview_setup.md` — PulseView install + configuration

## Quick start

```
1. Plug Nucleo into PC via its mini-USB connector (not the STLINK V3)
2. Run: .\flash.ps1
3. Wait for "DONE" message
4. Disconnect and reconnect the Nucleo
5. Open Device Manager — note the COM port for the Nucleo VCP
6. Open PulseView (see pulseview_setup.md)
7. Wire your target signals to PB0-PB7 per pinout.md
8. Start capturing
```

## Caveats — F401 binary on F411

The precompiled binary was built for Nucleo F401RE. The F411RE has slightly
different clocking (100 MHz vs 84 MHz), so:

- ✅ Sample rates up to **~1 MSPS work fine** — our use case
- ⚠ Sample rates 1-5 MSPS — timing may be inaccurate (NOP loops were
  calibrated for F401)
- ❌ 10 MSPS — definitely unreliable on F411

For our captures (UART at 115200 baud, stepper steps at <1 kHz, PWM at tens
of kHz), 1 MSPS is way more than needed. So the F401 binary is fine.

If we ever need higher accuracy, we rebuild from source — see `source/README.md`.

## What the LA can capture

- 8 simultaneous digital channels (PB0-PB7)
- Configurable sample rate up to ~1 MSPS reliable, 5 MSPS less so
- Trigger on rising/falling edge or pattern across channels
- Buffer: 32 KB samples (handful of milliseconds at 1 MSPS)

For our project this means we can capture:
- All 4 ULN2803A pan/tilt GPIO inputs simultaneously (Stage 3b)
- IR-cut H-bridge GPIO pair (Stage 4 supplement)
- IR LED PWM channel (Stage 5)
- Cross-correlate any of these with HK32F UART simultaneously
