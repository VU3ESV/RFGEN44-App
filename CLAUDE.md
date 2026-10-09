# CLAUDE.md — RFGEN44-App

Native macOS app and CLI for the **CircuitValley RFGEN44**, a USB-HID RF
signal generator (35 MHz – 4.4 GHz, Analog Devices ADF4351 + PIC16F1459).
The manufacturer ships a Qt GUI and a Python CLI for Linux and Windows at
[circuitvalley/ADF4351_USB_RF_GEN](https://github.com/circuitvalley/ADF4351_USB_RF_GEN);
this repo brings the same feature set to the Mac as a SwiftUI app plus an
option-compatible `rfgen44` command-line tool.

Human-facing install and usage: [README.md](README.md). Wire format:
[docs/PROTOCOL.md](docs/PROTOCOL.md) — read it before touching packet
layouts, adding a command, or debugging device behaviour.

## Goals

1. **Feature parity** with upstream Qt app 2.0.0.5 and `rfgen44.py` — every
   control they expose works here (matrix in README).
2. **Mac-native**: SwiftUI, IOKit HID (no hidapi, no Qt, no drivers), universal
   binary, single window, menus with shortcuts.
3. **Correct register maths**, pinned by tests and by hardware read-back.
4. **Safe with real hardware**: never change a device's state on connect
   unless the user asks for it.

## Plan

- [x] M0 — Kit: ADF4351 solver + decoder, protocol encoders, macro/sweep
      models, IOKit transport with serialised query queue; unit tests.
- [x] M1 — `rfgen44` CLI with the Python tool's flags; verified read paths
      (`-l`, `-i`, `-r`, `--readregs`) on hardware (fw 1.5.456).
- [x] M2 — SwiftUI app: Control / Macro / Advanced tabs, device bar,
      app-driven sweep and macro, flash program/erase, identify, profiles,
      settings; `.app` packaging scripts.
- [ ] M3 — Hardware validation of **write** paths (SET_REG, RF_CTRL,
      identify, program/erase flash, in-device sweep) with a spectrum
      analyser; record results in CHANGELOG.
- [ ] M4 — Firmware 2.x: confirm macro RF-flag encoding and whether
      SET_MACRO alone enables the macro (see Open questions); then lock the
      default.
- [ ] M5 — Distribution: tag-triggered release workflow (Developer ID
      signing, notarisation, DMG) is in place, gated on the secrets in
      [docs/SIGNING-SECRETS.md](docs/SIGNING-SECRETS.md). Done when the
      secrets are set and v0.1.0 ships notarised. No per-push CI: macOS
      runners cost private-repo minutes — confirm with the owner first.
- [ ] M6 — Optional: MenuBarExtra (RF toggle + frequency), RadioPluginKit
      module for the Amateur Radio Suite, macro import from CSV.

## Working with the connected device

A real RFGEN44 is often plugged into the dev Mac. Treat it as lab equipment
in use: read-only commands (`0x82`, `0x83`, `0xB0`, `rfgen44 -l/-i/-r/--readregs`)
are fine anytime; anything that writes (SET_REG, RF_CTRL, DEVICE_CTRL incl.
identify, SET_MACRO, SET_SERIAL) needs the owner's go-ahead in the session.
Identify counts as a write: its packet carries a full settings block.

## Architecture decisions

- **One HID thread.** `HIDRunLoop` owns a dedicated CFRunLoop; the
  IOHIDManager, input callbacks and the command queue live there. The GUI
  hops to `@MainActor`; the CLI blocks on semaphores. This is why the CLI
  needs no run loop of its own.
- **Serialised commands.** `RFGenConnection` sends one report at a time and
  waits for the echoed reply on queries (firmware has a single IN buffer).
  Register writes share a `coalesceKey` so dial-spinning collapses to the
  latest value.
- **Write failure = disconnect**, as in upstream; the app reconnects when the
  device re-enumerates.
- **On connect, read — don't write.** Default `OnConnectBehavior` reads the
  live registers (`0x83`) and decodes them; upstream instead pushes its own
  settings. Both are selectable in Settings.
- **Run IDs** guard the sweep/macro tasks in `AppModel` so a cancelled run
  can't clobber the next one.
- **No upstream code is copied.** Upstream is CC BY-NC-ND 4.0 (no
  derivatives); this is a clean-room implementation of the protocol. Keep it
  that way — re-derive from behaviour and the ADF4351 datasheet.

## Open questions (upstream disagreements)

1. **Macro RF flag.** `rfgen44.py` writes `RF_ON` for an "on" step; Qt
   2.0.0.5 writes `RF_OFF` for "on". Firmware 2.x source is unpublished.
   Exposed as `MacroRFFlagEncoding` (Settings → Macro, CLI
   `--macro-rf-encoding`); default `.standard` (Python). Resolve on fw 2.x
   hardware.
2. **Macro enable.** Python follows SET_MACRO with DEVICE_CTRL(flash,
   `isMacroEnabled = 1`); Qt sends only SET_MACRO. We follow Python.
3. **AUX "internal reference out".** The datasheet lists four AUX functions;
   both apps expose three (`aux_select` 0–2). Value 3 is unconfirmed.
4. **`0x83` GET_REG on fw 2.x** — works on 1.5.456; unknown on 2.x. The app
   tolerates a timeout.

## Commands

```sh
swift test                              # Kit unit tests (register maths, packets, macro, sweep)
swift run RFGEN44App                    # debug GUI
swift run rfgen44 -l -i -r              # CLI against the connected device (read-only)
VERSION=0.1.0 scripts/build-app.sh      # universal dist/RFGEN44.app (+ dist/rfgen44)
scripts/install-local.sh                # build + copy to /Applications
VERSION=0.1.0 scripts/package-signed.sh # signed + notarised DMG (ad-hoc without secrets)
git tag v0.1.0 && git push origin v0.1.0  # CI release (.github/workflows/release.yml)
```

## Conventions

- Mirrors the sibling repos (LP-700-App, SO2RBoxApp): SwiftPM, macOS 14,
  `scripts/build-app.sh`, ad-hoc signing, `com.vu3esv.*` bundle IDs.
- Frequencies cross the wire as `UInt32` 10 kHz units via
  `ADF4351.tenKHzUnits` — round there, never truncate (upstream truncates,
  so 35.05 MHz goes out as 35.04; ~5 % of the 10 kHz grid is affected).
- New wire behaviour lands with a byte-level test in `ProtocolTests` or
  `MacroTests`; new register behaviour with a case in `RegisterTests`
  (the `testWholeBandIsExact` sweep must stay green).
