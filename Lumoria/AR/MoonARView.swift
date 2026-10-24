import ARKit
import Combine
import RealityKit
import SwiftUI

enum MoonARStatus: Equatable {
    case starting       // The camera is opening.
    case searching      // No surface under the screen center yet.
    case readyToPlace   // The reticle is on a surface; the Moon follows it.
    case placed         // The Moon is fixed in the room (or floating in the preview).
    case cameraDenied
    case unsupported
}

/// Lets SwiftUI buttons drive the AR session.
@MainActor
final class MoonARController {
    fileprivate weak var coordinator: MoonARView.Coordinator?

    func placeHere() { coordinator?.confirmPlacement() }
    func move() { coordinator?.startPlacing() }
    func placeInFront() { coordinator?.placeInFront() }
    func setRealSize(_ real: Bool) { coordinator?.setRealSize(real) }
}

/// The 3D Moon in an ARView.
/// `.preview` floats it in front of a fixed camera (home screen, simulator);
/// `.table` runs world tracking: a reticle follows the surface you point at and
/// the Moon is fixed there when you place it.
struct MoonARView: UIViewRepresentable {
    enum Mode { case preview, table }

    let sites: [LandingSite]
    var mode: Mode
    /// What to place; the Moon with `sites` when nil.
    var content: PlaceableScene?
    var selectedID: String?
    var interactive = true
    var controller: MoonARController?
    var onSelect: (LandingSite) -> Void = { _ in }
    var onStatus: (MoonARStatus) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(scene: content ?? MoonScene(sites: sites)) }

    func makeUIView(context: Context) -> ARView {
        let coordinator = context.coordinator
        coordinator.parent = self
        controller?.coordinator = coordinator

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
            arView.addGestureRecognizer(UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.pinched(_:))))
        }

        Task { await coordinator.scene.prepare() }
        return arView
    }

    func updateUIView(_ arView: ARView, context: Context) {
        context.coordinator.parent = self
        controller?.coordinator = context.coordinator
        context.coordinator.applyPose()
    }

    static func dismantleUIView(_ arView: ARView, coordinator: Coordinator) {
        coordinator.updates?.cancel()
        arView.session.pause()
    }

    @MainActor
    final class Coordinator: NSObject, ARSessionDelegate {
        static let previewFOV: Float = 30

        var parent: MoonARView?
        weak var arView: ARView?
        let scene: PlaceableScene
        private var previewCamera: SIMD3<Float> { [0, 0, scene.previewDistance] }
        fileprivate var updates: Cancellable?

        private let worldAnchor = AnchorEntity(world: .zero)
        private let reticle: Entity
        private var placing = true
        private var status: MoonARStatus?
        /// Turns the near side toward the viewer; set when the Moon is placed.
        private var facingYaw: Float = 0
        private var yaw: Float = 0
        private var pitch: Float = 0
        private var size: Float = 1
        private var panStart: (yaw: Float, pitch: Float) = (0, 0)
        private var pinchStart: Float = 1
        /// Where the object sat at table size, to return there from real size.
        private var tablePosition: SIMD3<Float>?

        init(scene: PlaceableScene) {
            self.scene = scene
            reticle = MoonARView.makeReticle(radius: scene.footprint)
        }
        /// Apple's "move iPhone" guide, shown once at the start and never again after a surface is found.
        private var coaching: ARCoachingOverlayView?

        // MARK: Setup

        func startTracking() {
            guard let arView else { return }
            // Ask for the camera image explicitly so the room shows behind the Moon.
            arView.environment.background = .cameraFeed()

            let config = ARWorldTrackingConfiguration()
            config.planeDetection = [.horizontal]
            arView.session.delegate = self
            arView.session.run(config)


            scene.root.isEnabled = false
            worldAnchor.addChild(scene.root)
            worldAnchor.addChild(reticle)
            reticle.isEnabled = false
            arView.scene.addAnchor(worldAnchor)

            let coaching = ARCoachingOverlayView()
            coaching.session = arView.session
            coaching.goal = .horizontalPlane
            // Driven by hand: on until the first surface, so it can't come back mid-demo,
            // and transparent to touches so the buttons always work.
            coaching.activatesAutomatically = false
            coaching.isUserInteractionEnabled = false
            coaching.frame = arView.bounds
            coaching.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            arView.addSubview(coaching)
            coaching.setActive(true, animated: true)
            self.coaching = coaching

            updates = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] _ in
                MainActor.assumeIsolated { self?.trackReticle() }
            }
            report(.starting)

        }


        func placePreview() {
            guard let arView else { return }
            let cameraAnchor = AnchorEntity(world: .zero)
            let camera = PerspectiveCamera()
            // Fit the Moon to the view's width, whatever its height.
            camera.camera.fieldOfViewOrientation = .horizontal
            camera.camera.fieldOfViewInDegrees = Self.previewFOV
            camera.position = previewCamera
            cameraAnchor.addChild(camera)
            cameraAnchor.addChild(scene.root)
            arView.scene.addAnchor(cameraAnchor)
            placing = false
            report(.placed)
        }

        // MARK: Placement

        /// While placing, the reticle and the Moon follow the surface under the screen center.
        private func trackReticle() {
            guard placing, let arView else { return }
            // Until the camera delivers frames there is nothing to aim at.
            guard let frame = arView.session.currentFrame, frame.camera.trackingState != .notAvailable else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let hit = arView.raycast(from: center, allowing: .estimatedPlane, alignment: .horizontal).first else {
                reticle.isEnabled = false
                scene.root.isEnabled = false
                report(.searching)
                return
            }
            let point = SIMD3<Float>(hit.worldTransform.columns.3.x, hit.worldTransform.columns.3.y, hit.worldTransform.columns.3.z)
            reticle.position = point
            reticle.isEnabled = true
            endCoaching()
            setMoon(onSurfaceAt: point)
            report(.readyToPlace)
        }

        private func setMoon(onSurfaceAt point: SIMD3<Float>) {
            scene.root.position = point + [0, scene.restHeight * size, 0]
            scene.root.isEnabled = true
            faceCamera()
        }

        private func faceCamera() {
            guard let camera = arView?.cameraTransform.translation else { return }
            let toCamera = camera - scene.root.position
            facingYaw = atan2(toCamera.x, toCamera.z)
            applyPose()
        }

        func confirmPlacement() {
            guard placing, reticle.isEnabled else { return }
            placing = false
            reticle.isEnabled = false
            report(.placed)
        }

        func startPlacing() {
            guard arView?.cameraMode == .ar else { return }
            placing = true
            yaw = 0
            pitch = 0
            report(.searching)
        }

        /// Places the Moon half a meter in front of the camera, for when no surface is found.
        private func endCoaching() {
            guard let coaching else { return }
            coaching.setActive(false, animated: true)
            self.coaching = nil
        }

        func placeInFront() {
            guard let arView, arView.cameraMode == .ar else { return }
            endCoaching()
            let camera = arView.cameraTransform
            let forward = camera.matrix.columns.2
            scene.root.position = camera.translation - SIMD3(forward.x, forward.y, forward.z) * 0.5
            scene.root.isEnabled = true
            reticle.isEnabled = false
            placing = false
            faceCamera()
            report(.placed)
        }

        func applyPose() {
            scene.apply(yaw: facingYaw + yaw, pitch: scene.allowsTilt ? pitch : 0, selectedID: parent?.selectedID)
            scene.root.scale = .init(repeating: size)
        }

        // MARK: Gestures

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let arView, let parent else { return }
            let point = gesture.location(in: arView)
            // ARView's own hit test only knows the AR camera, not the preview's fixed one.
            let hitID = arView.cameraMode == .ar ? arView.entity(at: point)?.name : previewPick(point, in: arView)
            if let site = parent.sites.first(where: { $0.id == hitID }) {
                parent.onSelect(site)
            } else if placing {
                confirmPlacement()
            }
        }

        @objc func panned(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began { panStart = (yaw, pitch) }
            let t = gesture.translation(in: gesture.view)
            yaw = panStart.yaw + Float(t.x) * 0.008
            if scene.allowsTilt { pitch = max(-1.2, min(1.2, panStart.pitch + Float(t.y) * 0.008)) }
            applyPose()
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard arView?.cameraMode == .ar else { return }
            if gesture.state == .began { pinchStart = size }
            let range = scene.sizeRange
            resize(to: min(range.upperBound, max(range.lowerBound, pinchStart * Float(gesture.scale))))
        }

        /// Switches between the starting size and the object's real size.
        func setRealSize(_ real: Bool) {
            guard let realSize = scene.realSize else { return }
            guard real else {
                resize(to: 1)
                if let tablePosition { scene.root.position = tablePosition }
                tablePosition = nil
                return
            }
            tablePosition = scene.root.position
            resize(to: realSize)
            placeOnFloorAhead()
        }

        /// Moves a real-size object onto the floor in front of the viewer, far enough
        /// that its nearest edge is a couple of meters away instead of around them.
        private func placeOnFloorAhead() {
            guard let arView, arView.cameraMode == .ar else { return }
            let camera = arView.cameraTransform
            let forward = camera.matrix.columns.2
            var ahead = SIMD3<Float>(-forward.x, 0, -forward.z)
            ahead = simd_length(ahead) > 0.01 ? simd_normalize(ahead) : [0, 0, -1]

            let local = scene.root.visualBounds(relativeTo: scene.root)
            let radius = max(local.extents.x, local.extents.z) / 2 * size
            let target = camera.translation + ahead * (radius + 2)

            // The floor under that spot; if ARKit hasn't seen it, assume the phone is held ~1.4 m up.
            let surface = scene.root.position.y - scene.restHeight * size
            var floor = min(surface, camera.translation.y - 1.4)
            let down = ARRaycastQuery(origin: [target.x, camera.translation.y, target.z], direction: [0, -1, 0],
                                      allowing: .estimatedPlane, alignment: .horizontal)
            if let hit = arView.session.raycast(down).first { floor = hit.worldTransform.columns.3.y }

            scene.root.position = [target.x, floor + scene.restHeight * size, target.z]
            faceCamera()
        }

        /// Changes size while keeping the object resting on the same surface.
        private func resize(to newSize: Float) {
            let surface = scene.root.position.y - scene.restHeight * size
            size = newSize
            scene.root.position.y = surface + scene.restHeight * size
            applyPose()
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
            let origin = previewCamera
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

        /// Deferred so it never lands while SwiftUI is still building the view; repeats are dropped.
        private func report(_ new: MoonARStatus) {
            guard new != status else { return }
            status = new
            Task { @MainActor [weak self] in self?.parent?.onStatus(new) }
        }

        // MARK: ARSessionDelegate (called on the main queue)


        nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
            let denied = (error as? ARError)?.code == .cameraUnauthorized
            MainActor.assumeIsolated {
                report(denied ? .cameraDenied : .unsupported)
            }
        }
    }

    /// A flat signal disc that marks where the object will go.
    @MainActor
    static func makeReticle(radius: Float) -> Entity {
        let signal = UIColor(red: 1, green: 0.42, blue: 0.10, alpha: 1)
        var fill = UnlitMaterial(color: signal)
        fill.blending = .transparent(opacity: 0.25)
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.001, radius: radius), materials: [fill])
        let dot = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: radius * 0.07),
                              materials: [UnlitMaterial(color: signal)])
        disc.addChild(dot)
        return disc
    }
}
