import Foundation
import Supabase

enum SupabaseService {
    /// Nil when Secrets.xcconfig is missing, so the app still runs on bundled data.
    static let client: SupabaseClient? = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let host = info["SUPABASE_HOST"] as? String, !host.isEmpty,
              let key = info["SUPABASE_ANON_KEY"] as? String, !key.isEmpty,
              let url = URL(string: "https://\(host)")
        else { return nil }
        return SupabaseClient(supabaseURL: url, supabaseKey: key)
    }()
}
