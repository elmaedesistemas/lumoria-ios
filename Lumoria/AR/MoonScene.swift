import RealityKit
import UIKit

/// The Moon entity tree: a textured sphere and a light on each site.
/// Shared by the home preview and the AR table mode.
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
            light.isEnabled = false
            root.addChild(light)
            lights[site.id] = light
        }

        // Lights appear one by one in mission order, ~120 ms apart.
        for site in sites {
            try? await Task.sleep(for: .milliseconds(120))
            lights[site.id]?.isEnabled = true
        }
    }

    /// World positions of the lights that are showing.
    var visibleLights: [(id: String, position: SIMD3<Float>)] {
        lights.compactMap { id, light in light.isEnabled ? (id, light.position(relativeTo: nil)) : nil }
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
    /// Checked against Tycho, Copernicus and the maria in the simulator.
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
