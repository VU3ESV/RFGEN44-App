import SwiftUI
import RFGen44Kit

/// "Macro" tab: up to 14 steps of frequency / dwell / RF state, run from
/// the Mac or written to the device's flash (firmware 2.0+).
struct MacroTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let running = model.activity.isRunning
        let pll = Macro.pllRecalcFlags(for: model.macroSteps)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(statusText).font(.headline)
                Spacer()
                elapsed
            }

            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                    GridRow {
                        Text("#")
                        Text("Frequency")
                        Text("Time")
                        Text("RF Output")
                        Text("Recal PLL").frame(width: 70)
                        Text("")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                    Divider()

                    ForEach(Array($model.macroSteps.enumerated()), id: \.element.id) { index, $step in
                        GridRow {
                            Text("\(index + 1)")
                                .monospacedDigit()
                                .frame(width: 26, height: 22)
                                .background(RoundedRectangle(cornerRadius: 4).fill(currentStep == index ? Color.green.opacity(0.45) : .clear))
                            NumberField(title: "Step \(index + 1) frequency", value: $step.frequencyMHz,
                                        range: ADF4351Limits.minFrequencyMHz...ADF4351Limits.maxFrequencyMHz)
                            IntField(title: "Step \(index + 1) time", value: $step.durationMs,
                                     range: MacroLimits.minDurationMs...MacroLimits.maxDurationMs, unit: "ms", step: 10, width: 100)
                            Picker("Step \(index + 1) RF", selection: $step.rfOn) {
                                Text("On").tag(true)
                                Text("Off").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                            Image(systemName: pll[index] ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(pll[index] ? Color.accentColor : .secondary)
                                .help("Recalculated automatically: the PLL is reprogrammed when the frequency differs from the previous step")
                                .frame(width: 70)
                            rowActions(index)
                        }
                        .disabled(running)
                    }
                }
                .padding(.vertical, 4)
            }

            HStack(spacing: 10) {
                Button {
                    model.macroSteps.append(model.macroSteps.last.map { MacroStep(frequencyMHz: $0.frequencyMHz, durationMs: $0.durationMs, rfOn: $0.rfOn) } ?? MacroStep())
                } label: {
                    Label("Add Step", systemImage: "plus")
                }
                .disabled(running || model.macroSteps.count >= MacroLimits.maxSteps)

                Spacer()

                Button("Start Macro", action: model.startMacro)
                    .disabled(!model.isConnected || running)
                    .help("Run the steps from this Mac")
                Button("Stop Macro", action: model.stopActivity)
                    .disabled(!isMacroRunning)
                Toggle("Loop", isOn: $model.macroLoop)
                    .disabled(running)

                Spacer()

                Button("Program Macro to Flash", action: model.programMacro)
                    .disabled(!canProgram)
                    .help(programHelp)
            }
        }
        .padding(14)
    }

    private func rowActions(_ index: Int) -> some View {
        HStack(spacing: 2) {
            Button { model.macroSteps.swapAt(index, index - 1) } label: { Image(systemName: "chevron.up") }
                .disabled(index == 0)
                .help("Move up")
            Button { model.macroSteps.swapAt(index, index + 1) } label: { Image(systemName: "chevron.down") }
                .disabled(index == model.macroSteps.count - 1)
                .help("Move down")
            Button { model.macroSteps.remove(at: index) } label: { Image(systemName: "minus.circle") }
                .disabled(model.macroSteps.count <= MacroLimits.minSteps)
                .help("Remove step")
        }
        .buttonStyle(.borderless)
    }

    private var currentStep: Int? {
        if case .macro(let step, _, _) = model.activity { return step }
        return nil
    }

    private var isMacroRunning: Bool { currentStep != nil }

    private var statusText: String {
        if let step = currentStep { return "Status: Step \(step + 1)  |  Steps: \(model.macroSteps.count)" }
        return "Status: Idle  |  Steps: \(model.macroSteps.count)"
    }

    @ViewBuilder private var elapsed: some View {
        if case .macro(_, let started, let durationMs) = model.activity {
            TimelineView(.periodic(from: started, by: 0.1)) { context in
                let elapsed = min(context.date.timeIntervalSince(started), Double(durationMs) / 1000)
                Text(String(format: "%.1fs / %.1fs", elapsed, Double(durationMs) / 1000))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var canProgram: Bool {
        model.isConnected && !model.activity.isRunning && (model.firmware?.supportsMacros ?? false)
    }

    private var programHelp: String {
        guard let fw = model.firmware else { return "Write the macro to the device's flash (firmware 2.0+)" }
        return fw.supportsMacros
            ? "Write the macro to the device's flash and run it at power-up"
            : "Needs device firmware 2.0+ (this device has \(fw)). Please update the firmware."
    }
}
