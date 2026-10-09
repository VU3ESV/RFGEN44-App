import Foundation

/// A linear start → stop sweep with a fixed step and dwell.
///
/// Used for both the app-driven sweep (PC sends every step) and the
/// standalone "In Device Sweep" saved to flash.
public struct SweepPlan: Codable, Equatable, Hashable, Sendable {
    public var startMHz: Double = 100
    public var stopMHz: Double = 500
    public var stepMHz: Double = 100
    public var dwellMs: Int = 500
    public var loop = true

    public static let minDwellMs = 30

    public init() {}

    public init(startMHz: Double, stopMHz: Double, stepMHz: Double, dwellMs: Int, loop: Bool = true) {
        self.startMHz = startMHz
        self.stopMHz = stopMHz
        self.stepMHz = stepMHz
        self.dwellMs = dwellMs
        self.loop = loop
    }

    private var start10k: Int { Int(ADF4351.tenKHzUnits(startMHz)) }
    private var stop10k: Int { Int(ADF4351.tenKHzUnits(stopMHz)) }
    private var step10k: Int { Int(ADF4351.tenKHzUnits(stepMHz)) }

    /// Number of frequencies in one pass (start and stop inclusive), or nil
    /// if the plan is degenerate.
    public var stepCount: Int? {
        guard stop10k > start10k, step10k > 0 else { return nil }
        return (stop10k - start10k) / step10k + 1
    }

    /// Duration of one pass in milliseconds.
    public var passDurationMs: Int? { stepCount.map { $0 * dwellMs } }

    /// Largest step that still fits in the span (what Qt shows as "Max Step").
    public var maxStepMHz: Double { max(0, min(stopMHz - startMHz, ADF4351Limits.maxFrequencyMHz)) }

    /// Frequency of step `index` in one pass, computed in 10 kHz units so
    /// repeated addition never drifts.
    public func frequencyMHz(at index: Int) -> Double {
        Double(start10k + index * step10k) / 100
    }

    /// Problems for app-side sweeping.
    public func validate() -> [String] {
        var p: [String] = []
        let r = ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz
        if !r.contains(startMHz) || !r.contains(stopMHz) { p.append("Start and stop must be within 35–4400 MHz.") }
        if stopMHz <= startMHz { p.append("Stop must be above start.") }
        if stepMHz <= 0 { p.append("Step must be positive.") }
        else if startMHz + stepMHz > stopMHz { p.append("Step is larger than the sweep span.") }
        if dwellMs < Self.minDwellMs { p.append("Dwell must be at least \(Self.minDwellMs) ms.") }
        return p
    }

    /// Problems for the standalone sweep stored in flash (dwell is a u16).
    public func validateForDevice() -> [String] {
        var p = validate()
        if dwellMs > DeviceSettingsBlock.maxDeviceDwellMs {
            p.append("In-device sweep dwell is limited to \(DeviceSettingsBlock.maxDeviceDwellMs) ms.")
        }
        return p
    }
}

public enum DurationFormat {
    /// "450 ms", "12.5 s", "3.2 min", "1.25 hr" — same thresholds as Qt.
    public static func string(ms: Double) -> String {
        switch ms {
        case ..<1000: return "\(Int(ms)) ms"
        case ..<60_000: return String(format: "%.1f s", ms / 1000)
        case ..<3_600_000: return String(format: "%.1f min", ms / 60_000)
        default: return String(format: "%.2f hr", ms / 3_600_000)
        }
    }
}
