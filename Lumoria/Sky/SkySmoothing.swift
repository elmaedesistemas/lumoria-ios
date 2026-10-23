import CoreGraphics
import Foundation

/// One Euro filter (Casiez et al., 2012): smooths hard when the signal is still,
/// follows quickly when it moves. Used for the ring's screen position.
struct OneEuroFilter {
    /// Cutoff at rest, in Hz: lower is smoother.
    var minCutoff: Double = 1.2
    /// How much speed raises the cutoff: higher follows fast moves with less lag.
    var beta: Double = 0.02
    var derivativeCutoff: Double = 1.0

    private var last: (value: Double, derivative: Double, time: TimeInterval)?

    mutating func filter(_ value: Double, at time: TimeInterval) -> Double {
        guard let previous = last, time > previous.time else {
            last = (value, 0, time)
            return value
        }
        let dt = time - previous.time
        let rawDerivative = (value - previous.value) / dt
        let derivative = Self.lowPass(rawDerivative, previous.derivative, dt: dt, cutoff: derivativeCutoff)
        let cutoff = minCutoff + beta * abs(derivative)
        let smoothed = Self.lowPass(value, previous.value, dt: dt, cutoff: cutoff)
        last = (smoothed, derivative, time)
        return smoothed
    }

    mutating func reset() { last = nil }

    private static func lowPass(_ x: Double, _ previous: Double, dt: Double, cutoff: Double) -> Double {
        let tau = 1 / (2 * .pi * cutoff)
        let alpha = 1 / (1 + tau / dt)
        return previous + alpha * (x - previous)
    }
}

/// One Euro filter on both screen axes.
struct PointFilter {
    private var x = OneEuroFilter()
    private var y = OneEuroFilter()

    mutating func filter(_ p: CGPoint, at time: TimeInterval) -> CGPoint {
        CGPoint(x: x.filter(Double(p.x), at: time), y: y.filter(Double(p.y), at: time))
    }

    mutating func reset() {
        x.reset()
        y.reset()
    }
}

/// Decides which Moon detections may move the compass correction.
/// A big jump from the current correction counts only when the next detection agrees with it,
/// so a single reflection or passing light can't throw the ring across the sky.
struct DetectionGate {
    /// Degrees: jumps larger than this need a second detection to confirm.
    var jumpLimit: Double = 2.5
    /// Degrees: how close the confirming detection must be.
    var agreement: Double = 1.0

    private var pending: (azimuth: Double, altitude: Double)?

    /// Returns the correction to aim for, or nil to ignore this detection.
    mutating func accept(azimuth: Double, altitude: Double,
                         current: (azimuth: Double, altitude: Double), hasLock: Bool) -> (azimuth: Double, altitude: Double)? {
        let candidate = (azimuth: azimuth, altitude: altitude)
        // First lock, or a small step from where we are: take it.
        guard hasLock, Self.distance(candidate, current) > jumpLimit else {
            pending = nil
            return candidate
        }
        if let pending, Self.distance(candidate, pending) <= agreement {
            self.pending = nil
            return candidate
        }
        pending = candidate
        return nil
    }

    mutating func reset() { pending = nil }

    private static func distance(_ a: (azimuth: Double, altitude: Double), _ b: (azimuth: Double, altitude: Double)) -> Double {
        hypot(a.azimuth - b.azimuth, a.altitude - b.altitude)
    }
}
