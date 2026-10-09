import XCTest
@testable import RFGen44Kit

final class RegisterTests: XCTestCase {
    /// Upstream Qt defaults at 100 MHz: 25 MHz ref, R = 50 → PFD 0.5 MHz,
    /// RF divider 32, N = 6400 (integer), +5 dBm.
    func testDefaultsAt100MHz() {
        let p = ADF4351.solve(ADF4351Settings())
        XCTAssertEqual(p.pfdMHz, 0.5, accuracy: 1e-12)
        XCTAssertEqual(p.outputDivider, 32)
        XCTAssertEqual(p.int, 6400)
        XCTAssertEqual(p.frac, 0)
        XCTAssertEqual(p.mod, 2)
        XCTAssertEqual(p.bandSelectDivider, 4)
        XCTAssertEqual(p.registers.map(ADF4351.hex),
                       ["0C800000", "08008011", "000C8E42", "000004B3", "00D0403C", "00580005"])
        XCTAssertTrue(p.warnings.isEmpty, "\(p.warnings)")
    }

    /// 50 MHz: same N with divider 64 — matches the register row visible in
    /// the Advance Control screenshot of the RFGEN44 datasheet.
    func testDatasheetScreenshotAt50MHz() {
        var s = ADF4351Settings()
        s.frequencyMHz = 50
        XCTAssertEqual(ADF4351.solve(s).registers.map(ADF4351.hex),
                       ["0C800000", "08008011", "000C8E42", "000004B3", "00E0403C", "00580005"])
    }

    func testFractionalIsGCDReduced() {
        var s = ADF4351Settings()
        s.frequencyMHz = 100.01 // N = 6400.64 → FRAC/MOD = 320/500 = 16/25
        let p = ADF4351.solve(s)
        XCTAssertEqual(p.int, 6400)
        XCTAssertEqual(p.frac, 16)
        XCTAssertEqual(p.mod, 25)
        XCTAssertEqual(ADF4351.hex(p.registers[0]), "0C800080")
        XCTAssertEqual(ADF4351.hex(p.registers[1]), "080080C9")
        XCTAssertEqual(p.actualFrequencyMHz, 100.01, accuracy: 1e-9)
    }

    func testDivideBy2Band() {
        var s = ADF4351Settings()
        s.frequencyMHz = 1234.56 // div 2, N = 4938.24 → 6/25
        let p = ADF4351.solve(s)
        XCTAssertEqual(p.outputDivider, 2)
        XCTAssertEqual(ADF4351.hex(p.registers[0]), "09A50030")
        XCTAssertEqual(ADF4351.hex(p.registers[4]), "0090403C")
    }

    func testDividedFeedback() {
        var s = ADF4351Settings()
        s.feedback = .divided
        s.frequencyMHz = 100 // N = 100 / 0.5 = 200
        let p = ADF4351.solve(s)
        XCTAssertEqual(p.int, 200)
        XCTAssertEqual(p.registers[4] >> 23 & 1, 0)
        XCTAssertEqual(p.actualFrequencyMHz, 100, accuracy: 1e-9)
    }

    func testOutputDividerBoundaries() {
        XCTAssertEqual(ADF4351.outputDivider(for: 4400), 1)
        XCTAssertEqual(ADF4351.outputDivider(for: 2200), 1)
        XCTAssertEqual(ADF4351.outputDivider(for: 2199.99), 2)
        XCTAssertEqual(ADF4351.outputDivider(for: 1100), 2)
        XCTAssertEqual(ADF4351.outputDivider(for: 550), 4)
        XCTAssertEqual(ADF4351.outputDivider(for: 275), 8)
        XCTAssertEqual(ADF4351.outputDivider(for: 137.5), 16)
        XCTAssertEqual(ADF4351.outputDivider(for: 68.75), 32)
        XCTAssertEqual(ADF4351.outputDivider(for: 35), 64)
    }

    /// Every 10 kHz-aligned frequency in band (sampled) must produce a valid
    /// FRAC < MOD ≤ 4095 and land within 0.5 kHz of the request.
    func testWholeBandIsExact() {
        var s = ADF4351Settings()
        var f10k = 3500
        while f10k <= 440_000 {
            s.frequencyMHz = Double(f10k) / 100
            let p = ADF4351.solve(s)
            XCTAssertLessThan(p.frac, p.mod)
            XCTAssertLessThanOrEqual(p.mod, 4095)
            XCTAssertEqual(p.actualFrequencyMHz, s.frequencyMHz, accuracy: 0.0005, "f=\(s.frequencyMHz)")
            XCTAssertTrue((2200.0...4400.0001).contains(p.vcoMHz), "VCO \(p.vcoMHz) for \(s.frequencyMHz)")
            f10k += 7 // co-prime stride hits every residue class over the band
        }
    }

    func testAllFieldsLandInTheirBits() {
        var s = ADF4351Settings()
        s.phaseAdjust = true
        s.prescaler = .fourFifths
        s.phaseValue = 4095
        s.noiseMode = .lowSpur
        s.muxOut = .digitalLockDetect
        s.referenceDoubler = true
        s.referenceDivideBy2 = true
        s.doubleBuffer = true
        s.chargePumpCurrent = 15
        s.lockDetectFunction = .intN
        s.lockDetectPrecision = .sixNs
        s.phaseDetectorPolarity = .negative
        s.powerDown = true
        s.chargePumpThreeState = true
        s.counterReset = true
        s.bandSelectClockMode = .high
        s.antiBacklashPulse = .threeNsIntN
        s.chargeCancellation = true
        s.cycleSlipReduction = true
        s.clockDividerMode = .resync
        s.clockDivider = 4095
        s.vcoPowerDown = true
        s.muteTillLockDetect = true
        s.auxOutputSelect = .fundamental
        s.auxOutputEnable = true
        s.auxOutputPower = .plus5
        s.rfOutputEnable = false
        s.rfOutputPower = .minus4
        s.lockDetectPin = .high
        let r = ADF4351.solve(s).registers
        XCTAssertEqual(r[1] & 0xFFFF_8007, 1 << 28 | 0xFFF << 15 | 1)
        XCTAssertEqual(r[2] & ~(0x3FF << 14),
                       3 << 29 | 6 << 26 | 1 << 25 | 1 << 24 | 1 << 13 | 0xF << 9 | 1 << 8 | 1 << 7 | 1 << 5 | 1 << 4 | 1 << 3 | 2)
        XCTAssertEqual(r[3], 1 << 23 | 1 << 22 | 1 << 21 | 1 << 18 | 2 << 15 | 0xFFF << 3 | 3)
        XCTAssertEqual(r[4] & 0x0FFF, 1 << 11 | 1 << 10 | 1 << 9 | 1 << 8 | 3 << 6 | 0 << 5 | 0 << 3 | 4)
        XCTAssertEqual(r[5], 3 << 22 | 3 << 19 | 5)
    }

    func testWarnings() {
        var s = ADF4351Settings()
        s.referenceDoubler = true
        s.rCounter = 1 // PFD 50 MHz
        s.frequencyMHz = 2200.01 // N = 44 + 1/5000 → MOD 5000
        let p = ADF4351.solve(s)
        XCTAssertEqual(p.mod, 5000)
        let messages = p.warnings.map(\.message).joined(separator: "\n")
        XCTAssertTrue(messages.contains("MOD"), messages)
        XCTAssertTrue(messages.contains("FRAC-N limit"), messages)
        XCTAssertTrue(messages.contains("INT = 44"), messages)
        XCTAssertTrue(messages.contains("Band select"), messages)
    }

    func testHexParsing() {
        XCTAssertEqual(ADF4351.parseHex("0C800000"), 0x0C80_0000)
        XCTAssertEqual(ADF4351.parseHex("0x580005"), 0x58_0005)
        XCTAssertNil(ADF4351.parseHex("XYZ"))
        XCTAssertNil(ADF4351.parseHex("123456789"))
    }
}

final class DecodeTests: XCTestCase {
    /// Registers read back from a real RFGEN44 (firmware 1.5.456) after the
    /// Qt app left it at its 100 MHz defaults.
    func testDecodeHardwareReadback() {
        let regs: [UInt32] = [0x0C80_0000, 0x0800_8011, 0x000C_8E42, 0x0000_04B3, 0x00D0_403C, 0x0058_0005]
        XCTAssertEqual(ADF4351.decode(registers: regs, referenceMHz: 25), ADF4351Settings())
    }

    func testRoundTrip() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<500 {
            var s = ADF4351Settings()
            s.frequencyMHz = Double(Int.random(in: 3500...440_000, using: &rng)) / 100
            s.rfOutputPower = OutputPower.allCases.randomElement(using: &rng)!
            s.auxOutputPower = OutputPower.allCases.randomElement(using: &rng)!
            s.muxOut = MuxOut.allCases.randomElement(using: &rng)!
            s.chargePumpCurrent = Int.random(in: 0...15, using: &rng)
            s.clockDivider = Int.random(in: 0...4095, using: &rng)
            s.phaseValue = Int.random(in: 0...4095, using: &rng)
            s.lockDetectPin = LockDetectPinMode.allCases.randomElement(using: &rng)!
            s.rfOutputEnable = Bool.random(using: &rng)
            s.muteTillLockDetect = Bool.random(using: &rng)
            s.feedback = FeedbackSelect.allCases.randomElement(using: &rng)!
            let decoded = ADF4351.decode(registers: ADF4351.solve(s).registers, referenceMHz: s.referenceMHz)
            XCTAssertEqual(decoded, s)
        }
    }

    func testRejectsGarbage() {
        XCTAssertNil(ADF4351.decode(registers: [0, 0, 0, 0, 0, 0], referenceMHz: 25))
        XCTAssertNil(ADF4351.decode(registers: [0, 1, 2], referenceMHz: 25))
    }
}
