import Foundation

public enum MacroLimits {
    public static let maxSteps = 14
    public static let minSteps = 2
    public static let stepsPerBlock = 7
    /// Shortest dwell the Python CLI accepts for on-device execution.
    public static let minDurationMs = 30
    /// `step_ms` is a uint24 on the wire (~4.66 h).
    public static let maxDurationMs = 0xFF_FFFF
    /// 7 × 7-byte steps + 1-byte count + padding.
    public static let blockByteCount = 56
}

public struct MacroStep: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var frequencyMHz: Double
    public var durationMs: Int
    public var rfOn: Bool

    public init(id: UUID = UUID(), frequencyMHz: Double = 100, durationMs: Int = 500, rfOn: Bool = true) {
        self.id = id
        self.frequencyMHz = frequencyMHz
        self.durationMs = durationMs
        self.rfOn = rfOn
    }
}

/// How the per-step RF state is written into `status_flag` bits [2:1].
///
/// The two upstream tools disagree: `rfgen44.py` writes `RF_ON (0x01)` for an
/// "on" step, while the Qt app 2.0.0.5 writes `RF_OFF (0x02)` for "on". The
/// firmware 2.x source is not published, so this is user-selectable until it
/// is confirmed on hardware.
public enum MacroRFFlagEncoding: String, Codable, CaseIterable, Identifiable, Sendable {
    case standard
    case invertedQt

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .standard: return "Standard (Python CLI)"
        case .invertedQt: return "Inverted (Qt app 2.0.0.5)"
        }
    }
}

public enum MacroFlag {
    public static let enabled: UInt8 = 0x01
    public static let rfShift: UInt8 = 1
    public static let rfOn: UInt8 = 0x01
    public static let rfOff: UInt8 = 0x02
    public static let recalcPLL: UInt8 = 0x08
}

public enum Macro {
    /// Which steps need the PLL reprogrammed: a step whose frequency differs
    /// from the step before it, wrapping the first step around to the last
    /// (the macro loops). A single step always recalculates. Matches the
    /// "Recal PLL" column of the Qt app.
    public static func pllRecalcFlags(for steps: [MacroStep]) -> [Bool] {
        guard steps.count > 1 else { return steps.map { _ in true } }
        return steps.indices.map { i in
            let prev = i == 0 ? steps[steps.count - 1] : steps[i - 1]
            return ADF4351.tenKHzUnits(prev.frequencyMHz) != ADF4351.tenKHzUnits(steps[i].frequencyMHz)
        }
    }

    public static func statusFlag(rfOn: Bool, recalcPLL: Bool, encoding: MacroRFFlagEncoding) -> UInt8 {
        let semanticOn = encoding == .standard ? rfOn : !rfOn
        var flag = MacroFlag.enabled
        flag |= (semanticOn ? MacroFlag.rfOn : MacroFlag.rfOff) << MacroFlag.rfShift
        if recalcPLL { flag |= MacroFlag.recalcPLL }
        return flag
    }

    /// Packs up to 14 steps into the two 56-byte `devicemacro_t` blocks sent
    /// with `COMMAND_SET_MACRO` (block 0 = steps 1–7, block 1 = steps 8–14).
    ///
    /// Step layout: `u24 frequency (10 kHz units) | u24 dwell ms | u8 flags`.
    public static func encodeBlocks(_ steps: [MacroStep], encoding: MacroRFFlagEncoding) -> [[UInt8]] {
        let pll = pllRecalcFlags(for: steps)
        return (0..<2).map { blockIndex in
            let lower = blockIndex * MacroLimits.stepsPerBlock
            let slice = steps.indices.filter { $0 >= lower && $0 < lower + MacroLimits.stepsPerBlock }
            var w = ByteWriter()
            for i in slice {
                let s = steps[i]
                w.u24(ADF4351.tenKHzUnits(s.frequencyMHz) & 0xFF_FFFF)
                w.u24(UInt32(clamping: min(max(s.durationMs, 0), MacroLimits.maxDurationMs)))
                w.u8(statusFlag(rfOn: s.rfOn, recalcPLL: pll[i], encoding: encoding))
            }
            w.bytes += [UInt8](repeating: 0, count: (MacroLimits.stepsPerBlock - slice.count) * 7)
            w.u8(UInt8(slice.count))
            w.bytes += [UInt8](repeating: 0, count: MacroLimits.blockByteCount - w.bytes.count)
            return w.bytes
        }
    }

    /// Problems that would make the macro unusable on the device.
    public static func validate(_ steps: [MacroStep]) -> [String] {
        var problems: [String] = []
        if steps.count < MacroLimits.minSteps { problems.append("A macro needs at least \(MacroLimits.minSteps) steps.") }
        if steps.count > MacroLimits.maxSteps { problems.append("A macro supports at most \(MacroLimits.maxSteps) steps.") }
        for (i, s) in steps.enumerated() {
            if s.frequencyMHz < ADF4351Limits.minFrequencyMHz || s.frequencyMHz > ADF4351Limits.maxFrequencyMHz {
                problems.append("Step \(i + 1): frequency must be 35–4400 MHz.")
            }
            if s.durationMs < MacroLimits.minDurationMs || s.durationMs > MacroLimits.maxDurationMs {
                problems.append("Step \(i + 1): duration must be \(MacroLimits.minDurationMs)–\(MacroLimits.maxDurationMs) ms.")
            }
        }
        return problems
    }

    /// Default two-step macro shown on first launch.
    public static let defaultSteps: [MacroStep] = [
        MacroStep(frequencyMHz: 100, durationMs: 500, rfOn: true),
        MacroStep(frequencyMHz: 200, durationMs: 500, rfOn: true),
    ]
}
