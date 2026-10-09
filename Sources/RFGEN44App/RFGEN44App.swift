import AppKit
import SwiftUI
import RFGen44Kit

@main
struct RFGEN44App: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("RFGEN44", id: "main") {
            ContentView()
                .environment(model)
                .onAppear {
                    appDelegate.model = model
                    model.start()
                }
        }
        .defaultSize(width: 1080, height: 660)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Import Profile…") { model.showImporter = true }
                    .keyboardShortcut("o")
                Button("Export Profile…") { model.showExporter = true }
                    .keyboardShortcut("e")
            }
            DeviceCommands(model: model)
        }

        Settings {
            SettingsView().environment(model)
        }
    }
}

struct DeviceCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandMenu("Device") {
            let connected = model.isConnected
            let running = model.activity.isRunning
            Button(model.rfOn == true ? "Turn RF Off" : "Turn RF On", action: model.toggleRF)
                .keyboardShortcut("r")
                .disabled(!connected || running)
            Button("Write Registers", action: model.writeRegisterText)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(!connected || running)
            Button("Identify", action: model.identify)
                .keyboardShortcut("i")
                .disabled(!connected || running)
            Button("Read Settings from Device") { model.readFromDevice() }
                .disabled(!connected || running)
            Divider()
            Button("Start Sweep", action: model.startSweep)
                .disabled(!connected || running)
            Button("Start Macro", action: model.startMacro)
                .disabled(!connected || running)
            Button("Stop", action: model.stopActivity)
                .keyboardShortcut(".")
                .disabled(!running)
            Divider()
            Button("Program Flash", action: model.programFlash)
                .disabled(!connected || running)
            Button("Program Macro to Flash", action: model.programMacro)
                .disabled(!connected || running || !(model.firmware?.supportsMacros ?? false))
            Button("Erase Flash…") { model.confirmErase = true }
                .disabled(!connected || running)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    @MainActor var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor func applicationWillTerminate(_ notification: Notification) {
        model?.stopActivity()
        model?.save()
    }
}
