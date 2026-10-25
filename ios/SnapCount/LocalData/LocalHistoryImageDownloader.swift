import Foundation

/// Authenticated migration downloads never follow redirects or send a user's
/// bearer token to an arbitrary URL stored in a historical row.
final class LocalHistoryImageDownloader {
    typealias Fetch = (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let baseURL: URL
    private let fetch: Fetch

    init(baseURL: URL, fetch: Fetch? = nil) {
        self.baseURL = baseURL
        self.fetch = fetch ?? { request in
            let session = URLSession(configuration: .ephemeral, delegate: HistoryNoRedirectDelegate(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw LocalDataError.invalidRecord }
            return (data, http)
        }
    }

    func download(paths: Set<String>, cloudUserID: String, accessToken: String,
                  expectedHashes: [String: String] = [:],
                  isCurrent: () -> Bool = { true }) async throws -> [String: Data] {
        guard let user = UUID(uuidString: cloudUserID), !accessToken.isEmpty else { throw LocalHistoryMigrationError.invalidCloudIdentity }
        var result: [String: Data] = [:]
        var byteCount = 0
        for path in paths.sorted() {
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            let url = try validatedURL(path: path, user: user)
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await fetch(request)
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            guard response.statusCode == 200, response.url == url,
                  !data.isEmpty, data.count <= 16 * 1024 * 1024 else { throw LocalDataError.invalidRecord }
            byteCount += data.count
            guard byteCount <= 128 * 1024 * 1024 else { throw LocalDataError.invalidRecord }
            if let hash = expectedHashes[path] {
                guard hash.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) != nil,
                      LocalImageStore.sha256(data) == hash.lowercased() else { throw LocalDataError.invalidRecord }
            }
            result[path] = data
        }
        return result
    }

    private func validatedURL(path: String, user: UUID) throws -> URL {
        guard baseURL.scheme == "https", baseURL.user == nil, baseURL.password == nil,
              let host = baseURL.host, !path.contains("\\"), !path.contains("%"),
              !path.split(separator: "/").contains("..") else { throw LocalDataError.invalidRecord }
        let owner = user.uuidString.lowercased()
        if let absolute = URL(string: path), absolute.scheme != nil {
            guard absolute.scheme == "https", absolute.host == host, absolute.port == baseURL.port,
                  absolute.user == nil, absolute.password == nil, absolute.fragment == nil else { throw LocalDataError.invalidRecord }
            let prefixes = ["sign", "public", "authenticated"].map { "/storage/v1/object/\($0)/receipt-images/\(owner)/" }
            guard prefixes.contains(where: { absolute.path.lowercased().hasPrefix($0) }) else { throw LocalDataError.invalidRecord }
            return absolute
        }
        guard path.lowercased().hasPrefix(owner + "/"), !path.contains("?"), !path.contains("#") else { throw LocalDataError.invalidRecord }
        return baseURL.appendingPathComponent("storage/v1/object/authenticated/receipt-images").appendingPathComponent(path)
    }
}

private final class HistoryNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
