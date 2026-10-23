import Foundation

/// Text in both of Lumoria's languages.
struct Localized: Codable, Hashable, Sendable {
    let en: String
    let es: String

    var current: String {
        Locale.preferredLanguages.first?.hasPrefix("es") == true ? es : en
    }
}

/// A place where human equipment rests. Mirrors a row of `public.sites`.
struct LandingSite: Codable, Identifiable, Hashable, Sendable {
    struct Photo: Codable, Hashable, Sendable {
        let url: URL?
        let credit: String?
    }

    let id: String
    let body: String
    let mission: String
    let missionOrder: Int
    let label: String
    let lander: String
    let region: Localized
    let landedAt: Date
    let crewSurface: [String]
    let crewOrbit: String?
    /// Selenographic latitude in degrees, north-positive.
    let lat: Double
    /// Selenographic longitude in degrees, east-positive (-180...180).
    let lon: Double
    let leftBehind: [Localized]
    let story: Localized
    let photo: Photo?

    enum CodingKeys: String, CodingKey {
        case id, body, mission, label, lander, region, lat, lon, story, photo
        case missionOrder = "mission_order"
        case landedAt = "landed_at"
        case crewSurface = "crew_surface"
        case crewOrbit = "crew_orbit"
        case leftBehind = "left_behind"
    }
}

/// The shape of the bundled `sites.json`, used when Supabase can't be reached.
struct SitesFile: Decodable {
    struct Site: Decodable {
        struct Crew: Decodable { let surface: [String]; let orbit: String? }
        struct Coordinates: Decodable { let lat: Double; let lon: Double }

        let id: String
        let mission: String
        let order: Int
        let label: String
        let lander: String
        let region: Localized
        let landedAt: Date
        let crew: Crew
        let coordinates: Coordinates
        let leftBehind: [Localized]
        let story: Localized
        let photo: LandingSite.Photo?
    }

    let body: String
    let sites: [Site]

    var landingSites: [LandingSite] {
        sites.map {
            LandingSite(
                id: $0.id, body: body, mission: $0.mission, missionOrder: $0.order,
                label: $0.label, lander: $0.lander, region: $0.region, landedAt: $0.landedAt,
                crewSurface: $0.crew.surface, crewOrbit: $0.crew.orbit,
                lat: $0.coordinates.lat, lon: $0.coordinates.lon,
                leftBehind: $0.leftBehind, story: $0.story, photo: $0.photo
            )
        }
    }
}
