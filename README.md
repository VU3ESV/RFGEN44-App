# RFGEN44 for macOS

A native macOS app and command-line tool for the
[CircuitValley RFGEN44](https://www.circuitvalley.com/2025/08/rfgen44-open-source-ghz-usb-rf-signal-generator.html)
USB RF signal generator (35 MHz – 4.4 GHz, ADF4351).

The manufacturer provides a Qt application and a Python CLI for Linux and
Windows ([circuitvalley/ADF4351_USB_RF_GEN](https://github.com/circuitvalley/ADF4351_USB_RF_GEN)).
This project gives the Mac the same features, built with SwiftUI and IOKit.
It needs no drivers, hidapi or Qt.

## Install

Requires macOS 14 or later. The app is universal (Apple silicon + Intel).

**From a release:** download `RFGEN44-<version>.dmg` from
[Releases](https://github.com/VU3ESV/RFGEN44-App/releases), open it and drag
**RFGEN44.app** to Applications. Releases are signed with Developer ID and
notarized by Apple. The CLI is inside the app:
`sudo ln -sf /Applications/RFGEN44.app/Contents/Helpers/rfgen44 /usr/local/bin/rfgen44`.

**From source:**

```sh
git clone https://github.com/VU3ESV/RFGEN44-App.git
cd RFGEN44-App
scripts/install-local.sh          # builds, installs /Applications/RFGEN44.app (+ rfgen44 CLI)
```

Or build only: `VERSION=0.1.0 scripts/build-app.sh` → `dist/RFGEN44.app` and `dist/rfgen44`.

A source build is ad-hoc signed. If you copy it to another Mac, clear the
quarantine flag once: `xattr -dr com.apple.quarantine /Applications/RFGEN44.app`.

## Using the app

Plug in the RFGEN44. It appears in the **RF Gen USB Device** picker at the
bottom of the window, and the title bar shows its firmware and serial number.
By default the app reads the device's current state on connect and does not
overwrite it (see **Settings → Connection**).

- **Control**: set the frequency on the dial. Click a digit, then use ↑/↓,
  the scroll wheel, or type a digit. Also on this tab: RF power, the signal-path
  diagram (click **RF OUT** to toggle the output), the PC-driven sweep/hop, and
  the settings stored in flash (AUX function, load-on-boot, in-device sweep,
  Program/Erase Flash).
- **Macro**: 2–14 steps of frequency, dwell and RF on/off. Run them from
  the Mac, or use **Program Macro to Flash** for standalone operation (needs
  device firmware 2.0+).
- **Advanced Control**: every ADF4351 register field, the six register words
  (edit and **Write** to send raw values), **Read from Device**, and the PLL
  summary with datasheet-limit warnings.
- **Auto Write** sends every change immediately. Turn it off to stage
  changes and press **Write**.
- **File → Import/Export Profile** saves all settings, sweep and macro as JSON.
- The **Device** menu has RF (⌘R), Write (⌘↩), Identify (⌘I), Stop (⌘.) and the
  flash operations.

## Command line

`rfgen44` accepts the same options as the upstream `rfgen44.py`:

```sh
rfgen44 -l                                   # list devices
rfgen44 -i                                   # firmware version
rfgen44 -f 433.92 -w -r on                   # tune and enable RF
rfgen44 -f 100 -t                            # save 100 MHz to flash
rfgen44 -p 100.0,200.0,1.0,50                # standalone sweep in flash
rfgen44 -m --macrostep 100,500,on --macrostep 200,500,on --macrostep 100,1000,off
rfgen44 --readregs                           # read R0–R5 back from the device
```

Extras: `--power -4|-1|2|5`, `--aux syncout|syncin|extref`, `--ref MHZ`,
`--macro-rf-encoding standard|inverted`. Run `rfgen44 -h` for everything. Inside
the app bundle the CLI is at `RFGEN44.app/Contents/Helpers/rfgen44`.

## Feature parity

| Upstream feature (Qt 2.0.0.5 / Python CLI)          | macOS |
|------------------------------------------------------|:-----:|
| Frequency 35–4400 MHz in 10 kHz steps                | ✓ dial + field |
| Click-a-digit adaptive step size                     | ✓ dial (click, ↑/↓, scroll, type) |
| RF power (−4 / −1 / +2 / +5 dBm)                     | ✓ |
| Signal-path pictogram, click to toggle RF            | ✓ |
| Firmware / serial in title and footer                | ✓ |
| Sweep/hop: start, end, step, dwell, loop, step info  | ✓ + progress bar |
| AUX pin: Sync Out / Sync In / Ext Ref                 | ✓ |
| Flash load on boot, in-device sweep                  | ✓ |
| Program Flash, Erase Flash                           | ✓ (erase asks first) |
| Device busy indicator                                | ✓ |
| Program serial number (production build)             | ✓ Settings → Factory tools |
| 14-step macro, auto "Recal PLL", loop, step highlight, elapsed time | ✓ |
| Program macro to flash (firmware 2.0+)               | ✓ |
| Every ADF4351 field (R0–R5)                          | ✓ |
| Hex register view, raw edit + Write                  | ✓ |
| Multiple devices by serial, hot-plug                 | ✓ |
| Identify (LED blink), Auto Write / Write, RF toggle  | ✓ |
| CLI: list, info, write, flashwrite, identify, erase, rfstate, programsweep, programmacro | ✓ `rfgen44` |

**macOS additions:** reads the device's live registers and decodes them;
leaves the device untouched on connect by default; shows PLL values (PFD,
INT/FRAC/MOD, VCO, band-select clock) with datasheet-limit warnings; uses
exact 10 kHz arithmetic (upstream truncation sends some frequencies 10 kHz
low); saves settings between launches; imports and exports JSON profiles;
adds menus and keyboard shortcuts.

## Hardware status

- **Verified on a real RFGEN44 (firmware 1.5.456):** enumeration, firmware
  query, RF state query and register read-back. The read-back matches this
  project's register calculation bit for bit.
- **Not yet verified on hardware:** the write paths (set frequency, RF
  on/off, identify, program/erase flash, sweeps). They follow the upstream
  protocol byte for byte and are covered by unit tests.
- **Firmware 2.x macros:** the upstream tools disagree on how a step's RF
  state is encoded. If a macro programmed to flash runs with RF inverted,
  change **Settings → Macro → RF flag encoding**.

## Development

```sh
swift test               # unit tests
swift run RFGEN44App     # run the GUI from source
swift run rfgen44 -l     # run the CLI from source
```

Releases: push a `vX.Y.Z` tag (or run the Release workflow) and GitHub Actions
builds, signs, notarizes and publishes the DMG. Setup is in
[docs/SIGNING-SECRETS.md](docs/SIGNING-SECRETS.md).

See [CLAUDE.md](CLAUDE.md) for architecture and the plan, and
[docs/PROTOCOL.md](docs/PROTOCOL.md) for the USB protocol.

## License

This repository's code is MIT-licensed (see [LICENSE](LICENSE)). It contains
no upstream code: the RFGEN44 hardware, firmware and CircuitValley's software
are © CircuitValley and licensed CC BY-NC-ND 4.0 in their own repository.
RFGEN44 and CircuitValley are names of their respective owner. This project
is not affiliated with them.
