import Foundation

private enum NativeContractTimestamp {
    static func isValid(_ rawValue: String?) -> Bool {
        guard let value = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return false }

        let standard = ISO8601DateFormatter()
        if standard.date(from: value) != nil { return true }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) != nil
    }
}

protocol SettingsRepositoryProtocol {
    func fetch(userId: String, accessToken: String) async throws -> NativeUserSettings
    func fetchAccountConsentStatus(accessToken: String) async throws -> NativeAccountConsentStatus
    func acceptCurrentAccountConsent(accessToken: String) async throws -> NativeAccountConsentStatus
    func update(userId: String, values: [String: AnyCodable], accessToken: String) async throws
    func export(_ request: NativeDataExportRequest, accessToken: String) async throws -> NativeExportedFile
    func cleanupSourceImages(accessToken: String) async throws -> NativeImageCleanupResult
    func deleteAccount(accessToken: String) async throws -> NativeAccountDeletionResult
    func fetchAccountDeletionStatus(accessToken: String) async throws -> NativeAccountDeletionResult
}

final class SettingsRepository: SettingsRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) {
        self.remoteClient = remoteClient
    }

    func fetch(userId: String, accessToken: String) async throws -> NativeUserSettings {
        let rows = try await remoteClient.get(
            [SettingsRow].self,
            path: "rest/v1/user_configs",
            queryItems: [
                URLQueryItem(name: "select", value: "plan,screenshot_vision_primary,photo_vision_primary,qwen_screenshot_model,qwen_photo_model,qwen_screenshot_enable_thinking,qwen_photo_enable_thinking,ai_insight_provider,companion_enabled,companion_memory_enabled,companion_persona,companion_memory_strength,companion_expression_style,companion_custom_note,ai_logs_enabled,prompt_optimization_enabled,expression_improvement_enabled,keep_source_images,image_retention_days"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        guard let row = rows.first else { return NativeUserSettings() }
        return row.settings
    }

    func fetchAccountConsentStatus(accessToken: String) async throws -> NativeAccountConsentStatus {
        try await remoteClient.rpc(
            NativeAccountConsentStatus.self,
            name: "get_my_consent_status",
            body: [:],
            accessToken: accessToken
        )
    }

    func acceptCurrentAccountConsent(accessToken: String) async throws -> NativeAccountConsentStatus {
        let consent = NativeRegistrationConsent.current()
        return try await remoteClient.rpc(
            NativeAccountConsentStatus.self,
            name: "accept_my_consent",
            body: [
                "p_terms_version": AnyCodable(consent.termsVersion),
                "p_privacy_version": AnyCodable(consent.privacyVersion),
                "p_sensitive_data_version": AnyCodable(consent.sensitiveDataVersion)
            ],
            accessToken: accessToken
        )
    }

    func update(userId: String, values: [String: AnyCodable], accessToken: String) async throws {
        var body = values
        body["updated_at"] = AnyCodable(ISO8601DateFormatter().string(from: Date()))
        try await remoteClient.patch(
            path: "rest/v1/user_configs",
            queryItems: [URLQueryItem(name: "user_id", value: "eq.\(userId)")],
            body: body,
            accessToken: accessToken
        )
    }

    func cleanupSourceImages(accessToken: String) async throws -> NativeImageCleanupResult {
        try await remoteClient.postFunction(
            NativeImageCleanupResult.self,
            path: "functions/v1/ingest-receipt",
            body: ["action": AnyCodable("cleanup_all_images")],
            accessToken: accessToken
        )
    }

    func deleteAccount(accessToken: String) async throws -> NativeAccountDeletionResult {
        try await remoteClient.postFunction(
            NativeAccountDeletionResult.self,
            path: "functions/v1/ingest-receipt",
            body: ["action": AnyCodable("delete_account")],
            accessToken: accessToken
        )
    }

    func fetchAccountDeletionStatus(accessToken: String) async throws -> NativeAccountDeletionResult {
        try await remoteClient.postFunction(
            NativeAccountDeletionResult.self,
            path: "functions/v1/ingest-receipt",
            body: ["action": AnyCodable("get_account_deletion_status")],
            accessToken: accessToken
        )
    }

    func export(_ request: NativeDataExportRequest, accessToken: String) async throws -> NativeExportedFile {
        let range = Self.dateRange(request.range)
        let payload: Any
        switch request.content {
        case .expense:
            payload = try await expenseRows(range: range, accessToken: accessToken)
        case .income:
            payload = try await incomeRows(range: range, accessToken: accessToken)
        case .allFinance:
            payload = [
                "expenses": try await expenseRows(range: range, accessToken: accessToken),
                "incomes": try await incomeRows(range: range, accessToken: accessToken)
            ]
        case .universal:
            payload = try await universalRows(range: range, accessToken: accessToken)
        }

        let data: Data
        if request.format == .json {
            data = try JSONSerialization.data(withJSONObject: Self.jsonObject(payload), options: [.prettyPrinted, .sortedKeys])
        } else {
            data = Data(Self.csv(payload: payload, request: request).utf8)
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let filename = "jiezi_\(request.content.rawValue)_\(formatter.string(from: Date())).\(request.format.rawValue)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return NativeExportedFile(url: url)
    }

    private func expenseRows(range: (String, String), accessToken: String) async throws -> [[String: AnyCodable]] {
        try await rows(
            path: "rest/v1/transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "transaction_date,transaction_time,amount,merchant_name,category,platform,payment_method,note"),
                URLQueryItem(name: "type", value: "eq.expense"),
                URLQueryItem(name: "status", value: "eq.done"),
                URLQueryItem(name: "transaction_date", value: "gte.\(range.0)"),
                URLQueryItem(name: "transaction_date", value: "lte.\(range.1)"),
                URLQueryItem(name: "order", value: "transaction_date.desc")
            ],
            accessToken: accessToken
        )
    }

    private func incomeRows(range: (String, String), accessToken: String) async throws -> [[String: AnyCodable]] {
        try await rows(
            path: "rest/v1/income_records",
            queryItems: [
                URLQueryItem(name: "select", value: "income_date,amount,category,source_name,note"),
                URLQueryItem(name: "income_date", value: "gte.\(range.0)"),
                URLQueryItem(name: "income_date", value: "lte.\(range.1)"),
                URLQueryItem(name: "order", value: "income_date.desc")
            ],
            accessToken: accessToken
        )
    }

    private func universalRows(range: (String, String), accessToken: String) async throws -> [[String: AnyCodable]] {
        try await rows(
            path: "rest/v1/data_records",
            queryItems: [
                URLQueryItem(name: "select", value: "occurred_at,domain_key,title,summary,payload_jsonb"),
                URLQueryItem(name: "occurred_at", value: "gte.\(range.0)T00:00:00"),
                URLQueryItem(name: "occurred_at", value: "lte.\(range.1)T23:59:59"),
                URLQueryItem(name: "order", value: "occurred_at.desc")
            ],
            accessToken: accessToken
        )
    }

    private func rows(path: String, queryItems: [URLQueryItem], accessToken: String) async throws -> [[String: AnyCodable]] {
        let pageSize = 1000
        var offset = 0
        var allRows: [[String: AnyCodable]] = []
        while true {
            let page = try await remoteClient.get(
                [[String: AnyCodable]].self,
                path: path,
                queryItems: queryItems + [
                    URLQueryItem(name: "limit", value: "\(pageSize)"),
                    URLQueryItem(name: "offset", value: "\(offset)")
                ],
                accessToken: accessToken
            )
            allRows.append(contentsOf: page)
            guard page.count == pageSize else { break }
            offset += pageSize
        }
        return allRows
    }

    private static func dateRange(_ range: NativeExportRange) -> (String, String) {
        let calendar = Calendar.current
        let now = Date()
        let currentStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let start: Date
        switch range {
        case .thisMonth: start = currentStart
        case .lastMonth: start = calendar.date(byAdding: .month, value: -1, to: currentStart) ?? currentStart
        case .lastThreeMonths: start = calendar.date(byAdding: .month, value: -2, to: currentStart) ?? currentStart
        case .all: start = calendar.date(from: DateComponents(year: 2020, month: 1, day: 1)) ?? currentStart
        }
        let endBase = range == .lastMonth ? currentStart : calendar.date(byAdding: .month, value: 1, to: currentStart) ?? now
        let end = calendar.date(byAdding: .day, value: -1, to: endBase) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return (formatter.string(from: start), formatter.string(from: end))
    }

    private static func csv(payload: Any, request: NativeDataExportRequest) -> String {
        let rows: [[String: AnyCodable]]
        let columns: [(String, String)]
        switch request.content {
        case .expense:
            rows = payload as? [[String: AnyCodable]] ?? []
            columns = [("transaction_date", "日期"), ("transaction_time", "时间"), ("amount", "金额"), ("merchant_name", "商家"), ("category", "分类"), ("platform", "平台"), ("payment_method", "支付方式"), ("note", "备注")]
        case .income:
            rows = payload as? [[String: AnyCodable]] ?? []
            columns = [("income_date", "日期"), ("amount", "金额"), ("category", "分类"), ("source_name", "来源"), ("note", "备注")]
        case .allFinance:
            let values = payload as? [String: [[String: AnyCodable]]] ?? [:]
            rows = (values["expenses"] ?? []).map { ["record_type": AnyCodable("expense")].merging($0) { _, value in value } }
                + (values["incomes"] ?? []).map { ["record_type": AnyCodable("income")].merging($0) { _, value in value } }
            columns = [("record_type", "类型"), ("transaction_date", "支出日期"), ("income_date", "收入日期"), ("amount", "金额"), ("merchant_name", "商家"), ("source_name", "来源"), ("category", "分类"), ("note", "备注")]
        case .universal:
            let universalRows = payload as? [[String: AnyCodable]] ?? []
            rows = request.includeFullPayload ? universalRows : universalRows.map { row in
                row.merging(["detail": AnyCodable(universalDetail(row))]) { _, value in value }
            }
            columns = [("occurred_at", "时间"), ("domain_key", "数据域"), ("title", "标题"), ("summary", "摘要"), (request.includeFullPayload ? "payload_jsonb" : "detail", request.includeFullPayload ? "完整数据" : "关键数据")]
        }
        let header = columns.map(\.1).joined(separator: ",")
        let body = rows.map { row in
            columns.map { key, _ in csvCell(row[key]?.value) }.joined(separator: ",")
        }.joined(separator: "\n")
        return "\u{FEFF}\(header)\n\(body)"
    }

    private static func universalDetail(_ row: [String: AnyCodable]) -> String {
        let payload = row.dictionary("payload_jsonb") ?? [:]
        switch row.string("domain_key") {
        case "food":
            let dishes = (payload.array("dishes") ?? []).compactMap { item -> String? in
                (item as? [String: Any])?["name"] as? String
            }.joined(separator: "+")
            let meal = mealTitle(payload.string("meal_type"))
            return [meal, dishes, numberText(payload.double("total_calorie_kcal"), suffix: "千卡")].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "·")
        case "sleep":
            return [
                numberText(payload.double("sleep_hours"), suffix: "h"),
                payload.double("quality_score").map { "评分\(String(format: "%.0f", $0))" },
                payload.string("quality_level")
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "·")
        case "sport":
            return [
                payload.string("sport_type"),
                numberText(payload.double("duration_minutes"), suffix: "分钟"),
                numberText(payload.double("distance_km"), suffix: "km"),
                numberText(payload.double("calories"), suffix: "千卡")
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "·")
        case "reading":
            return [
                payload.string("book_name"),
                numberText(payload.double("reading_minutes"), suffix: "分钟"),
                numberText(payload.double("pages"), suffix: "页")
            ].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "·")
        default:
            return payload
                .filter { !($0.value.value is [Any]) && !($0.value.value is [String: Any]) && !($0.value.value is NSNull) }
                .map { "\($0.key):\($0.value.displayValue)" }
                .sorted()
                .joined(separator: "·")
        }
    }

    private static func mealTitle(_ value: String?) -> String? {
        switch value {
        case "breakfast": return "早餐"
        case "lunch": return "午餐"
        case "dinner": return "晚餐"
        default: return value
        }
    }

    private static func numberText(_ value: Double?, suffix: String) -> String? {
        guard let value else { return nil }
        let formatted = value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formatted)\(suffix)"
    }

    private static func csvCell(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        let string: String
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let json = String(data: data, encoding: .utf8) {
            string = json
        } else {
            string = String(describing: value)
        }
        let escaped = string.replacingOccurrences(of: "\"", with: "\"\"")
        return escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") ? "\"\(escaped)\"" : escaped
    }

    private static func jsonObject(_ value: Any) -> Any {
        if let rows = value as? [[String: AnyCodable]] {
            return rows.map { $0.mapValues(\.value) }
        }
        if let groups = value as? [String: [[String: AnyCodable]]] {
            return groups.mapValues { $0.map { $0.mapValues(\.value) } }
        }
        return value
    }
}

struct NativeImageCleanupResult: Decodable, Equatable {
    let status: String
    let deleted: Int
    let queued: Int
    let failed: Int
    let deadLetter: Int
    let remaining: Int
    let skippedExternal: Int
    let total: Int

    var isComplete: Bool {
        status == "ok" && failed == 0 && deadLetter == 0 && remaining == 0
    }

    var displayMessage: String {
        if total == 0 {
            return "没有需要清理的云端原图"
        }

        var details: [String] = []
        if deleted > 0 { details.append("已删除 \(deleted) 张云端原图") }
        if skippedExternal > 0 { details.append("跳过 \(skippedExternal) 个外部链接") }
        if remaining > 0 { details.append("剩余 \(remaining) 张将在后台重试") }
        if deadLetter > 0 { details.append("其中 \(deadLetter) 张需要稍后重新处理") }

        if details.isEmpty {
            return isComplete ? "云端原图清理完成" : "原图清理已提交后台处理"
        }
        return details.joined(separator: "，")
    }

    private enum CodingKeys: String, CodingKey {
        case status, deleted, queued, failed, remaining, total
        case deadLetter = "dead_letter"
        case skippedExternal = "skipped_external"
    }
}

struct NativeAccountDeletionResult: Codable, Equatable {
    let status: String
    let message: String?
    let cleanup: NativeAccountDeletionCleanupResult?
    let deletionStatus: String?
    let requestId: String?
    let requestedAt: String?
    let completedAt: String?
    let estimatedCompletionAt: String?
    let supportReference: String?
    let retryable: Bool?

    init(
        status: String,
        message: String?,
        cleanup: NativeAccountDeletionCleanupResult?,
        deletionStatus: String? = nil,
        requestId: String? = nil,
        requestedAt: String? = nil,
        completedAt: String? = nil,
        estimatedCompletionAt: String? = nil,
        supportReference: String? = nil,
        retryable: Bool? = nil
    ) {
        self.status = status
        self.message = message
        self.cleanup = cleanup
        self.deletionStatus = deletionStatus
        self.requestId = requestId
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.estimatedCompletionAt = estimatedCompletionAt
        self.supportReference = supportReference
        self.retryable = retryable
    }

    var isPending: Bool {
        status == "deletion_pending"
            || ["requested", "cleaning", "deleting", "failed"].contains(deletionStatus ?? "")
    }

    var isCompleted: Bool {
        status == "deleted" || deletionStatus == "completed"
    }

    var hasDeletionRequest: Bool {
        guard let requestId,
              UUID(uuidString: requestId) != nil,
              hasValidSupportReference,
              NativeContractTimestamp.isValid(requestedAt),
              NativeContractTimestamp.isValid(estimatedCompletionAt) else { return false }

        switch deletionStatus {
        case "requested", "cleaning", "deleting", "failed":
            return status == "deletion_pending"
                && retryable == true
                && completedAt == nil
        case "completed":
            return status == "deleted"
                && retryable == false
                && NativeContractTimestamp.isValid(completedAt)
        default:
            return false
        }
    }

    private var hasValidSupportReference: Bool {
        guard let supportReference,
              supportReference.hasPrefix("DEL-"),
              supportReference.count == 16,
              supportReference == supportReference.uppercased() else { return false }
        let allowed = CharacterSet(charactersIn: "0123456789ABCDEF")
        return supportReference.dropFirst(4).unicodeScalars.allSatisfy(allowed.contains)
    }

    var displayMessage: String {
        var details: [String] = []
        if let message, !message.isEmpty {
            details.append(message.trimmingCharacters(in: CharacterSet(charactersIn: "。")))
        } else if let cleanup {
            if isPending {
                details.append("账户删除已提交；已删除 \(cleanup.processed) 张云端原图，剩余 \(cleanup.remaining) 张将在后台清理，完成后自动删除账户")
            } else {
                details.append("账户及其云端数据已删除；已删除 \(cleanup.processed) 张云端原图，跳过 \(cleanup.skippedExternal) 个外部链接")
            }
        } else {
            details.append(isPending
                ? "账户删除已提交，云端原图清理完成后会自动删除全部数据"
                : "账户及其云端数据已删除")
        }

        if isPending, deletionStatus != "failed" {
            details.append("后台异步处理，通常在提交后 24 小时内完成")
        }
        if let supportReference, !supportReference.isEmpty {
            details.append("支持编号：\(supportReference)")
        }
        return details.joined(separator: "。") + "。"
    }

    private enum CodingKeys: String, CodingKey {
        case status, message, cleanup, retryable
        case deletionStatus = "deletion_status"
        case requestId = "request_id"
        case requestedAt = "requested_at"
        case completedAt = "completed_at"
        case estimatedCompletionAt = "estimated_completion_at"
        case supportReference = "support_reference"
    }
}

struct NativeAccountDeletionCleanupResult: Codable, Equatable {
    let total: Int
    let queued: Int
    let processed: Int
    let failed: Int
    let deadLetter: Int
    let skippedExternal: Int
    let remaining: Int

    private enum CodingKeys: String, CodingKey {
        case total, queued, processed, failed, remaining
        case deadLetter = "dead_letter"
        case skippedExternal = "skipped_external"
    }
}

protocol NativeAccountDeletionReceiptStoreProtocol {
    func load() -> NativeAccountDeletionResult?
    func save(_ receipt: NativeAccountDeletionResult) throws
    func clear()
}

enum NativeAccountDeletionReceiptStoreError: LocalizedError {
    case invalidReceipt
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .invalidReceipt:
            return "删除请求回执不完整"
        case .verificationFailed:
            return "删除请求回执未能保存到本机"
        }
    }
}

struct NativeAccountDeletionReceiptStore: NativeAccountDeletionReceiptStoreProtocol {
    static let defaultKey = "account_deletion_receipt_v1"

    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    func load() -> NativeAccountDeletionResult? {
        guard let data = defaults.data(forKey: key) else { return nil }
        guard let receipt = try? JSONDecoder().decode(NativeAccountDeletionResult.self, from: data),
              receipt.hasDeletionRequest else { return nil }
        return receipt
    }

    func save(_ receipt: NativeAccountDeletionResult) throws {
        guard receipt.hasDeletionRequest else {
            throw NativeAccountDeletionReceiptStoreError.invalidReceipt
        }
        defaults.set(try JSONEncoder().encode(receipt), forKey: key)
        guard load() == receipt else {
            throw NativeAccountDeletionReceiptStoreError.verificationFailed
        }
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

struct NativeAccountConsentStatus: Decodable, Equatable {
    let isActive: Bool
    let needsConsent: Bool
    let missing: [String]
    let requiredVersions: [String: String]
    let acceptedVersions: [String: String?]
    let legalConsentAt: String?
    let sensitiveDataConsentAt: String?

    init(
        isActive: Bool,
        needsConsent: Bool,
        missing: [String],
        requiredVersions: [String: String],
        acceptedVersions: [String: String?],
        legalConsentAt: String? = nil,
        sensitiveDataConsentAt: String? = nil
    ) {
        self.isActive = isActive
        self.needsConsent = needsConsent
        self.missing = missing
        self.requiredVersions = requiredVersions
        self.acceptedVersions = acceptedVersions
        self.legalConsentAt = legalConsentAt
        self.sensitiveDataConsentAt = sensitiveDataConsentAt
    }

    var isCurrent: Bool {
        guard isActive,
              !needsConsent,
              missing.isEmpty,
              NativeContractTimestamp.isValid(legalConsentAt),
              NativeContractTimestamp.isValid(sensitiveDataConsentAt) else { return false }

        return ["terms", "privacy", "sensitive_data"].allSatisfy { key in
            guard let required = requiredVersions[key], !required.isEmpty else { return false }
            return (acceptedVersions[key] ?? nil) == required
        }
    }

    enum CodingKeys: String, CodingKey {
        case isActive = "is_active"
        case needsConsent = "needs_consent"
        case missing
        case requiredVersions = "required_versions"
        case acceptedVersions = "accepted_versions"
        case legalConsentAt = "legal_consent_at"
        case sensitiveDataConsentAt = "sensitive_data_consent_at"
    }
}

private struct SettingsRow: Decodable {
    let plan: String?
    let screenshotVisionPrimary: String?
    let photoVisionPrimary: String?
    let qwenScreenshotModel: String?
    let qwenPhotoModel: String?
    let qwenScreenshotThinking: Bool?
    let qwenPhotoThinking: Bool?
    let aiInsightProvider: String?
    let companionEnabled: Bool?
    let companionMemoryEnabled: Bool?
    let companionPersona: String?
    let companionMemoryStrength: String?
    let companionExpressionStyle: String?
    let companionCustomNote: String?
    let aiLogsEnabled: Bool?
    let promptOptimizationEnabled: Bool?
    let expressionImprovementEnabled: Bool?
    let keepSourceImages: Bool?
    let imageRetentionDays: Int?

    var settings: NativeUserSettings {
        NativeUserSettings(
            plan: plan ?? "free",
            screenshotVisionPrimary: NativeSettingsOptions.normalizedVisionProvider(screenshotVisionPrimary ?? "auto"),
            photoVisionPrimary: NativeSettingsOptions.normalizedVisionProvider(photoVisionPrimary ?? "qwen", fallback: "qwen"),
            qwenScreenshotModel: NativeSettingsOptions.normalizedQwenModel(qwenScreenshotModel ?? "qwen3.6-flash"),
            qwenPhotoModel: NativeSettingsOptions.normalizedQwenModel(qwenPhotoModel ?? "qwen3.6-flash"),
            qwenScreenshotThinking: qwenScreenshotThinking ?? false,
            qwenPhotoThinking: qwenPhotoThinking ?? false,
            aiInsightProvider: NativeSettingsOptions.normalizedInsightProvider(aiInsightProvider ?? "auto"),
            companionEnabled: companionEnabled ?? true,
            companionMemoryEnabled: companionMemoryEnabled ?? true,
            companionPersona: companionPersona ?? "observer",
            companionMemoryStrength: companionMemoryStrength ?? "balanced",
            companionExpressionStyle: companionExpressionStyle ?? "plain",
            companionCustomNote: companionCustomNote ?? "",
            aiLogsEnabled: aiLogsEnabled ?? false,
            promptOptimizationEnabled: promptOptimizationEnabled ?? false,
            expressionImprovementEnabled: expressionImprovementEnabled ?? false,
            keepSourceImages: keepSourceImages ?? true,
            imageRetentionDays: imageRetentionDays ?? -1
        )
    }

    enum CodingKeys: String, CodingKey {
        case plan
        case screenshotVisionPrimary = "screenshot_vision_primary"
        case photoVisionPrimary = "photo_vision_primary"
        case qwenScreenshotModel = "qwen_screenshot_model"
        case qwenPhotoModel = "qwen_photo_model"
        case qwenScreenshotThinking = "qwen_screenshot_enable_thinking"
        case qwenPhotoThinking = "qwen_photo_enable_thinking"
        case aiInsightProvider = "ai_insight_provider"
        case companionEnabled = "companion_enabled"
        case companionMemoryEnabled = "companion_memory_enabled"
        case companionPersona = "companion_persona"
        case companionMemoryStrength = "companion_memory_strength"
        case companionExpressionStyle = "companion_expression_style"
        case companionCustomNote = "companion_custom_note"
        case aiLogsEnabled = "ai_logs_enabled"
        case promptOptimizationEnabled = "prompt_optimization_enabled"
        case expressionImprovementEnabled = "expression_improvement_enabled"
        case keepSourceImages = "keep_source_images"
        case imageRetentionDays = "image_retention_days"
    }
}
