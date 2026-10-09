import XCTest
@testable import RFGen44Kit

final class ProtocolTests: XCTestCase {
    private func block() -> DeviceSettingsBlock {
        let p = ADF4351.solve(ADF4351Settings())
        var b = DeviceSettingsBlock(registers: p.registers, frequencyMHz: 100, referenceMHz: 25)
        b.sweepStartMHz = 100
        b.sweepStopMHz = 500
        b.sweepStepMHz = 1.5
        b.sweepDwellMs = 50
        b.auxFunction = .externalReference
        b.sweepEnabled = true
        b.startOnBoot = true
        b.macroEnabled = true
        return b
    }

    func testSettingsBlockLayout() {
        let bytes = block().encoded()
        XCTAssertEqual(bytes.count, 56)
        XCTAssertEqual(Array(bytes[0..<4]), [0x00, 0x00, 0x80, 0x0C]) // reg0 LE
        XCTAssertEqual(Array(bytes[20..<24]), [0x05, 0x00, 0x58, 0x00]) // reg5 LE
        XCTAssertEqual(Array(bytes[24..<28]), [0x10, 0x27, 0, 0]) // 100 MHz = 10000
        XCTAssertEqual(Array(bytes[28..<32]), [0xC4, 0x09, 0, 0]) // 25 MHz = 2500
        XCTAssertEqual(Array(bytes[40..<44]), [0x96, 0, 0, 0]) // 1.5 MHz = 150
        XCTAssertEqual(Array(bytes[44..<46]), [50, 0]) // step_ms
        XCTAssertEqual(Array(bytes[46..<48]), [2, 0]) // aux = ext ref
        XCTAssertEqual(Array(bytes[48..<54]), [1, 1, 0, 0, 0, 1])
        XCTAssertEqual(Array(bytes[54..<56]), [0, 0])
    }

    func testDwellClampsToU16() {
        var b = block()
        b.sweepDwellMs = 100_000
        XCTAssertEqual(Array(b.encoded()[44..<46]), [0xFF, 0xFF])
    }

    func testPacketsAreAlways64Bytes() {
        let b = block()
        let packets = [
            RFGenPacket.setRegisters(b), RFGenPacket.rfControl(on: true), RFGenPacket.readRFControl(),
            RFGenPacket.getBuildInfo(), RFGenPacket.deviceControl(writeFlash: true, identify: false, block: b),
            RFGenPacket.eraseFlash(), RFGenPacket.setSerialNumber(0xABCDE),
            RFGenPacket.setMacroBlock(index: 1, block: [UInt8](repeating: 0, count: 56)),
        ]
        for p in packets { XCTAssertEqual(p.count, 64) }
    }

    func testCommandBytes() {
        let b = block()
        XCTAssertEqual(RFGenPacket.setRegisters(b)[0], 0x80)
        XCTAssertEqual(Array(RFGenPacket.setRegisters(b)[1...56]), b.encoded())
        XCTAssertEqual(Array(RFGenPacket.rfControl(on: true)[0...2]), [0x81, 1, 0])
        XCTAssertEqual(Array(RFGenPacket.rfControl(on: false)[0...1]), [0x81, 0])
        XCTAssertEqual(RFGenPacket.readRFControl()[0], 0x82)
        XCTAssertEqual(RFGenPacket.getBuildInfo()[0], 0xB0)

        let identify = RFGenPacket.deviceControl(writeFlash: false, identify: true, block: b)
        XCTAssertEqual(Array(identify[0...3]), [0x84, 0, 1, 0])
        XCTAssertEqual(Array(identify[4..<60]), b.encoded())

        let flash = RFGenPacket.deviceControl(writeFlash: true, identify: false, block: b)
        XCTAssertEqual(Array(flash[0...3]), [0x84, 1, 0, 0])

        let erase = RFGenPacket.eraseFlash()
        XCTAssertEqual(Array(erase[0...3]), [0x84, 1, 1, 1])
        XCTAssertTrue(erase[4...].allSatisfy { $0 == 0xFF })

        XCTAssertEqual(Array(RFGenPacket.setSerialNumber(0x000A_BCDE)[0...4]), [0x85, 0xDE, 0xBC, 0x0A, 0x00])

        let macro = RFGenPacket.setMacroBlock(index: 1, block: [UInt8](repeating: 7, count: 56))
        XCTAssertEqual(Array(macro[0...2]), [0x86, 1, 7])
        XCTAssertEqual(macro[57], 7)
        XCTAssertEqual(macro[58], 0)
    }

    func testResponses() {
        func report(_ head: [UInt8]) -> [UInt8] { head + [UInt8](repeating: 0, count: 64 - head.count) }
        XCTAssertEqual(RFGenResponse(report: report([0x82, 1, 0])), .rfStatus(RFStatus(rfOn: true, busy: false)))
        XCTAssertEqual(RFGenResponse(report: report([0x82, 0, 1])), .rfStatus(RFStatus(rfOn: false, busy: true)))
        XCTAssertEqual(RFGenResponse(report: report([0xB0, 2, 0, 0x01, 0x02])),
                       .firmware(FirmwareInfo(major: 2, minor: 0, build: 258)))
        XCTAssertEqual(RFGenResponse(report: report([0x83, 1, 0, 0, 0, 2, 0, 0, 0])),
                       .registers([1, 2, 0, 0, 0, 0]))
        XCTAssertEqual(RFGenResponse(report: report([0x42])), .other(command: 0x42))
        XCTAssertNil(RFGenResponse(report: []))
    }

    func testFirmwareMacroSupport() {
        XCTAssertFalse(FirmwareInfo(major: 1, minor: 3, build: 78).supportsMacros)
        XCTAssertTrue(FirmwareInfo(major: 2, minor: 0, build: 1).supportsMacros)
        XCTAssertEqual(FirmwareInfo(major: 2, minor: 1, build: 9).description, "2.1.9")
    }
}
