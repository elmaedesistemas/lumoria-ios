import SwiftUI

/// The catalog of sites, in mission order.
struct ArchiveView: View {
    @Binding var path: [Route]
    @Environment(SitesStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var openSite: LandingSite?

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.ink)
                            .frame(width: 44, height: 44)
                            .background(Color.surface, in: Circle())
                    }
                    .accessibilityLabel(tr("Back", "Atrás"))
                    .padding(.bottom, Spacing.s6)

                    Text("\(tr("Archive", "Archivo")) · \(store.sites.count) \(tr("sites", "sitios"))")
                        .style(.label)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.bottom, Spacing.s2)
                    Text(tr("Everything we left on the Moon.", "Todo lo que dejamos en la Luna."))
                        .style(.display)
                        .foregroundStyle(Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, Spacing.s8)

                    section(tr("Apollo landings", "Alunizajes Apolo"), store.sites.filter(\.isCrewed))
                    section(tr("Probes, rovers and impacts", "Sondas, vehículos e impactos"),
                            store.sites.filter { !$0.isCrewed })
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s8)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $openSite) { site in
            StoryCardView(site: site) {
                openSite = nil
                path.append(.moon(selected: site.id))
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color.surface)
            .presentationCornerRadius(Radius.lg)
        }
    }
}

private extension ArchiveView {
    @ViewBuilder
    func section(_ title: String, _ sites: [LandingSite]) -> some View {
        if !sites.isEmpty {
            Text("\(title) · \(sites.count)")
                .style(.label)
                .foregroundStyle(Color.inkMuted)
                .padding(.top, Spacing.s6)
                .padding(.bottom, Spacing.s2)
            Rectangle().fill(Color.line).frame(height: 1)
            ForEach(Array(sites.enumerated()), id: \.element.id) { index, site in
                Button { openSite = site } label: { ArchiveRow(site: site, number: index + 1) }
                    .buttonStyle(.plain)
                Rectangle().fill(Color.line).frame(height: 1)
            }
        }
    }
}

private struct ArchiveRow: View {
    let site: LandingSite
    let number: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s4) {
            Text(String(format: "%02d", number))
                .style(.index)
                .foregroundStyle(Color.signalText)
                .frame(width: 32, alignment: .leading)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(site.mission).font(TextStyle.heading.font).foregroundStyle(Color.ink)
                Text("\(site.region.current) · \(site.landedAt.formatted(.dateTime.year()))")
                    .style(.bodySmall).foregroundStyle(Color.ink)
                Text(site.coordinateText).style(.label).font(.custom("IBMPlexMono-Medium", size: 12))
                    .foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.inkMuted)
        }
        .padding(.vertical, Spacing.s4)
        .contentShape(Rectangle())
    }
}
