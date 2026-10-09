import XCTest
@testable import RFGen44Kit

final class MacroTests: XCTestCase {
    private func steps(_ spec: [(Double, Int, Bool)]) -> [MacroStep] {
        spec.map { MacroStep(frequencyMHz: $0.0, durationMs: $0.1, rfOn: $0.2) }
    }

    func testPLLFlagsWrapAround() {
        XCTAssertEqual(Macro.pllRecalcFlags(for: steps([(100, 500, true)])), [true])
        XCTAssertEqual(Macro.pllRecalcFlags(for: steps([(100, 500, true), (200, 500, true)])), [true, true])
        XCTAssertEqual(Macro.pllRecalcFlags(for: steps([(100, 500, true), (100, 500, false)])), [false, false])
        // Step 1 equals the last step, so looping back needs no relock.
        XCTAssertEqual(Macro.pllRecalcFlags(for: steps([(100, 500, true), (200, 500, false), (100, 500, true)])),
                       [false, true, true])
    }

    func testBlockEncodingStandard() {
        let blocks = Macro.encodeBlocks(steps([(100, 500, true), (200, 1000, false), (100, 30, true)]), encoding: .standard)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].count, 56)
        XCTAssertEqual(blocks[1].count, 56)
        // freq 10000 = 0x002710, 500 ms = 0x0001F4, enabled | RF_ON<<1
        XCTAssertEqual(Array(blocks[0][0..<7]), [0x10, 0x27, 0x00, 0xF4, 0x01, 0x00, 0x03])
        // 200 MHz, 1000 ms, enabled | RF_OFF<<1 | recalc
        XCTAssertEqual(Array(blocks[0][7..<14]), [0x20, 0x4E, 0x00, 0xE8, 0x03, 0x00, 0x0D])
        XCTAssertEqual(blocks[0][20], 0x0B)
        XCTAssertEqual(blocks[0][49], 3) // macroSteps
        XCTAssertTrue(blocks[1].allSatisfy { $0 == 0 })
    }

    func testBlockEncodingInvertedQt() {
        let blocks = Macro.encodeBlocks(steps([(100, 500, true), (200, 500, false)]), encoding: .invertedQt)
        XCTAssertEqual(blocks[0][6], 0x01 | 0x04 | 0x08)
        XCTAssertEqual(blocks[0][13], 0x01 | 0x02 | 0x08)
    }

    func testFourteenStepsSplitAcrossBlocks() {
        let s = (0..<14).map { MacroStep(frequencyMHz: 100 + Double($0), durationMs: 100, rfOn: true) }
        let blocks = Macro.encodeBlocks(s, encoding: .standard)
        XCTAssertEqual(blocks[0][49], 7)
        XCTAssertEqual(blocks[1][49], 7)
        // Step 8 (index 7) is first in block 1: 107 MHz = 10700 = 0x29CC
        XCTAssertEqual(Array(blocks[1][0..<3]), [0xCC, 0x29, 0x00])
        XCTAssertEqual(Array(blocks[0][50...]), [0, 0, 0, 0, 0, 0])
    }

    func testValidation() {
        XCTAssertFalse(Macro.validate(steps([(100, 500, true)])).isEmpty)
        XCTAssertTrue(Macro.validate(steps([(100, 500, true), (4400, 30, false)])).isEmpty)
        XCTAssertFalse(Macro.validate(steps([(100, 29, true), (200, 500, true)])).isEmpty)
        XCTAssertFalse(Macro.validate(steps([(34.99, 500, true), (200, 500, true)])).isEmpty)
        XCTAssertFalse(Macro.validate(Array(repeating: MacroStep(), count: 15)).isEmpty)
    }
}

final class SweepTests: XCTestCase {
    func testStepCountAndFrequencies() {
        let plan = SweepPlan(startMHz: 100, stopMHz: 500, stepMHz: 100, dwellMs: 500)
        XCTAssertEqual(plan.stepCount, 5)
        XCTAssertEqual(plan.passDurationMs, 2500)
        XCTAssertEqual((0..<5).map(plan.frequencyMHz(at:)), [100, 200, 300, 400, 500])
    }

    func testStepThatDoesNotDivideSpan() {
        let plan = SweepPlan(startMHz: 100, stopMHz: 500, stepMHz: 150, dwellMs: 50)
        XCTAssertEqual(plan.stepCount, 3) // 100, 250, 400
        XCTAssertEqual(plan.frequencyMHz(at: 2), 400)
    }

    func testNoFloatingPointDrift() {
        let plan = SweepPlan(startMHz: 35, stopMHz: 4400, stepMHz: 0.01, dwellMs: 30)
        XCTAssertEqual(plan.stepCount, 436_501)
        XCTAssertEqual(plan.frequencyMHz(at: 436_500), 4400)
        XCTAssertEqual(plan.frequencyMHz(at: 123_457), 1269.57)
    }

    func testValidation() {
        XCTAssertTrue(SweepPlan().validate().isEmpty)
        XCTAssertFalse(SweepPlan(startMHz: 500, stopMHz: 100, stepMHz: 1, dwellMs: 50).validate().isEmpty)
        XCTAssertFalse(SweepPlan(startMHz: 100, stopMHz: 101, stepMHz: 2, dwellMs: 50).validate().isEmpty)
        XCTAssertFalse(SweepPlan(startMHz: 100, stopMHz: 200, stepMHz: 1, dwellMs: 29).validate().isEmpty)
        XCTAssertTrue(SweepPlan(startMHz: 100, stopMHz: 200, stepMHz: 1, dwellMs: 70_000).validate().isEmpty)
        XCTAssertFalse(SweepPlan(startMHz: 100, stopMHz: 200, stepMHz: 1, dwellMs: 70_000).validateForDevice().isEmpty)
        XCTAssertNil(SweepPlan(startMHz: 100, stopMHz: 100, stepMHz: 1, dwellMs: 50).stepCount)
    }

    func testDurationFormat() {
        XCTAssertEqual(DurationFormat.string(ms: 450), "450 ms")
        XCTAssertEqual(DurationFormat.string(ms: 12_500), "12.5 s")
        XCTAssertEqual(DurationFormat.string(ms: 192_000), "3.2 min")
        XCTAssertEqual(DurationFormat.string(ms: 4_500_000), "1.25 hr")
    }
}
