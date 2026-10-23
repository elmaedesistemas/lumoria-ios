import Foundation

/// Loads landing sites from Supabase, falling back to the bundled sites.json
/// so the demo works without a network.
struct SitesRepository: Sendable {
    enum Source: String, Sendable { case supabase, bundled }

    enum LoadError: Error { case notConfigured, missingBundledFile }

    func load(body: String = "moon") async -> (sites: [LandingSite], source: Source) {
        do {
            return (try await fetchRemote(body: body), .supabase)
        } catch {
            return ((try? loadBundled()) ?? [], .bundled)
        }
    }

    func fetchRemote(body: String = "moon") async throws -> [LandingSite] {
        guard let client = SupabaseService.client else { throw LoadError.notConfigured }
        return try await client
            .from("sites")
            .select()
            .eq("body", value: body)
            .order("mission_order")
            .execute()
            .value
    }

    func loadBundled() throws -> [LandingSite] {
        guard let url = Bundle.main.url(forResource: "sites", withExtension: "json") else {
            throw LoadError.missingBundledFile
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let file = try decoder.decode(SitesFile.self, from: Data(contentsOf: url))
        return file.landingSites.sorted { $0.missionOrder < $1.missionOrder }
    }
}
