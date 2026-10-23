import XCTest
@testable import Lumoria

final class SkySmoothingTests: XCTestCase {
    func testOneEuroCutsJitterWhenStill() {
        var filter = OneEuroFilter()
        var raw: [Double] = [], out: [Double] = []
        for i in 0..<120 {   // Two seconds at 60 fps of ±4 pt jitter around 200.
            let value = 200 + (i.isMultiple(of: 2) ? 4.0 : -4.0)
            raw.append(value)
            out.append(filter.filter(value, at: Double(i) / 60))
        }
        let spread = { (xs: ArraySlice<Double>) in xs.max()! - xs.min()! }
        XCTAssertLessThan(spread(out.suffix(60)), spread(raw.suffix(60)) / 3)
        XCTAssertEqual(out.last!, 200, accuracy: 2)
    }

    func testOneEuroFollowsAFastMove() {
        var filter = OneEuroFilter()
        var value = 0.0
        for i in 0..<30 { value = filter.filter(Double(i) * 20, at: Double(i) / 60) }   // 1200 pt/s sweep.
        XCTAssertGreaterThan(value, 29 * 20 - 60, "Should lag only a little during a fast pan")
    }

    func testGateTakesSmallStepsRightAway() throws {
        var gate = DetectionGate()
        let result = try XCTUnwrap(gate.accept(azimuth: 3.4, altitude: -1.0, current: (3.0, -1.2), hasLock: true))
        XCTAssertEqual(result.azimuth, 3.4)
    }

    func testGateNeedsTwoDetectionsForABigJump() throws {
        var gate = DetectionGate()
        XCTAssertNil(gate.accept(azimuth: 9, altitude: 2, current: (3, -1), hasLock: true), "One frame isn't enough")
        let confirmed = try XCTUnwrap(gate.accept(azimuth: 9.3, altitude: 2.2, current: (3, -1), hasLock: true))
        XCTAssertEqual(confirmed.azimuth, 9.3)
    }

    func testGateDropsAnOutlierThatDoesNotRepeat() {
        var gate = DetectionGate()
        XCTAssertNil(gate.accept(azimuth: 12, altitude: 0, current: (3, -1), hasLock: true))
        XCTAssertNil(gate.accept(azimuth: -6, altitude: 4, current: (3, -1), hasLock: true), "A second, different jump isn't confirmation")
    }

    func testGateTakesTheFirstLockWhateverItsSize() {
        var gate = DetectionGate()
        XCTAssertNotNil(gate.accept(azimuth: 9, altitude: 2, current: (0, 0), hasLock: false))
    }
}
