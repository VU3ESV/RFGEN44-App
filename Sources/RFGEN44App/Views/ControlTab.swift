import SwiftUI
import RFGen44Kit

/// "Control" tab: frequency and power, app-driven sweep/hop, and the
/// settings stored in the device's flash.
struct ControlTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            FrequencySection().frame(minWidth: 380)
            SweepSection().frame(minWidth: 260)
            DeviceSettingsSection().frame(minWidth: 240)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

private struct FrequencySection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 14) {
            FrequencyDial(
                frequencyMHz: $model.settings.frequencyMHz,
                displayMHz: model.displayFrequencyMHz,
                isEditable: !model.activity.isRunning
            )

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                FieldRow(title: "Set frequency") {
                    NumberField(title: "Frequency", value: $model.settings.frequencyMHz,
                                range: ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz)
                        .disabled(model.activity.isRunning)
                        .help("RF output frequency, 35 – 4400 MHz in 10 kHz steps")
                }
                OptionRow(title: "RF power", value: $model.settings.rfOutputPower,
                          help: "RF output power level")
            }

            DeviceDiagram(
                referenceMHz: model.settings.referenceMHz,
                aux: model.auxFunction,
                rfOn: model.rfOn,
                isEnabled: model.isConnected && !model.activity.isRunning,
                toggleRF: model.toggleRF
            )
            .frame(maxWidth: .infinity)

            Text(firmwareLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
        .card("Frequency")
    }

    private var firmwareLine: String {
        let fw = model.firmware.map(\.description) ?? "--"
        return "FW: \(fw)  |  SN: \(model.connectedSerial ?? "--")"
    }
}

private struct SweepSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let running = model.activity.isRunning
        let range = ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                FieldRow(title: "Start") {
                    NumberField(title: "Start", value: $model.sweep.startMHz, range: range)
                }
                FieldRow(title: "End") {
                    NumberField(title: "End", value: $model.sweep.stopMHz, range: range)
                }
                FieldRow(title: "Step") {
                    NumberField(title: "Step", value: $model.sweep.stepMHz, range: 0.01...4400)
                }
                FieldRow(title: "Dwell") {
                    IntField(title: "Dwell", value: $model.sweep.dwellMs, range: SweepPlan.minDwellMs...100_000_000,
                             unit: "ms", step: 10)
                }
            }
            .disabled(running)
            .help("Sweep from start to end in fixed steps, dwelling at each frequency")

            Toggle("Loop", isOn: $model.sweep.loop)
                .disabled(running)
                .help("Restart from the start frequency after the end")

            HStack {
                Button("Start Sweep", action: model.startSweep)
                    .disabled(!model.isConnected || running)
                    .help("Run the sweep from this Mac")
                Button("Stop", action: model.stopActivity)
                    .disabled(!isSweeping)
            }

            sweepInfo
        }
        .card("Sweep / Hop")
    }

    private var isSweeping: Bool {
        if case .sweeping = model.activity { return true }
        return false
    }

    @ViewBuilder private var sweepInfo: some View {
        if case .sweeping(let index, let count, let f) = model.activity {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(index + 1), total: Double(count))
                Text("Step \(index + 1) of \(count) · \(Format.mhz(f))")
                    .font(.caption).monospacedDigit()
            }
        } else if let problem = model.sweep.validate().first {
            Label(problem, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.orange)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text("Steps: \(model.sweep.stepCount.map(String.init) ?? "--")")
                Text("Max step: \(Format.mhz(model.sweep.maxStepMHz))")
                Text("Total: \(model.sweep.passDurationMs.map { DurationFormat.string(ms: Double($0)) } ?? "--")")
            }
            .font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}

private struct DeviceSettingsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let running = model.activity.isRunning
        VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                OptionRow(title: "AUX pin", value: $model.auxFunction,
                          help: "Sync Out: pulse at sweep/macro start · Sync In: external trigger · Ext Ref In: use an external 10–250 MHz reference")
            }
            Toggle("Flash load on boot", isOn: $model.flashLoadOnBoot)
                .help("Apply the saved settings (and enable RF) as soon as the device is powered")
            Toggle("In-device sweep", isOn: $model.inDeviceSweep)
                .help("Save the Sweep / Hop settings so the device sweeps on its own after power-up")

            if model.deviceBusy {
                Label("Device busy…", systemImage: "hourglass")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Button("Erase Flash…") { model.confirmErase = true }
                    .help("Erase all settings saved in the device's flash")
                Button("Program Flash", action: model.programFlash)
                    .help("Save the current settings to the device's flash")
            }
            .disabled(!model.isConnected || running)

            if model.inDeviceSweep, let problem = model.sweep.validateForDevice().first {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .card("Device Settings")
    }
}
