import CoreGraphics

/// Finds the Moon in a camera frame: the brightest compact spot near where it should be.
/// Works on the luma (Y) plane only, so it's cheap enough to run several times a second.
enum MoonSpotFinder {
    struct Spot: Equatable {
        /// Centroid in image pixels.
        var center: CGPoint
        var peak: UInt8
        var area: Int
    }

    /// - Parameters:
    ///   - luma: Y plane bytes, `height` rows of `bytesPerRow`.
    ///   - near: predicted Moon position, in image pixels.
    ///   - searchRadius: how far from the prediction to look, in pixels.
    ///   - moonRadius: expected disk radius in pixels (glare makes it look bigger).
    /// - Returns: nil unless there's one bright, compact spot on a dark sky.
    static func find(luma: UnsafeRawBufferPointer, width: Int, height: Int, bytesPerRow: Int,
                     near: CGPoint, searchRadius: CGFloat, moonRadius: CGFloat) -> Spot? {
        let x0 = max(0, Int(near.x - searchRadius)), x1 = min(width - 1, Int(near.x + searchRadius))
        let y0 = max(0, Int(near.y - searchRadius)), y1 = min(height - 1, Int(near.y + searchRadius))
        guard x0 < x1, y0 < y1 else { return nil }
        let step = 2   // Every other pixel is plenty for a blob tens of pixels wide.

        var peak: UInt8 = 0
        var total = 0, samples = 0
        for y in stride(from: y0, through: y1, by: step) {
            let row = y * bytesPerRow
            for x in stride(from: x0, through: x1, by: step) {
                let v = luma[row + x]
                if v > peak { peak = v }
                total += Int(v)
                samples += 1
            }
        }
        // The Moon saturates the sensor at night; the sky around it is dark.
        guard peak >= 200, samples > 0, total / samples < 90 else { return nil }

        let threshold = max(190, Int(peak) - 30)
        var sumX = 0, sumY = 0, count = 0
        for y in stride(from: y0, through: y1, by: step) {
            let row = y * bytesPerRow
            for x in stride(from: x0, through: x1, by: step) where Int(luma[row + x]) >= threshold {
                sumX += x
                sumY += y
                count += 1
            }
        }
        guard count > 0 else { return nil }

        // Reject big bright areas (a lit wall, a window): allow the disk plus generous glare.
        let maxArea = Double.pi * pow(Double(max(moonRadius, 4)) * 6, 2) / Double(step * step)
        guard Double(count) <= maxArea else { return nil }

        // And reject two separate lights: the bright pixels must sit close to their centroid.
        let cx = Double(sumX) / Double(count), cy = Double(sumY) / Double(count)
        var spread = 0.0
        for y in stride(from: y0, through: y1, by: step) {
            let row = y * bytesPerRow
            for x in stride(from: x0, through: x1, by: step) where Int(luma[row + x]) >= threshold {
                spread = max(spread, hypot(Double(x) - cx, Double(y) - cy))
            }
        }
        guard spread <= Double(max(moonRadius, 4)) * 6 else { return nil }

        return Spot(center: CGPoint(x: cx, y: cy), peak: peak, area: count * step * step)
    }
}
