import ARKit
import RealityKit
import SwiftUI

enum MoonARStatus: Equatable {
    case searching      // Looking for a horizontal surface.
    case placed         // The Moon is on the table (or floating in the preview).
    case cameraDenied
    case unsupported
}

/// The 3D Moon in an ARView.
/// `.preview` floats it in front of a fixed camera (home screen, simulator);
/// `.table` runs world tracking and places it on the first horizontal surface found.
struct MoonARView: UIViewRepresentable {
    enum Mode { case preview, table }

    let sites: [LandingSite]
    var mode: Mode
    var selectedID: String?
    var interactive = true
    /// Increment to place the Moon in front of the camera.
    var placeInFrontRequest = 0
    var onSelect: (LandingSite) -> Void = { _ in }
    var onStatus: (MoonARStatus) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> ARView {
        let coordinator = context.coordinator
        coordinator.parent = self

        #if targetEnvironment(simulator)
        let runsAR = false
        #else
        let runsAR = mode == .table && ARWorldTrackingConfiguration.isSupported
        #endif

        let arView = ARView(frame: .zero, cameraMode: runsAR ? .ar : .nonAR, automaticallyConfigureSession: false)
        arView.renderOptions.insert(.disableMotionBlur)
        coordinator.arView = arView

        if runsAR {
            coordinator.startTracking()
        } else {
            arView.environment.background = .color(UIColor(red: 0.043, green: 0.047, blue: 0.055, alpha: 1))
            coordinator.placePreview()
        }

        if interactive {
            arView.addGestureRecognizer(UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.tapped(_:))))
            arView.addGestureRecognizer(UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.panned(_:))))
        }

        Task { await coordinator.scene.build(sites: sites) }
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.applyPose()
        if placeInFrontRequest != coordinator.lastPlaceRequest {
            coordinator.lastPlaceRequest = placeInFrontRequest
            coordinator.placeInFront()
        }
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        var parent: MoonARView?
        var lastPlaceRequest = 0
        weak var arView: ARView?
        let scene = MoonScene()
        private var anchor: AnchorEntity?
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var panStart: (yaw: Float, pitch: Float) = (0, 0)

        func startTracking() {
            guard let arView else { return }
            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            arView.session.delegate = self
            arView.session.run(config)

            let coaching = ARCoachingOverlayView()
            coaching.session = arView.session
            coaching.goal = .horizontalPlane
            coaching.activatesAutomatically = true
            coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(coaching)

            report(.searching)
        }

        func placePreview() {
            guard let arView else { return }
            let cameraAnchor = AnchorEntity(world: .zero)
            let camera = PerspectiveCamera()
            // Fit the Moon to the view's width, whatever its height.
            camera.camera.fieldOfViewOrientation = .horizontal
            camera.camera.fieldOfViewInDegrees = Self.previewFOV
            camera.position = Self.previewCamera
            cameraAnchor.addChild(camera)
            cameraAnchor.addChild(scene.root)
            arView.scene.addAnchor(cameraAnchor)
            report(.placed)
        }

        /// Moves the Moon so it floats just above `transform` (a point on a surface).
        func place(on transform: simd_float4x4) {
            guard let arView else { return }
            anchor?.removeFromParent()
            let newAnchor = AnchorEntity(world: transform)
            scene.root.position = [0, MoonScene.radius * 1.5, 0]
            newAnchor.addChild(scene.root)
            arView.scene.addAnchor(newAnchor)
            anchor = newAnchor
            report(.placed)
        }

        /// Places the Moon half a meter in front of the camera, for when no surface is found.
        func placeInFront() {
            guard let camera = arView?.session.currentFrame?.camera.transform else { return }
            var offset = matrix_identity_float4x4
            offset.columns.3.z = -0.5
            offset.columns.3.y = -MoonScene.radius * 1.5
            place(on: camera * offset)
        }

        func applyPose() {
            scene.apply(yaw: yaw, pitch: pitch, selectedID: parent?.selectedID)
        }

        static let previewFOV: Float = 30
        static let previewCamera: SIMD3<Float> = [0, 0, 0.42]

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let arView, let parent else { return }
            let point = gesture.location(in: arView)
            // ARView's own hit test only knows the AR camera, not the preview's fixed one.
            let hitID = arView.cameraMode == .ar ? arView.entity(at: point)?.name : previewPick(point, in: arView)
            if let site = parent.sites.first(where: { $0.id == hitID }) {
                parent.onSelect(site)
                return
            }
            // Tapping a surface (re)places the Moon there.
            if parent.mode == .table,
               let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first {
                place(on: hit.worldTransform)
            }
        }

        /// The light under `point` on the near-facing half, casting a ray from the preview camera.
        private func previewPick(_ point: CGPoint, in view: UIView) -> String? {
            let w = Float(view.bounds.width), h = Float(view.bounds.height)
            guard w > 0, h > 0 else { return nil }
            let tanHalf = tan(Self.previewFOV * .pi / 360)
            let direction = simd_normalize(SIMD3<Float>(
                (Float(point.x) / w * 2 - 1) * tanHalf,
                (1 - Float(point.y) / h * 2) * tanHalf * h / w,
                -1
            ))
            let origin = Self.previewCamera
            let reach = MoonScene.radius * 0.12
            return scene.visibleLights
                .filter { $0.position.z > 0 }  // Only lights on the side facing the camera.
                .compactMap { light -> (String, Float)? in
                    let along = simd_dot(light.position - origin, direction)
                    let miss = simd_length(light.position - (origin + direction * along))
                    return miss < reach ? (light.id, along) : nil
                }
                .min { $0.1 < $1.1 }?.0
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { panStart = (yaw, pitch) }
            let t = gesture.translation(in: gesture.view)
            yaw = panStart.yaw + Float(t.x) * 0.008
            pitch = max(-1.2, min(1.2, panStart.pitch + Float(t.y) * 0.008))
            applyPose()
        }

        /// Deferred so it never lands while SwiftUI is still building the view.
        private func report(_ status: MoonARStatus) {
            Task { @MainActor [weak self] in self?.parent?.onStatus(status) }
        }

        // MARK: ARSessionDelegate (called on the main queue)

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            let planes = anchors.compactMap { ($0 as? ARPlaneAnchor)?.transform }
            MainActor.assumeIsolated {
                // The first surface found gets the Moon; later taps can move it.
                guard anchor == nil, let first = planes.first else { return }
                place(on: first)
            }
        }

        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let denied = (error as? ARError)?.code == .cameraUnauthorized
            MainActor.assumeIsolated {
                report(denied ? .cameraDenied : .unsupported)
            }
        }
    }
}
