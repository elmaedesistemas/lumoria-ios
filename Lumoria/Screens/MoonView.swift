import SwiftUI

/// Table mode, flat for now: the near side with a light per site.
/// The AR version will place this same Moon on a detected plane.
struct MoonView: View {
    var initialSelection: String?
    @Environment(SitesStore.self) private var store
    @State private var selectedID: String?

    var body: some View {
        ZStack {
            Color.space.ignoresSafeArea()

            VStack(spacing: Spacing.s6) {
                Text(tr("Near side · \(store.sites.count) sites", "Cara visible · \(store.sites.count) sitios"))
                    .style(.label)
                    .foregroundStyle(Color.inkMuted)

                MoonDisk(sites: store.sites, selectedID: selectedID) { selectedID = $0.id }
                    .padding(.horizontal, Spacing.s4)

                Text(tr("Tap a light to open its story.", "Toca una luz para abrir su historia."))
                    .style(.bodySmall)
                    .foregroundStyle(Color.inkMuted)

                chips

                Spacer(minLength: 0)
            }
            .padding(.top, Spacing.s4)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.space, for: .navigationBar)
        .onAppear { selectedID = initialSelection }
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

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.s2) {
                ForEach(store.sites) { site in
                    Button { selectedID = site.id } label: {
                        Text(site.mission.replacingOccurrences(of: "Apollo", with: tr("Apollo", "Apolo")))
                            .font(TextStyle.bodySmall.font)
                            .foregroundStyle(site.id == selectedID ? Color.onSignal : Color.ink)
                            .padding(.horizontal, Spacing.s3)
                            .frame(height: 36)
                            .background(site.id == selectedID ? Color.signal : Color.surface,
                                        in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Spacing.s4)
        }
    }
}
