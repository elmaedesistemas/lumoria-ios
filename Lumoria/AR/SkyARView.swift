import ARKit
import Combine
import RealityKit
import SwiftUI

/// Where the Moon falls on screen, refreshed every frame from the AR camera.
@MainActor
@Observable
final class SkyTracker {
    /// Moon center on screen, or nil when it's behind the camera.
    var moonPoint: CGPoint?
    /// The real disk's diameter on screen, in points.
    var moonDiameter: CGFloat = 0
    /// Direction toward the Moon when it's off screen: degrees clockwise from screen-up.
    var offscreenAngle: Double?
    var viewSize: CGSize = .zero
    var isTracking = false

    /// Correction from a tap on the real Moon (compass error), in degrees.
    var azimuthOffset: Double = 0
    var altitudeOffset: Double = 0
    var isCalibrated = false
    /// The ring is following the Moon found in the camera image.
    var isLocked = false

    func resetCalibration() {
        azimuthOffset = 0
        altitudeOffset = 0
        isCalibrated = false
        isLocked = false
    }
}

/// The camera with world axes locked to gravity and true north, so a sky direction
/// (azimuth, altitude) can be projected straight onto the screen.
struct SkyARView: UIViewRepresentable {
    let sky: SkySnapshot
    let tracker: SkyTracker

    func makeCoordinator() -> Coordinator { Coordinator(tracker: tracker) }

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        arView.environment.background = .cameraFeed()
        let config = ARWorldTrackingConfiguration()
        // y up, -z true north, x east.
        config.worldAlignment = .gravityAndHeading
        arView.session.run(config)

        let coordinator = context.coordinator
        coordinator.arView = arView
        coordinator.sky = sky
        coordinator.updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak coordinator] _ in
            MainActor.assumeIsolated { coordinator?.track() }
        }
        arView.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:))))
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.sky = sky
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject {
        let tracker: SkyTracker
        weak var arView: ARView?
        var sky: SkySnapshot?
        var updates: Cancellable?
        private var frameCount = 0
        private var lastLock: Date?

        init(tracker: SkyTracker) { self.tracker = tracker }

        /// Unit vector in the AR world for a sky direction.
        static func direction(azimuth: Double, altitude: Double) -> SIMD3<Float> {
            let a = azimuth * .pi / 180, h = altitude * .pi / 180
            return SIMD3(Float(cos(h) * sin(a)), Float(sin(h)), Float(-cos(h) * cos(a)))
        }

        func track() {
            guard let arView, let sky, let frame = arView.session.currentFrame else { return }
            tracker.viewSize = arView.bounds.size
            if case .normal = frame.camera.trackingState { tracker.isTracking = true } else { tracker.isTracking = false }

            let azimuth = sky.azimuth + tracker.azimuthOffset
            let altitude = sky.altitude + tracker.altitudeOffset
            let camera = arView.cameraTransform
            // Far enough that moving the phone around doesn't shift it.
            let reach: Float = 1000
            let target = camera.translation + Self.direction(azimuth: azimuth, altitude: altitude) * reach
            let edge = camera.translation + Self.direction(azimuth: azimuth, altitude: altitude + sky.diameter) * reach

            let toTarget = simd_mul(camera.matrix.inverse, SIMD4(target, 1))
            let inFront = toTarget.z < 0   // The camera looks down its -z.
            if inFront, let p = arView.project(target), let e = arView.project(edge) {
                tracker.moonPoint = p
                tracker.moonDiameter = CGFloat(hypot(e.x - p.x, e.y - p.y))
                let onScreen = arView.bounds.insetBy(dx: 8, dy: 8).contains(p)
                tracker.offscreenAngle = onScreen ? nil : atan2(Double(p.x - arView.bounds.midX), Double(arView.bounds.midY - p.y)) * 180 / .pi
                // Look for the real Moon a few times a second.
                frameCount += 1
                if frameCount % 6 == 0 { lockOnMoon(near: p, frame: frame, sky: sky, in: arView) }
            } else {
                tracker.moonPoint = nil
                // Behind: point the way to turn, from the camera-space direction.
                tracker.offscreenAngle = atan2(Double(toTarget.x), Double(toTarget.y)) * 180 / .pi
            }
        }

        /// Finds the bright disk near the prediction and eases the compass correction toward it.
        private func lockOnMoon(near predicted: CGPoint, frame: ARFrame, sky: SkySnapshot, in arView: ARView) {
            let buffer = frame.capturedImage
            CVPixelBufferLockBaseAddress(buffer, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
            guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return }
            let width = CVPixelBufferGetWidthOfPlane(buffer, 0), height = CVPixelBufferGetHeightOfPlane(buffer, 0)
            let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)

            // Screen points <-> image pixels through the camera's display transform.
            let view = arView.bounds.size
            let toView = frame.displayTransform(for: .portrait, viewportSize: view)
            let toImage = toView.inverted()
            let n = CGPoint(x: predicted.x / view.width, y: predicted.y / view.height).applying(toImage)
            let pixelsPerDegree = CGFloat(frame.camera.intrinsics[0][0]) * .pi / 180

            let spot = MoonSpotFinder.find(
                luma: UnsafeRawBufferPointer(start: base, count: bytesPerRow * height),
                width: width, height: height, bytesPerRow: bytesPerRow,
                near: CGPoint(x: n.x * CGFloat(width), y: n.y * CGFloat(height)),
                searchRadius: 12 * pixelsPerDegree,
                moonRadius: CGFloat(sky.diameter / 2) * pixelsPerDegree
            )
            guard let spot else {
                if let lastLock, Date().timeIntervalSince(lastLock) > 1.5 { tracker.isLocked = false }
                return
            }

            let v = CGPoint(x: spot.center.x / CGFloat(width), y: spot.center.y / CGFloat(height)).applying(toView)
            guard let ray = arView.ray(through: CGPoint(x: v.x * view.width, y: v.y * view.height)) else { return }
            let target = Self.offsets(for: simd_normalize(ray.direction), sky: sky)
            // Ease in so one noisy frame can't jerk the ring.
            tracker.azimuthOffset += (target.azimuth - tracker.azimuthOffset) * 0.35
            tracker.altitudeOffset += (target.altitude - tracker.altitudeOffset) * 0.35
            tracker.isLocked = true
            tracker.isCalibrated = true
            lastLock = Date()
        }

        /// The correction that moves the predicted Moon onto direction `d`.
        static func offsets(for d: SIMD3<Float>, sky: SkySnapshot) -> (azimuth: Double, altitude: Double) {
            let azimuth = (atan2(Double(d.x), Double(-d.z)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let altitude = asin(Double(d.y)) * 180 / .pi
            var dAz = (azimuth - sky.azimuth).truncatingRemainder(dividingBy: 360)
            if dAz > 180 { dAz -= 360 } else if dAz < -180 { dAz += 360 }
            return (dAz, altitude - sky.altitude)
        }

        /// A tap on the real Moon: the difference from the prediction is the compass error.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let arView, let sky, let ray = arView.ray(through: gesture.location(in: arView)) else { return }
            let correction = Self.offsets(for: simd_normalize(ray.direction), sky: sky)
            tracker.azimuthOffset = correction.azimuth
            tracker.altitudeOffset = correction.altitude
            tracker.isCalibrated = true
        }
    }
}
