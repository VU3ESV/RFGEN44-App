import SwiftUI
import RFGen44Kit

/// Decimal entry with clamping, an optional stepper and a unit label.
struct NumberField: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double>
    var fractionDigits = 2
    var unit = "MHz"
    var step: Double?
    var width: CGFloat = 92

    var body: some View {
        let clamped = Binding<Double>(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        HStack(spacing: 4) {
            TextField(title, value: clamped, format: .number.precision(.fractionLength(fractionDigits)).grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
            if let step {
                Stepper(title, value: clamped, in: range, step: step).labelsHidden()
            }
            Text(unit).foregroundStyle(.secondary)
        }
    }
}

/// Integer entry with clamping, stepper and unit label.
struct IntField: View {
    let title: String
    @Binding var value: Int
    var range: ClosedRange<Int>
    var unit = ""
    var step = 1
    var width: CGFloat = 92

    var body: some View {
        let clamped = Binding<Int>(
            get: { value },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
        HStack(spacing: 4) {
            TextField(title, value: clamped, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: width)
            Stepper(title, value: clamped, in: range, step: step).labelsHidden()
            if !unit.isEmpty { Text(unit).foregroundStyle(.secondary) }
        }
    }
}

/// `Label: [Picker]` grid row for any enumerated register field.
struct OptionRow<T: RegisterOption>: View {
    let title: String
    @Binding var value: T
    var help = ""

    var body: some View {
        GridRow {
            Text(title).gridColumnAlignment(.trailing)
            Picker(title, selection: $value) {
                ForEach(T.allCases) { Text($0.label).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
            .help(help)
        }
    }
}

/// `Label: [✓]` grid row.
struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var help = ""

    var body: some View {
        GridRow {
            Text(title).gridColumnAlignment(.trailing)
            Toggle(title, isOn: $isOn).labelsHidden().help(help)
        }
    }
}

/// `Label: content` grid row.
struct FieldRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        GridRow {
            Text(title).gridColumnAlignment(.trailing)
            content
        }
    }
}

/// Small rounded "chip" used by the block diagram.
struct DiagramBox<Content: View>: View {
    var stroke: Color = .secondary.opacity(0.5)
    var fill: Color = Color(nsColor: .controlBackgroundColor)
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(.caption)
            .multilineTextAlignment(.center)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(stroke))
    }
}

extension View {
    /// Section card in the style of the Qt group boxes.
    func card(_ title: String) -> some View {
        GroupBox {
            self.frame(maxWidth: .infinity, alignment: .topLeading).padding(6)
        } label: {
            Text(title).font(.headline)
        }
    }
}

enum Format {
    /// Locale-aware "123.45 MHz" (matches the decimal separator of the fields).
    static func mhz(_ v: Double, digits: Int = 2) -> String {
        v.formatted(.number.precision(.fractionLength(digits)).grouping(.never)) + " MHz"
    }
}
