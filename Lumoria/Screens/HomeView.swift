import SwiftUI

/// Start screen: the real Moon with its six lights, the promise, and the mode selector.
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(SitesStore.self) private var store
    @State private var mode: Mode = .table
    /// The hero's 3D view only exists while this screen shows, so it never runs beside the AR session.
    @State private var isVisible = false

    enum Mode { case table, sky }

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, Spacing.s4)

                hero

                VStack(alignment: .leading, spacing: Spacing.s3) {
                    Text(tr("The stories we left on the Moon.", "Las historias que dejamos en la Luna."))
                        .style(.display)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(tr("Six places where people landed, and what is still there.",
                            "Seis lugares donde alunizaron personas, y lo que sigue ahí."))
                        .style(.bodySmall)
                        .foregroundStyle(Color.inkMuted)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s6)

                VStack(spacing: Spacing.s3) {
                    modePicker
                    Button(mode == .table ? tr("Place the Moon", "Colocar la Luna")
                                          : tr("Find the Moon", "Buscar la Luna")) {
                        path.append(.moon(selected: nil))
                    }
                    .buttonStyle(.primary)
                    .disabled(mode == .sky || store.sites.isEmpty)
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s2)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    private var header: some View {
        HStack(spacing: Spacing.s2) {
            MoonDisk(sites: store.sites).frame(width: 22, height: 22)
            Text("Lumoria").style(.wordmarkSmall).foregroundStyle(Color.ink)
            Spacer()
            Button { path.append(.archive) } label: {
                Text(tr("Archive", "Archivo")).style(.label).foregroundStyle(Color.ink)
                    .padding(.horizontal, Spacing.s3)
                    .frame(height: 32)
                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.line))
            }
        }
        .frame(height: 44)
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            if isVisible && !store.sites.isEmpty {
                MoonARView(sites: store.sites, mode: .preview, interactive: false)
                    .allowsHitTesting(false)
            }
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(tr("Near side", "Cara visible")).style(.label).foregroundStyle(Color.inkMuted)
                Text("\(store.sites.count) \(tr("sites", "sitios")) · 1969–1972")
                    .style(.label).foregroundStyle(Color.inkMuted)
            }
            .padding(.horizontal, Spacing.s4)
            .padding(.top, Spacing.s2)

            if let source = store.source {
                HStack(spacing: Spacing.s1) {
                    Circle().fill(source == .supabase ? Color.signal : Color.inkMuted).frame(width: 6, height: 6)
                    Text(source == .supabase ? tr("Live", "En línea") : tr("Offline", "Sin conexión"))
                        .style(.label).foregroundStyle(Color.inkMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                .padding(Spacing.s4)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
    }

    private var modePicker: some View {
        HStack(spacing: Spacing.s2) {
            ModeTab(title: tr("Table", "Mesa"),
                    detail: tr("On any surface", "Sobre cualquier superficie"),
                    selected: mode == .table) { mode = .table }
            ModeTab(title: tr("Sky", "Cielo"),
                    detail: tr("The real Moon, soon", "La Luna real, pronto"),
                    selected: mode == .sky) { mode = .sky }
        }
    }
}

private struct ModeTab: View {
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(title).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                Text(detail).font(.custom("Archivo-Medium", size: 13, relativeTo: .footnote))
                    .foregroundStyle(selected ? Color.signalText : Color.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.s3)
            .padding(.vertical, Spacing.s3)
            .background(selected ? Color.surfaceRaised : Color.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(selected ? Color.signal : Color.line, lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
