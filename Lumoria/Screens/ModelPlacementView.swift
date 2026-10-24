import SwiftUI

/// Places a site's spacecraft model on a surface around you, at table size or real size.
struct ModelPlacementView: View {
    let site: LandingSite
    @Environment(\.dismiss) private var dismiss
    @State private var scene: ModelScene?
    @State private var controller = MoonARController()
    @State private var status: MoonARStatus = .starting
    @State private var realSize = false
    @State private var ready = false

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()
            if let scene {
                MoonARView(sites: [], mode: .table, content: scene, controller: controller, onStatus: { status = $0 })
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
                        Button {
                            // Back to table size first, so the reticle places a small model.
                            controller.setRealSize(false)
                            realSize = false
                            controller.move()
                        } label: {
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
                    HStack(spacing: Spacing.s2) {
                        sizeTab(tr("Table", "Mesa"), selected: !realSize) { realSize = false }
                        sizeTab(String(format: tr("Real · %.1f m", "Real · %.1f m"), info.realHeight), selected: realSize) { realSize = true }
                    }
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
        .onChange(of: realSize) { _, real in controller.setRealSize(real) }
    }

    private func sizeTab(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(TextStyle.bodyStrong.font)
                .foregroundStyle(selected ? Color.onSignal : Color.ink)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(selected ? Color.signal : Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
    }
}
