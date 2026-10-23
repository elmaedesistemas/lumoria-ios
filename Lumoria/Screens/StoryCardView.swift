import SwiftUI

/// The card that opens when you tap a site (design system: StoryCard).
struct StoryCardView: View {
    let site: LandingSite
    /// The one primary action, shown only when set.
    var onSeeOnMoon: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s3) {
                HStack(spacing: Spacing.s3) {
                    SiteMarker(size: 40)
                    Text(site.label).style(.label).foregroundStyle(Color.inkMuted)
                }

                Text(site.mission).style(.title).foregroundStyle(Color.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(site.coordinateText).style(.coordinate).foregroundStyle(Color.inkMuted)

                Text(site.story.current)
                    .style(.body)
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.s2)

                VStack(alignment: .leading, spacing: Spacing.s1) {
                    meta(tr("Lander", "Módulo"), site.lander)
                    meta(tr("Crew", "Tripulación"), site.crewSurface.joined(separator: ", "))
                    meta(tr("Region", "Región"), site.region.current)
                }
                .padding(.top, Spacing.s2)

                Text(tr("What was left behind", "Lo que quedó ahí"))
                    .style(.heading)
                    .foregroundStyle(Color.ink)
                    .padding(.top, Spacing.s6)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(site.leftBehind, id: \.self) { item in
                        Rectangle().fill(Color.line).frame(height: 1)
                        Text(item.current)
                            .style(.bodySmall)
                            .foregroundStyle(Color.ink)
                            .padding(.vertical, Spacing.s2)
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
        HStack(alignment: .firstTextBaseline, spacing: Spacing.s2) {
            Text(key).style(.label).foregroundStyle(Color.inkMuted)
            Text(value).style(.bodySmall).foregroundStyle(Color.ink)
        }
    }
}
