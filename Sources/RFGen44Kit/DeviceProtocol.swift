import Foundation

/// USB identity and framing of the RFGEN44.
///
/// Every transfer is one 64-byte HID report with no report ID. Byte 0 of an
/// OUT report is the command; IN reports echo the command in byte 0.
public enum RFGen44USB {
    public static let vendorID = 0x1209
    public static let productID = 0x7877
    public static let reportSize = 64
}

public enum RFGenCommand: UInt8, Sendable {
    /// Write the six ADF4351 registers plus the settings block to RAM.
    case setRegisters = 0x80
    /// Drive the PDBRF pin: payload byte 1 = 1 (RF on) / 0 (RF off).
    case rfControl = 0x81
    /// Read back RF state. Reply: `[0x82, rfOn, busy]`.
    case readRFControl = 0x82
    /// Read registers from RAM (firmware 1.x source; unused by upstream apps).
    case getRegisters = 0x83
    /// `[0x84, writeFlash, identify, erase, settingsBlock…]`.
    case deviceControl = 0x84
    /// Factory only: `[0x85, serial u32 LE]`.
    case setSerialInfo = 0x85
    /// `[0x86, blockIndex, macroBlock(56)]` — firmware 2.0+.
    case setMacro = 0x86
    /// Declared upstream but never used by the official apps.
    case getMacro = 0x87
    /// Reply: `[0xB0, major, minor, buildHi, buildLo]`.
    case getBuildInfo = 0xB0
}

/// Function of the rear AUX (Ref/Trigger) SMA connector.
public enum AuxFunction: Int, RegisterOption {
    case syncOut = 0, syncIn = 1, externalReference = 2
    public var label: String {
        switch self {
        case .syncOut: return "Sync Out"
        case .syncIn: return "Sync In"
        case .externalReference: return "Ext Ref In"
        }
    }
}

/// The 56-byte `ADF4351_reg_t` the firmware keeps in RAM and (on request)
/// in flash. Frequencies are fixed-point in units of 10 kHz (MHz × 100).
///
/// Layout (little-endian, packed):
/// ```
///  0  u32 reg[6]          24  u32 frequency       28  u32 ref_freq
/// 32  u32 start_freq      36  u32 stop_freq       40  u32 step_freq
/// 44  u16 step_ms         46  u16 aux_select      48  u8  isSweepEnabled
/// 49  u8  isStartOnBoot   50  u8  isStartOfSweep  51  u8  flashWritePending
/// 52  u8  flashReadPending 53 u8  isMacroEnabled  54  u16 sanityCheck
/// ```
public struct DeviceSettingsBlock: Equatable, Sendable {
    public static let byteCount = 56
    /// `step_ms` is a u16 on the wire, so device-side dwell tops out here.
    public static let maxDeviceDwellMs = Int(UInt16.max)

    public var registers: [UInt32]
    public var frequencyMHz: Double
    public var referenceMHz: Double
    public var sweepStartMHz: Double = 100
    public var sweepStopMHz: Double = 500
    public var sweepStepMHz: Double = 100
    public var sweepDwellMs: Int = 500
    public var auxFunction: AuxFunction = .syncOut
    public var sweepEnabled = false
    public var startOnBoot = false
    public var startOfSweep = false
    public var macroEnabled = false

    public init(registers: [UInt32], frequencyMHz: Double, referenceMHz: Double) {
        self.registers = registers
        self.frequencyMHz = frequencyMHz
        self.referenceMHz = referenceMHz
    }

    public func encoded() -> [UInt8] {
        var w = ByteWriter()
        for i in 0..<6 { w.u32(i < registers.count ? registers[i] : 0) }
        w.u32(ADF4351.tenKHzUnits(frequencyMHz))
        w.u32(ADF4351.tenKHzUnits(referenceMHz))
        w.u32(ADF4351.tenKHzUnits(sweepStartMHz))
        w.u32(ADF4351.tenKHzUnits(sweepStopMHz))
        w.u32(ADF4351.tenKHzUnits(sweepStepMHz))
        w.u16(UInt16(clamping: sweepDwellMs))
        w.u16(UInt16(auxFunction.rawValue))
        w.u8(sweepEnabled ? 1 : 0)
        w.u8(startOnBoot ? 1 : 0)
        w.u8(startOfSweep ? 1 : 0)
        w.u8(0) // flashWritePending (firmware-internal)
        w.u8(0) // flashReadPending (firmware-internal)
        w.u8(macroEnabled ? 1 : 0)
        w.u16(0) // sanityCheck
        assert(w.bytes.count == Self.byteCount)
        return w.bytes
    }
}

/// Builders for every 64-byte OUT report the upstream apps send.
public enum RFGenPacket {
    public static func make(_ command: RFGenCommand, _ payload: [UInt8] = []) -> [UInt8] {
        var p = [command.rawValue] + payload
        precondition(p.count <= RFGen44USB.reportSize, "payload too large")
        p += [UInt8](repeating: 0, count: RFGen44USB.reportSize - p.count)
        return p
    }

    public static func setRegisters(_ block: DeviceSettingsBlock) -> [UInt8] {
        make(.setRegisters, block.encoded())
    }

    public static func rfControl(on: Bool) -> [UInt8] {
        make(.rfControl, [on ? 1 : 0])
    }

    public static func readRFControl() -> [UInt8] { make(.readRFControl) }

    public static func getBuildInfo() -> [UInt8] { make(.getBuildInfo) }

    /// Identify (LED blink) and/or persist `block` to flash.
    public static func deviceControl(writeFlash: Bool, identify: Bool, block: DeviceSettingsBlock) -> [UInt8] {
        make(.deviceControl, [writeFlash ? 1 : 0, identify ? 1 : 0, 0] + block.encoded())
    }

    /// Erase the saved configuration. Mirrors the Qt app: write + blink +
    /// erase flags, remainder filled with 0xFF.
    public static func eraseFlash() -> [UInt8] {
        make(.deviceControl, [1, 1, 1] + [UInt8](repeating: 0xFF, count: RFGen44USB.reportSize - 4))
    }

    /// Factory-only serial number programming.
    public static func setSerialNumber(_ serial: UInt32) -> [UInt8] {
        var w = ByteWriter()
        w.u32(serial)
        return make(.setSerialInfo, w.bytes)
    }

    public static func setMacroBlock(index: UInt8, block: [UInt8]) -> [UInt8] {
        precondition(block.count == MacroLimits.blockByteCount)
        return make(.setMacro, [index] + block)
    }
}

// MARK: - Responses

public struct FirmwareInfo: Equatable, Hashable, Sendable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var build: Int
    public init(major: Int, minor: Int, build: Int) {
        self.major = major; self.minor = minor; self.build = build
    }
    /// On-device macro storage arrived in firmware 2.0.
    public var supportsMacros: Bool { major >= 2 }
    public var description: String { "\(major).\(minor).\(build)" }
}

public struct RFStatus: Equatable, Sendable {
    public var rfOn: Bool
    public var busy: Bool
}

public enum RFGenResponse: Equatable, Sendable {
    case rfStatus(RFStatus)
    case firmware(FirmwareInfo)
    case registers([UInt32])
    case other(command: UInt8)

    public init?(report: [UInt8]) {
        guard let cmd = report.first else { return nil }
        switch RFGenCommand(rawValue: cmd) {
        case .readRFControl where report.count >= 3:
            self = .rfStatus(RFStatus(rfOn: report[1] != 0, busy: report[2] != 0))
        case .getBuildInfo where report.count >= 5:
            self = .firmware(FirmwareInfo(major: Int(report[1]), minor: Int(report[2]),
                                          build: Int(report[3]) << 8 | Int(report[4])))
        case .getRegisters where report.count >= 25:
            var r = ByteReader(report, offset: 1)
            self = .registers((0..<6).map { _ in r.u32() })
        default:
            self = .other(command: cmd)
        }
    }
}

// MARK: - Byte helpers

struct ByteWriter {
    var bytes: [UInt8] = []
    mutating func u8(_ v: UInt8) { bytes.append(v) }
    mutating func u16(_ v: UInt16) { bytes += [UInt8(v & 0xFF), UInt8(v >> 8)] }
    mutating func u24(_ v: UInt32) { bytes += [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF)] }
    mutating func u32(_ v: UInt32) { u16(UInt16(v & 0xFFFF)); u16(UInt16(v >> 16)) }
}

struct ByteReader {
    let bytes: [UInt8]
    var offset: Int
    init(_ bytes: [UInt8], offset: Int = 0) { self.bytes = bytes; self.offset = offset }
    mutating func u8() -> UInt8 { defer { offset += 1 }; return bytes[offset] }
    mutating func u32() -> UInt32 {
        defer { offset += 4 }
        return (0..<4).reduce(0) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }
}
