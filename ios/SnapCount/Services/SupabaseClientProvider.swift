import Foundation
import Supabase

enum SupabaseClientProvider {
    static let client: SupabaseClient? = {
        guard let url = URL(string: AppConfig.supabaseURL), !AppConfig.supabaseAnonKey.isEmpty else {
            return nil
        }
        let options = SupabaseClientOptions(
            auth: .init(
                storageKey: "jiezi.auth.session",
                autoRefreshToken: true,
                emitLocalSessionAsInitialSession: true
            )
        )
        return SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey, options: options)
    }()
}
