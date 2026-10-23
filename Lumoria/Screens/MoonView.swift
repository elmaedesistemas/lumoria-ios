import SwiftUI

/// Table mode: the camera, the Moon on a surface, and the six sites to jump between.
struct MoonView: View {
    var initialSelection: String?
    @Environment(SitesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var status: MoonARStatus = .searching
    @State private var controller = MoonARController()
    @State private var showPlaceFallback = false

    #if targetEnvironment(simulator)
    private let runsAR = false
    #else
    private let runsAR = true
    #endif

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            if !store.sites.isEmpty {
                MoonARView(
                    sites: store.sites,
                    mode: .table,
                    selectedID: selectedID,
                    controller: controller,
                    onSelect: { selectedID = $0.id },
                    onStatus: { status = $0 }
                )
                .ignoresSafeArea()
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottom
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { selectedID = initialSelection }
        .task(id: status) {
            // If no surface shows up after a while, offer to place the Moon in the air.
            showPlaceFallback = false
            guard status == .searching else { return }
            try? await Task.sleep(for: .seconds(6))
            showPlaceFallback = true
        }
        .sheet(item: Binding(
            get: { store.site(id: selectedID) },
            set: { selectedID = $0?.id }
        )) { site in
            StoryCardView(site: site)
                .presentationDetents([.medium, .large])
                .presentationBackground(Color.surface)
                .presentationCornerRadius(Radius.lg)
        }
    }

    private var topBar: some View {
        HStack(spacing: Spacing.s2) {
            CircleButton(systemName: "chevron.left", label: tr("Back", "Atrás")) { dismiss() }
            Spacer()
            Text(statusText)
                .style(.label)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.s3)
                .frame(height: 32)
                .background(Color.surface, in: Capsule())
            if runsAR && status == .placed {
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
    }

    @ViewBuilder
    private var bottom: some View {
        switch status {
        case .cameraDenied:
            panel {
                Text(tr("Lumoria needs the camera to place the Moon on a surface.",
                        "Lumoria necesita la cámara para colocar la Luna sobre una superficie."))
                    .style(.bodySmall).foregroundStyle(Color.ink)
                Button(tr("Open Settings", "Abrir Ajustes")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.primary)
            }
        case .unsupported:
            panel {
                Text(tr("This device can't run AR. The Archive has every story.",
                        "Este dispositivo no puede usar AR. El archivo tiene todas las historias."))
                    .style(.bodySmall).foregroundStyle(Color.ink)
            }
        case .searching:
            panel {
                Text(tr("Point at a table and move your iPhone slowly.",
                        "Apunta a una mesa y mueve el iPhone despacio."))
                    .style(.bodySmall).foregroundStyle(Color.ink)
                if showPlaceFallback {
                    Button(tr("Place it in front of me", "Colocarla frente a mí")) { controller.placeInFront() }
                        .buttonStyle(.secondary)
                }
            }
        case .readyToPlace:
            panel {
                Text(tr("The Moon will rest over the circle.", "La Luna quedará sobre el círculo."))
                    .style(.bodySmall).foregroundStyle(Color.inkMuted)
                Button(tr("Place it here", "Colocar aquí")) { controller.placeHere() }
                    .buttonStyle(.primary)
            }
        case .placed:
            siteStrip
        }
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
            .padding(Spacing.s4)
    }

    private var siteStrip: some View {
        VStack(alignment: .leading, spacing: Spacing.s2) {
            Text(tr("Drag to turn · pinch to resize", "Arrastra para girar · pellizca para cambiar el tamaño"))
                .style(.label)
                .font(.custom("IBMPlexMono-Medium", size: 11))
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.s3)
                .frame(height: 26)
                .background(Color.surface.opacity(0.9), in: Capsule())
                .padding(.horizontal, Spacing.s4)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.s2) {
                    ForEach(store.sites) { site in
                        Button { selectedID = site.id } label: {
                            VStack(alignment: .leading, spacing: Spacing.s1) {
                                Text(site.label).style(.label).font(.custom("IBMPlexMono-Medium", size: 11))
                                    .foregroundStyle(site.id == selectedID ? Color.signalText : Color.inkMuted)
                                Text(site.mission).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                            }
                            .padding(Spacing.s3)
                            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.md))
                            .overlay {
                                RoundedRectangle(cornerRadius: Radius.md)
                                    .strokeBorder(site.id == selectedID ? Color.signal : Color.line,
                                                  lineWidth: site.id == selectedID ? 1.5 : 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Spacing.s4)
            }
        }
        .padding(.bottom, Spacing.s4)
    }

    private var statusText: String {
        switch status {
        case .searching: tr("Finding a surface", "Buscando superficie")
        case .readyToPlace: tr("Surface found", "Superficie lista")
        case .placed: tr("Tap a light", "Toca una luz")
        case .cameraDenied: tr("Camera off", "Cámara apagada")
        case .unsupported: tr("AR unavailable", "AR no disponible")
        }
    }
}

/// A round 44 pt control on a surface fill, for overlays on the camera.
struct CircleButton: View {
    let systemName: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.ink)
                .frame(width: 44, height: 44)
                .background(Color.surface, in: Circle())
        }
        .accessibilityLabel(label)
    }
}
