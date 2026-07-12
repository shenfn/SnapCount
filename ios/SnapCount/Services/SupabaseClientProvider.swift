import Foundation
import Supabase

enum SupabaseClientProvider {
    static let client: SupabaseClient? = {
        guard let url = URL(string: AppConfig.supabaseURL), !AppConfig.supabaseAnonKey.isEmpty else {
            return nil
        }
        return SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey)
    }()
}
