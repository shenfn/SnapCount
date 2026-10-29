import Foundation
import CryptoKit
import os

struct LocalHistoryMigrationContextError: Error, LocalizedError {
    let table: String
    let field: String?
    let recordID: String
    let underlying: Error

    var errorDescription: String? {
        let fieldText = field.map { ".\($0)" } ?? ""
        return "\(table)\(fieldText) 的历史记录无法安全映射；尚未入账，请查看脱敏诊断。"
    }
}

struct LocalHistoryMigrationPostCommitRefreshError: Error, LocalizedError {
    var errorDescription: String? { "历史数据已提交，但本机列表投影刷新失败。" }
}

enum LocalHistoryMigrationValidationError: Error {
    case accountBalanceMismatch
}

struct LocalWriteRefreshError: Error, LocalizedError {
    var errorDescription: String? { "本机数据已保存，但列表投影刷新失败。" }
}

struct LocalHistoryMigrationDiagnostic: Codable, Equatable, Identifiable {
    let id: String
    let code: String
    var operation: String? = nil
    let phase: String
    let accountHint: String?
    let sourceTable: String?
    let sourceField: String?
    let recordHint: String?
    let attemptID: String
    let buildVersion: String
    let occurredAt: Date
    let underlyingCause: String
    let safeReason: String?
    let progressSummary: String?
    let committed: Bool
    let recoveryAction: String
    var resolution: String? = nil
    var resolvedAt: Date? = nil
    var httpStatus: Int? = nil
    var storageCode: String? = nil
    var requestAttempts: Int? = nil
    var elapsedMilliseconds: Int? = nil
    var responseBytes: Int? = nil

    var userMessage: String {
        let location = sourceTable.map { "（来源表 \($0)\(sourceField.map { ".\($0)" } ?? "")）" } ?? ""
        let record = recordHint.map { "，记录 #\($0)" } ?? ""
        let operation = self.operation ?? "history-migration"
        let subject: String
        switch operation {
        case "cloud-inventory": subject = "云端数据盘点"
        case "local-inventory": subject = "本机数据盘点"
        case "local-sync": subject = "云同步"
        case "local-storage-init": subject = "本机存储"
        case "local-write-refresh": subject = "本机列表刷新"
        default: subject = "历史迁移"
        }
        let failure = operation == "history-migration" ? "在\(phase)暂停"
            : (operation == "local-storage-init" ? "初始化失败" : "失败")
        let impact: String
        switch operation {
        case "history-migration": impact = committed ? "迁移内容已提交（可能含待核对原文），但后续刷新未完成。" : "本次尚未入账。"
        case "local-sync": impact = "本机事实仍保留；云端同步结果可能未完整确认。"
        case "local-storage-init": impact = "本机数据库不可用；未改用空库或云端覆盖。"
        case "local-write-refresh": impact = "数据已保存；当前列表尚未刷新。"
        default: impact = "未修改业务数据。"
        }
        let reason = safeReason.map { " 原因：\($0)" } ?? ""
        return "\(subject)\(failure)\(location)\(record)。\(impact)\(reason) \(recoveryAction) 诊断编号：\(id)。"
    }

    var shareText: String {
        [
            "诊断编号：\(id)", "错误码：\(code)", "阶段：\(phase)",
            "操作：\(operation ?? "history-migration")",
            accountHint.map { "账户脱敏标识：#\($0)" },
            sourceTable.map { "来源表：\($0)" }, sourceField.map { "字段：\($0)" },
            recordHint.map { "脱敏记录：#\($0)" }, "尝试编号：\(attemptID)",
            "构建版本：\(buildVersion)", "时间：\(ISO8601DateFormatter().string(from: occurredAt))",
            "原因类别：\(code)", safeReason.map { "安全原因说明：\($0)" },
            httpStatus.map { "HTTP状态：\($0)" }, storageCode.map { "存储错误类别：\($0)" },
            requestAttempts.map { "请求尝试次数：\($0)" },
            elapsedMilliseconds.map { "本图请求耗时毫秒：\($0)" }, responseBytes.map { "响应字节数：\($0)" },
            "底层原因：\(underlyingCause)", progressSummary.map { "进度：\($0)" }, "操作结果：\(commitSummary)",
            "恢复建议：\(recoveryAction)", resolution.map { "恢复结果：\($0)" },
            resolvedAt.map { "恢复时间：\(ISO8601DateFormatter().string(from: $0))" }
        ].compactMap { $0 }.joined(separator: "\n")
    }

    private var commitSummary: String {
        switch operation ?? "history-migration" {
        case "history-migration": return committed ? "迁移内容已提交，待核对原文不等于正式入账" : "尚未入账"
        case "local-write-refresh": return committed ? "原数据已保存" : "原数据未确认保存"
        case "local-sync": return committed ? "同步完整完成" : "未确认全部完成"
        default: return committed ? "业务数据已修改" : "未修改业务数据"
        }
    }
}

/// Stores only bounded, redacted migration diagnostics on this device.
final class LocalHistoryMigrationDiagnosticStore {
    static let maximumEntries = 50
    static let maximumAge: TimeInterval = 90 * 24 * 60 * 60
    static let maximumFileBytes = 128 * 1024
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.jiezi.app", category: "HistoryMigration")

    private let fileURL: URL
    private let lock = NSLock()

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    convenience init() throws {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("JieziLocalData", isDirectory: true)
        try self.init(fileURL: support.appendingPathComponent("history-migration-diagnostics.json"))
    }

    @discardableResult
    func record(
        _ error: Error,
        phase: String,
        sourceTable: String? = nil,
        sourceField: String? = nil,
        recordID: String? = nil,
        accountID: String? = nil,
        operation: String = "history-migration",
        codeOverride: String? = nil,
        progressSummary: String? = nil,
        attemptID: UUID,
        committed: Bool,
        recoveryAction: String? = nil,
        at now: Date = Date()
    ) -> LocalHistoryMigrationDiagnostic {
        let contextual = error as? LocalHistoryMigrationContextError
        let underlyingError = contextual?.underlying ?? error
        let nsError = underlyingError as NSError
        let mappingContext = Self.mappingContext(for: error)
        let contextualRecordID = contextual.flatMap { $0.recordID.isEmpty ? nil : $0.recordID }
        var entry = LocalHistoryMigrationDiagnostic(
            id: UUID().uuidString.lowercased(),
            code: codeOverride.map { Self.safeText($0, limit: 48) } ?? Self.code(for: underlyingError),
            operation: Self.safeText(operation, limit: 48),
            phase: Self.safeText(phase, limit: 48),
            accountHint: accountID.map(Self.identityHint),
            sourceTable: (sourceTable ?? mappingContext?.table ?? contextual?.table).map { Self.safeText($0, limit: 64) },
            sourceField: (sourceField ?? mappingContext?.field ?? contextual?.field).map { Self.safeText($0, limit: 64) },
            recordHint: (recordID ?? mappingContext?.recordID ?? contextualRecordID).map(Self.recordHint),
            attemptID: attemptID.uuidString.lowercased(),
            buildVersion: Self.buildVersion,
            occurredAt: now,
            underlyingCause: Self.causeChain(nsError),
            safeReason: Self.safeReason(for: underlyingError).map { Self.safeText($0, limit: 120) },
            progressSummary: progressSummary.map { Self.safeText($0, limit: 160) },
            committed: committed,
            recoveryAction: Self.safeText(recoveryAction ?? Self.recovery(for: underlyingError), limit: 120)
        )
        if let http = underlyingError as? LocalHistoryImageHTTPError {
            entry.httpStatus = http.statusCode
            entry.storageCode = http.storageCode
            entry.requestAttempts = http.attempts
            entry.elapsedMilliseconds = http.elapsedMilliseconds
            entry.responseBytes = http.responseBytes
        } else if let imageError = underlyingError as? LocalHistoryImageDownloadError,
                  case .invalidResponse(let status) = imageError, status > 0 {
            entry.httpStatus = status
        }

        lock.lock()
        defer { lock.unlock() }
        do {
            var entries = try load(at: now)
            entries.append(entry)
            entries = Array(entries.suffix(Self.maximumEntries))
            try save(entries)
        } catch {
            Self.logger.error("diagnostic_write_failed id=\(entry.id, privacy: .public) code=\(entry.code, privacy: .public)")
        }
        Self.logger.error("local_diagnostic_recorded id=\(entry.id, privacy: .public) code=\(entry.code, privacy: .public) phase=\(entry.phase, privacy: .public)")
        return entry
    }

    func recent() throws -> [LocalHistoryMigrationDiagnostic] {
        lock.lock()
        defer { lock.unlock() }
        let entries = try load(at: Date())
        try save(entries)
        return entries
    }

    func resolve(_ diagnosticID: String, outcome: String, expectedAccountID: String? = nil, at now: Date = Date()) throws {
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(at: now)
        guard let index = entries.lastIndex(where: { $0.id == diagnosticID }) else { return }
        if let expectedAccountID,
           entries[index].accountHint != Self.identityHint(expectedAccountID) { return }
        entries[index].resolution = Self.safeText(outcome, limit: 120)
        entries[index].resolvedAt = now
        try save(entries)
    }

    @discardableResult
    func resolveLatest(operation: String, outcome: String, expectedAccountID: String?, at now: Date = Date()) throws -> LocalHistoryMigrationDiagnostic? {
        lock.lock()
        defer { lock.unlock() }
        var entries = try load(at: now)
        let accountHint = expectedAccountID.map(Self.identityHint)
        guard let index = entries.lastIndex(where: {
            $0.operation == operation && $0.accountHint == accountHint && $0.resolution == nil
        }) else {
            try save(entries)
            return nil
        }
        entries[index].resolution = Self.safeText(outcome, limit: 120)
        entries[index].resolvedAt = now
        try save(entries)
        return entries[index]
    }

    private func load(at now: Date) throws -> [LocalHistoryMigrationDiagnostic] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        guard let size = (attributes[.size] as? NSNumber)?.intValue, size <= Self.maximumFileBytes else {
            throw CocoaError(.fileReadTooLarge)
        }
        let data = try Data(contentsOf: fileURL)
        let cutoff = now.addingTimeInterval(-Self.maximumAge)
        return try JSONDecoder().decode([LocalHistoryMigrationDiagnostic].self, from: data)
            .filter { $0.occurredAt >= cutoff }
    }

    private func save(_ entries: [LocalHistoryMigrationDiagnostic]) throws {
        var retained = Array(entries.suffix(Self.maximumEntries))
        var data = try JSONEncoder().encode(retained)
        while data.count > Self.maximumFileBytes, retained.count > 1 {
            retained.removeFirst()
            data = try JSONEncoder().encode(retained)
        }
        guard data.count <= Self.maximumFileBytes else { throw CocoaError(.fileWriteOutOfSpace) }
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: fileURL.path
        )
    }

    private static var buildVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return safeText("\(version)(\(build))", limit: 32)
    }

    private static func code(for error: Error) -> String {
        if let http = error as? LocalHistoryImageHTTPError { return code(for: http.failure) }
        if (error as NSError).domain == NSURLErrorDomain { return "NETWORK-REQUEST-FAILED" }
        if let error = error as? LocalHistoryMigrationValidationError,
           case .accountBalanceMismatch = error { return "HIST-ACCOUNT-BALANCE-MISMATCH" }
        if let error = error as? LocalSyncError {
            switch error {
            case .syncNotAuthorized, .bindingMismatch: return "SYNC-NOT-AUTHORIZED"
            case .partialFailure: return "SYNC-PARTIAL-FAILURE"
            case .cursorExpired: return "SYNC-CURSOR-EXPIRED"
            case .remoteConflict: return "SYNC-CONFLICT"
            case .invalidResponse: return "SYNC-INVALID-RESPONSE"
            case .invalidWorkspace, .staleAttempt: return "SYNC-STATE-INVALID"
            }
        }
        if let error = error as? LocalHistoryImageDownloadError {
            switch error {
            case .unsupportedPathFormat: return "HIST-IMAGE-PATH-UNSUPPORTED"
            case .sourceScopeMismatch: return "HIST-IMAGE-SCOPE-MISMATCH"
            case .sessionExpired: return "HIST-IMAGE-401"
            case .accessDenied: return "HIST-IMAGE-403"
            case .missingImage: return "HIST-IMAGE-404"
            case .missingTemporaryImage: return "HIST-TEMP-IMAGE-404"
            case .invalidResponse: return "HIST-IMAGE-HTTP"
            case .emptyResponse: return "HIST-IMAGE-EMPTY"
            case .imageTooLarge: return "HIST-IMAGE-SINGLE-TOO-LARGE"
            case .totalSizeExceeded: return "HIST-IMAGE-TOTAL-TOO-LARGE"
            case .responseAddressMismatch: return "HIST-IMAGE-RESPONSE-ADDRESS"
            case .hashMismatch: return "HIST-IMAGE-HASH"
            }
        }
        if let error = error as? LocalHistoryMappingError {
            switch error {
            case .sourceFieldMissing: return "HIST-SOURCE-FIELD-MISSING"
            case .sourceFieldInvalid: return "HIST-SOURCE-FIELD-INVALID"
            case .unsupported: return "HIST-MAP-UNSUPPORTED"
            case .rows: return "HIST-MAP-ROWS"
            }
        }
        if let error = error as? LocalCompleteBackupError,
           case .invalidImage(_) = error { return "HIST-IMAGE-HASH" }
        if error is LocalHistoryMigrationPostCommitRefreshError { return "HIST-POST-COMMIT-REFRESH" }
        if error is LocalWriteRefreshError { return "LOCAL-POST-COMMIT-REFRESH" }
        if let error = error as? LocalHistoryMigrationError {
            switch error {
            case .invalidWorkspace: return "HIST-WORKSPACE-INVALID"
            case .invalidCloudIdentity: return "HIST-IDENTITY-INVALID"
            case .invalidCursorScope, .invalidExpectedScopes, .expectedScopesChanged: return "HIST-SCOPE-INVALID"
            case .incompleteScopes: return "HIST-SOURCE-INCOMPLETE"
            case .identityMismatch: return "HIST-IDENTITY-MISMATCH"
            case .alreadyCompleted: return "HIST-ALREADY-COMPLETED"
            case .staleAttempt: return "HIST-ATTEMPT-STALE"
            }
        }
        if error is CancellationError { return "HIST-CANCELLED" }
        if error is LocalDataError { return "HIST-LOCAL-DATA" }
        if error is LocalCompleteBackupError { return "HIST-ARCHIVE" }
        return "HIST-UNKNOWN"
    }

    private static func mappingContext(for error: Error) -> (table: String, field: String, recordID: String)? {
        guard let error = error as? LocalHistoryMappingError else { return nil }
        switch error {
        case .sourceFieldMissing(let table, let field, let recordID),
             .sourceFieldInvalid(let table, let field, let recordID):
            return (table, field, recordID)
        case .unsupported:
            return nil
        case .rows:
            return nil
        }
    }

    private static func recovery(for error: Error) -> String {
        if let http = error as? LocalHistoryImageHTTPError {
            if http.statusCode == 400, http.storageCode == "NoSuchKey" {
                return "云端原图不存在；本图会跳过，仍可导入可映射的结构化记录。未删除源数据，不反复重试无效请求。"
            }
            if http.statusCode == 400 {
                return "服务器拒绝图片读取请求；请按HTTP状态和存储错误类别核对。未入账，缓存保留，不反复重试无效请求。"
            }
            if [429, 500, 502, 503, 504].contains(http.statusCode) {
                return "临时服务错误已达到有限重试次数；稍后继续迁移，已缓存内容保留。"
            }
            return recovery(for: http.failure)
        }
        if (error as NSError).domain == NSURLErrorDomain { return "请检查网络后重试；已缓存的源页和图片会保留。" }
        if let error = error as? LocalHistoryMigrationValidationError,
           case .accountBalanceMismatch = error {
            return "请核对账户期初余额与有效流水；核对一致前不会入账。"
        }
        switch error as? LocalHistoryImageDownloadError {
        case .unsupportedPathFormat: return "请核对历史图片字段格式；原图和源记录仍保留，确认路径受支持后可重试。"
        case .sourceScopeMismatch: return "该图片不属于当前账户已读取的迁移记录或项目存储范围；请核对源记录，不要跳过。"
        case .sessionExpired: return "请重新登录后重试。"
        case .accessDenied: return "请核对当前登录账户对该原图的访问权限。"
        case .missingImage: return "云端原图不可读取；本图会跳过，仍可导入可映射的结构化记录，不删除源数据。"
        case .missingTemporaryImage: return "临时原图不可读取；本图会跳过，仍可导入可映射的结构化记录，不删除源数据。"
        case .invalidResponse: return "请检查网络和图片服务后重试；本次不会入账。"
        case .emptyResponse: return "图片服务返回空内容；本图会跳过，仍可导入可映射的结构化记录。"
        case .imageTooLarge: return "该图片超过单图迁移上限；请核对图片来源与大小后再继续。"
        case .totalSizeExceeded: return "图片总量超过本机迁移上限；请释放本机空间或分批评估迁移范围。"
        case .responseAddressMismatch: return "图片服务返回了不同地址；请检查服务端存储响应，不会跟随该地址。"
        case .hashMismatch: return "图片内容与源记录哈希不一致；请核对云端对象和源哈希后重试。"
        case nil: break
        }
        if error is LocalHistoryMappingError { return "请查看问题记录；无法等价恢复的数据需要先核对来源。" }
        if error is LocalHistoryMigrationPostCommitRefreshError { return "只重试读取本机列表；不要重新提交迁移。" }
        if error is LocalWriteRefreshError { return "只重试读取本机列表；不要重复执行原保存操作。" }
        if error is LocalSyncError { return "本机事实保留；核对同步状态后可重试当前支持范围。" }
        if error is CancellationError { return "可以从已缓存页和图片继续预检。" }
        return "请查看脱敏诊断并按错误阶段处理；不要丢弃无法恢复的数据后重试。"
    }

    private static func safeReason(for error: Error) -> String? {
        if let http = error as? LocalHistoryImageHTTPError {
            return "HTTP \(http.statusCode)，存储类别 \(http.storageCode ?? "Unknown")；\(safeReason(for: http.failure) ?? "图片请求失败")"
        }
        if (error as NSError).domain == NSURLErrorDomain { return "网络请求未完成，源数据尚未全部核对。" }
        if let error = error as? LocalHistoryMigrationValidationError,
           case .accountBalanceMismatch = error {
            return "账户当前余额与有效账户流水合计不一致，系统已阻止迁移入账。"
        }
        if let error = error as? LocalHistoryMappingError {
            switch error {
            case .sourceFieldMissing(_, let field, _):
                return field == "occurred_at"
                    ? "历史记录缺少可确认的发生时间，未使用创建时间替代。"
                    : "历史记录缺少必需字段，无法安全映射。"
            case .sourceFieldInvalid:
                return "历史记录中的必需字段格式无法识别，无法安全映射。"
            case .unsupported:
                return "历史记录字段或状态不符合当前兼容规则，无法无损迁移。"
            case .rows(let issues):
                return "本次预检发现 \(issues.count) 项无法等价转换的历史记录，全部未入账。"
            }
        }
        if let error = error as? LocalHistoryImageDownloadError {
            switch error {
            case .unsupportedPathFormat: return "历史图片路径不符合当前受支持格式，未按目录外观推断其归属。"
            case .sourceScopeMismatch: return "图片引用未通过当前账户、inspection源记录或项目对象路径范围校验。"
            case .sessionExpired: return "图片读取会话已失效，需要重新登录。"
            case .accessDenied: return "当前账户无权读取该图片。"
            case .missingTemporaryImage: return "同账户临时图片当前不可读取，具体是已清理还是路径失效尚未确认。"
            case .missingImage: return "历史图片当前不可读取，来源状态尚未确认。"
            case .invalidResponse(let status):
                return status > 0 ? "图片服务返回HTTP \(status)，未取得可用原图。" : "图片服务未返回HTTP响应。"
            case .emptyResponse: return "图片服务返回空内容，未把空响应当作原图。"
            case .imageTooLarge: return "单张历史图片超过本机迁移上限。"
            case .totalSizeExceeded: return "历史图片合计超过本机迁移上限。"
            case .responseAddressMismatch: return "图片响应地址与当前账户的 authenticated 请求地址不一致。"
            case .hashMismatch: return "历史图片内容与源记录哈希不一致。"
            }
        }
        if let error = error as? LocalDataError {
            switch error {
            case .invalidAmount: return "金额不是可安全表示的数值。"
            case .invalidIdentifier: return "记录标识无效，无法安全关联。"
            case .invalidRecord: return "历史记录结构或字段格式不符合预期。"
            case .invalidAccountKind: return "账户类型不受当前迁移规则支持。"
            case .accountRequired: return "记录缺少必需账户关联。"
            case .recordNotFound: return "所需的关联记录不存在。"
            case .versionConflict: return "数据版本与预期不一致。"
            }
        }
        if let error = error as? LocalHistoryMigrationError {
            switch error {
            case .identityMismatch: return "迁移缓存属于另一个云账户。"
            case .incompleteScopes: return "云端源数据分页尚未全部读取。"
            case .staleAttempt: return "当前迁移尝试已失效。"
            case .alreadyCompleted: return "此本机工作区已完成该账户的历史迁移。"
            case .invalidWorkspace: return "迁移工作区与当前本机工作区不匹配。"
            case .invalidCloudIdentity: return "云账户或会话无法确认。"
            case .invalidCursorScope, .invalidExpectedScopes, .expectedScopesChanged:
                return "迁移范围或分页状态不一致。"
            }
        }
        if error is LocalHistoryMigrationPostCommitRefreshError { return "迁移内容已保存（可能包含待核对原文），但本机列表尚未刷新。" }
        if error is LocalWriteRefreshError { return "原数据已保存，但本机列表尚未刷新。" }
        if error is CancellationError { return "操作已取消，未将取消视为数据失败。" }
        if let error = error as? LocalCompleteBackupError {
            switch error {
            case .invalidImage: return "历史图片完整性校验未通过。"
            case .missingImage: return "完整恢复所需的图片内容缺失。"
            case .conflictingStableID: return "本机已有同标识但内容不同的记录。"
            case .duplicateID: return "迁移数据中存在重复稳定标识。"
            case .invalidFormat, .unsupportedSchemaVersion, .archiveTooLarge, .invalidRows, .invalidRowIssues:
                return "迁移归档格式、规模或记录关系不符合当前恢复规则。"
            }
        }
        if error is LocalSyncError { return "云同步未能完整确认；本机事实仍保留。" }
        return "当前错误类型尚无更具体的安全说明，请提供脱敏诊断编号继续定位。"
    }

    private static func causeChain(_ error: NSError) -> String {
        var parts: [String] = []
        var current: NSError? = error
        var depth = 0
        while let value = current, depth < 4 {
            parts.append("domain-#\(identityHint(value.domain))#\(value.code)")
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
            depth += 1
        }
        return parts.joined(separator: " <- ")
    }

    private static func recordHint(_ recordID: String) -> String {
        identityHint(recordID)
    }

    static func identityHint(_ value: String) -> String {
        String(SHA256.hash(data: Data(value.lowercased().utf8)).map { String(format: "%02x", $0) }.joined().prefix(10))
    }

    private static func safeText(_ value: String, limit: Int) -> String {
        let filtered = value.unicodeScalars.filter { CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._-/()#")).contains($0) }
        return String(String.UnicodeScalarView(filtered).prefix(limit))
    }
}
