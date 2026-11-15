import Foundation
import Supabase

#if targetEnvironment(simulator)
/// 模拟器专用的 Supabase Auth 本地存储。
///
/// 本机没有可用的代码签名身份（`security find-identity -v -p codesigning` 为 0 个），
/// 模拟器构建只能是 ad-hoc 签名，拿不到 `keychain-access-groups` 这类受控 entitlement，
/// 于是 Supabase Auth 默认的 `KeychainLocalStorage` 在首次读写会话时就返回
/// `errSecMissingEntitlement`（-34018），登录会在写会话这一步失败。
///
/// 这里用 UserDefaults 顶替，仅影响模拟器：会话是明文，只用于本机联调；
/// 真机 / TestFlight 仍走 `KeychainLocalStorage`。
struct SimulatorAuthStorage: AuthLocalStorage {
    private let prefix = "com.jiezi.app.simulator.auth."

    func store(key: String, value: Data) throws {
        UserDefaults.standard.set(value, forKey: prefix + key)
    }

    func retrieve(key: String) throws -> Data? {
        UserDefaults.standard.data(forKey: prefix + key)
    }

    func remove(key: String) throws {
        UserDefaults.standard.removeObject(forKey: prefix + key)
    }
}
#endif

enum SupabaseClientProvider {
    static let client: SupabaseClient? = {
        guard let url = URL(string: AppConfig.supabaseURL), !AppConfig.supabaseAnonKey.isEmpty else {
            return nil
        }
#if targetEnvironment(simulator)
        // 模拟器没有 Keychain entitlement（-34018），会话改存 UserDefaults；真机不变。
        let auth = SupabaseClientOptions.AuthOptions(
            storage: SimulatorAuthStorage(),
            storageKey: "jiezi.auth.session",
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
#else
        let auth = SupabaseClientOptions.AuthOptions(
            storageKey: "jiezi.auth.session",
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
#endif
        let options = SupabaseClientOptions(auth: auth)
        return SupabaseClient(supabaseURL: url, supabaseKey: AppConfig.supabaseAnonKey, options: options)
    }()
}
