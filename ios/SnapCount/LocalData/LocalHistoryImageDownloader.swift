import Foundation

enum LocalHistoryImageDownloadError: Error, Equatable, LocalizedError {
    case sessionExpired, accessDenied, missingImage, missingTemporaryImage, invalidResponse(Int)
    var errorDescription: String? {
        switch self {
        case .sessionExpired: return "图片下载凭据已失效（401），请重新登录后继续；已缓存内容保留。"
        case .accessDenied: return "当前账户无权读取此图片（403）；原图未删除，已缓存内容保留。"
        case .missingImage: return "云端原图不存在（404）；请核对原图来源，迁移未完成。"
        case .missingTemporaryImage: return "同账户临时图片返回404；它可能已按隐私策略清理，也可能是来源路径失效，当前无法确认具体原因。迁移未完成。"
        case .invalidResponse(let code): return "图片服务返回异常状态（\(code)），迁移未完成。"
        }
    }
}

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
            var url = try validatedURL(path: path, user: user)
            var request = URLRequest(url: url)
            request.timeoutInterval = 30
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            var (data, response) = try await fetch(request)
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            let signedPrefix = "/storage/v1/object/sign/receipt-images/"
            if [400, 401, 403].contains(response.statusCode), url.path.lowercased().hasPrefix(signedPrefix) {
                let relative = String(url.path.dropFirst(signedPrefix.count))
                url = try validatedURL(path: relative, user: user)
                request.url = url
                (data, response) = try await fetch(request)
                guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            }
            switch response.statusCode {
            case 200: break
            case 401: throw LocalHistoryImageDownloadError.sessionExpired
            case 403: throw LocalHistoryImageDownloadError.accessDenied
            case 404:
                throw Self.isTemporaryPath(path, owner: user)
                    ? LocalHistoryImageDownloadError.missingTemporaryImage
                    : LocalHistoryImageDownloadError.missingImage
            default: throw LocalHistoryImageDownloadError.invalidResponse(response.statusCode)
            }
            guard response.url == url,
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
              let host = baseURL.host, !path.contains("\\"), !path.contains("%") else {
            throw LocalDataError.invalidRecord
        }
        let owner = user.uuidString.lowercased()
        if let absolute = URL(string: path), absolute.scheme != nil {
            guard absolute.scheme == "https", absolute.host == host, absolute.port == baseURL.port,
                  absolute.user == nil, absolute.password == nil, absolute.fragment == nil,
                  !absolute.path.contains("%") else { throw LocalDataError.invalidRecord }
            let prefixes = ["sign", "public", "authenticated"].map { "/storage/v1/object/\($0)/receipt-images/" }
            guard let prefix = prefixes.first(where: { absolute.path.lowercased().hasPrefix($0) }) else {
                throw LocalDataError.invalidRecord
            }
            let objectPath = String(absolute.path.dropFirst(prefix.count))
            guard !absolute.path.contains("\\"),
                  !absolute.path.dropFirst().split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  Self.isOwnedObjectPath(objectPath, owner: owner) else { throw LocalDataError.invalidRecord }
            return absolute
        }
        guard !path.split(separator: "/", omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              Self.isOwnedObjectPath(path, owner: owner), !path.contains("?"), !path.contains("#") else {
            throw LocalDataError.invalidRecord
        }
        return baseURL.appendingPathComponent("storage/v1/object/authenticated/receipt-images").appendingPathComponent(path)
    }

    private static func isOwnedObjectPath(_ path: String, owner: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        return (parts.first?.lowercased() == owner && parts.count > 1)
            || (parts.count > 2 && parts[0] == "tmp" && parts[1].lowercased() == owner)
    }

    private static func isTemporaryPath(_ path: String, owner: UUID) -> Bool {
        let ownerID = owner.uuidString.lowercased()
        let objectPath: String
        if let url = URL(string: path), url.scheme != nil,
           let range = url.path.range(of: "/storage/v1/object/"),
           let bucketRange = url.path[range.upperBound...].range(of: "/receipt-images/") {
            objectPath = String(url.path[bucketRange.upperBound...])
        } else {
            objectPath = path
        }
        let components = objectPath.split(separator: "/").map(String.init)
        return components.count > 2 && components[0] == "tmp" && components[1].lowercased() == ownerID
    }
}

private final class HistoryNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
