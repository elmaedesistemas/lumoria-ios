import SwiftUI

/// The card that opens when you tap a site (design system: StoryCard).
struct StoryCardView: View {
    let site: LandingSite
    /// The one primary action, shown only when set.
    var onSeeOnMoon: (() -> Void)?
    @Environment(SitesStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: Spacing.s3) {
                        HStack(spacing: Spacing.s2) {
                            SiteMarker(size: 28)
                            Text(site.label).style(.label).foregroundStyle(Color.inkMuted)
                        }
                        Text(site.mission).style(.title).foregroundStyle(Color.ink)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                        Text(site.coordinateText).style(.coordinate).foregroundStyle(Color.inkMuted)
                    }
                    Spacer(minLength: Spacing.s3)
                    // Where it is on the near side.
                    MoonDisk(sites: store.sites, selectedID: site.id)
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                }

                Text(site.story.current)
                    .style(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.s3)

                VStack(spacing: 0) {
                    meta(tr("Lander", "Módulo"), site.lander)
                    meta(tr("Crew", "Tripulación"), site.crewSurface.joined(separator: ", "))
                    meta(tr("Region", "Región"), site.region.current)
                    Rectangle().fill(Color.line).frame(height: 1)
                }
                .padding(.top, Spacing.s3)

                Text(tr("What was left behind", "Lo que quedó ahí"))
                    .style(.label)
                    .foregroundStyle(Color.inkMuted)
                    .padding(.top, Spacing.s6)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(site.leftBehind.enumerated()), id: \.offset) { index, item in
                        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
                            Text(String(format: "%02d", index + 1))
                                .style(.label).foregroundStyle(Color.signalText)
                            Text(item.current).style(.bodySmall).foregroundStyle(Color.ink)
                        }
                        .padding(.vertical, Spacing.s3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
                    }
                }

                if let onSeeOnMoon {
                    Button(tr("See it on the Moon", "Verlo en la Luna"), action: onSeeOnMoon)
                        .buttonStyle(.primary)
                        .padding(.top, Spacing.s3)
                }
            }
            .padding(Spacing.s6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func meta(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s3) {
            Text(key).style(.label).foregroundStyle(Color.inkMuted)
                .frame(width: 110, alignment: .leading)
            Text(value).style(.bodySmall).foregroundStyle(Color.ink)
            Spacer(minLength: 0)
        }
        .padding(.vertical, Spacing.s2)
        .overlay(alignment: .top) { Rectangle().fill(Color.line).frame(height: 1) }
    }
}
