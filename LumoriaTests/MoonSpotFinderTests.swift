import XCTest
@testable import Lumoria

/// Synthetic camera frames: a dark sky, the Moon as a saturated disk, and things that aren't the Moon.
final class MoonSpotFinderTests: XCTestCase {
    private let width = 640, height = 480

    private func frame(background: UInt8 = 12) -> [UInt8] {
        [UInt8](repeating: background, count: width * height)
    }

    private func disk(_ pixels: inout [UInt8], x cx: Int, y cy: Int, radius: Int, value: UInt8 = 255) {
        for y in max(0, cy - radius)...min(height - 1, cy + radius) {
            for x in max(0, cx - radius)...min(width - 1, cx + radius) where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius {
                pixels[y * width + x] = value
            }
        }
    }

    private func find(_ pixels: [UInt8], near: CGPoint) -> MoonSpotFinder.Spot? {
        pixels.withUnsafeBytes {
            MoonSpotFinder.find(luma: $0, width: width, height: height, bytesPerRow: width,
                                near: near, searchRadius: 150, moonRadius: 6)
        }
    }

    func testFindsTheMoonOffsetFromThePrediction() throws {
        var pixels = frame()
        disk(&pixels, x: 380, y: 200, radius: 8)
        disk(&pixels, x: 380, y: 200, radius: 14, value: 120)   // Glare halo, below threshold.
        disk(&pixels, x: 380, y: 200, radius: 8)
        let spot = try XCTUnwrap(find(pixels, near: CGPoint(x: 320, y: 240)))
        XCTAssertEqual(spot.center.x, 380, accuracy: 1.5)
        XCTAssertEqual(spot.center.y, 200, accuracy: 1.5)
    }

    func testIgnoresLightsOutsideTheSearchArea() {
        var pixels = frame()
        disk(&pixels, x: 600, y: 450, radius: 8)   // A street lamp far from where the Moon should be.
        XCTAssertNil(find(pixels, near: CGPoint(x: 200, y: 150)))
    }

    func testRejectsTwoSeparateLights() {
        var pixels = frame()
        disk(&pixels, x: 250, y: 200, radius: 6)
        disk(&pixels, x: 400, y: 280, radius: 6)
        XCTAssertNil(find(pixels, near: CGPoint(x: 320, y: 240)), "Two lights: don't guess which is the Moon")
    }

    func testRejectsABrightSky() {
        var pixels = frame(background: 170)       // Daytime or a lit wall.
        disk(&pixels, x: 320, y: 240, radius: 8)
        XCTAssertNil(find(pixels, near: CGPoint(x: 320, y: 240)))
    }

    func testRejectsALargeBrightArea() {
        var pixels = frame()
        disk(&pixels, x: 320, y: 240, radius: 70)  // A window, not a half-degree disk.
        XCTAssertNil(find(pixels, near: CGPoint(x: 320, y: 240)))
    }
}
