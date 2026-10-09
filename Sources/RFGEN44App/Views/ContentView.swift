import SwiftUI
import UniformTypeIdentifiers
import RFGen44Kit

enum MainTab: String, Hashable {
    case control, macro, advanced
}

struct ContentView: View {
    @Environment(AppModel.self) private var model
    /// Remembered between launches; `-selectedTab macro` on the command line overrides it.
    @AppStorage("selectedTab") private var tab: MainTab = .control

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            TabView(selection: $tab) {
                ControlTab()
                    .tabItem { Text(isSweeping ? "Control ●" : "Control") }
                    .tag(MainTab.control)
                MacroTab()
                    .tabItem { Text(isMacroRunning ? "Macro ●" : "Macro") }
                    .tag(MainTab.macro)
                AdvancedTab()
                    .tabItem { Text("Advanced Control") }
                    .tag(MainTab.advanced)
            }
            .padding([.horizontal, .top], 10)

            DeviceBar()
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .frame(minWidth: 960, minHeight: 600)
        .navigationTitle("RFGEN44")
        .navigationSubtitle(model.titleDetail)
        .confirmationDialog("Erase the configuration saved in the device's flash?",
                            isPresented: $model.confirmErase) {
            Button("Erase Flash", role: .destructive, action: model.eraseFlash)
        } message: {
            Text("The device will no longer restore its frequency, sweep or macro at power-up. The status LED blinks to confirm.")
        }
        .fileExporter(isPresented: $model.showExporter,
                      document: ProfileDocument(profile: model.profile),
                      contentType: .json,
                      defaultFilename: "RFGEN44 Profile") { result in
            if case .failure(let error) = result { model.setStatus(error.localizedDescription, error: true) }
            else { model.setStatus("Profile exported.") }
        }
        .fileImporter(isPresented: $model.showImporter, allowedContentTypes: [.json]) { result in
            importProfile(result)
        }
        .onChange(of: model.profile) { model.save() }
    }

    private var isSweeping: Bool {
        if case .sweeping = model.activity { return true }
        return false
    }

    private var isMacroRunning: Bool {
        if case .macro = model.activity { return true }
        return false
    }

    private func importProfile(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let profile = try JSONDecoder().decode(Profile.self, from: Data(contentsOf: url))
            model.apply(profile)
            model.setStatus("Imported \(url.lastPathComponent).")
        } catch {
            model.setStatus("Import failed: \(error.localizedDescription)", error: true)
        }
    }
}

/// Bottom bar, as in the Qt app: device picker, Identify, Auto Write, Write, RF.
struct DeviceBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let running = model.activity.isRunning
        HStack(spacing: 10) {
            Text("RF Gen USB Device:")
            Picker("RF Gen USB Device", selection: Binding(
                get: { model.selectedSerial ?? "" },
                set: { model.select(serial: $0) }
            )) {
                if model.devices.isEmpty { Text("No Device Found").tag("") }
                ForEach(model.devices) { Text($0.serialNumber).tag($0.serialNumber) }
            }
            .labelsHidden()
            .frame(width: 170)
            .disabled(model.devices.isEmpty || running)
            .help("Select which RFGEN44 to control")

            Circle()
                .fill(model.isConnected ? Color.green : Color.secondary.opacity(0.5))
                .frame(width: 9, height: 9)
                .help(model.titleDetail)

            Button("Identify", action: model.identify)
                .disabled(!model.isConnected || running)
                .help("Blink the status LED of the selected device")

            Text(model.statusMessage)
                .font(.callout)
                .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Toggle("Auto Write", isOn: $model.autoWrite)
                .disabled(running)
                .help(running ? "Auto Write is forced on while a sweep or macro runs"
                              : "Send register updates on every parameter change")
            Button("Write", action: model.writeRegisterText)
                .disabled(model.autoWrite || !model.isConnected || running)
                .help("Send the current register values to the device")

            Button(action: model.toggleRF) {
                Label(rfTitle, systemImage: "antenna.radiowaves.left.and.right")
                    .frame(minWidth: 86)
            }
            .buttonStyle(.borderedProminent)
            .tint(rfTint)
            .disabled(!model.isConnected || running)
            .help("Toggle the RF output on / off")
        }
    }

    private var rfTitle: String {
        switch model.rfOn {
        case true?: return "RF: ON"
        case false?: return "RF: OFF"
        case nil: return "RF: --"
        }
    }

    private var rfTint: Color {
        switch model.rfOn {
        case true?: return .green
        case false?: return .red
        case nil: return .gray
        }
    }
}

/// JSON profile: every setting plus the sweep and the macro.
struct ProfileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var profile: Profile

    init(profile: Profile) { self.profile = profile }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        profile = try JSONDecoder().decode(Profile.self, from: data)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return FileWrapper(regularFileWithContents: try encoder.encode(profile))
    }
}
