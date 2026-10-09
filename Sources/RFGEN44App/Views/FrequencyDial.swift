import AppKit
import Observation
import SwiftUI
import RFGen44Kit

/// VFO-style frequency readout, the Mac counterpart of the Qt app's
/// "click on a digit to set the step size" spin box.
///
/// - Click a digit to select it (underlined); ↑/↓ change it by its place value.
/// - ←/→ move the selection; typing 0–9 overwrites the selected digit.
/// - Hover a digit and scroll (mouse wheel or trackpad) to tune it.
struct FrequencyDial: View {
    @Binding var frequencyMHz: Double
    /// What to show (differs from `frequencyMHz` while sweeping).
    var displayMHz: Double
    var range: ClosedRange<Double> = ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz
    var isEditable = true

    @State private var selected = 3
    @State private var wheel = ScrollWheelMonitor()
    @FocusState private var focused: Bool

    /// Place value of each digit in 10 kHz units: 1000, 100, 10, 1, 0.1, 0.01 MHz.
    private static let places = [100_000, 10_000, 1_000, 100, 10, 1]

    private var units: Int { Int((displayMHz * 100).rounded()) }

    var body: some View {
        let digits = Self.places.map { (units / $0) % 10 }
        let firstSignificant = digits.firstIndex { $0 != 0 } ?? 3
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(0..<6, id: \.self) { i in
                if i == 4 { Text(".").foregroundStyle(.secondary) }
                digit(digits[i], index: i, dimmed: i < min(firstSignificant, 3))
            }
            Text(" MHz")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 38, weight: .medium, design: .monospaced))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(focused ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: focused ? 2 : 1)
        )
        .focusable(isEditable)
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.upArrow) { step(1); return .handled }
        .onKeyPress(.downArrow) { step(-1); return .handled }
        .onKeyPress(.leftArrow) { selected = max(0, selected - 1); return .handled }
        .onKeyPress(.rightArrow) { selected = min(5, selected + 1); return .handled }
        .onKeyPress(characters: .decimalDigits) { press in
            guard let d = Int(press.characters) else { return .ignored }
            overwrite(d)
            return .handled
        }
        .onAppear {
            wheel.onStep = { place, direction in
                selected = place
                step(direction)
            }
            wheel.install()
        }
        .onDisappear { wheel.remove() }
        .opacity(isEditable ? 1 : 0.85)
        .help("Click a digit, then use ↑/↓, the scroll wheel or type a digit to tune")
        .accessibilityElement()
        .accessibilityLabel("Frequency")
        .accessibilityValue(String(format: "%.2f megahertz", displayMHz))
        .accessibilityAdjustableAction { direction in
            step(direction == .increment ? 1 : -1)
        }
    }

    private func digit(_ value: Int, index: Int, dimmed: Bool) -> some View {
        let isSelected = focused && index == selected
        return Text("\(value)")
            .foregroundStyle(dimmed ? Color.secondary.opacity(0.35) : Color.primary)
            .padding(.horizontal, 1)
            .background(
                RoundedRectangle(cornerRadius: 3)
                    .fill(wheel.hovered == index && isEditable ? Color.accentColor.opacity(0.12) : .clear)
            )
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle().fill(Color.accentColor).frame(height: 3).offset(y: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                guard isEditable else { return }
                selected = index
                focused = true
            }
            .onHover { inside in
                if inside { wheel.hovered = index } else if wheel.hovered == index { wheel.hovered = nil }
            }
    }

    private func step(_ direction: Int) {
        guard isEditable else { return }
        set(units: units + direction * Self.places[selected])
    }

    private func overwrite(_ d: Int) {
        guard isEditable else { return }
        let place = Self.places[selected]
        let current = (units / place) % 10
        set(units: units + (d - current) * place)
        selected = min(5, selected + 1)
    }

    private func set(units new: Int) {
        let lower = Int((range.lowerBound * 100).rounded())
        let upper = Int((range.upperBound * 100).rounded())
        frequencyMHz = Double(min(max(new, lower), upper)) / 100
    }
}

/// Converts scroll-wheel events over a hovered digit into ±1 steps.
@Observable
@MainActor
final class ScrollWheelMonitor {
    var hovered: Int?
    @ObservationIgnored var onStep: ((Int, Int) -> Void)?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var accumulated: CGFloat = 0

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            // Trackpads deliver many small precise deltas; wheels deliver lines.
            let threshold: CGFloat = event.hasPreciseScrollingDeltas ? 14 : 0.9
            let delta = event.scrollingDeltaY
            let ended = event.phase == .ended || event.momentumPhase == .ended
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard let self, let place = self.hovered, let onStep = self.onStep else { return false }
                self.accumulated += delta
                while abs(self.accumulated) >= threshold {
                    let direction = self.accumulated > 0 ? 1 : -1
                    onStep(place, direction)
                    self.accumulated -= CGFloat(direction) * threshold
                }
                if ended { self.accumulated = 0 }
                return true
            }
            return consumed ? nil : event
        }
    }

    func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
