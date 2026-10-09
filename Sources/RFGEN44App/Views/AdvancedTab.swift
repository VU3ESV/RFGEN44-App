import SwiftUI
import RFGen44Kit

/// "Advanced" tab: every ADF4351 register field, the six register words
/// (editable for raw writes) and the derived PLL values.
struct AdvancedTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    referenceSection
                    loopSection
                    outputSection
                }
                RegistersSection()
                PLLSummary(solution: model.solution)
            }
            .padding(14)
            .disabled(model.activity.isRunning)
        }
    }

    private var referenceSection: some View {
        @Bindable var model = model
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
            FieldRow(title: "RF frequency") {
                NumberField(title: "RF frequency", value: $model.settings.frequencyMHz,
                            range: ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz)
            }
            FieldRow(title: "Reference") {
                NumberField(title: "Reference", value: $model.settings.referenceMHz,
                            range: ADF4351Limits.minReferenceMHz...ADF4351Limits.maxReferenceMHz)
                    .help("Reference oscillator: 25 MHz internal, or the external reference on AUX")
            }
            ToggleRow(title: "Ref ×2", isOn: $model.settings.referenceDoubler, help: "Reference doubler")
            ToggleRow(title: "Ref ÷2", isOn: $model.settings.referenceDivideBy2, help: "Reference divide-by-2")
            FieldRow(title: "R counter") {
                IntField(title: "R counter", value: $model.settings.rCounter, range: ADF4351Limits.rCounterRange)
            }
            OptionRow(title: "Feedback", value: $model.settings.feedback, help: "VCO feedback path")
            OptionRow(title: "Prescaler", value: $model.settings.prescaler)
            ToggleRow(title: "Phase adjust", isOn: $model.settings.phaseAdjust)
            FieldRow(title: "Phase value") {
                IntField(title: "Phase value", value: $model.settings.phaseValue, range: ADF4351Limits.phaseRange)
            }
            OptionRow(title: "Mode", value: $model.settings.noiseMode, help: "Low noise or low spur mode")
        }
        .card("Reference & N Divider")
    }

    private var loopSection: some View {
        @Bindable var model = model
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
            FieldRow(title: "Charge pump") {
                Picker("Charge pump current", selection: $model.settings.chargePumpCurrent) {
                    ForEach(ChargePumpCurrent.range, id: \.self) { Text(ChargePumpCurrent.label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            ToggleRow(title: "CP three-state", isOn: $model.settings.chargePumpThreeState)
            OptionRow(title: "PD polarity", value: $model.settings.phaseDetectorPolarity)
            OptionRow(title: "MUXOUT", value: $model.settings.muxOut)
            OptionRow(title: "LDF", value: $model.settings.lockDetectFunction, help: "Lock detect function")
            OptionRow(title: "LDP", value: $model.settings.lockDetectPrecision, help: "Lock detect precision")
            OptionRow(title: "LD pin", value: $model.settings.lockDetectPin)
            ToggleRow(title: "Double buffer", isOn: $model.settings.doubleBuffer, help: "Double-buffer R4 divider select")
            ToggleRow(title: "Counter reset", isOn: $model.settings.counterReset)
            ToggleRow(title: "Power-down", isOn: $model.settings.powerDown)
        }
        .card("Charge Pump & Lock Detect")
    }

    private var outputSection: some View {
        @Bindable var model = model
        return Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 9) {
            OptionRow(title: "Band sel. clock", value: $model.settings.bandSelectClockMode)
            OptionRow(title: "ABP", value: $model.settings.antiBacklashPulse, help: "Anti-backlash pulse width")
            ToggleRow(title: "Charge cancel", isOn: $model.settings.chargeCancellation)
            ToggleRow(title: "CSR", isOn: $model.settings.cycleSlipReduction, help: "Cycle slip reduction")
            OptionRow(title: "Clock div mode", value: $model.settings.clockDividerMode)
            FieldRow(title: "Clock divider") {
                IntField(title: "Clock divider", value: $model.settings.clockDivider, range: ADF4351Limits.clockDividerRange)
            }
            ToggleRow(title: "VCO power-down", isOn: $model.settings.vcoPowerDown)
            ToggleRow(title: "MTLD", isOn: $model.settings.muteTillLockDetect, help: "Mute till lock detect")
            ToggleRow(title: "RF out enable", isOn: $model.settings.rfOutputEnable, help: "R4 RF output enable bit")
            OptionRow(title: "RF out power", value: $model.settings.rfOutputPower)
            OptionRow(title: "AUX output", value: $model.settings.auxOutputSelect)
            ToggleRow(title: "AUX enable", isOn: $model.settings.auxOutputEnable)
            OptionRow(title: "AUX power", value: $model.settings.auxOutputPower)
        }
        .card("Band Select & Outputs")
    }
}

private struct RegistersSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("R\(i)").font(.caption).foregroundStyle(.secondary)
                        TextField("R\(i)", text: $model.registerText[i])
                            .labelsHidden()
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 96)
                            .foregroundStyle(isEdited(i) ? Color.orange : Color.primary)
                            .onSubmit { if model.autoWrite { model.writeRegisterText() } }
                            .help("Register \(i) as hex. Edit and press Write (or Return with Auto Write) to send raw values")
                    }
                }
            }
            HStack {
                Button("Write", action: model.writeRegisterText)
                    .disabled(!model.isConnected)
                Button("Revert", action: model.revertRegisterText)
                    .disabled(!model.registersEdited)
                Button("Read from Device") { model.readFromDevice() }
                    .disabled(!model.isConnected)
                    .help("Load the registers the device is running now (COMMAND_GET_REG)")
                if model.registersEdited {
                    Text("Edited — not derived from the settings above").font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .card("Registers")
    }

    private func isEdited(_ i: Int) -> Bool {
        model.registerText[i] != ADF4351.hex(model.solution.registers[i])
    }
}

private struct PLLSummary: View {
    let solution: PLLSolution

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    value("PFD", Format.mhz(solution.pfdMHz, digits: 4))
                    value("N", "\(solution.int) + \(solution.frac)/\(solution.mod)")
                    value("RF divider", "÷\(solution.outputDivider)")
                }
                GridRow {
                    value("VCO", Format.mhz(solution.vcoMHz, digits: 4))
                    value("Band select", "÷\(solution.bandSelectDivider) → " + String(format: "%.1f kHz", solution.bandSelectClockKHz))
                    value("Output", Format.mhz(solution.actualFrequencyMHz, digits: 6))
                }
            }
            ForEach(solution.warnings) { w in
                Label(w.message, systemImage: w.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(w.severity == .error ? .red : .orange)
                    .font(.callout)
            }
        }
        .card("PLL")
    }

    private func value(_ title: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(text).monospacedDigit().textSelection(.enabled)
        }
    }
}
