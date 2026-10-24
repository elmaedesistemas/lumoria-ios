import Foundation
import RealityKit

/// A spacecraft model from Resources/Models, sized for a table and switchable to real size.
@MainActor
final class ModelScene: PlaceableScene {
    struct Info: Sendable {
        let file: String
        let name: Localized
        /// For the switcher when a site has several models.
        let shortName: Localized
        /// Height of the real object, in meters.
        let realHeight: Float
        /// Height at table size, in meters; set so the model's footprint suits a table.
        let tableHeight: Float
        let credit: String
        /// What the model shows versus what is actually on the Moon.
        let note: Localized?
    }

    nonisolated static let catalog: [String: Info] = [
        "lunar-module": Info(
            file: "lunar-module",
            name: Localized(en: "Apollo Lunar Module", es: "Módulo Lunar del Apolo"),
            shortName: Localized(en: "Lunar module", es: "Módulo lunar"),
            realHeight: 7.04,
            tableHeight: 0.25,
            credit: "NASA 3D Resources",
            note: Localized(en: "The whole lander is shown. Only its lower half, the descent stage, stayed on the Moon; the top flew the crew back to orbit.",
                            es: "Se muestra el módulo completo. En la Luna solo quedó la mitad de abajo, la etapa de descenso; la parte de arriba despegó con la tripulación de vuelta a la órbita.")
        ),
        "lunar-rover": Info(
            file: "lunar-rover",
            name: Localized(en: "Lunar Roving Vehicle", es: "Vehículo Lunar Explorador"),
            shortName: Localized(en: "Rover", es: "Rover"),
            realHeight: 1.14,
            // ~3.1 m long, so about 27 cm on the table.
            tableHeight: 0.1,
            credit: "OldSchool3D (CC0), from NASA references",
            note: Localized(en: "Apollo 15, 16 and 17 each drove one of these and left it parked on the Moon, where all three still are. It folded up to ride on the side of the lunar module.",
                            es: "El Apolo 15, el 16 y el 17 manejaron uno cada uno y lo dejaron estacionado en la Luna, donde los tres siguen. Viajaba plegado en un costado del módulo lunar.")
        ),
    ]

    let info: Info
    let root = Entity()
    let restHeight: Float = 0
    let footprint: Float = 0.14
    let allowsTilt = false
    let previewDistance: Float = 0.9
    let visibleLights: [(id: String, position: SIMD3<Float>)] = []
    var realSize: Float? { info.realHeight / info.tableHeight }
    var sizeRange: ClosedRange<Float> { 0.4...(info.realHeight / info.tableHeight * 1.1) }

    private var loading: Task<Void, Never>?

    init?(model: String) {
        guard let info = Self.catalog[model] else { return nil }
        self.info = info
    }

    /// Loads the model once; later callers wait for the same load (it can take seconds).
    func prepare() async {
        if loading == nil { loading = Task { await load() } }
        await loading?.value
    }

    private func load() async {
        guard let url = Bundle.main.url(forResource: info.file, withExtension: "usdz"),
              let model = try? await Entity(contentsOf: url) else { return }
        // Scale to table height and put the base center at the root's origin.
        let bounds = model.visualBounds(relativeTo: nil)
        let scale = info.tableHeight / max(bounds.extents.y, 0.001)
        model.scale = .init(repeating: scale)
        model.position = SIMD3(-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale)
        root.addChild(model)
    }

    func apply(yaw: Float, pitch: Float, selectedID: String?) {
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
