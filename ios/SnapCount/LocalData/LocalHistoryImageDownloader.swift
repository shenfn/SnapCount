import Foundation

enum LocalHistoryImageDownloadError: Error, Equatable, LocalizedError {
    case unsupportedPathFormat
    case sourceScopeMismatch
    case sessionExpired
    case accessDenied
    case missingImage
    case missingTemporaryImage
    case invalidResponse(Int)
    case emptyResponse
    case imageTooLarge
    case totalSizeExceeded
    case responseAddressMismatch
    case hashMismatch

    var errorDescription: String? {
        switch self {
        case .unsupportedPathFormat: return "历史图片路径格式不受支持；本次迁移未入账，原图保留。"
        case .sourceScopeMismatch: return "图片路径不属于当前账户已读取的迁移记录或项目存储范围；本次迁移未入账。"
        case .sessionExpired: return "图片读取会话已失效（401）；请重新登录后继续，已缓存内容保留。"
        case .accessDenied: return "云端拒绝当前账户读取此图片（HTTP 403/400）；本图已跳过，对应记录仍会导入。"
        case .missingImage: return "云端原图不存在（HTTP 400/404）；本图已跳过，可继续迁移结构化记录。"
        case .missingTemporaryImage: return "同账户临时图片不可读取（HTTP 400/404）；本图已跳过，可继续迁移结构化记录。"
        case .invalidResponse(let code): return "图片服务返回异常状态（\(code)），迁移未完成。"
        case .emptyResponse: return "图片服务返回空内容；本图已跳过，可继续迁移结构化记录。"
        case .imageTooLarge: return "单张历史图片超过本机迁移上限；迁移未完成。"
        case .totalSizeExceeded: return "历史图片总量超过本机迁移上限；迁移未完成。"
        case .responseAddressMismatch: return "图片服务响应地址与受信请求不一致，已拒绝该响应。"
        case .hashMismatch: return "历史图片完整性校验未通过；迁移未完成。"
        }
    }
}

/// Contains only bounded, allowlisted response metadata, never a URL or raw body.
struct LocalHistoryImageHTTPError: Error, LocalizedError {
    let failure: LocalHistoryImageDownloadError
    let statusCode: Int
    let storageCode: String?
    let attempts: Int
    let elapsedMilliseconds: Int
    let responseBytes: Int

    var errorDescription: String? {
        "HTTP \(statusCode)，类别 \(storageCode ?? "Unknown")，尝试 \(attempts) 次；\(failure.localizedDescription)"
    }
}

/// Authenticated migration downloads never follow redirects or send a user's
/// bearer token to an arbitrary URL stored in a historical row.
final class LocalHistoryImageDownloader {
    typealias Fetch = @MainActor (URLRequest) async throws -> (Data, HTTPURLResponse)
    typealias Pause = @MainActor (UInt64) async throws -> Void
    private struct ValidatedStoragePath {
        let requestURL: URL
        let isTemporary: Bool
    }

    private let baseURL: URL
    private let fetch: Fetch
    private let pause: Pause
    private let session: URLSession?
    private static let maximumImageBytes = 16 * 1024 * 1024
    private static let unreservedASCII = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    init(baseURL: URL,
         pause: @escaping Pause = { try await Task.sleep(nanoseconds: $0) },
         fetch: Fetch? = nil) {
        self.baseURL = baseURL
        self.pause = pause
        if let fetch {
            self.fetch = fetch
            self.session = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpMaximumConnectionsPerHost = 3
            configuration.urlCache = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            let session = URLSession(configuration: configuration, delegate: HistoryNoRedirectDelegate(), delegateQueue: nil)
            self.session = session
            self.fetch = { request in
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw LocalHistoryImageDownloadError.invalidResponse(0)
            }
            return (data, http)
            }
        }
    }

    deinit { session?.invalidateAndCancel() }

    @MainActor
    func download(reference: LocalHistoryMigrationImageReference,
                  inspection: LocalHistoryMigrationInspection,
                  cloudUserID: String,
                  accessToken: String,
                  isCurrent: () -> Bool = { true }) async throws -> [String: Data] {
        guard let user = UUID(uuidString: cloudUserID), !accessToken.isEmpty else {
            throw LocalHistoryMigrationError.invalidCloudIdentity
        }
        guard inspection.authorizesImage(reference, cloudUserID: user.uuidString) else {
            throw LocalHistoryImageDownloadError.sourceScopeMismatch
        }
        let expectedHash = try inspection.expectedImageHash(for: reference.path)
        if let hash = expectedHash,
           hash.range(of: #"^[0-9a-fA-F]{64}$"#, options: .regularExpression) == nil {
            throw LocalHistoryImageDownloadError.hashMismatch
        }
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }

        let validated = try validatedURL(path: reference.path, user: user)
        var request = URLRequest(url: validated.requestURL)
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        let started = ProcessInfo.processInfo.systemUptime
        var attempt = 0
        var data = Data()
        while true {
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            attempt += 1
            let (body, response) = try await fetch(request)
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            guard response.url == validated.requestURL else {
                throw LocalHistoryImageDownloadError.responseAddressMismatch
            }
            if response.statusCode == 200 { data = body; break }
            let storageCode = Self.storageErrorCode(body)
            // Only transient HTTP responses are retried; auth, missing objects and bad paths fail immediately.
            if [429, 500, 502, 503, 504].contains(response.statusCode), attempt < 3 {
                let suggested = response.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
                let seconds = suggested.flatMap { $0.isFinite && $0 >= 0 ? min($0, 5) : nil }
                    ?? (Double(attempt) * 0.5)
                try await pause(UInt64(seconds * 1_000_000_000))
                continue
            }
            let failure: LocalHistoryImageDownloadError
            switch response.statusCode {
            case 401: failure = .sessionExpired
            case 403: failure = .accessDenied
            case 404:
                failure = validated.isTemporary ? .missingTemporaryImage : .missingImage
            case 400 where storageCode == "NoSuchKey":
                // Supabase Storage wraps the underlying 404 as HTTP 400 for
                // this endpoint. Treat the storage fact as a missing image so
                // migration can preserve the record without its bytes.
                failure = validated.isTemporary ? .missingTemporaryImage : .missingImage
            case 400 where storageCode == "AccessDenied":
                // 对象存在、但当前账户的存储策略不允许读取时，Storage 同样用 400 承载
                // AccessDenied（不是 403，也不是 NoSuchKey）。这是「这一张图读不到」，
                // 不是「迁移不可行」：归类为 accessDenied，由上层跳过该图。
                failure = .accessDenied
            default: failure = .invalidResponse(response.statusCode)
            }
            throw LocalHistoryImageHTTPError(failure: failure, statusCode: response.statusCode,
                storageCode: storageCode, attempts: attempt,
                elapsedMilliseconds: Int((ProcessInfo.processInfo.systemUptime - started) * 1000),
                responseBytes: body.count)
        }
        guard !data.isEmpty else { throw LocalHistoryImageDownloadError.emptyResponse }
        guard data.count <= Self.maximumImageBytes else { throw LocalHistoryImageDownloadError.imageTooLarge }
        if let hash = expectedHash {
            guard LocalImageStore.sha256(data) == hash.lowercased() else {
                throw LocalHistoryImageDownloadError.hashMismatch
            }
        }
        return [reference.path: data]
    }

    private static func storageErrorCode(_ body: Data) -> String? {
        guard body.count <= 16 * 1024,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else { return nil }
        let known: Set<String> = ["NoSuchKey", "NoSuchBucket", "InvalidJWT", "InvalidRequest", "InvalidKey",
            "AccessDenied", "SlowDown", "InternalError", "DatabaseError", "DatabaseTimeout", "TenantNotFound",
            "not_found", "unauthorized", "too many requests", "internal_server_error", "database_timeout"]
        for key in ["code", "error"] {
            if let value = json[key] as? String, known.contains(value) { return value }
        }
        return nil
    }

    private func validatedURL(path: String, user: UUID) throws -> ValidatedStoragePath {
        guard let base = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              base.scheme?.lowercased() == "https", let baseHost = base.host,
              base.user == nil, base.password == nil, base.query == nil, base.fragment == nil,
              base.path.isEmpty || base.path == "/" else {
            throw LocalHistoryImageDownloadError.sourceScopeMismatch
        }

        if let absolute = URLComponents(string: path), absolute.scheme != nil {
            guard absolute.scheme?.lowercased() == "https", let host = absolute.host,
                  host.lowercased() == baseHost.lowercased(), effectivePort(absolute) == effectivePort(base),
                  absolute.user == nil, absolute.password == nil, absolute.fragment == nil else {
                throw LocalHistoryImageDownloadError.sourceScopeMismatch
            }
            let prefixes = [
                "/storage/v1/object/sign/receipt-images/",
                "/storage/v1/object/public/receipt-images/",
                "/storage/v1/object/authenticated/receipt-images/"
            ]
            guard let prefix = prefixes.first(where: {
                absolute.percentEncodedPath.lowercased().hasPrefix($0.lowercased())
            }) else { throw LocalHistoryImageDownloadError.sourceScopeMismatch }
            let encodedObjectPath = String(absolute.percentEncodedPath.dropFirst(prefix.count))
            let objectPath = try decodedObjectPath(encodedObjectPath)
            let isTemporary = try validateObjectPath(objectPath, owner: user.uuidString.lowercased())
            return ValidatedStoragePath(requestURL: try authenticatedURL(objectPath, base: base), isTemporary: isTemporary)
        }

        guard !path.contains("://"), !path.contains("%"), !path.contains("\\"),
              !path.contains("?"), !path.contains("#") else {
            throw LocalHistoryImageDownloadError.unsupportedPathFormat
        }
        let isTemporary = try validateObjectPath(path, owner: user.uuidString.lowercased())
        return ValidatedStoragePath(requestURL: try authenticatedURL(path, base: base), isTemporary: isTemporary)
    }

    private func decodedObjectPath(_ encodedPath: String) throws -> String {
        let encodedParts = encodedPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !encodedParts.isEmpty else { throw LocalHistoryImageDownloadError.unsupportedPathFormat }
        let decodedParts = try encodedParts.map { part -> String in
            guard !part.isEmpty, let decoded = part.removingPercentEncoding,
                  decoded != ".", decoded != "..", !decoded.contains("/"), !decoded.contains("\\"),
                  !decoded.contains("%"), !decoded.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw LocalHistoryImageDownloadError.unsupportedPathFormat
            }
            return decoded
        }
        return decodedParts.joined(separator: "/")
    }

    /// Returns whether the validated object path belongs to the temporary namespace.
    private func validateObjectPath(_ path: String, owner: String) throws -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ part in
            !part.isEmpty && part != "." && part != ".." && !part.contains("%") &&
                !part.contains("\\") && !part.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        }) else { throw LocalHistoryImageDownloadError.unsupportedPathFormat }

        if let first = parts.first, let firstOwner = UUID(uuidString: first) {
            guard firstOwner.uuidString.lowercased() == owner else {
                throw LocalHistoryImageDownloadError.sourceScopeMismatch
            }
            guard parts.count >= 2, parts.dropFirst().allSatisfy(Self.isFilename) else {
                throw LocalHistoryImageDownloadError.unsupportedPathFormat
            }
            return false
        }

        if parts.first == "tmp" {
            if parts.count >= 3, let pathOwner = UUID(uuidString: parts[1]) {
                guard pathOwner.uuidString.lowercased() == owner else {
                    throw LocalHistoryImageDownloadError.sourceScopeMismatch
                }
                guard parts.dropFirst(2).allSatisfy(Self.isFilename) else {
                    throw LocalHistoryImageDownloadError.unsupportedPathFormat
                }
                return true
            }
            guard parts.count == 3, Self.isDate(parts[1]), Self.isFilename(parts[2]) else {
                throw LocalHistoryImageDownloadError.unsupportedPathFormat
            }
            return true
        }

        guard parts.count == 2, Self.isDate(parts[0]), Self.isFilename(parts[1]) else {
            throw LocalHistoryImageDownloadError.unsupportedPathFormat
        }
        return false
    }

    private func authenticatedURL(_ objectPath: String, base: URLComponents) throws -> URL {
        let components = objectPath.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        var encoded: [String] = []
        for component in components {
            guard let segment = component.addingPercentEncoding(withAllowedCharacters: Self.unreservedASCII) else {
                throw LocalHistoryImageDownloadError.unsupportedPathFormat
            }
            encoded.append(segment)
        }
        var request = base
        request.percentEncodedPath = "/storage/v1/object/authenticated/receipt-images/" + encoded.joined(separator: "/")
        request.percentEncodedQuery = nil
        request.fragment = nil
        guard let url = request.url else { throw LocalHistoryImageDownloadError.unsupportedPathFormat }
        return url
    }

    private func effectivePort(_ components: URLComponents) -> Int? {
        components.port ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private static func isDate(_ value: String) -> Bool {
        guard value.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value).map { formatter.string(from: $0) == value } ?? false
    }

    private static func isFilename(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
            !value.contains("/") && !value.contains("\\") && !value.contains("%") &&
            !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
}

private final class HistoryNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
