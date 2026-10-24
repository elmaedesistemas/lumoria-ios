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
    func setSize(_ size: Float) { coordinator?.setSize(size) }
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
    /// The object's size as a multiple of its starting size, after a pinch or `setSize`.
    var onSize: (Float) -> Void = { _ in }

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
        context.coordinator.focusSelection()
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
        /// The surface point where a model was placed; growing it moves it away from there.
        private var placedSpot: SIMD3<Float>?
        /// Height of the floor, from a plane ARKit classified as floor or else the lowest one well below the phone.
        private var floorY: Float?
        private var floorIsClassified = false
        /// The site the Moon last turned toward, and the turn in progress.
        private var focusedID: String?
        private var focusTurn: Cancellable?

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
        /// Where the screen point meets a horizontal surface: a detected plane if there is one,
        /// else ARKit's estimate, else the floor plane extended past the part that's been scanned.
        private func surfaceHit(at point: CGPoint, in arView: ARView) -> ARRaycastResult? {
            if let hit = arView.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .horizontal).first {
                return hit
            }
            if let hit = arView.raycast(from: point, allowing: .estimatedPlane, alignment: .horizontal).first {
                return hit
            }
            guard let floorY else { return nil }
            return arView.raycast(from: point, allowing: .existingPlaneInfinite, alignment: .horizontal)
                .first { abs($0.worldTransform.columns.3.y - floorY) < 0.05 }
        }

        private func trackReticle() {
            guard placing, let arView else { return }
            // Until the camera delivers frames there is nothing to aim at.
            guard let frame = arView.session.currentFrame, frame.camera.trackingState != .notAvailable else { return }
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            guard let hit = surfaceHit(at: center, in: arView) else {
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
            focusSelection()
        }

        /// Turns the Moon so the selected site faces the viewer, once per new selection.
        func focusSelection() {
            guard let selectedID = parent?.selectedID else { focusedID = nil; return }
            guard selectedID != focusedID, !placing, scene is MoonScene, let arView,
                  let site = parent?.sites.first(where: { $0.id == selectedID }) else { return }
            focusedID = selectedID

            // Direction to the viewer from the Moon's center; in the preview it's straight ahead.
            var toViewer = previewCamera - scene.root.position
            if arView.cameraMode == .ar { toViewer = arView.cameraTransform.translation - scene.root.position }
            let viewerYaw = atan2(toViewer.x, toViewer.z)
            let viewerElevation = atan2(toViewer.y, hypot(toViewer.x, toViewer.z))

            // A site at (lat, lon) faces +Z after turning by -lon and tilting by lat.
            // Tilting less points it up at a viewer looking down on the table, and
            // `lift` (~30°) puts it in the Moon's upper half, above the story card.
            let λ = Float(site.lon * .pi / 180), φ = Float(site.lat * .pi / 180)
            let lift: Float = 0.5
            let targetYaw = yaw + remainder(viewerYaw - λ - facingYaw - yaw, 2 * .pi)
            let targetPitch = max(-1.2, min(1.2, φ - viewerElevation - lift))

            let start = (yaw: yaw, pitch: pitch)
            var elapsed: Float = 0
            let duration: Float = 0.7
            focusTurn?.cancel()
            focusTurn = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                guard let self else { return }
                elapsed = min(duration, elapsed + Float(event.deltaTime))
                let t = elapsed / duration
                let eased = t * t * (3 - 2 * t)
                self.yaw = start.yaw + (targetYaw - start.yaw) * eased
                self.pitch = start.pitch + (targetPitch - start.pitch) * eased
                self.applyPose()
                if t >= 1 { self.focusTurn?.cancel(); self.focusTurn = nil }
            }
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
            if scene.realSize != nil {
                // A model goes back to table size so the reticle places something small.
                placedSpot = nil
                size = 1
                applyPose()
                parent?.onSize(size)
            }
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
            if gesture.state == .began {
                // A drag takes over from a focus turn still in progress.
                focusTurn?.cancel()
                focusTurn = nil
                panStart = (yaw, pitch)
            }
            let t = gesture.translation(in: gesture.view)
            yaw = panStart.yaw + Float(t.x) * 0.008
            if scene.allowsTilt { pitch = max(-1.2, min(1.2, panStart.pitch + Float(t.y) * 0.008)) }
            applyPose()
        }

        @objc func pinched(_ gesture: UIPinchGestureRecognizer) {
            guard arView?.cameraMode == .ar else { return }
            if gesture.state == .began { pinchStart = size }
            setSize(pinchStart * Float(gesture.scale))
        }

        /// Sets the size as a multiple of the starting size, within the scene's limits.
        /// A model in AR also steps back from the viewer as it grows, and stands on the floor once it's tall.
        func setSize(_ newSize: Float) {
            let range = scene.sizeRange
            let clamped = min(range.upperBound, max(range.lowerBound, newSize))
            guard scene.realSize != nil, !placing, let arView, arView.cameraMode == .ar else {
                resize(to: clamped)
                parent?.onSize(size)
                return
            }
            if placedSpot == nil { placedSpot = scene.root.position - [0, scene.restHeight * size, 0] }
            size = clamped
            keepClearOfViewer(in: arView)
            applyPose()
            parent?.onSize(size)
        }

        private func keepClearOfViewer(in arView: ARView) {
            guard let spot = placedSpot else { return }
            let camera = arView.cameraTransform
            let local = scene.root.visualBounds(relativeTo: scene.root)
            let radius = max(local.extents.x, local.extents.z) / 2 * size
            let height = local.extents.y * size

            // The gap to the nearest edge grows with the object, up to 1.5 m at real size.
            var away = SIMD3<Float>(spot.x - camera.translation.x, 0, spot.z - camera.translation.z)
            let distance = simd_length(away)
            if distance > 0.01 {
                away /= distance
            } else {
                let forward = camera.matrix.columns.2
                away = simd_normalize(SIMD3<Float>(-forward.x, 0, -forward.z) + [0, 0, 0.0001])
            }
            let needed = radius + min(radius, 1.5)
            var target = spot
            if distance < needed {
                target = camera.translation + away * needed
                target.y = spot.y
            }

            // Taller than a table can hold: stand it on the floor ARKit has found, or the
            // estimate under that spot, or ~1.4 m below the phone if neither exists yet.
            if height > 1 {
                if let floorY {
                    target.y = floorY
                } else {
                    let down = ARRaycastQuery(origin: [target.x, camera.translation.y, target.z], direction: [0, -1, 0],
                                              allowing: .estimatedPlane, alignment: .horizontal)
                    target.y = arView.session.raycast(down).first?.worldTransform.columns.3.y
                        ?? min(spot.y, camera.translation.y - 1.4)
                }
            }
            scene.root.position = target + [0, scene.restHeight * size, 0]
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

        nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
            let cameraY = session.currentFrame?.camera.transform.columns.3.y
            MainActor.assumeIsolated { notePlanes(planes, cameraY: cameraY) }
        }

        nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            let planes = anchors.compactMap { $0 as? ARPlaneAnchor }
            let cameraY = session.currentFrame?.camera.transform.columns.3.y
            MainActor.assumeIsolated { notePlanes(planes, cameraY: cameraY) }
        }

        private func notePlanes(_ planes: [ARPlaneAnchor], cameraY: Float?) {
            for plane in planes where plane.alignment == .horizontal {
                let y = plane.transform.columns.3.y
                if plane.classification == .floor {
                    // A classified floor wins over any guess; keep the lowest if there are several.
                    floorY = floorIsClassified ? min(floorY ?? y, y) : y
                    floorIsClassified = true
                } else if !floorIsClassified, let cameraY, y < cameraY - 0.8 {
                    floorY = min(floorY ?? y, y)
                }
            }
        }


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
