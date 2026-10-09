# Changelog

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
