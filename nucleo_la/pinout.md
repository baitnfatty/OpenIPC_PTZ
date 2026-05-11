# Nucleo F411RE — LogicAlNucleo Channel Pinout

The SUMP firmware samples Port B pins 0-7 as the 8 logic analyzer input channels.
On the Nucleo F411RE, these PB pins are **scattered** across the headers — not
contiguous. Here's where each one is.

## Channel → header pin mapping

| Channel | F411 pin | Arduino-style header (CN5/CN6/CN8/CN9) | Morpho header |
|:-:|:-:|:-:|:-:|
| **CH0** | PB0 | A3 (CN8 pin 4) | CN10 pin 31 |
| **CH1** | PB1 | — (not on Arduino headers) | CN10 pin 7 |
| **CH2** | PB2 | — (BOOT1 strap — see warning) | CN10 pin 22 |
| **CH3** | PB3 | D3 (CN9 pin 4) | CN10 pin 15 |
| **CH4** | PB4 | D5 (CN9 pin 5) | CN10 pin 27 |
| **CH5** | PB5 | D4 (CN9 pin 6) | CN10 pin 29 |
| **CH6** | PB6 | D10 (CN5 pin 3) | CN10 pin 17 |
| **CH7** | PB7 | — (not on Arduino headers) | CN7 pin 21 |

## Important: PB2 is BOOT1

PB2 is the BOOT1 strap on F411RE. Driving PB2 high during reset can put the
chip in a different boot mode. Two options:

1. **Use only CH0, CH3-CH7 (skip CH1, CH2)** — gives you 6 channels but avoids
   any strap concerns. Plenty for our needs.
2. **Or use CH2 carefully** — make sure your input signal is LOW when the Nucleo
   resets. Most logic signals are LOW during the brief reset window so this
   usually works, but it's a trap if your signal idles HIGH.

For our PTZ campaign, we mostly need 4-6 channels (4 stepper GPIOs + maybe
PWM + maybe UART), so skipping CH1/CH2 is fine.

## Recommended channel assignments for our captures

### Stage 3b — Method 1 pan/tilt GPIO capture

Wire the 4 ULN2803A inputs to:

| Channel | Connection |
|:-:|:-|
| CH0 (PB0, A3) | ULN2803A pin 1 (pan coil A+) |
| CH3 (PB3, D3) | ULN2803A pin 2 (pan coil A-) |
| CH4 (PB4, D5) | ULN2803A pin 3 (pan coil B+) |
| CH5 (PB5, D4) | ULN2803A pin 4 (pan coil B-) |

Plus: GND from any Nucleo GND pin (e.g. CN6 pin 7 or CN10 pin 11).

For tilt, swap to ULN2803A pins 5-8 or use CH6/CH7 in addition.

### Stage 5 — IR LED PWM

| Channel | Connection |
|:-:|:-|
| CH0 (PB0) | IR LED PWM line (camera-side) |
| GND | NET cable GND |

Single channel is enough for PWM frequency + duty measurement.

### Cross-correlation: GPIO + UART

If you want to capture HK32F UART traffic alongside GPIO state changes, wire:

| Channel | Connection |
|:-:|:-|
| CH0 (PB0) | R2 RED (HK32F TX) |
| CH3 (PB3) | R2 BLACK (SoC TX) |
| CH4 (PB4) | ULN2803A pan input 1 |
| CH5 (PB5) | ULN2803A pan input 2 |
| CH6 (PB6) | ULN2803A tilt input 1 |
| CH7 (PB7) | ULN2803A tilt input 2 |

Then trigger PTZ commands and see UART + GPIO toggles in the same timeline.
PulseView's UART decoder will reconstruct ASCII/hex from CH0/CH3.

## Voltage levels

The F411 is a 3.3V chip. Inputs are **5V-tolerant** on most pins (PB0-PB7
included), so you can probe either 3.3V or 5V signals safely.

For our targets:
- ULN2803A inputs: 3.3V (driven by SoC GPIOs) — direct connection fine
- HK32F UART: 3.3V — direct
- IR LED PWM: 3.3V — direct
- ANY 5V source: also fine due to 5V tolerance

## Probe leads

Cheap option: jumper wires (male-to-female 20-pack from any electronics
hobby site). Stick the male end into the Nucleo header, alligator clip or
tack the female end to the camera signal point.
