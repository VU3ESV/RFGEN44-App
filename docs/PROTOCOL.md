# RFGEN44 USB protocol

Reverse-documented from the upstream sources at
[circuitvalley/ADF4351_USB_RF_GEN](https://github.com/circuitvalley/ADF4351_USB_RF_GEN)
(Qt app 2.0.0.5 `hid_pnp.{h,cpp}` / `usbioboard.cpp`, `PythonApplication/rfgen44.py`,
`Firmware_source/` 1.x). The code of truth in this repo is
`Sources/RFGen44Kit/DeviceProtocol.swift` and `Macro.swift`; tests pin every byte.

## Transport

- USB HID, VID `0x1209`, PID `0x7877`, vendor usage page `0xFF00`.
- One 64-byte report each way, **no report ID**. hidapi callers prepend a
  `0x00` report-ID byte (65-byte buffers); IOKit takes the 64 bytes directly
  with `reportID = 0`.
- OUT byte 0 = command. IN replies echo the command in byte 0.
- The firmware has a single IN buffer and drops a reply if the previous one
  has not been read, so queries are serialised: send, wait for the echo (or
  time out), then send the next. `RFGenConnection` enforces this.
- Devices are told apart by USB serial string (e.g. `RFGEN44003FC`).
  Manufacturer string on firmware 1.5 is `"CicuitValley "` (sic).

## Commands

| Cmd    | Name             | OUT payload (after byte 0)                         | IN reply                              | Used by |
|--------|------------------|----------------------------------------------------|---------------------------------------|---------|
| `0x80` | SET_REG          | settings block (56 B)                              | —                                     | Qt, Py  |
| `0x81` | RF_CTRL          | `[on]` (1/0) — drives the PDBRF pin                | —                                     | Qt, Py  |
| `0x82` | READ_RF_CTRL     | —                                                  | `[0x82, rfOn, busy]`                  | Qt, Py  |
| `0x83` | GET_REG          | —                                                  | `[0x83, reg0..reg5 u32 LE]`           | fw source only; works on fw 1.5 |
| `0x84` | DEVICE_CTRL      | `[writeFlash, identify, erase, settings block]`    | —                                     | Qt, Py  |
| `0x85` | SET_SERIAL_INFO  | `[serial u32 LE]` (factory)                        | —                                     | Qt (PRODUCTION build) |
| `0x86` | SET_MACRO        | `[blockIndex, macro block (56 B)]` — fw 2.0+       | —                                     | Qt, Py  |
| `0x87` | GET_MACRO        | declared, never used upstream                      | unknown                               | —       |
| `0xB0` | GET_BUILD_INFO   | —                                                  | `[0xB0, major, minor, buildHi, buildLo]` | Qt, Py |

Erase (Qt form): `[0x84, 1, 1, 1, 0xFF × 60]`.

## Settings block (`ADF4351_reg_t`, 56 bytes, packed little-endian)

| Off | Type     | Field              | Notes |
|-----|----------|--------------------|-------|
| 0   | u32 × 6  | reg[0..5]          | ADF4351 R0…R5, control bits included |
| 24  | u32      | frequency          | MHz × 100 (10 kHz units) |
| 28  | u32      | ref_freq           | MHz × 100 |
| 32  | u32      | start_freq         | in-device sweep |
| 36  | u32      | stop_freq          | |
| 40  | u32      | step_freq          | |
| 44  | u16      | step_ms            | dwell; u16, so ≤ 65 535 ms on the device |
| 46  | u16      | aux_select         | 0 Sync Out, 1 Sync In, 2 Ext Ref In |
| 48  | u8       | isSweepEnabled     | run the stored sweep standalone |
| 49  | u8       | isStartOnBoot      | apply flash config at power-up |
| 50  | u8       | isStartOfSweep     | set on the first step of each pass (sync pulse) |
| 51  | u8       | flashWritePending  | firmware-internal, send 0 |
| 52  | u8       | flashReadPending   | firmware-internal, send 0 |
| 53  | u8       | isMacroEnabled     | run the stored macro standalone |
| 54  | u16      | sanityCheck        | send 0 (Python names it; Qt leaves it zero) |

## Macro block (`devicemacro_t`, 56 bytes)

Seven 7-byte steps, then `u8 macroSteps`, then zero padding.
Block 0 = steps 1–7, block 1 = steps 8–14 (`macroSteps` = 0 when unused).

Step: `u24 frequency (10 kHz units) | u24 dwell ms | u8 status_flag`

`status_flag`: bit0 ENABLED, bits[2:1] RF field (`RF_ON = 1`, `RF_OFF = 2`),
bit3 RECALC_PLL. **The two upstream tools disagree on the RF field** — see
CLAUDE.md, "Open questions".

## ADF4351 register maths

Mirrors upstream `BuildRegisters()`: PFD = ref × (2?) / (2?) / R; RF divider
chosen so the VCO sits in 2.2–4.4 GHz; MOD = round(PFD in kHz), then
FRAC/MOD reduced by GCD (MOD = 1 → 2); band-select divider =
ceil(8 × PFD) (low) or ceil(2 × PFD) (high), max 255. This repo evaluates N
exactly in 10 kHz units and carries FRAC = MOD into INT, which upstream's
floating-point version can get wrong.

Verified on hardware: a device left at the Qt defaults reads back
`0C800000 08008011 000C8E42 000004B3 00D0403C 00580005` via `0x83`, identical
to `ADF4351.solve(ADF4351Settings())`.
