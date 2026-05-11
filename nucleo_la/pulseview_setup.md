# PulseView — Install + Configure for LogicAlNucleo

PulseView is the GUI front-end for sigrok. It speaks the SUMP protocol our
Nucleo firmware uses, so once flashed the Nucleo appears as a logic analyzer
in PulseView.

## Install (Windows)

1. Go to https://sigrok.org/wiki/Downloads
2. Under "PulseView (binary distribution)" → download the **64-bit Windows installer**
3. Run the installer with default options
4. Plug in the flashed Nucleo (with its USB cable to PC)

The installer also bundles `sigrok-cli`, the command-line version. Either works.

## First-time configuration

1. **Open PulseView**
2. Click **"Connect to Device"** (the icon that looks like a USB plug, top-left)
3. In the dropdown, choose driver: **"Openbench Logic Sniffer & SUMP-compatibles (ols)"**
4. Set **Interface: Serial port**
5. **Serial port:** pick the COM port that appeared when you plugged in the
   Nucleo. Should be labeled "STMicroelectronics Virtual COM Port" in Device Manager.
6. **Baud rate:** 115200 (the SUMP protocol default — this is the *control*
   baud, not the sample rate)
7. Click **Scan for devices**
8. The Nucleo should appear in the list. Click **OK**

If it doesn't appear:
- Try replugging the Nucleo
- Verify the COM port is correct in Device Manager
- The flash may have failed — re-run `.\flash.ps1`

## Capture configuration

After connection:

| Setting | Recommended |
|---|---|
| **Sample rate** | 1 MHz (1 MSPS) for our purposes — slow signals |
| **Number of samples** | 8192 to start (leaves headroom for trigger) |
| **Channels enabled** | tick D0-D7 as needed (or just the ones you wired) |
| **Trigger type** | "Falling edge on D0" or "rising edge" depending on your target |

Hit **Run** (the green play button). PulseView captures and displays the
waveforms.

## Built-in test mode

The LogicAlNucleo firmware has a self-test mode that generates known PWM
signals on its own pins, then captures them. Useful for verifying the LA
works before wiring to the camera.

To trigger test mode: not exposed via PulseView directly — you'd need to
send a specific SUMP command. For now, easier sanity check is:

1. Wire CH0 (PB0) to the Nucleo's own user button (B1 / blue button)
2. Capture
3. Press the button → you should see a transition from high to low (or
   v.v., depending on pull-up direction)

## Useful PulseView features for our work

- **Decoders** (View → Decoders) — adds protocol decoders. We need:
  - **UART** — for the AJ protocol on HK32F TX line
  - **Manchester** or **NRZI** — if any signal turns out to use these
  
- **Cursor / measure** — shift-click to drop a cursor, useful for measuring
  pulse widths and intervals

- **Zoom** — Ctrl+scroll, or the +/- buttons. Captures get dense fast.

- **Search** — look for specific patterns within the capture

- **Save session** — File → Save → `.sr` format. Reopens with all decoders
  intact.

- **Export** — File → Export → CSV (text), VCD (waveform format),
  or other tools' formats

## Cross-correlating LA captures with our existing tools

PulseView can decode UART and export the decoded text. For the AJ protocol
specifically:

1. Set up a UART decoder on whichever channel has R2 RED (HK32F TX)
2. Configure: 115200 baud, 8 data, no parity, 1 stop, MSB last
3. Capture during a PTZ action
4. Decoder shows hex bytes inline with the GPIO transitions
5. Compare frame timing to GPIO state changes

This is exactly what enables Stage 3b (Method 1 pan/tilt GPIO bit-bang
capture) and the cross-correlation we want.

## Sigrok-cli alternative (scriptable)

If you prefer command-line/scriptable captures:

```cmd
:: Capture 8 channels at 1 MHz for 1 second
sigrok-cli -d ols:conn=COM5 -c samplerate=1000000 --samples 1000000 -o capture.sr

:: Decode UART from the capture
sigrok-cli -i capture.sr -P uart:rx=D0 --protocol-decoders uart
```

This pairs well with our existing `aj_diff_campaign.ps1` — we can launch a
sigrok capture in parallel with the UART captures.
