import SwiftUI

/// Places a site's spacecraft model on a surface around you, at table size or real size.
struct ModelPlacementView: View {
    let site: LandingSite
    @Environment(\.dismiss) private var dismiss
    @State private var scene: ModelScene?
    @State private var controller = MoonARController()
    @State private var status: MoonARStatus = .starting
    /// Size as a multiple of table size (1) up to real size.
    @State private var size: Float = 1
    @State private var ready = false

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()
            if let scene {
                MoonARView(sites: [], mode: .table, content: scene, controller: controller,
                           onStatus: { status = $0 }, onSize: { size = $0 })
                    .ignoresSafeArea()
            }
            if !ready {
                VStack(spacing: Spacing.s3) {
                    ProgressView().tint(Color.ink)
                    Text(tr("Loading the model…", "Cargando el modelo…")).style(.bodySmall).foregroundStyle(Color.inkMuted)
                }
            }
            VStack(spacing: 0) {
                HStack {
                    CircleButton(systemName: "xmark", label: tr("Close", "Cerrar")) { dismiss() }
                    Spacer()
                    Text(site.mission)
                        .style(.label)
                        .foregroundStyle(Color.ink)
                        .padding(.horizontal, Spacing.s3)
                        .frame(height: 32)
                        .background(Color.surface, in: Capsule())
                    if status == .placed {
                        Button { controller.move() } label: {
                            Text(tr("Move", "Mover")).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                                .padding(.horizontal, Spacing.s3)
                                .frame(height: 32)
                                .background(Color.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(Color.inkMuted, lineWidth: 1))
                        }
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.top, Spacing.s2)
                Spacer()
                if status == .placed, let info = scene?.info {
                    sizeBar(info)
                        .padding(.horizontal, Spacing.s4)
                }
                panel
            }
        }
        .task {
            if scene == nil, let model = site.model { scene = ModelScene(model: model) }
            await scene?.prepare()
            ready = true
        }
    }

    @ViewBuilder
    private var panel: some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            if let info = scene?.info {
                Text(info.name.current).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                switch status {
                case .starting:
                    HStack(spacing: Spacing.s3) {
                        ProgressView().tint(Color.ink)
                        Text(tr("Opening the camera…", "Abriendo la cámara…")).style(.bodySmall).foregroundStyle(Color.ink)
                    }
                case .searching:
                    Text(tr("Point at the floor or a table and move your iPhone slowly.",
                            "Apunta al piso o a una mesa y mueve el iPhone despacio."))
                        .style(.bodySmall).foregroundStyle(Color.ink)
                    Button(tr("Place it in front of me", "Colocarlo frente a mí")) { controller.placeInFront() }
                        .buttonStyle(.secondary)
                case .readyToPlace:
                    Button(tr("Place it here", "Colocar aquí")) { controller.placeHere() }
                        .buttonStyle(.primary)
                case .placed:
                    if let note = info.note {
                        Text(note.current).style(.bodySmall).foregroundStyle(Color.inkMuted)
                    }
                case .cameraDenied:
                    Text(tr("Lumoria needs the camera to place the model.", "Lumoria necesita la cámara para colocar el modelo."))
                        .style(.bodySmall).foregroundStyle(Color.ink)
                case .unsupported:
                    Text(tr("This device can't run AR.", "Este dispositivo no puede usar AR."))
                        .style(.bodySmall).foregroundStyle(Color.ink)
                }
                Text("\(tr("Model", "Modelo")): \(info.credit)")
                    .style(.label).font(.custom("IBMPlexMono-Medium", size: 11))
                    .foregroundStyle(Color.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .padding(Spacing.s4)
    }

    /// Floating over the camera: Table and Real jump to either end, the slider sets anything between.
    /// The slider is logarithmic, so the small sizes aren't squeezed into its first few points.
    private func sizeBar(_ info: ModelScene.Info) -> some View {
        let real = info.realHeight / ModelScene.tableHeight
        let height = ModelScene.tableHeight * size
        let ratio = info.realHeight / height
        let scaleText = ratio < 1.05 ? "1:1" : "1:\(Int(ratio.rounded()))"
        let heightText = height < 1 ? "\(Int((height * 100).rounded())) cm" : String(format: "%.1f m", height)
        let position = Binding<Double>(
            get: { Double(log(max(size, 1)) / log(real)) },
            set: { controller.setSize(exp(Float($0) * log(real))) }
        )
        return VStack(spacing: Spacing.s2) {
            Text("\(tr("Scale", "Escala")) \(scaleText) · \(heightText)")
                .style(.label)
                .foregroundStyle(Color.ink)
            HStack(spacing: Spacing.s3) {
                sizeButton(tr("Table", "Mesa"), selected: size <= 1.01) { controller.setSize(1) }
                Slider(value: position, in: 0...1)
                    .tint(Color.signal)
                    .accessibilityLabel(tr("Model size", "Tamaño del modelo"))
                    .accessibilityValue("\(scaleText), \(heightText)")
                sizeButton(tr("Real", "Real"), selected: size >= real * 0.99) { controller.setSize(real) }
            }
        }
        .padding(.horizontal, Spacing.s3)
        .padding(.vertical, Spacing.s3)
        .background(Color.surface.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.lg))
    }

    private func sizeButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TextStyle.bodyStrong.font)
                .foregroundStyle(selected ? Color.onSignal : Color.ink)
                .padding(.horizontal, Spacing.s3)
                .frame(minHeight: 36)
                .background(selected ? Color.signal : Color.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
