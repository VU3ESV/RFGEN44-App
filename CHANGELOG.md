# Changelog

## 0.1.2 — 2026-10-11

- **Fix: after a firmware update the display didn't match the output.**
  Firmware 2.0.501 starts with no settings loaded when a firmware update
  has erased flash. It then puts out ~113.37 MHz, and the register read-back
  is blank (all `0xFF`). The app showed its own saved frequency and wrote
  nothing. It now recognises the blank read-back and writes its settings on
  connect, as the upstream app does, so the display matches the output
  (Auto Write on; RF on/off untouched).
- `rfgen44 --readregs` reports a blank read-back as "no settings loaded"
  and exits non-zero, rather than printing six `0xFFFFFFFF` registers.
- Hardware-verified on firmware 2.0.501: SET_REG and RF on measured on a
  spectrum analyser at 100, 433.92, 1000 and 2400 MHz (all within 0.3 ppm),
  and register read-back, which on 2.0.501 also returns the rest of the
  settings block.

## 0.1.0 — 2026-10-09

First version.

- `RFGen44Kit`: ADF4351 register solver and decoder, the RFGEN44 USB protocol
  (all commands used by the upstream Qt 2.0.0.5 app and Python CLI), macro
  and sweep models, and an IOKit HID transport with a serialised query queue.
- SwiftUI app with Control, Macro and Advanced Control tabs, the device bar,
  sweeps and macros driven from the Mac, flash program/erase, identify, JSON
  profiles and settings.
- `rfgen44` CLI, option-compatible with upstream `rfgen44.py`, plus
  `--readregs`, `--power`, `--aux` and `--ref`.
- Release workflow: a `vX.Y.Z` tag builds a Developer ID-signed,
  notarized and stapled `RFGEN44-<version>.dmg` and publishes it as a GitHub
  Release.
- Hardware-verified read paths on an RFGEN44 running firmware 1.5.456. A
  device left at the Qt defaults reads back the registers this project
  computes, bit for bit.
