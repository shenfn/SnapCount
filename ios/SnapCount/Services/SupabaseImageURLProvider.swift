import Foundation
import Supabase

actor SupabaseImageURLProvider {
    static let shared = SupabaseImageURLProvider()

    private struct CacheEntry {
        let url: URL
        let expiresAt: Date
    }

    private let bucket = "receipt-images"
    private let signedURLLifetime = 3600
    private let cacheLifetime: TimeInterval = 3000
    private var cache: [String: CacheEntry] = [:]

    func signedURLMap(paths: [String]) async throws -> [String: URL] {
        let normalizedPaths = Array(Set(paths.filter { !$0.isEmpty }))
        var result: [String: URL] = [:]
        var unresolvedPaths: [String] = []
        let now = Date()

        for path in normalizedPaths {
            if path.hasPrefix("https://"), let url = URL(string: path) {
                result[path] = url
            } else if let entry = cache[path], entry.expiresAt > now {
                result[path] = entry.url
            } else {
                cache[path] = nil
                unresolvedPaths.append(path)
            }
        }

        guard !unresolvedPaths.isEmpty else { return result }
        guard let client = SupabaseClientProvider.client else {
            throw SupabaseRemoteError.missingConfig
        }

        for path in unresolvedPaths {
            let url = try await createSignedURL(path: path, client: client)
            result[path] = url
            cache[path] = CacheEntry(url: url, expiresAt: now.addingTimeInterval(cacheLifetime))
        }
        return result
    }

    func invalidate(path: String) {
        cache[path] = nil
    }

    private func createSignedURL(path: String, client: SupabaseClient) async throws -> URL {
        do {
            return try await client.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: signedURLLifetime)
        } catch {
            try await Task.sleep(for: .milliseconds(250))
            return try await client.storage
                .from(bucket)
                .createSignedURL(path: path, expiresIn: signedURLLifetime)
        }
    }
}
