import Foundation
import IOKit
import IOKit.hid

// MARK: - Errors

public enum RFGenError: LocalizedError, Equatable {
    case noDevice
    case multipleDevices([String])
    case deviceNotFound(String)
    case disconnected
    case io(Int32)
    case timeout(UInt8)

    public var errorDescription: String? {
        switch self {
        case .noDevice: return "No RFGEN44 device connected."
        case .multipleDevices(let s): return "Multiple RFGEN44 devices found (\(s.joined(separator: ", "))); choose one by serial number."
        case .deviceNotFound(let s): return "RFGEN44 with serial \(s) not found."
        case .disconnected: return "The RFGEN44 was disconnected."
        case .io(let code): return String(format: "USB I/O error 0x%08X.", UInt32(bitPattern: code))
        case .timeout(let cmd): return String(format: "No reply from device to command 0x%02X.", cmd)
        }
    }
}

// MARK: - HID run loop thread

/// Hands a value across threads that are synchronised by a semaphore.
final class UncheckedBox<T>: @unchecked Sendable {
    var value: T?
}

/// Owns a dedicated thread running a CFRunLoop. Every IOKit HID object and
/// every piece of transport state lives on this thread, so the GUI (main
/// actor) and the CLI (blocking main thread) share one model.
final class HIDRunLoop: @unchecked Sendable {
    static let shared = HIDRunLoop()

    let runLoop: CFRunLoop
    private let thread: Thread

    private init() {
        final class Box: @unchecked Sendable { var runLoop: CFRunLoop? }
        let box = Box()
        let ready = DispatchSemaphore(value: 0)
        let thread = Thread {
            box.runLoop = CFRunLoopGetCurrent()
            // A timer that never fires keeps CFRunLoopRun from returning
            // while no HID sources are attached yet.
            let keepAlive = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
            CFRunLoopAddTimer(box.runLoop, keepAlive, .defaultMode)
            ready.signal()
            while true { CFRunLoopRun() }
        }
        thread.name = "RFGen44 HID"
        thread.qualityOfService = .userInitiated
        thread.start()
        ready.wait()
        self.runLoop = box.runLoop!
        self.thread = thread
    }

    var isCurrent: Bool { Thread.current === thread }

    func async(_ block: @escaping () -> Void) {
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, block)
        CFRunLoopWakeUp(runLoop)
    }

    func sync<T>(_ block: @escaping () -> T) -> T {
        if isCurrent { return block() }
        let result = UncheckedBox<T>()
        let done = DispatchSemaphore(value: 0)
        async {
            result.value = block()
            done.signal()
        }
        done.wait()
        return result.value!
    }

    func after(_ seconds: TimeInterval, _ block: @escaping () -> Void) -> CFRunLoopTimer {
        let timer = CFRunLoopTimerCreateWithHandler(kCFAllocatorDefault, CFAbsoluteTimeGetCurrent() + seconds, 0, 0, 0) { _ in block() }!
        CFRunLoopAddTimer(runLoop, timer, .defaultMode)
        return timer
    }
}

// MARK: - Device discovery

public struct RFGenDeviceInfo: Hashable, Sendable, Identifiable {
    public var serialNumber: String
    public var product: String
    public var manufacturer: String
    public var locationID: UInt32
    public var id: String { serialNumber }
}

/// Enumerates RFGEN44s (VID 0x1209 / PID 0x7877) and reports hot-plug.
public final class RFGenHIDManager: @unchecked Sendable {
    public typealias DevicesHandler = @Sendable ([RFGenDeviceInfo]) -> Void

    private let loop = HIDRunLoop.shared
    private var manager: IOHIDManager?
    private var hidDevices: [IOHIDDevice] = []
    private var devicesHandler: DevicesHandler?
    private var removalObservers: [ObjectIdentifier: (IOHIDDevice) -> Void] = [:]

    public init() {}

    /// Starts matching. `onChange` is called on the HID thread with the
    /// sorted device list whenever a device appears or disappears, and once
    /// immediately with the current list.
    public func start(onChange: DevicesHandler? = nil) {
        loop.sync { [self] in
            devicesHandler = onChange
            if manager == nil {
                let m = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
                let matching: [String: Any] = [
                    kIOHIDVendorIDKey: RFGen44USB.vendorID,
                    kIOHIDProductIDKey: RFGen44USB.productID,
                ]
                IOHIDManagerSetDeviceMatching(m, matching as CFDictionary)
                let ctx = Unmanaged.passUnretained(self).toOpaque()
                IOHIDManagerRegisterDeviceMatchingCallback(m, Self.matched, ctx)
                IOHIDManagerRegisterDeviceRemovalCallback(m, Self.removed, ctx)
                IOHIDManagerScheduleWithRunLoop(m, loop.runLoop, CFRunLoopMode.defaultMode.rawValue)
                IOHIDManagerOpen(m, IOOptionBits(kIOHIDOptionsTypeNone))
                manager = m
                // Seed synchronously so one-shot CLI calls see devices at once.
                if let set = IOHIDManagerCopyDevices(m) as? Set<IOHIDDevice> {
                    hidDevices = Array(set)
                }
            }
            devicesHandler?(snapshot())
        }
    }

    /// Current devices, sorted by serial number.
    public var devices: [RFGenDeviceInfo] { loop.sync { [self] in snapshot() } }

    private func snapshot() -> [RFGenDeviceInfo] {
        hidDevices.map(Self.info(for:)).sorted { $0.serialNumber < $1.serialNumber }
    }

    /// Opens a connection. With `serial == nil` exactly one device must be present.
    public func connect(
        serial: String?,
        onReport: (@Sendable ([UInt8]) -> Void)? = nil,
        onDisconnect: (@Sendable () -> Void)? = nil
    ) throws -> RFGenConnection {
        let result: Result<RFGenConnection, Error> = loop.sync { [self] in
            let candidates = hidDevices.map { ($0, Self.info(for: $0)) }
            let match: (IOHIDDevice, RFGenDeviceInfo)?
            if let serial {
                match = candidates.first { $0.1.serialNumber == serial }
                guard match != nil else { return .failure(RFGenError.deviceNotFound(serial)) }
            } else {
                guard !candidates.isEmpty else { return .failure(RFGenError.noDevice) }
                guard candidates.count == 1 else {
                    return .failure(RFGenError.multipleDevices(candidates.map(\.1.serialNumber).sorted()))
                }
                match = candidates[0]
            }
            let (device, info) = match!
            let connection = RFGenConnection(device: device, info: info, loop: loop,
                                             onReport: onReport, onDisconnect: onDisconnect)
            removalObservers[ObjectIdentifier(connection)] = { [weak connection] removed in
                if let connection, removed === connection.device { connection.handleRemoval() }
            }
            connection.manager = self
            connection.attach()
            return .success(connection)
        }
        return try result.get()
    }

    func forget(_ connection: RFGenConnection) {
        removalObservers[ObjectIdentifier(connection)] = nil
    }

    // MARK: IOKit callbacks (HID thread)

    private static let matched: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx else { return }
        let me = Unmanaged<RFGenHIDManager>.fromOpaque(ctx).takeUnretainedValue()
        guard !me.hidDevices.contains(where: { $0 === device }) else { return }
        me.hidDevices.append(device)
        me.devicesHandler?(me.snapshot())
    }

    private static let removed: IOHIDDeviceCallback = { ctx, _, _, device in
        guard let ctx else { return }
        let me = Unmanaged<RFGenHIDManager>.fromOpaque(ctx).takeUnretainedValue()
        me.hidDevices.removeAll { $0 === device }
        for observer in me.removalObservers.values { observer(device) }
        me.devicesHandler?(me.snapshot())
    }

    static func info(for device: IOHIDDevice) -> RFGenDeviceInfo {
        func string(_ key: String) -> String? { IOHIDDeviceGetProperty(device, key as CFString) as? String }
        func int(_ key: String) -> Int? { (IOHIDDeviceGetProperty(device, key as CFString) as? NSNumber)?.intValue }
        let location = UInt32(truncatingIfNeeded: int(kIOHIDLocationIDKey) ?? 0)
        var serial = string(kIOHIDSerialNumberKey) ?? ""
        if serial.isEmpty { serial = String(format: "LOC-%08X", location) }
        return RFGenDeviceInfo(
            serialNumber: serial,
            product: string(kIOHIDProductKey) ?? "RFGEN44",
            manufacturer: string(kIOHIDManufacturerKey) ?? "CircuitValley",
            locationID: location
        )
    }
}

// MARK: - Connection

/// An open RFGEN44. Writes and queries go through one FIFO so a query's
/// reply is never confused with another command and the firmware's single
/// IN buffer is never overrun.
public final class RFGenConnection: @unchecked Sendable {
    public let info: RFGenDeviceInfo
    let device: IOHIDDevice
    weak var manager: RFGenHIDManager?

    private let loop: HIDRunLoop
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: RFGen44USB.reportSize)
    private var onReport: (@Sendable ([UInt8]) -> Void)?
    private var onDisconnect: (@Sendable () -> Void)?
    private var retainedSelf: Unmanaged<RFGenConnection>?

    private struct Operation {
        var packet: [UInt8]
        var expect: UInt8?
        var timeout: TimeInterval
        var coalesceKey: String?
        var completion: (Result<[UInt8], Error>) -> Void
    }
    private var queue: [Operation] = []
    private var inFlight: Operation?
    private var inFlightTimer: CFRunLoopTimer?
    private var connected = true

    init(device: IOHIDDevice, info: RFGenDeviceInfo, loop: HIDRunLoop,
         onReport: (@Sendable ([UInt8]) -> Void)?, onDisconnect: (@Sendable () -> Void)?) {
        self.device = device
        self.info = info
        self.loop = loop
        self.onReport = onReport
        self.onDisconnect = onDisconnect
        buffer.initialize(repeating: 0, count: RFGen44USB.reportSize)
    }

    deinit { buffer.deallocate() }

    /// HID thread. The manager is scheduled on the HID run loop and has the
    /// device open, so registering the input callback is all that's needed.
    func attach() {
        retainedSelf = Unmanaged.passRetained(self)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, RFGen44USB.reportSize, Self.inputReport, retainedSelf!.toOpaque())
    }

    public var isConnected: Bool { loop.sync { [self] in connected } }

    public func close() {
        loop.sync { [self] in teardown(error: RFGenError.disconnected, notify: false) }
    }

    // MARK: Public API

    /// Queue a write. Writes sharing a `coalesceKey` that are still queued
    /// are replaced by the newest one (used for rapid register updates).
    public func send(_ packet: [UInt8], coalesceKey: String? = nil,
                     completion: (@Sendable (Error?) -> Void)? = nil) {
        enqueue(Operation(packet: packet, expect: nil, timeout: 0, coalesceKey: coalesceKey) { result in
            if case .failure(let e) = result { completion?(e) } else { completion?(nil) }
        })
    }

    /// Queue a request and wait for the IN report whose byte 0 is `expecting`.
    public func query(_ packet: [UInt8], expecting: RFGenCommand, timeout: TimeInterval = 1.0,
                      completion: @escaping @Sendable (Result<[UInt8], Error>) -> Void) {
        enqueue(Operation(packet: packet, expect: expecting.rawValue, timeout: timeout, coalesceKey: nil, completion: completion))
    }

    public func send(_ packet: [UInt8]) async throws {
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            send(packet) { error in
                if let error { c.resume(throwing: error) } else { c.resume() }
            }
        }
    }

    public func query(_ packet: [UInt8], expecting: RFGenCommand, timeout: TimeInterval = 1.0) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { c in
            query(packet, expecting: expecting, timeout: timeout) { c.resume(with: $0) }
        }
    }

    /// Blocking variants for the CLI. Must not be called on the HID thread.
    public func sendSync(_ packet: [UInt8]) throws {
        _ = try blocking { done in self.send(packet) { done($0.map { .failure($0) } ?? .success([])) } }
    }

    public func querySync(_ packet: [UInt8], expecting: RFGenCommand, timeout: TimeInterval = 1.0) throws -> [UInt8] {
        try blocking { done in self.query(packet, expecting: expecting, timeout: timeout, completion: done) }
    }

    private func blocking(_ start: (@escaping @Sendable (Result<[UInt8], Error>) -> Void) -> Void) throws -> [UInt8] {
        precondition(!loop.isCurrent, "blocking call on HID thread")
        let box = UncheckedBox<Result<[UInt8], Error>>()
        let sem = DispatchSemaphore(value: 0)
        start { box.value = $0; sem.signal() }
        sem.wait()
        return try box.value!.get()
    }

    // MARK: Queue (HID thread)

    private func enqueue(_ op: Operation) {
        precondition(op.packet.count == RFGen44USB.reportSize, "reports are exactly 64 bytes")
        loop.async { [self] in
            guard connected else { op.completion(.failure(RFGenError.disconnected)); return }
            if let key = op.coalesceKey, let i = queue.firstIndex(where: { $0.coalesceKey == key }) {
                let superseded = queue[i].completion
                queue[i] = op
                superseded(.success([]))
            } else {
                queue.append(op)
            }
            pump()
        }
    }

    private func pump() {
        while inFlight == nil, connected, !queue.isEmpty {
            let op = queue.removeFirst()
            let status = op.packet.withUnsafeBufferPointer { p in
                IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, p.baseAddress!, p.count)
            }
            guard status == kIOReturnSuccess else {
                op.completion(.failure(RFGenError.io(status)))
                // Same policy as the Qt app: any write failure drops the
                // connection; the app reconnects when the device re-enumerates.
                teardown(error: RFGenError.io(status), notify: true)
                return
            }
            if let _ = op.expect {
                inFlight = op
                inFlightTimer = loop.after(op.timeout) { [weak self] in self?.inFlightTimedOut() }
            } else {
                op.completion(.success([]))
            }
        }
    }

    private func inFlightTimedOut() {
        guard let op = inFlight else { return }
        inFlight = nil
        inFlightTimer = nil
        op.completion(.failure(RFGenError.timeout(op.expect ?? 0)))
        pump()
    }

    private func received(_ report: [UInt8]) {
        if let op = inFlight, report.first == op.expect {
            if let t = inFlightTimer { CFRunLoopTimerInvalidate(t) }
            inFlight = nil
            inFlightTimer = nil
            op.completion(.success(report))
        }
        onReport?(report)
        pump()
    }

    func handleRemoval() {
        teardown(error: RFGenError.disconnected, notify: true)
    }

    private func teardown(error: Error, notify: Bool) {
        guard connected else { return }
        connected = false
        if let t = inFlightTimer { CFRunLoopTimerInvalidate(t) }
        inFlightTimer = nil
        let pending = (inFlight.map { [$0] } ?? []) + queue
        inFlight = nil
        queue.removeAll()
        IOHIDDeviceRegisterInputReportCallback(device, buffer, RFGen44USB.reportSize, nil, nil)
        manager?.forget(self)
        for op in pending { op.completion(.failure(error)) }
        let disconnect = onDisconnect
        onReport = nil
        onDisconnect = nil
        if notify { disconnect?() }
        // Balance attach(); deferred so we don't free self mid-callback.
        if let r = retainedSelf {
            retainedSelf = nil
            loop.async { r.release() }
        }
    }

    private static let inputReport: IOHIDReportCallback = { ctx, result, _, _, _, report, length in
        guard let ctx, result == kIOReturnSuccess else { return }
        let me = Unmanaged<RFGenConnection>.fromOpaque(ctx).takeUnretainedValue()
        me.received(Array(UnsafeBufferPointer(start: report, count: length)))
    }
}
