import Foundation
import RealityKit

/// A spacecraft model from Resources/Models, sized for a table and switchable to real size.
@MainActor
final class ModelScene: PlaceableScene {
    struct Info: Sendable {
        let file: String
        let name: Localized
        /// Height of the real object, in meters.
        let realHeight: Float
        let credit: String
        /// What the model shows versus what is actually on the Moon.
        let note: Localized?
    }

    nonisolated static let catalog: [String: Info] = [
        "lunar-module": Info(
            file: "lunar-module",
            name: Localized(en: "Apollo Lunar Module", es: "Módulo Lunar del Apolo"),
            realHeight: 7.04,
            credit: "NASA 3D Resources",
            note: Localized(en: "The whole lander is shown. Only its lower half, the descent stage, stayed on the Moon; the top flew the crew back to orbit.",
                            es: "Se muestra el módulo completo. En la Luna solo quedó la mitad de abajo, la etapa de descenso; la parte de arriba despegó con la tripulación de vuelta a la órbita.")
        ),
    ]

    /// Height on the table, in meters.
    static let tableHeight: Float = 0.25

    let info: Info
    let root = Entity()
    let restHeight: Float = 0
    let footprint: Float = 0.14
    let allowsTilt = false
    let previewDistance: Float = 0.9
    let visibleLights: [(id: String, position: SIMD3<Float>)] = []
    var realSize: Float? { info.realHeight / Self.tableHeight }
    var sizeRange: ClosedRange<Float> { 0.4...(info.realHeight / Self.tableHeight * 1.1) }

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
        let scale = Self.tableHeight / max(bounds.extents.y, 0.001)
        model.scale = .init(repeating: scale)
        model.position = SIMD3(-bounds.center.x * scale, -bounds.min.y * scale, -bounds.center.z * scale)
        root.addChild(model)
    }

    func apply(yaw: Float, pitch: Float, selectedID: String?) {
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
    }
}
