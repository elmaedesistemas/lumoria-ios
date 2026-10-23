import SwiftUI

/// Start screen: the six lights, the tagline and the mode selector.
struct HomeView: View {
    @Binding var path: [Route]
    @Environment(SitesStore.self) private var store
    @State private var mode: Mode = .table

    enum Mode { case table, sky }

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s6) {
                    HStack {
                        Text("Lumoria").style(.wordmark).foregroundStyle(Color.ink)
                        Spacer()
                        Button(tr("Archive", "Archivo")) { path.append(.archive) }
                            .font(TextStyle.bodySmall.font)
                    }

                    MoonDisk(sites: store.sites)
                        .frame(maxWidth: 220)
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        Text(tr("The stories we left on the Moon.", "Las historias que dejamos en la Luna."))
                            .style(.heading)
                            .foregroundStyle(Color.ink)
                        Text(tr("Six places where people landed, and what is still there.",
                                "Seis lugares donde alunizaron personas, y lo que sigue ahí."))
                            .style(.body)
                            .foregroundStyle(Color.inkMuted)
                    }

                    VStack(spacing: Spacing.s3) {
                        ModeOption(
                            tag: tr("Table", "Mesa"),
                            title: tr("The Moon on any surface", "La Luna sobre cualquier superficie"),
                            detail: tr("Indoors, by day. Tap a light to open its story.",
                                       "Bajo techo, de día. Toca una luz para abrir su historia."),
                            selected: mode == .table
                        ) { mode = .table }

                        ModeOption(
                            tag: tr("Sky · in progress", "Cielo · en desarrollo"),
                            title: tr("Point at the real Moon", "Apunta a la Luna real"),
                            detail: tr("At night, each site appears where it really is.",
                                       "De noche, cada sitio aparece donde está de verdad."),
                            selected: mode == .sky
                        ) { mode = .sky }
                    }

                    VStack(spacing: Spacing.s3) {
                        Button(mode == .table ? tr("Place the Moon", "Colocar la Luna")
                                              : tr("Find the Moon", "Buscar la Luna")) {
                            path.append(.moon(selected: nil))
                        }
                        .buttonStyle(.primary)
                        .disabled(mode == .sky || store.sites.isEmpty)

                        if let source = store.source {
                            Text(source == .supabase ? tr("Live archive", "Archivo en línea")
                                                     : tr("Offline archive", "Archivo sin conexión"))
                                .style(.label)
                                .foregroundStyle(Color.inkMuted)
                        }
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.vertical, Spacing.s4)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct ModeOption: View {
    let tag: String
    let title: String
    let detail: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.s2) {
                Text(tag).style(.label).foregroundStyle(selected ? Color.signalText : Color.inkMuted)
                Text(title).font(TextStyle.bodyStrong.font).foregroundStyle(Color.ink)
                Text(detail).style(.bodySmall).foregroundStyle(Color.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.s4)
            .background(selected ? Color.surfaceRaised : Color.surface,
                        in: RoundedRectangle(cornerRadius: Radius.md))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md)
                    .strokeBorder(selected ? Color.signal : Color.line, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
