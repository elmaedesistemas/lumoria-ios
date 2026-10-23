import XCTest
@testable import Lumoria

/// Checks the app's sky math against values computed by scripts/moon_sky.py and NASA JPL Horizons
/// for San José, Sat 14 Nov 2026 18:00 local (00:00 UTC on the 15th).
final class SkyModelTests: XCTestCase {
    private let date = ISO8601DateFormatter().date(from: "2026-11-15T00:00:00Z")!

    private func snapshot() throws -> SkySnapshot {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sites", withExtension: "json")
            ?? Bundle.main.url(forResource: "sites", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let sites = try decoder.decode(SitesFile.self, from: Data(contentsOf: url)).landingSites
        return SkyModel.snapshot(at: date, latitude: SkyModel.sanJose.latitude, longitude: SkyModel.sanJose.longitude,
                                 height: SkyModel.sanJose.height, sites: sites)
    }

    func testPositionMatchesHorizons() throws {
        let sky = try snapshot()
        // Horizons: azimuth 222.8158, elevation 43.4378, illuminated 26.81%.
        XCTAssertEqual(sky.altitude, 43.4378, accuracy: 0.01)
        XCTAssertEqual(sky.azimuth, 222.8158, accuracy: 0.01)
        XCTAssertEqual(sky.illuminatedFraction * 100, 26.81, accuracy: 1)
    }

    func testDiskOrientationMatchesScript() throws {
        let sky = try snapshot()
        // Horizons gives the pole angle as 350.81; the script, 350.96.
        XCTAssertEqual(sky.polePositionAngle, 350.81, accuracy: 0.3)
        XCTAssertEqual(sky.parallacticAngle, 47.11, accuracy: 0.05)
        XCTAssertEqual(sky.northFromUp, -56.15, accuracy: 0.3)
    }

    func testSiteDaylightMatchesScript() throws {
        let sky = try snapshot()
        XCTAssertEqual(try XCTUnwrap(sky.siteSunElevation["apollo-17"]), 5.4, accuracy: 0.2)
        XCTAssertEqual(try XCTUnwrap(sky.siteSunElevation["apollo-12"]), -47.6, accuracy: 0.2)
        XCTAssertEqual(try XCTUnwrap(sky.siteSunElevation["apollo-11"]), -1.0, accuracy: 0.2)
    }

    func testMoonsetIsTheSameEvening() throws {
        let sky = try snapshot()
        let set = try XCTUnwrap(sky.moonset)
        // Script: Moonset Sat 14 Nov 21:40 local = 03:40 UTC on the 15th.
        XCTAssertEqual(set.timeIntervalSince(date) / 3600, 3.67, accuracy: 0.05)
    }

    func testNearSideSitesAreOnTheDisk() throws {
        let sky = try snapshot()
        let point = try XCTUnwrap(SkyModel.diskPoint(lat: 26.132, lon: 3.633, in: sky))
        XCTAssertLessThan(hypot(point.x, point.y), 1)
        XCTAssertNil(SkyModel.diskPoint(lat: 0, lon: 180, in: sky), "The far side should not be visible")
    }
}
