import Foundation
import Observation
import RFGen44Kit

/// What to do with the device state when a connection opens.
enum OnConnectBehavior: String, CaseIterable, Identifiable, Codable {
    /// Read the live registers back and show them (non-destructive).
    case readFromDevice
    /// Push the app's settings to the device (upstream Qt behaviour).
    case applyAppSettings
    /// Leave both sides alone.
    case nothing

    var id: String { rawValue }
    var label: String {
        switch self {
        case .readFromDevice: return "Read settings from the device"
        case .applyAppSettings: return "Apply app settings to the device"
        case .nothing: return "Do nothing"
        }
    }
}

enum ConnectionState: Equatable {
    case noDevice
    case disconnected
    case connected
}

/// App-driven sweep or macro currently running.
enum Activity: Equatable {
    case idle
    case sweeping(index: Int, count: Int, frequencyMHz: Double)
    case macro(step: Int, started: Date, durationMs: Int)

    var isRunning: Bool { self != .idle }
}

/// Everything persisted between launches and exported as a profile.
struct Profile: Codable, Equatable {
    var settings = ADF4351Settings()
    var sweep = SweepPlan()
    var auxFunction: AuxFunction = .syncOut
    var flashLoadOnBoot = true
    var inDeviceSweep = false
    var autoWrite = true
    var macroSteps = Macro.defaultSteps
    var macroLoop = true
}

@MainActor
@Observable
final class AppModel {
    // MARK: Device-independent state (persisted)

    var settings = ADF4351Settings() { didSet { settingsChanged(oldValue) } }
    var sweep = SweepPlan()
    var auxFunction: AuxFunction = .syncOut { didSet { if auxFunction != oldValue { autoWriteIfNeeded() } } }
    var flashLoadOnBoot = true
    var inDeviceSweep = false
    var autoWrite = true { didSet { if autoWrite && !oldValue { autoWriteIfNeeded() } } }
    var macroSteps = Macro.defaultSteps
    var macroLoop = true

    // MARK: Preferences

    var onConnect: OnConnectBehavior = .readFromDevice { didSet { defaults.set(onConnect.rawValue, forKey: Keys.onConnect) } }
    var macroEncoding: MacroRFFlagEncoding = .standard { didSet { defaults.set(macroEncoding.rawValue, forKey: Keys.macroEncoding) } }
    var showFactoryTools = false { didSet { defaults.set(showFactoryTools, forKey: Keys.factory) } }

    // MARK: Derived

    private(set) var solution = ADF4351.solve(ADF4351Settings())
    /// Hex text of R0…R5 as shown (and editable) on the Advanced tab.
    var registerText: [String] = Array(repeating: "", count: 6)
    var registersEdited: Bool { registerText != solution.registers.map(ADF4351.hex) }

    // MARK: Device state

    private(set) var devices: [RFGenDeviceInfo] = []
    var selectedSerial: String?
    private(set) var connectionState: ConnectionState = .noDevice
    private(set) var firmware: FirmwareInfo?
    private(set) var rfOn: Bool?
    private(set) var deviceBusy = false
    private(set) var activity: Activity = .idle
    private(set) var statusMessage = ""
    private(set) var statusIsError = false

    // MARK: UI requests (sheets / dialogs raised from menus)

    var confirmErase = false
    var showImporter = false
    var showExporter = false

    var isConnected: Bool { connectionState == .connected }
    var connectedSerial: String? { connection?.info.serialNumber }

    /// Frequency the dial shows: live sweep frequency while sweeping.
    var displayFrequencyMHz: Double {
        if case .sweeping(_, _, let f) = activity { return f }
        return settings.frequencyMHz
    }

    // MARK: Private

    @ObservationIgnored private let manager = RFGenHIDManager()
    @ObservationIgnored private var connection: RFGenConnection?
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private var pollInFlight = false
    @ObservationIgnored private var suppressAutoWrite = false
    @ObservationIgnored private var autoWriteBeforeRun = true
    @ObservationIgnored private var runID = UUID()
    @ObservationIgnored private var runActive = false
    @ObservationIgnored private var runFrequency = 0.0
    @ObservationIgnored private let defaults = UserDefaults.standard

    private enum Keys {
        static let profile = "profile.v1"
        static let serial = "selectedSerial"
        static let onConnect = "onConnect"
        static let macroEncoding = "macroRFEncoding"
        static let factory = "showFactoryTools"
    }

    init() {
        if let data = defaults.data(forKey: Keys.profile),
           let profile = try? JSONDecoder().decode(Profile.self, from: data) {
            apply(profile, write: false)
        }
        selectedSerial = defaults.string(forKey: Keys.serial)
        onConnect = defaults.string(forKey: Keys.onConnect).flatMap(OnConnectBehavior.init) ?? .readFromDevice
        macroEncoding = defaults.string(forKey: Keys.macroEncoding).flatMap(MacroRFFlagEncoding.init) ?? .standard
        showFactoryTools = defaults.bool(forKey: Keys.factory)
        recalculate()
    }

    func start() {
        manager.start { [weak self] list in
            Task { @MainActor in self?.devicesChanged(list) }
        }
    }

    // MARK: Profile / persistence

    var profile: Profile {
        Profile(settings: settings, sweep: sweep, auxFunction: auxFunction, flashLoadOnBoot: flashLoadOnBoot,
                inDeviceSweep: inDeviceSweep, autoWrite: autoWrite, macroSteps: macroSteps, macroLoop: macroLoop)
    }

    func apply(_ p: Profile, write: Bool = true) {
        suppressAutoWrite = true
        settings = p.settings
        sweep = p.sweep
        auxFunction = p.auxFunction
        flashLoadOnBoot = p.flashLoadOnBoot
        inDeviceSweep = p.inDeviceSweep
        autoWrite = p.autoWrite
        macroSteps = Array(p.macroSteps.prefix(MacroLimits.maxSteps))
        if macroSteps.count < MacroLimits.minSteps { macroSteps = Macro.defaultSteps }
        macroLoop = p.macroLoop
        suppressAutoWrite = false
        recalculate()
        if write { autoWriteIfNeeded() }
    }

    func save() {
        if let data = try? JSONEncoder().encode(profile) { defaults.set(data, forKey: Keys.profile) }
        defaults.set(selectedSerial, forKey: Keys.serial)
    }

    func resetToDefaults() {
        apply(Profile())
        setStatus("Settings reset to defaults.")
    }

    // MARK: Register pipeline

    private func settingsChanged(_ old: ADF4351Settings) {
        guard settings != old else { return }
        recalculate()
        autoWriteIfNeeded()
    }

    private func recalculate() {
        solution = ADF4351.solve(settings)
        registerText = solution.registers.map(ADF4351.hex)
    }

    private func autoWriteIfNeeded() {
        guard autoWrite, !suppressAutoWrite, isConnected, !activity.isRunning else { return }
        sendRegisters(solution.registers, frequencyMHz: settings.frequencyMHz)
    }

    /// The firmware's settings block for the current UI state.
    private func settingsBlock(registers: [UInt32], frequencyMHz: Double, startOfSweep: Bool = false) -> DeviceSettingsBlock {
        var b = DeviceSettingsBlock(registers: registers, frequencyMHz: frequencyMHz, referenceMHz: settings.referenceMHz)
        b.sweepStartMHz = sweep.startMHz
        b.sweepStopMHz = sweep.stopMHz
        b.sweepStepMHz = sweep.stepMHz
        b.sweepDwellMs = sweep.dwellMs
        b.auxFunction = auxFunction
        b.sweepEnabled = inDeviceSweep
        b.startOnBoot = flashLoadOnBoot
        b.startOfSweep = startOfSweep
        return b
    }

    private func sendRegisters(_ registers: [UInt32], frequencyMHz: Double, startOfSweep: Bool = false) {
        let block = settingsBlock(registers: registers, frequencyMHz: frequencyMHz, startOfSweep: startOfSweep)
        send(RFGenPacket.setRegisters(block), coalesceKey: "registers")
    }

    /// "Write" button: sends the (possibly hand-edited) hex registers.
    func writeRegisterText() {
        let parsed = registerText.compactMap(ADF4351.parseHex)
        guard parsed.count == 6 else {
            setStatus("Register values must be 8-digit hex.", error: true)
            return
        }
        guard (0..<6).allSatisfy({ parsed[$0] & 7 == UInt32($0) }) else {
            setStatus("Each register's low 3 bits must equal its index (R0 = …0, R1 = …1, …).", error: true)
            return
        }
        sendRegisters(parsed, frequencyMHz: settings.frequencyMHz)
        setStatus(registersEdited ? "Wrote hand-edited registers." : "Registers written.")
    }

    func revertRegisterText() {
        registerText = solution.registers.map(ADF4351.hex)
    }

    // MARK: Device list / connection

    private func devicesChanged(_ list: [RFGenDeviceInfo]) {
        devices = list
        if let c = connection, !list.contains(where: { $0.serialNumber == c.info.serialNumber }) {
            handleDisconnect()
        }
        if connection == nil {
            if selectedSerial == nil || !list.contains(where: { $0.serialNumber == selectedSerial }) {
                // Like the Qt app: fall back to the first device found, but
                // remember the user's choice while it is unplugged.
                if let first = list.first, selectedSerial == nil || list.count == 1 { selectedSerial = first.serialNumber }
            }
            connectSelected()
        }
        if list.isEmpty { connectionState = .noDevice }
    }

    func select(serial: String) {
        guard !serial.isEmpty, serial != connection?.info.serialNumber else { return }
        stopActivity()
        connection?.close()
        connection = nil
        selectedSerial = serial
        resetDeviceState()
        save()
        connectSelected()
    }

    private func connectSelected() {
        guard connection == nil, let serial = selectedSerial, devices.contains(where: { $0.serialNumber == serial }) else {
            if connection == nil { connectionState = devices.isEmpty ? .noDevice : .disconnected }
            return
        }
        do {
            connection = try manager.connect(
                serial: serial,
                onReport: { [weak self] report in Task { @MainActor in self?.handle(report: report) } },
                onDisconnect: { [weak self] in Task { @MainActor in self?.handleDisconnect() } }
            )
            connectionState = .connected
            setStatus("Connected to \(serial).")
            didConnect()
        } catch {
            connectionState = .disconnected
            setStatus(error.localizedDescription, error: true)
        }
    }

    private func didConnect() {
        query(RFGenPacket.getBuildInfo(), expecting: .getBuildInfo)
        query(RFGenPacket.readRFControl(), expecting: .readRFControl)
        switch onConnect {
        case .readFromDevice: readFromDevice(silent: true)
        case .applyAppSettings: if autoWrite { sendRegisters(solution.registers, frequencyMHz: settings.frequencyMHz) }
        case .nothing: break
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.poll()
            }
        }
    }

    private func poll() {
        guard let c = connection, !pollInFlight else { return }
        pollInFlight = true
        if firmware == nil {
            c.query(RFGenPacket.getBuildInfo(), expecting: .getBuildInfo, timeout: 0.5) { _ in }
        }
        c.query(RFGenPacket.readRFControl(), expecting: .readRFControl, timeout: 0.5) { [weak self] _ in
            Task { @MainActor in self?.pollInFlight = false }
        }
    }

    private func handle(report: [UInt8]) {
        switch RFGenResponse(report: report) {
        case .rfStatus(let s)?:
            rfOn = s.rfOn
            deviceBusy = s.busy
        case .firmware(let fw)?:
            firmware = fw
        default:
            break
        }
    }

    private func handleDisconnect() {
        guard connection != nil else { return }
        stopActivity()
        connection?.close()
        connection = nil
        resetDeviceState()
        connectionState = devices.isEmpty ? .noDevice : .disconnected
        setStatus("Device disconnected.", error: true)
    }

    private func resetDeviceState() {
        pollTask?.cancel()
        pollTask = nil
        pollInFlight = false
        firmware = nil
        rfOn = nil
        deviceBusy = false
    }

    private func send(_ packet: [UInt8], coalesceKey: String? = nil, success: String? = nil) {
        guard let c = connection else {
            setStatus("No device connected.", error: true)
            return
        }
        c.send(packet, coalesceKey: coalesceKey) { [weak self] error in
            Task { @MainActor in
                if let error { self?.setStatus(error.localizedDescription, error: true) }
                else if let success { self?.setStatus(success) }
            }
        }
    }

    private func query(_ packet: [UInt8], expecting: RFGenCommand) {
        connection?.query(packet, expecting: expecting) { _ in }
    }

    // MARK: Commands

    func toggleRF() { setRF(!(rfOn ?? false)) }

    func setRF(_ on: Bool) {
        send(RFGenPacket.rfControl(on: on))
        rfOn = on
    }

    func identify() {
        send(RFGenPacket.deviceControl(writeFlash: false, identify: true,
                                       block: settingsBlock(registers: solution.registers, frequencyMHz: settings.frequencyMHz)),
             success: "Identify sent — the status LED on \(connectedSerial ?? "the device") blinks.")
    }

    /// Saves the current configuration (and the in-device sweep, if enabled)
    /// so the device runs standalone after power-up.
    func programFlash() {
        if inDeviceSweep, let problem = sweep.validateForDevice().first {
            setStatus("In-device sweep: \(problem)", error: true)
            return
        }
        let block = settingsBlock(registers: solution.registers, frequencyMHz: settings.frequencyMHz)
        send(RFGenPacket.setRegisters(block))
        send(RFGenPacket.deviceControl(writeFlash: true, identify: false, block: block),
             success: "Configuration saved to flash.")
    }

    func eraseFlash() {
        send(RFGenPacket.eraseFlash(), success: "Flash erased.")
    }

    func programSerialNumber(_ serial: UInt32) {
        send(RFGenPacket.setSerialNumber(serial),
             success: String(format: "Serial 0x%05X written. Re-plug the device to see the new USB serial.", serial))
    }

    /// Loads the live registers from the device into the editor.
    func readFromDevice(silent: Bool = false) {
        guard let c = connection else { return }
        c.query(RFGenPacket.make(.getRegisters), expecting: .getRegisters) { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                switch result {
                case .success(let report):
                    guard case .registers(let regs)? = RFGenResponse(report: report),
                          var decoded = ADF4351.decode(registers: regs, referenceMHz: self.settings.referenceMHz)
                    else {
                        self.setStatus("Device returned registers that could not be decoded.", error: true)
                        return
                    }
                    decoded.frequencyMHz = min(max(decoded.frequencyMHz, ADF4351Limits.minFrequencyMHz), ADF4351Limits.maxFrequencyMHz)
                    self.suppressAutoWrite = true
                    self.settings = decoded
                    self.suppressAutoWrite = false
                    self.setStatus(String(format: "Loaded device state: %.2f MHz.", decoded.frequencyMHz))
                case .failure(let error):
                    if !silent { self.setStatus("Read failed: \(error.localizedDescription)", error: true) }
                }
            }
        }
    }

    // MARK: Sweep (app-driven)

    func startSweep() {
        guard isConnected else { return }
        if let problem = sweep.validate().first { setStatus(problem, error: true); return }
        guard let count = sweep.stepCount else { return }
        stopActivity()
        let id = beginRun()
        let plan = sweep
        setRF(true)
        activity = .sweeping(index: 0, count: count, frequencyMHz: plan.startMHz)
        runTask = Task { [weak self] in
            var index = 0
            while let self, self.runID == id, !Task.isCancelled {
                let f = plan.frequencyMHz(at: index)
                var s = self.settings // live: power/AUX edits apply at the next step
                s.frequencyMHz = f
                // isStartOfSweep marks the first step so the firmware can
                // pulse SYNC OUT at the start of every pass.
                self.sendRegisters(ADF4351.solve(s).registers, frequencyMHz: f, startOfSweep: index == 0)
                self.activity = .sweeping(index: index, count: count, frequencyMHz: f)
                self.runFrequency = f
                try? await Task.sleep(for: .milliseconds(plan.dwellMs))
                index += 1
                if index >= count {
                    guard plan.loop else { break }
                    index = 0
                }
            }
            if let self, self.runID == id { self.finishRun() }
        }
        setStatus("Sweeping \(String(format: "%.2f–%.2f MHz", plan.startMHz, plan.stopMHz)).")
    }

    // MARK: Macro (app-driven)

    func startMacro() {
        guard isConnected else { return }
        if let problem = Macro.validate(macroSteps).first { setStatus(problem, error: true); return }
        stopActivity()
        let id = beginRun()
        let steps = macroSteps
        let pll = Macro.pllRecalcFlags(for: steps)
        let loop = macroLoop
        activity = .macro(step: 0, started: Date(), durationMs: steps[0].durationMs)
        runTask = Task { [weak self] in
            var i = 0
            var first = true
            while let self, self.runID == id, !Task.isCancelled {
                let step = steps[i]
                // Retune before un-muting and mute before retuning, so the
                // output never shows the previous step's frequency.
                if !step.rfOn { self.setRF(false) }
                if pll[i] || first {
                    var s = self.settings // live: power/AUX edits apply at the next step
                    s.frequencyMHz = step.frequencyMHz
                    self.sendRegisters(ADF4351.solve(s).registers, frequencyMHz: step.frequencyMHz, startOfSweep: i == 0)
                    self.runFrequency = step.frequencyMHz
                }
                if step.rfOn { self.setRF(true) }
                first = false
                self.activity = .macro(step: i, started: Date(), durationMs: step.durationMs)
                try? await Task.sleep(for: .milliseconds(step.durationMs))
                i += 1
                if i >= steps.count {
                    guard loop else { break }
                    i = 0
                }
            }
            if let self, self.runID == id { self.finishRun() }
        }
        setStatus("Macro running (\(steps.count) steps\(loop ? ", looping" : "")).")
    }

    /// Writes the macro to flash (firmware 2.0+) and enables it at boot.
    func programMacro() {
        guard let fw = firmware, fw.supportsMacros else {
            setStatus("On-device macros need firmware 2.0 or newer.", error: true)
            return
        }
        if let problem = Macro.validate(macroSteps).first { setStatus(problem, error: true); return }
        for (i, block) in Macro.encodeBlocks(macroSteps, encoding: macroEncoding).enumerated() {
            send(RFGenPacket.setMacroBlock(index: UInt8(i), block: block))
        }
        var s = settings
        s.frequencyMHz = macroSteps[0].frequencyMHz
        var block = settingsBlock(registers: ADF4351.solve(s).registers, frequencyMHz: s.frequencyMHz)
        block.macroEnabled = true
        block.sweepEnabled = false
        send(RFGenPacket.deviceControl(writeFlash: true, identify: false, block: block),
             success: "Macro (\(macroSteps.count) steps) saved to flash.")
    }

    func stopActivity() {
        runTask?.cancel()
        runTask = nil
        finishRun()
    }

    /// Starts a run and returns its ID; a task only acts while its ID is current.
    private func beginRun() -> UUID {
        runID = UUID()
        runActive = true
        runFrequency = settings.frequencyMHz
        autoWriteBeforeRun = autoWrite
        suppressAutoWrite = true
        autoWrite = true // forced on while running, as in the Qt app
        suppressAutoWrite = false
        return runID
    }

    private func finishRun() {
        guard runActive else { return }
        runActive = false
        runID = UUID()
        runTask = nil
        activity = .idle
        // The device is now at the last step; reflect that without resending.
        suppressAutoWrite = true
        settings.frequencyMHz = runFrequency
        autoWrite = autoWriteBeforeRun
        suppressAutoWrite = false
        setStatus("Stopped at \(String(format: "%.2f", runFrequency)) MHz.")
    }

    // MARK: Status

    func setStatus(_ message: String, error: Bool = false) {
        statusMessage = message
        statusIsError = error
    }

    /// Window subtitle in the spirit of the Qt title bar.
    var titleDetail: String {
        switch connectionState {
        case .noDevice: return "Device Not Found"
        case .disconnected: return "Disconnected"
        case .connected:
            let fw = firmware.map { "FW \($0)" } ?? "FW …"
            return "\(fw) · SN \(connectedSerial ?? "?") · Connected"
        }
    }
}
