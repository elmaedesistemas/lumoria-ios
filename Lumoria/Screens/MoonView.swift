import SwiftUI

/// Table mode: the camera, the Moon on a surface, and the six sites to jump between.
struct MoonView: View {
    var initialSelection: String?
    @Environment(SitesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var selectedID: String?
    @State private var status: MoonARStatus = .searching
    @State private var placeRequest = 0
    @State private var showPlaceFallback = false

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            if !store.sites.isEmpty {
                MoonARView(
                    sites: store.sites,
                    mode: .table,
                    selectedID: selectedID,
                    placeInFrontRequest: placeRequest,
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
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .frame(width: 44, height: 44)
                    .background(Color.surface, in: Circle())
            }
            .accessibilityLabel(tr("Back", "Atrás"))
            Spacer()
            Text(statusText)
                .style(.label)
                .foregroundStyle(Color.ink)
                .padding(.horizontal, Spacing.s3)
                .frame(height: 32)
                .background(Color.surface, in: Capsule())
        }
        .padding(.horizontal, Spacing.s4)
        .padding(.top, Spacing.s2)
    }

    @ViewBuilder
    private var bottom: some View {
        switch status {
        case .cameraDenied:
            notice(tr("Lumoria needs the camera to place the Moon on a surface.",
                      "Lumoria necesita la cámara para colocar la Luna sobre una superficie."),
                   action: tr("Open Settings", "Abrir Ajustes")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
        case .unsupported:
            notice(tr("This device can't run AR. The Archive has every story.",
                      "Este dispositivo no puede usar AR. El archivo tiene todas las historias."),
                   action: nil) {}
        case .searching:
            VStack(spacing: Spacing.s3) {
                Text(tr("Move your iPhone slowly over a table.", "Mueve el iPhone despacio sobre una mesa."))
                    .style(.bodySmall)
                    .foregroundStyle(Color.ink)
                if showPlaceFallback {
                    Button(tr("Place it in front of me", "Colocarla frente a mí")) { placeRequest += 1 }
                        .buttonStyle(.secondary)
                }
            }
            .padding(Spacing.s4)
            .frame(maxWidth: .infinity)
            .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
            .padding(Spacing.s4)
        case .placed:
            siteStrip
        }
    }

    private var siteStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(store.sites) { site in
                    Button { selectedID = site.id } label: {
                        VStack(alignment: .leading, spacing: Spacing.s1) {
                            Text(site.label).style(.label).font(.custom("IBMPlexMono-Medium", size: 11))
                                .foregroundStyle(site.id == selectedID ? Color.signalText : Color.inkMuted)
                            Text(site.mission).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                        }
                        .padding(.horizontal, Spacing.s3)
                        .padding(.vertical, Spacing.s3)
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
        .padding(.bottom, Spacing.s4)
    }

    private func notice(_ text: String, action: String?, perform: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: Spacing.s3) {
            Text(text).style(.bodySmall).foregroundStyle(Color.ink)
            if let action {
                Button(action, action: perform).buttonStyle(.primary)
            }
        }
        .padding(Spacing.s4)
        .background(Color.surface, in: RoundedRectangle(cornerRadius: Radius.lg))
        .padding(Spacing.s4)
    }

    private var statusText: String {
        switch status {
        case .searching: tr("Finding a surface", "Buscando superficie")
        case .placed: tr("Tap a light", "Toca una luz")
        case .cameraDenied: tr("Camera off", "Cámara apagada")
        case .unsupported: tr("AR unavailable", "AR no disponible")
        }
    }
}
