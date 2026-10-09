import Foundation
import RFGen44Kit

// Command-line control of the RFGEN44, option-compatible with the upstream
// PythonApplication/rfgen44.py (Linux/Windows CLI). Actions run in the same
// order as the Python tool: list, write, info, flashwrite, identify, erase,
// programsweep, programmacro, rfstate.

let version = "1.0.0"

let usage = """
CircuitValley RFGEN44 RF Signal Generator — macOS command-line control \(version)

USAGE: rfgen44 [options]

  -l, --list                     List connected RFGEN44 devices
  -s, --serial_number SERIAL     Target device serial (required if several are connected)
  -f, --frequency MHZ            Frequency in MHz, 35.00 – 4400.00
  -w, --write                    Write --frequency (and --power/--aux) to the device
  -i, --info                     Print firmware version
  -t, --flashwrite               Save --frequency to flash (loaded on power-up)
  -d, --devindetify, --identify  Blink the status LED
  -e, --erase                    Erase the saved configuration in flash
  -r, --rfstate [on|off|1|0]     Get, or set, the RF output state
      --readregs                 Read the six ADF4351 registers back from the device
  -p, --programsweep START,STOP,STEP,MS
                                 Save a standalone sweep to flash (e.g. 100,200,1,50)
  -m, --programmacro             Save a macro to flash (firmware 2.0+), with 2–14 --macrostep
      --macrostep FREQ,MS,on|off Add a macro step (repeat), e.g. --macrostep 100,500,on
      --power -4|-1|2|5          RF output power in dBm (default +5)
      --aux syncout|syncin|extref
                                 AUX (Ref/Trigger) pin function (default syncout)
      --ref MHZ                  Reference frequency (default 25.00)
      --macro-rf-encoding standard|inverted
                                 Macro RF flag encoding (see README; default standard)
  -h, --help                     Show this help
      --version                  Show version

EXAMPLES
  rfgen44 -l
  rfgen44 -f 433.92 -w -r on
  rfgen44 --programsweep 100.0,200.0,1.0,50
  rfgen44 --programmacro --macrostep 100.0,500,on --macrostep 200.0,500,on --macrostep 100.0,1000,off
"""

struct Options {
    var list = false
    var serial: String?
    var frequency: Double?
    var write = false
    var info = false
    var flashWrite = false
    var identify = false
    var erase = false
    var rfState: String?? = nil // nil = not given, .some(nil) = query
    var programSweep: String?
    var programMacro = false
    var readRegisters = false
    var macroSteps: [String] = []
    var power: OutputPower = .plus5
    var aux: AuxFunction = .syncOut
    var reference = 25.0
    var encoding: MacroRFFlagEncoding = .standard

    var needsDevice: Bool {
        write || info || flashWrite || identify || erase || rfState != nil || programSweep != nil || programMacro
            || readRegisters
    }
}

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

func parse(_ args: [String]) throws -> Options {
    var o = Options()
    var i = 0
    func value(_ name: String) throws -> String {
        i += 1
        guard i < args.count else { throw CLIError("\(name) requires a value") }
        return args[i]
    }
    while i < args.count {
        var arg = args[i]
        var inline: String?
        if arg.hasPrefix("--"), let eq = arg.firstIndex(of: "=") {
            inline = String(arg[arg.index(after: eq)...])
            arg = String(arg[..<eq])
        }
        func v() throws -> String { if let inline { return inline }; return try value(arg) }
        switch arg {
        case "--": break
        case "-l", "--list": o.list = true
        case "-s", "--serial_number", "--serial": o.serial = try v()
        case "-f", "--frequency":
            guard let f = Double(try v()) else { throw CLIError("invalid frequency") }
            o.frequency = f
        case "-w", "--write": o.write = true
        case "-i", "--info": o.info = true
        case "-t", "--flashwrite": o.flashWrite = true
        case "-d", "--devindetify", "--identify": o.identify = true
        case "-e", "--erase": o.erase = true
        case "-r", "--rfstate":
            if let inline { o.rfState = .some(inline) }
            else if i + 1 < args.count, !args[i + 1].hasPrefix("-") { i += 1; o.rfState = .some(args[i]) }
            else { o.rfState = .some(nil) }
        case "-p", "--programsweep": o.programSweep = try v()
        case "-m", "--programmacro": o.programMacro = true
        case "--macrostep": o.macroSteps.append(try v())
        case "--readregs": o.readRegisters = true
        case "--power":
            switch try v() {
            case "-4": o.power = .minus4
            case "-1": o.power = .minus1
            case "2", "+2": o.power = .plus2
            case "5", "+5": o.power = .plus5
            case let p: throw CLIError("invalid power \(p); use -4, -1, 2 or 5")
            }
        case "--aux":
            switch try v().lowercased() {
            case "syncout": o.aux = .syncOut
            case "syncin": o.aux = .syncIn
            case "extref": o.aux = .externalReference
            case let a: throw CLIError("invalid aux function \(a)")
            }
        case "--ref":
            guard let r = Double(try v()), (ADF4351Limits.minReferenceMHz...ADF4351Limits.maxReferenceMHz).contains(r)
            else { throw CLIError("reference must be 10–250 MHz") }
            o.reference = r
        case "--macro-rf-encoding":
            switch try v() {
            case "standard": o.encoding = .standard
            case "inverted": o.encoding = .invertedQt
            case let e: throw CLIError("invalid encoding \(e)")
            }
        case "-h", "--help": print(usage); exit(0)
        case "--version": print(version); exit(0)
        default: throw CLIError("unknown option \(arg)")
        }
        i += 1
    }
    return o
}

func validateFrequency(_ f: Double) throws {
    if f < ADF4351Limits.minFrequencyMHz { throw CLIError("Frequency < 35.0 MHz is invalid") }
    if f > ADF4351Limits.maxFrequencyMHz { throw CLIError("Frequency > 4400.0 MHz is invalid") }
}

func settingsBlock(_ o: Options, frequency: Double) -> DeviceSettingsBlock {
    var s = ADF4351Settings()
    s.frequencyMHz = frequency
    s.referenceMHz = o.reference
    s.rfOutputPower = o.power
    var b = DeviceSettingsBlock(registers: ADF4351.solve(s).registers, frequencyMHz: frequency, referenceMHz: o.reference)
    b.auxFunction = o.aux
    b.startOnBoot = true
    return b
}

func parseMacroStep(_ text: String) throws -> MacroStep {
    let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    guard parts.count == 3 else { throw CLIError("Invalid macro step '\(text)'. Expected: frequency_mhz,duration_ms,on|off") }
    guard let f = Double(parts[0]) else { throw CLIError("Invalid frequency '\(parts[0])' in macro step.") }
    guard let ms = Int(parts[1]) else { throw CLIError("Invalid duration '\(parts[1])' in macro step.") }
    let rf: Bool
    switch parts[2].lowercased() {
    case "on", "1", "true": rf = true
    case "off", "0", "false": rf = false
    default: throw CLIError("Invalid RF state '\(parts[2])' in macro step. Use on/off/1/0.")
    }
    try validateFrequency(f)
    guard ms >= MacroLimits.minDurationMs else { throw CLIError("Step duration \(ms)ms is too short (minimum 30ms).") }
    return MacroStep(frequencyMHz: f, durationMs: ms, rfOn: rf)
}

func firmware(_ c: RFGenConnection) throws -> FirmwareInfo {
    let reply = try c.querySync(RFGenPacket.getBuildInfo(), expecting: .getBuildInfo)
    guard case .firmware(let fw)? = RFGenResponse(report: reply) else { throw CLIError("Unexpected firmware reply") }
    return fw
}

func run(_ o: Options) throws {
    let manager = RFGenHIDManager()
    manager.start()
    let devices = manager.devices

    if o.list {
        if devices.isEmpty {
            print(String(format: "No CircuitValley RFGEN devices found with VID=0x%04X PID=0x%04X",
                         RFGen44USB.vendorID, RFGen44USB.productID))
        } else {
            print(String(format: "Found %d device(s) with VID=0x%04X PID=0x%04X:\n",
                         devices.count, RFGen44USB.vendorID, RFGen44USB.productID))
            for d in devices {
                print(String(format: "  Location    : 0x%08X", d.locationID))
                print("  Manufacturer: \(d.manufacturer)")
                print("  Product     : \(d.product)")
                print("  Serial No.  : \(d.serialNumber)\n")
            }
        }
    }

    guard o.needsDevice else {
        if !o.list { print(usage) }
        return
    }

    var serial = o.serial
    if serial == nil {
        switch devices.count {
        case 0: throw CLIError("Error: No RFGEN device connected.")
        case 1: serial = devices[0].serialNumber; print("RFGEN Device \(serial!)")
        default: throw CLIError("Error: Multiple USB devices found, --serial_number must be specified.")
        }
    }
    let c = try manager.connect(serial: serial)
    defer { c.close() }

    if let f = o.frequency { print("Frequency set to: \(f) MHz") }

    if o.write {
        guard let f = o.frequency else { throw CLIError("Error: --write operation requires --frequency to be specified.") }
        try validateFrequency(f)
        try c.sendSync(RFGenPacket.setRegisters(settingsBlock(o, frequency: f)))
        print("Wrote \(String(format: "%.2f", f)) MHz.")
    }

    if o.info {
        let fw = try firmware(c)
        print("Serial Number \(c.info.serialNumber) Firmware version \(fw)")
    }

    if o.readRegisters {
        let reply = try c.querySync(RFGenPacket.make(.getRegisters), expecting: .getRegisters)
        guard case .registers(let regs)? = RFGenResponse(report: reply) else { throw CLIError("Unexpected register reply") }
        for (i, r) in regs.enumerated() { print("  R\(i) = 0x\(ADF4351.hex(r))") }
    }

    if o.flashWrite {
        guard let f = o.frequency else { throw CLIError("Error: --flashwrite operation requires --frequency to be specified.") }
        try validateFrequency(f)
        try c.sendSync(RFGenPacket.deviceControl(writeFlash: true, identify: false, block: settingsBlock(o, frequency: f)))
        print("Saved \(String(format: "%.2f", f)) MHz to flash (status LED blinks).")
    }

    if o.identify {
        let f = o.frequency ?? ADF4351Limits.minFrequencyMHz
        try c.sendSync(RFGenPacket.deviceControl(writeFlash: false, identify: true, block: settingsBlock(o, frequency: f)))
        print("Identify sent — watch for the blinking status LED.")
    }

    if o.erase {
        try c.sendSync(RFGenPacket.eraseFlash())
        print("Flash erase sent (status LED blinks).")
    }

    if let spec = o.programSweep {
        let parts = spec.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 4, let start = Double(parts[0]), let stop = Double(parts[1]),
              let step = Double(parts[2]), let ms = Int(parts[3])
        else { throw CLIError("Error: --programsweep format: start_mhz,stop_mhz,step_mhz,step_ms") }
        let plan = SweepPlan(startMHz: start, stopMHz: stop, stepMHz: step, dwellMs: ms)
        if let problem = plan.validateForDevice().first { throw CLIError("Error: \(problem)") }
        var b = settingsBlock(o, frequency: start)
        b.sweepStartMHz = start
        b.sweepStopMHz = stop
        b.sweepStepMHz = step
        b.sweepDwellMs = ms
        b.sweepEnabled = true
        try c.sendSync(RFGenPacket.deviceControl(writeFlash: true, identify: false, block: b))
        print("Programmed sweep \(start)–\(stop) MHz, step \(step) MHz, \(ms) ms (\(plan.stepCount ?? 0) steps).")
    }

    if o.programMacro {
        guard o.macroSteps.count >= MacroLimits.minSteps else {
            throw CLIError("Error: --programmacro requires at least 2 --macrostep arguments.")
        }
        guard o.macroSteps.count <= MacroLimits.maxSteps else {
            throw CLIError("Error: Maximum \(MacroLimits.maxSteps) macro steps allowed.")
        }
        let fw = try firmware(c)
        guard fw.supportsMacros else {
            throw CLIError("Error: Device firmware \(fw) does not support macro programming.\n       Firmware 2.0+ required. Please update firmware.")
        }
        print("Device firmware \(fw) — macro supported.")
        let steps = try o.macroSteps.map(parseMacroStep)
        for (i, block) in Macro.encodeBlocks(steps, encoding: o.encoding).enumerated() {
            print("Writing macro block \(i)...")
            try c.sendSync(RFGenPacket.setMacroBlock(index: UInt8(i), block: block))
        }
        var b = settingsBlock(o, frequency: steps[0].frequencyMHz)
        b.macroEnabled = true
        print("Enabling macro mode and writing settings to flash...")
        try c.sendSync(RFGenPacket.deviceControl(writeFlash: true, identify: false, block: b))
        print("\nMacro programmed: \(steps.count) steps")
        for (i, (s, pll)) in zip(steps, Macro.pllRecalcFlags(for: steps)).enumerated() {
            print(String(format: "  Step %2d: %10.2f MHz  %6d ms  RF:%@  %@",
                         i + 1, s.frequencyMHz, s.durationMs, s.rfOn ? "ON " : "OFF", pll ? "PLL" : "   "))
        }
    }

    if let rf = o.rfState {
        switch rf?.lowercased() {
        case nil:
            let reply = try c.querySync(RFGenPacket.readRFControl(), expecting: .readRFControl)
            guard case .rfStatus(let st)? = RFGenResponse(report: reply) else { throw CLIError("Unexpected RF reply") }
            print(st.rfOn ? "RF out Enabled" : "RF out Disabled")
        case "on", "true", "1":
            try c.sendSync(RFGenPacket.rfControl(on: true)); print("RF out Enabled")
        case "off", "false", "0":
            try c.sendSync(RFGenPacket.rfControl(on: false)); print("RF out Disabled")
        case let other?:
            throw CLIError("Invalid RF state '\(other)'. Use on/off/1/0.")
        }
    }
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    if args.isEmpty { print(usage); exit(1) }
    try run(try parse(args))
} catch {
    let message = (error as? LocalizedError)?.errorDescription ?? "\(error)"
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}
