import SwiftUI

/// The catalog of sites, in mission order.
struct ArchiveView: View {
    @Binding var path: [Route]
    @Environment(SitesStore.self) private var store
    @State private var openSite: LandingSite?

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tr("Archive", "Archivo")).style(.title).foregroundStyle(Color.ink)
                        .padding(.bottom, Spacing.s2)
                    Text(tr("Every place people landed on the Moon, 1969–1972.",
                            "Cada lugar donde alunizaron personas, 1969–1972."))
                        .style(.bodySmall)
                        .foregroundStyle(Color.inkMuted)
                        .padding(.bottom, Spacing.s6)

                    ForEach(store.sites) { site in
                        Button { openSite = site } label: { ArchiveRow(site: site) }
                            .buttonStyle(.plain)
                        Rectangle().fill(Color.line).frame(height: 1)
                    }
                }
                .padding(.horizontal, Spacing.s4)
                .padding(.bottom, Spacing.s8)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.space, for: .navigationBar)
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

private struct ArchiveRow: View {
    let site: LandingSite

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.s4) {
            SiteMarker(size: 40)
            VStack(alignment: .leading, spacing: Spacing.s1) {
                Text(site.label).style(.label).foregroundStyle(Color.inkMuted)
                Text(site.mission).font(TextStyle.heading.font).foregroundStyle(Color.ink)
                Text(site.region.current).style(.bodySmall).foregroundStyle(Color.ink)
                Text(site.coordinateText).style(.coordinate).foregroundStyle(Color.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s4)
        .contentShape(Rectangle())
    }
}
