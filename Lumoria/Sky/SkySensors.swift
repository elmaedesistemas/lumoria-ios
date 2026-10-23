import CoreLocation
import CoreMotion
import Observation

/// Where the phone is and where its back camera points.
@MainActor
@Observable
final class SkySensors: NSObject, CLLocationManagerDelegate {
    /// Device location, or nil while unknown / denied (callers fall back to San José).
    private(set) var location: CLLocation?
    private(set) var locationDenied = false
    /// Back-camera direction: degrees clockwise from true north, and degrees above the horizon.
    private(set) var cameraAzimuth: Double?
    private(set) var cameraElevation: Double?

    private let locationManager = CLLocationManager()
    private let motion = CMMotionManager()

    func start() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()

        // True-north reference needs location and the compass; not available in the simulator.
        guard motion.isDeviceMotionAvailable,
              CMMotionManager.availableAttitudeReferenceFrames().contains(.xTrueNorthZVertical) else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 30
        motion.startDeviceMotionUpdates(using: .xTrueNorthZVertical, to: .main) { [weak self] data, _ in
            guard let m = data?.attitude.rotationMatrix else { return }
            // Row 3 is the device's z axis in the reference frame (x north, y west, z up);
            // the back camera looks along -z.
            let north = -m.m31, west = -m.m32, up = -m.m33
            MainActor.assumeIsolated {
                self?.cameraAzimuth = (atan2(-west, north) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
                self?.cameraElevation = asin(max(-1, min(1, up))) * 180 / .pi
            }
        }
    }

    func stop() {
        locationManager.stopUpdatingLocation()
        motion.stopDeviceMotionUpdates()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { location = last }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated { locationDenied = status == .denied || status == .restricted }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
