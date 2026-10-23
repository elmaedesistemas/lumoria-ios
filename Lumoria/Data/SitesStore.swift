import Observation

/// Loads the sites once and shares them across screens.
@MainActor
@Observable
final class SitesStore {
    private(set) var sites: [LandingSite] = []
    private(set) var source: SitesRepository.Source?

    private let repository = SitesRepository()

    func load() async {
        guard sites.isEmpty else { return }
        let result = await repository.load()
        sites = result.sites
        source = result.source
    }

    func site(id: String?) -> LandingSite? {
        sites.first { $0.id == id }
    }
}
