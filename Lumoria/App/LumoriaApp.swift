import SwiftUI

@main
struct LumoriaApp: App {
    var body: some Scene {
        WindowGroup {
            SitesListView()
        }
    }
}

/// Temporary screen to check the data layer until the AR modes exist.
struct SitesListView: View {
    @State private var sites: [LandingSite] = []
    @State private var source: SitesRepository.Source?

    var body: some View {
        NavigationStack {
            List(sites) { site in
                VStack(alignment: .leading, spacing: 4) {
                    Text(site.label).font(.caption.monospaced()).foregroundStyle(.secondary)
                    Text(site.mission).font(.headline)
                    Text(site.story.current).font(.subheadline).lineLimit(3)
                }
            }
            .navigationTitle("Lumoria")
            .toolbar {
                if let source {
                    Text(source.rawValue.uppercased()).font(.caption2.monospaced())
                }
            }
            .task {
                let result = await SitesRepository().load()
                sites = result.sites
                source = result.source
            }
        }
    }
}
