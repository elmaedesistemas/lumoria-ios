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

    func resetCalibration() {
        azimuthOffset = 0
        altitudeOffset = 0
        isCalibrated = false
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
            } else {
                tracker.moonPoint = nil
                // Behind: point the way to turn, from the camera-space direction.
                tracker.offscreenAngle = atan2(Double(toTarget.x), Double(toTarget.y)) * 180 / .pi
            }
        }

        /// A tap on the real Moon: the difference from the prediction is the compass error.
        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let arView, let sky, let ray = arView.ray(through: gesture.location(in: arView)) else { return }
            let d = simd_normalize(ray.direction)
            let tappedAzimuth = (atan2(Double(d.x), Double(-d.z)) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let tappedAltitude = asin(Double(d.y)) * 180 / .pi
            var dAz = (tappedAzimuth - sky.azimuth).truncatingRemainder(dividingBy: 360)
            if dAz > 180 { dAz -= 360 } else if dAz < -180 { dAz += 360 }
            tracker.azimuthOffset = dAz
            tracker.altitudeOffset = tappedAltitude - sky.altitude
            tracker.isCalibrated = true
        }
    }
}
