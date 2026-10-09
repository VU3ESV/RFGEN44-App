import SwiftUI
import RFGen44Kit

/// Preferences window (⌘,).
struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var serialText = ""
    @State private var confirmSerial = false

    var body: some View {
        @Bindable var model = model
        Form {
            Section("Connection") {
                Picker("When a device connects", selection: $model.onConnect) {
                    ForEach(OnConnectBehavior.allCases) { Text($0.label).tag($0) }
                }
                Text("“Read settings” keeps a device running from flash untouched. “Apply app settings” matches the upstream Qt app, which pushes its settings on connect.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Macro") {
                Picker("RF flag encoding", selection: $model.macroEncoding) {
                    ForEach(MacroRFFlagEncoding.allCases) { Text($0.label).tag($0) }
                }
                Text("The upstream Python CLI and Qt app 2.0.0.5 encode a step's RF state in opposite ways when writing a macro to flash. If a programmed macro runs with RF inverted, switch this setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Factory tools") {
                Toggle("Show factory tools", isOn: $model.showFactoryTools)
                if model.showFactoryTools {
                    HStack {
                        TextField("Serial (hex)", text: $serialText)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 120)
                        Button("Program Serial Number…") { confirmSerial = true }
                            .disabled(parsedSerial == nil || !model.isConnected)
                    }
                    Text("Writes a new USB serial number (0–FFFFF hex). Intended for production only.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Reset All Settings to Defaults", role: .destructive, action: model.resetToDefaults)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Program serial number \(serialText.uppercased())?", isPresented: $confirmSerial) {
            Button("Program", role: .destructive) {
                if let s = parsedSerial { model.programSerialNumber(s) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently changes the serial number of \(model.connectedSerial ?? "the device").")
        }
    }

    private var parsedSerial: UInt32? {
        guard let v = UInt32(serialText.trimmingCharacters(in: .whitespaces), radix: 16), v <= 0xFFFFF else { return nil }
        return v
    }
}
