import XCTest
@testable import Lumoria

/// Checks the bundled Data/sites.json the app falls back to offline.
final class SitesDataTests: XCTestCase {
    private func sites() throws -> [LandingSite] {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "sites", withExtension: "json")
            ?? Bundle.main.url(forResource: "sites", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SitesFile.self, from: Data(contentsOf: url)).landingSites
    }

    func testSixApolloLightsAndTheProbes() throws {
        let all = try sites()
        XCTAssertEqual(all.filter(\.isCrewed).count, 6)
        XCTAssertEqual(all.filter { $0.kind == .robotic }.count, 6)
        XCTAssertEqual(all.filter { $0.kind == .impact }.count, 2)
        XCTAssertEqual(Set(all.map(\.id)).count, all.count)
        XCTAssertEqual(all.map(\.missionOrder), Array(1...all.count))
    }

    func testCoordinatesAreOnTheNearSide() throws {
        for site in try sites() {
            XCTAssertLessThan(abs(site.lat), 90, site.id)
            XCTAssertLessThan(abs(site.lon), 90, "\(site.id) should face Earth")
        }
    }

    func testEveryModelIsInTheCatalogAndBundle() throws {
        for site in try sites() {
            for model in site.models {
                let info = try XCTUnwrap(ModelScene.catalog[model], site.id)
                XCTAssertNotNil(Bundle.main.url(forResource: info.file, withExtension: "usdz"), model)
            }
        }
    }

    func testApolloRoverSitesShowTheRoverFirst() throws {
        let all = try sites()
        for id in ["apollo-15", "apollo-16", "apollo-17"] {
            XCTAssertEqual(all.first { $0.id == id }?.models.first, "lunar-rover", id)
        }
        for id in ["apollo-11", "apollo-12", "apollo-14"] {
            XCTAssertEqual(all.first { $0.id == id }?.models, ["lunar-module"], id)
        }
    }

    func testRobotsHaveNoCrew() throws {
        for site in try sites() where !site.isCrewed {
            XCTAssertTrue(site.crewSurface.isEmpty, site.id)
            XCTAssertNil(site.crewOrbit, site.id)
        }
    }
}
