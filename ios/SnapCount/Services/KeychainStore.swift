import Foundation
import Security

enum KeychainStoreError: LocalizedError {
    case unexpectedStatus(OSStatus)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            return "Keychain 操作失败：\(status)"
        case .invalidData:
            return "Keychain 数据格式无效"
        }
    }
}

final class KeychainStore {
    static let shared = KeychainStore()

    private let service: String

    init(service: String = "com.jiezi.app") {
        self.service = service
    }

    func setString(_ value: String, for key: String) throws {
#if targetEnvironment(simulator)
        UserDefaults.standard.set(value, forKey: simulatorStorageKey(for: key))
        return
#else
        let data = Data(value.utf8)
        var query = baseQuery(for: key)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            let updateStatus = SecItemUpdate(baseQuery(for: key) as CFDictionary, attributes as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw KeychainStoreError.unexpectedStatus(updateStatus)
            }
            return
        }

        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
#endif
    }

    func string(for key: String) throws -> String? {
#if targetEnvironment(simulator)
        return UserDefaults.standard.string(forKey: simulatorStorageKey(for: key))
#else
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw KeychainStoreError.invalidData
        }
        return value
#endif
    }

    func remove(_ key: String) throws {
#if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: simulatorStorageKey(for: key))
        return
#else
        let status = SecItemDelete(baseQuery(for: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainStoreError.unexpectedStatus(status)
        }
#endif
    }

#if targetEnvironment(simulator)
    private func simulatorStorageKey(for key: String) -> String {
        "\(service).simulator.\(key)"
    }
#endif

    private func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}

enum KeychainKeys {
    static let authSession = "auth_session"
    static let uploadToken = "upload_token"
    static let byokQwenAPIKey = "byok_qwen_api_key"
}
