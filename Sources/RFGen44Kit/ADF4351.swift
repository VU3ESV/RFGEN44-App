import Foundation

// MARK: - Limits

/// Hardware limits of the RFGEN44 / ADF4351 combination.
public enum ADF4351Limits {
    public static let minFrequencyMHz = 35.0
    public static let maxFrequencyMHz = 4400.0
    /// Frequency resolution the device firmware works in (10 kHz).
    public static let frequencyResolutionMHz = 0.01
    public static let minReferenceMHz = 10.0
    public static let maxReferenceMHz = 250.0
    public static let rCounterRange = 1...1023
    public static let phaseRange = 0...4095
    public static let clockDividerRange = 0...4095
    public static let vcoMinMHz = 2200.0
    public static let vcoMaxMHz = 4400.0
    public static let maxModulus: UInt32 = 4095
    public static let maxFracNPFDMHz = 32.0
    public static let maxIntNPFDMHz = 45.0
    public static let maxDoublerInputMHz = 30.0
}

// MARK: - Field options

/// Common shape for every enumerated register field so the UI can render
/// them generically with a `Picker`.
public protocol RegisterOption: CaseIterable, Identifiable, Hashable, Codable, Sendable
where AllCases == [Self] {
    var label: String { get }
}

extension RegisterOption where Self: RawRepresentable, RawValue == Int {
    public var id: Int { rawValue }
}

/// RF / AUX output power, R4 bits [4:3] and [7:6].
public enum OutputPower: Int, RegisterOption {
    case minus4 = 0, minus1, plus2, plus5
    public var label: String {
        switch self {
        case .minus4: return "−4 dBm"
        case .minus1: return "−1 dBm"
        case .plus2: return "+2 dBm"
        case .plus5: return "+5 dBm"
        }
    }
}

/// R2 bits [30:29]. Values 1 and 2 are reserved by the datasheet.
public enum NoiseMode: Int, RegisterOption {
    case lowNoise = 0
    case lowSpur = 3
    public var label: String { self == .lowNoise ? "Low Noise" : "Low Spur" }
}

/// R2 bits [28:26].
public enum MuxOut: Int, RegisterOption {
    case threeState = 0, dvdd, dgnd, rDivider, nDivider, analogLockDetect, digitalLockDetect, reserved
    public var label: String {
        switch self {
        case .threeState: return "Three-State"
        case .dvdd: return "DVdd"
        case .dgnd: return "DGND"
        case .rDivider: return "R Divider Output"
        case .nDivider: return "N Divider Output"
        case .analogLockDetect: return "Analog Lock Detect"
        case .digitalLockDetect: return "Digital Lock Detect"
        case .reserved: return "Reserved"
        }
    }
}

/// R1 bit 27.
public enum Prescaler: Int, RegisterOption {
    case fourFifths = 0, eightNinths = 1
    public var label: String { self == .fourFifths ? "4/5" : "8/9" }
    /// Minimum INT value allowed for this prescaler.
    public var minimumINT: UInt32 { self == .fourFifths ? 23 : 75 }
}

/// R2 bit 8.
public enum LockDetectFunction: Int, RegisterOption {
    case fracN = 0, intN = 1
    public var label: String { self == .fracN ? "FRAC-N" : "INT-N" }
}

/// R2 bit 7.
public enum LockDetectPrecision: Int, RegisterOption {
    case tenNs = 0, sixNs = 1
    public var label: String { self == .tenNs ? "10 ns" : "6 ns" }
}

/// R2 bit 6.
public enum PhaseDetectorPolarity: Int, RegisterOption {
    case negative = 0, positive = 1
    public var label: String { self == .negative ? "Negative" : "Positive" }
}

/// R3 bit 23.
public enum BandSelectClockMode: Int, RegisterOption {
    case low = 0, high = 1
    public var label: String { self == .low ? "Low" : "High" }
}

/// R3 bit 22.
public enum AntiBacklashPulse: Int, RegisterOption {
    case sixNsFracN = 0, threeNsIntN = 1
    public var label: String { self == .sixNsFracN ? "6 ns (FRAC-N)" : "3 ns (INT-N)" }
}

/// R3 bits [16:15].
public enum ClockDividerMode: Int, RegisterOption {
    case off = 0, fastLock, resync, reserved
    public var label: String {
        switch self {
        case .off: return "Clock Divider Off"
        case .fastLock: return "Fast-Lock Enable"
        case .resync: return "Resync Enable"
        case .reserved: return "Reserved"
        }
    }
}

/// R4 bit 23.
public enum FeedbackSelect: Int, RegisterOption {
    case divided = 0, fundamental = 1
    public var label: String { self == .divided ? "Divided" : "Fundamental" }
}

/// R4 bit 9.
public enum AuxOutputSelect: Int, RegisterOption {
    case divided = 0, fundamental = 1
    public var label: String { self == .divided ? "Divided Output" : "Fundamental (VCO)" }
}

/// R5 bits [23:22].
public enum LockDetectPinMode: Int, RegisterOption {
    case low = 0, digitalLockDetect = 1, lowAlt = 2, high = 3
    public var label: String {
        switch self {
        case .low: return "Low"
        case .digitalLockDetect: return "Digital Lock Detect"
        case .lowAlt: return "Low (alt)"
        case .high: return "High"
        }
    }
}

/// R2 bits [12:9]: 16 steps of 0.3125 mA (with the 5.1 kΩ RSET on the RFGEN44).
public enum ChargePumpCurrent {
    public static let range = 0...15
    public static func milliamps(_ index: Int) -> Double { Double(index + 1) * 0.3125 }
    public static func label(_ index: Int) -> String { String(format: "%.2f mA", milliamps(index)) }
}

// MARK: - Settings

/// Every user-visible ADF4351 parameter. Defaults match the upstream Qt
/// application's power-on state (100 MHz, 25 MHz ref, R = 50, +5 dBm).
public struct ADF4351Settings: Codable, Equatable, Hashable, Sendable {
    public var frequencyMHz: Double = 100.0
    public var referenceMHz: Double = 25.0
    public var referenceDoubler = false
    public var referenceDivideBy2 = false
    public var rCounter = 50

    // R1
    public var phaseAdjust = false
    public var prescaler: Prescaler = .eightNinths
    public var phaseValue = 1

    // R2
    public var noiseMode: NoiseMode = .lowNoise
    public var muxOut: MuxOut = .threeState
    public var doubleBuffer = false
    public var chargePumpCurrent = 7
    public var lockDetectFunction: LockDetectFunction = .fracN
    public var lockDetectPrecision: LockDetectPrecision = .tenNs
    public var phaseDetectorPolarity: PhaseDetectorPolarity = .positive
    public var powerDown = false
    public var chargePumpThreeState = false
    public var counterReset = false

    // R3
    public var bandSelectClockMode: BandSelectClockMode = .low
    public var antiBacklashPulse: AntiBacklashPulse = .sixNsFracN
    public var chargeCancellation = false
    public var cycleSlipReduction = false
    public var clockDividerMode: ClockDividerMode = .off
    public var clockDivider = 150

    // R4
    public var feedback: FeedbackSelect = .fundamental
    public var vcoPowerDown = false
    public var muteTillLockDetect = false
    public var auxOutputSelect: AuxOutputSelect = .divided
    public var auxOutputEnable = false
    public var auxOutputPower: OutputPower = .minus4
    public var rfOutputEnable = true
    public var rfOutputPower: OutputPower = .plus5

    // R5
    public var lockDetectPin: LockDetectPinMode = .digitalLockDetect

    public init() {}
}

// MARK: - Solution

public struct PLLWarning: Hashable, Sendable, Identifiable {
    public enum Severity: Sendable { case warning, error }
    public let severity: Severity
    public let message: String
    public var id: String { message }
}

/// Result of turning `ADF4351Settings` into register words, plus the
/// intermediate PLL values the Advanced tab displays.
public struct PLLSolution: Equatable, Sendable {
    public var registers: [UInt32]
    public var pfdMHz: Double
    public var outputDivider: Int
    public var int: UInt32
    public var frac: UInt32
    public var mod: UInt32
    public var bandSelectDivider: UInt32
    public var bandSelectClockKHz: Double
    public var vcoMHz: Double
    public var actualFrequencyMHz: Double
    public var warnings: [PLLWarning]
}

public enum ADF4351 {
    /// RF divider that keeps the VCO inside 2.2–4.4 GHz for `frequencyMHz`.
    public static func outputDivider(for frequencyMHz: Double) -> Int {
        switch frequencyMHz {
        case 2200...: return 1
        case 1100..<2200: return 2
        case 550..<1100: return 4
        case 275..<550: return 8
        case 137.5..<275: return 16
        case 68.75..<137.5: return 32
        default: return 64
        }
    }

    /// Frequency in the 10 kHz fixed-point units the firmware uses.
    public static func tenKHzUnits(_ mhz: Double) -> UInt32 {
        UInt32(max(0, (mhz * 100).rounded()))
    }

    public static func solve(_ s: ADF4351Settings) -> PLLSolution {
        let doubler: UInt64 = s.referenceDoubler ? 2 : 1
        let div2: UInt64 = s.referenceDivideBy2 ? 2 : 1
        let r = UInt64(min(max(s.rCounter, ADF4351Limits.rCounterRange.lowerBound), ADF4351Limits.rCounterRange.upperBound))
        let pfdMHz = s.referenceMHz * Double(doubler) / Double(div2) / Double(r)

        let outDiv = outputDivider(for: s.frequencyMHz)
        let feedbackFactor = UInt64(s.feedback == .fundamental ? outDiv : 1)

        // N = f * feedbackFactor / PFD, evaluated exactly in 10 kHz units so
        // that "round" frequencies never land a hair below an integer N.
        let f10k = UInt64(tenKHzUnits(s.frequencyMHz))
        let ref10k = UInt64(tenKHzUnits(s.referenceMHz))
        let num = f10k * feedbackFactor * div2 * r
        let den = max(ref10k * doubler, 1)
        var intN = num / den
        let rem = num % den

        // Modulus = PFD in kHz (1 kHz VCO channel spacing), as upstream does,
        // then reduced by the GCD with FRAC.
        let mod0 = max(UInt64((1000 * pfdMHz).rounded()), 1)
        var frac = (2 * rem * mod0 + den) / (2 * den)
        if frac >= mod0 {
            intN += 1
            frac -= mod0
        }
        let g = gcd(mod0, frac)
        var mod = mod0 / g
        frac /= g
        if mod == 1 { mod = 2 }

        let bandSelectScale = s.bandSelectClockMode == .low ? 8.0 : 2.0
        let bandSelectDivider = UInt32(min(max(ceil(bandSelectScale * pfdMHz - 1e-9), 1), 255))
        let bandSelectClockKHz = 1000 * pfdMHz / Double(bandSelectDivider)

        let feedbackMHz = (Double(intN) + Double(frac) / Double(mod)) * pfdMHz
        let actual = s.feedback == .fundamental ? feedbackMHz / Double(outDiv) : feedbackMHz
        let vco = actual * Double(outDiv)

        let registers = buildRegisters(
            s, int: UInt32(truncatingIfNeeded: intN), frac: UInt32(frac), mod: UInt32(truncatingIfNeeded: mod),
            outputDivider: outDiv, bandSelectDivider: bandSelectDivider
        )

        var solution = PLLSolution(
            registers: registers, pfdMHz: pfdMHz, outputDivider: outDiv,
            int: UInt32(truncatingIfNeeded: intN), frac: UInt32(frac), mod: UInt32(truncatingIfNeeded: mod),
            bandSelectDivider: bandSelectDivider, bandSelectClockKHz: bandSelectClockKHz,
            vcoMHz: vco, actualFrequencyMHz: actual, warnings: []
        )
        solution.warnings = warnings(for: s, solution: solution)
        return solution
    }

    static func buildRegisters(
        _ s: ADF4351Settings, int: UInt32, frac: UInt32, mod: UInt32,
        outputDivider: Int, bandSelectDivider: UInt32
    ) -> [UInt32] {
        func bit(_ v: Bool, _ shift: UInt32) -> UInt32 { v ? 1 << shift : 0 }
        func field(_ v: Int, _ mask: UInt32, _ shift: UInt32) -> UInt32 { (UInt32(truncatingIfNeeded: v) & mask) << shift }

        let r0 = (int & 0xFFFF) << 15 | (frac & 0xFFF) << 3 | 0
        let r1 = bit(s.phaseAdjust, 28)
            | field(s.prescaler.rawValue, 0x1, 27)
            | field(s.phaseValue, 0xFFF, 15)
            | (mod & 0xFFF) << 3
            | 1
        let r2 = field(s.noiseMode.rawValue, 0x3, 29)
            | field(s.muxOut.rawValue, 0x7, 26)
            | bit(s.referenceDoubler, 25)
            | bit(s.referenceDivideBy2, 24)
            | field(s.rCounter, 0x3FF, 14)
            | bit(s.doubleBuffer, 13)
            | field(s.chargePumpCurrent, 0xF, 9)
            | field(s.lockDetectFunction.rawValue, 0x1, 8)
            | field(s.lockDetectPrecision.rawValue, 0x1, 7)
            | field(s.phaseDetectorPolarity.rawValue, 0x1, 6)
            | bit(s.powerDown, 5)
            | bit(s.chargePumpThreeState, 4)
            | bit(s.counterReset, 3)
            | 2
        let r3 = field(s.bandSelectClockMode.rawValue, 0x1, 23)
            | field(s.antiBacklashPulse.rawValue, 0x1, 22)
            | bit(s.chargeCancellation, 21)
            | bit(s.cycleSlipReduction, 18)
            | field(s.clockDividerMode.rawValue, 0x3, 15)
            | field(s.clockDivider, 0xFFF, 3)
            | 3
        let dividerSelect = outputDivider.trailingZeroBitCount
        let r4 = field(s.feedback.rawValue, 0x1, 23)
            | field(dividerSelect, 0x7, 20)
            | (bandSelectDivider & 0xFF) << 12
            | bit(s.vcoPowerDown, 11)
            | bit(s.muteTillLockDetect, 10)
            | field(s.auxOutputSelect.rawValue, 0x1, 9)
            | bit(s.auxOutputEnable, 8)
            | field(s.auxOutputPower.rawValue, 0x3, 6)
            | bit(s.rfOutputEnable, 5)
            | field(s.rfOutputPower.rawValue, 0x3, 3)
            | 4
        let r5 = field(s.lockDetectPin.rawValue, 0x3, 22) | 0x3 << 19 | 5
        return [r0, r1, r2, r3, r4, r5]
    }

    static func warnings(for s: ADF4351Settings, solution p: PLLSolution) -> [PLLWarning] {
        var w: [PLLWarning] = []
        func warn(_ m: String) { w.append(PLLWarning(severity: .warning, message: m)) }
        func error(_ m: String) { w.append(PLLWarning(severity: .error, message: m)) }

        if s.frequencyMHz < ADF4351Limits.minFrequencyMHz || s.frequencyMHz > ADF4351Limits.maxFrequencyMHz {
            error("Frequency must be between 35 and 4400 MHz.")
        }
        if s.referenceMHz < ADF4351Limits.minReferenceMHz || s.referenceMHz > ADF4351Limits.maxReferenceMHz {
            error("Reference must be between 10 and 250 MHz.")
        }
        if s.referenceDoubler && s.referenceMHz > ADF4351Limits.maxDoublerInputMHz {
            warn("Reference doubler is only specified for inputs up to 30 MHz.")
        }
        if p.mod > ADF4351Limits.maxModulus {
            error(String(format: "MOD = %u exceeds 4095: PFD %.3f MHz is too high for this frequency. Increase R.", p.mod, p.pfdMHz))
        }
        if p.frac != 0 && p.pfdMHz > ADF4351Limits.maxFracNPFDMHz {
            error(String(format: "PFD %.3f MHz exceeds the 32 MHz FRAC-N limit.", p.pfdMHz))
        } else if p.pfdMHz > ADF4351Limits.maxIntNPFDMHz {
            error(String(format: "PFD %.3f MHz exceeds the 45 MHz INT-N limit.", p.pfdMHz))
        } else if p.frac == 0 && p.pfdMHz > ADF4351Limits.maxFracNPFDMHz && s.bandSelectClockMode == .low {
            warn("Band select clock mode must be High when PFD > 32 MHz in INT-N mode.")
        }
        if p.int < s.prescaler.minimumINT {
            error("INT = \(p.int) is below the \(s.prescaler.minimumINT) minimum for the \(s.prescaler.label) prescaler.")
        }
        if p.int > 65535 {
            error("INT = \(p.int) exceeds 65535.")
        }
        if s.prescaler == .fourFifths && p.vcoMHz > 3600 {
            warn("Prescaler 4/5 is limited to 3.6 GHz VCO; use 8/9.")
        }
        if p.bandSelectClockKHz > 500 {
            error(String(format: "Band select clock %.1f kHz exceeds 500 kHz.", p.bandSelectClockKHz))
        } else if p.bandSelectClockKHz > 125 && s.bandSelectClockMode == .low {
            warn(String(format: "Band select clock %.1f kHz > 125 kHz: set mode High.", p.bandSelectClockKHz))
        }
        let errorKHz = abs(p.actualFrequencyMHz - s.frequencyMHz) * 1000
        if errorKHz > 0.5 {
            warn(String(format: "Achievable frequency %.6f MHz differs by %.3f kHz.", p.actualFrequencyMHz, errorKHz))
        }
        return w
    }

    static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return max(a, 1)
    }
}

// MARK: - Register formatting

extension ADF4351 {
    public static func hex(_ value: UInt32) -> String { String(format: "%08X", value) }

    /// Parses an 8-digit hex register; tolerates a `0x` prefix and spaces.
    public static func parseHex(_ text: String) -> UInt32? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("0x") { t.removeFirst(2) }
        guard !t.isEmpty, t.count <= 8 else { return nil }
        return UInt32(t, radix: 16)
    }
}

// MARK: - Decoding

extension ADF4351 {
    /// Reconstructs settings from six register words (e.g. read back with
    /// `COMMAND_GET_REG`). The reference oscillator is not stored in the
    /// registers, so it must be supplied; the frequency is rounded to the
    /// firmware's 10 kHz grid.
    public static func decode(registers r: [UInt32], referenceMHz: Double) -> ADF4351Settings? {
        guard r.count == 6, (0..<6).allSatisfy({ r[$0] & 0x7 == UInt32($0) }) else { return nil }
        func bits(_ reg: Int, _ shift: UInt32, _ mask: UInt32) -> Int { Int((r[reg] >> shift) & mask) }
        func flag(_ reg: Int, _ shift: UInt32) -> Bool { bits(reg, shift, 1) == 1 }

        var s = ADF4351Settings()
        s.referenceMHz = referenceMHz
        s.phaseAdjust = flag(1, 28)
        s.prescaler = Prescaler(rawValue: bits(1, 27, 1)) ?? .eightNinths
        s.phaseValue = bits(1, 15, 0xFFF)

        s.noiseMode = NoiseMode(rawValue: bits(2, 29, 3)) ?? .lowNoise
        s.muxOut = MuxOut(rawValue: bits(2, 26, 7)) ?? .threeState
        s.referenceDoubler = flag(2, 25)
        s.referenceDivideBy2 = flag(2, 24)
        s.rCounter = max(bits(2, 14, 0x3FF), 1)
        s.doubleBuffer = flag(2, 13)
        s.chargePumpCurrent = bits(2, 9, 0xF)
        s.lockDetectFunction = LockDetectFunction(rawValue: bits(2, 8, 1)) ?? .fracN
        s.lockDetectPrecision = LockDetectPrecision(rawValue: bits(2, 7, 1)) ?? .tenNs
        s.phaseDetectorPolarity = PhaseDetectorPolarity(rawValue: bits(2, 6, 1)) ?? .positive
        s.powerDown = flag(2, 5)
        s.chargePumpThreeState = flag(2, 4)
        s.counterReset = flag(2, 3)

        s.bandSelectClockMode = BandSelectClockMode(rawValue: bits(3, 23, 1)) ?? .low
        s.antiBacklashPulse = AntiBacklashPulse(rawValue: bits(3, 22, 1)) ?? .sixNsFracN
        s.chargeCancellation = flag(3, 21)
        s.cycleSlipReduction = flag(3, 18)
        s.clockDividerMode = ClockDividerMode(rawValue: bits(3, 15, 3)) ?? .off
        s.clockDivider = bits(3, 3, 0xFFF)

        s.feedback = FeedbackSelect(rawValue: bits(4, 23, 1)) ?? .fundamental
        s.vcoPowerDown = flag(4, 11)
        s.muteTillLockDetect = flag(4, 10)
        s.auxOutputSelect = AuxOutputSelect(rawValue: bits(4, 9, 1)) ?? .divided
        s.auxOutputEnable = flag(4, 8)
        s.auxOutputPower = OutputPower(rawValue: bits(4, 6, 3)) ?? .minus4
        s.rfOutputEnable = flag(4, 5)
        s.rfOutputPower = OutputPower(rawValue: bits(4, 3, 3)) ?? .plus5

        s.lockDetectPin = LockDetectPinMode(rawValue: bits(5, 22, 3)) ?? .digitalLockDetect

        let intN = Double(bits(0, 15, 0xFFFF))
        let frac = Double(bits(0, 3, 0xFFF))
        let mod = Double(max(bits(1, 3, 0xFFF), 1))
        let divider = Double(1 << bits(4, 20, 7))
        let pfd = referenceMHz * (s.referenceDoubler ? 2 : 1) / (s.referenceDivideBy2 ? 2 : 1) / Double(s.rCounter)
        let feedbackMHz = (intN + frac / mod) * pfd
        let f = s.feedback == .fundamental ? feedbackMHz / divider : feedbackMHz
        s.frequencyMHz = (f * 100).rounded() / 100
        return s
    }
}
