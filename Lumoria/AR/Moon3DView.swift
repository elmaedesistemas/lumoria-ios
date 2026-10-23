import RealityKit
import SwiftUI
import UIKit

/// The Moon as a textured sphere with a light on each site.
/// On a device it sits on a detected horizontal plane (table mode, AR);
/// in the simulator, where AR is unavailable, it floats in front of a virtual camera.
struct Moon3DView: View {
    let sites: [LandingSite]
    var selectedID: String?
    var onSelect: (LandingSite) -> Void

    @State private var scene = MoonScene()
    @State private var yaw: Float = 0
    @State private var pitch: Float = 0
    @State private var dragStart: (yaw: Float, pitch: Float)?

    var body: some View {
        RealityView { content in
            #if targetEnvironment(simulator)
            content.camera = .virtual
            let camera = PerspectiveCamera()
            camera.camera.fieldOfViewInDegrees = 40
            camera.position = [0, 0, 0.42]
            content.add(camera)
            content.add(scene.root)
            #else
            content.camera = .spatialTracking
            let anchor = AnchorEntity(.plane(.horizontal, classification: .any, minimumBounds: [0.2, 0.2]))
            scene.root.position = [0, MoonScene.radius * 1.6, 0]
            anchor.addChild(scene.root)
            content.add(anchor)
            #endif
            await scene.build(sites: sites)
        } update: { _ in
            scene.apply(yaw: yaw, pitch: pitch, selectedID: selectedID)
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in
                    if let site = sites.first(where: { $0.id == value.entity.name }) { onSelect(site) }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { value in
                    let start = dragStart ?? (yaw, pitch)
                    dragStart = start
                    yaw = start.yaw + Float(value.translation.width) * 0.008
                    pitch = max(-1.2, min(1.2, start.pitch + Float(value.translation.height) * 0.008))
                }
                .onEnded { _ in dragStart = nil }
        )
    }
}

/// Owns the entities so SwiftUI updates can reach them.
@MainActor
final class MoonScene {
    static let radius: Float = 0.1

    let root = Entity()
    private var lights: [String: Entity] = [:]
    private var built = false

    func build(sites: [LandingSite]) async {
        guard !built else { return }
        built = true

        let globe = ModelEntity(mesh: .generateSphere(radius: Self.radius), materials: [await moonMaterial()])
        // Turn the texture so its longitude 0 faces the viewer (+Z).
        globe.orientation = simd_quatf(angle: Self.textureYaw, axis: [0, 1, 0])
        root.addChild(globe)

        let signal = UIColor(red: 1, green: 0.42, blue: 0.10, alpha: 1)
        var haloMaterial = UnlitMaterial(color: signal)
        haloMaterial.blending = .transparent(opacity: 0.3)

        for site in sites {
            let light = ModelEntity(mesh: .generateSphere(radius: Self.radius * 0.035),
                                    materials: [UnlitMaterial(color: signal)])
            light.name = site.id
            light.position = Self.surfacePoint(lat: site.lat, lon: site.lon, lift: 1.01)
            light.addChild(ModelEntity(mesh: .generateSphere(radius: Self.radius * 0.07), materials: [haloMaterial]))
            // Generous tap target so a finger can hit a 7 mm light.
            light.components.set(CollisionComponent(shapes: [.generateSphere(radius: Self.radius * 0.12)]))
            light.components.set(InputTargetComponent())
            root.addChild(light)
            lights[site.id] = light
        }
    }

    func apply(yaw: Float, pitch: Float, selectedID: String?) {
        root.orientation = simd_quatf(angle: pitch, axis: [1, 0, 0]) * simd_quatf(angle: yaw, axis: [0, 1, 0])
        for (id, light) in lights {
            light.scale = .init(repeating: id == selectedID ? 1.6 : 1)
        }
    }

    /// Selenographic latitude/longitude to a point on the sphere; the near side faces +Z.
    static func surfacePoint(lat: Double, lon: Double, lift: Float = 1) -> SIMD3<Float> {
        let φ = Float(lat * .pi / 180), λ = Float(lon * .pi / 180)
        let r = radius * lift
        return [r * cos(φ) * sin(λ), r * sin(φ), r * cos(φ) * cos(λ)]
    }

    /// Rotation that brings the equirectangular map's center (longitude 0) to +Z.
    static let textureYaw: Float = .pi / 2

    private func moonMaterial() async -> RealityKit.Material {
        guard let url = Bundle.main.url(forResource: "moon-color-2k", withExtension: "jpg"),
              let texture = try? await TextureResource(contentsOf: url) else {
            return UnlitMaterial(color: UIColor(red: 0.85, green: 0.83, blue: 0.78, alpha: 1))
        }
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        return material
    }
}
