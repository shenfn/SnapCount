import Foundation

protocol SettingsRepositoryProtocol {
    func fetch(userId: String, accessToken: String) async throws -> NativeUserSettings
    func update(userId: String, values: [String: AnyCodable], accessToken: String) async throws
    func export(_ request: NativeDataExportRequest, accessToken: String) async throws -> NativeExportedFile
    func cleanupSourceImages(accessToken: String) async throws
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
                URLQueryItem(name: "select", value: "plan,screenshot_vision_primary,photo_vision_primary,qwen_screenshot_model,qwen_photo_model,qwen_screenshot_enable_thinking,qwen_photo_enable_thinking,ai_insight_provider,companion_enabled,companion_memory_enabled,companion_persona,companion_memory_strength,companion_expression_style,companion_custom_note,ai_logs_enabled,prompt_optimization_enabled,keep_source_images,image_retention_days"),
                URLQueryItem(name: "user_id", value: "eq.\(userId)"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        guard let row = rows.first else { return NativeUserSettings() }
        return row.settings
    }

    func update(userId: String, values: [String: AnyCodable], accessToken: String) async throws {
        var body = values
        body["user_id"] = AnyCodable(userId)
        body["updated_at"] = AnyCodable(ISO8601DateFormatter().string(from: Date()))
        _ = try await remoteClient.upsert(
            [SettingsMutationRow].self,
            path: "rest/v1/user_configs",
            queryItems: [URLQueryItem(name: "on_conflict", value: "user_id")],
            body: body,
            accessToken: accessToken
        )
    }

    func cleanupSourceImages(accessToken: String) async throws {
        _ = try await remoteClient.postFunction(
            AnyCodable.self,
            path: "functions/v1/ingest-receipt",
            body: ["action": AnyCodable("cleanup_all_images")],
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
        try await remoteClient.get(
            [[String: AnyCodable]].self,
            path: path,
            queryItems: queryItems,
            accessToken: accessToken
        )
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
            rows = payload as? [[String: AnyCodable]] ?? []
            columns = [("occurred_at", "时间"), ("domain_key", "数据域"), ("title", "标题"), ("summary", "摘要"), (request.includeFullPayload ? "payload_jsonb" : "summary", request.includeFullPayload ? "完整数据" : "关键数据")]
        }
        let header = columns.map(\.1).joined(separator: ",")
        let body = rows.map { row in
            columns.map { key, _ in csvCell(row[key]?.value) }.joined(separator: ",")
        }.joined(separator: "\n")
        return "\u{FEFF}\(header)\n\(body)"
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
    let keepSourceImages: Bool?
    let imageRetentionDays: Int?

    var settings: NativeUserSettings {
        NativeUserSettings(
            plan: plan ?? "free",
            screenshotVisionPrimary: screenshotVisionPrimary ?? "auto",
            photoVisionPrimary: photoVisionPrimary ?? "qwen",
            qwenScreenshotModel: qwenScreenshotModel ?? "qwen3.6-flash",
            qwenPhotoModel: qwenPhotoModel ?? "qwen3.7-plus",
            qwenScreenshotThinking: qwenScreenshotThinking ?? false,
            qwenPhotoThinking: qwenPhotoThinking ?? true,
            aiInsightProvider: aiInsightProvider ?? "auto",
            companionEnabled: companionEnabled ?? true,
            companionMemoryEnabled: companionMemoryEnabled ?? true,
            companionPersona: companionPersona ?? "observer",
            companionMemoryStrength: companionMemoryStrength ?? "balanced",
            companionExpressionStyle: companionExpressionStyle ?? "plain",
            companionCustomNote: companionCustomNote ?? "",
            aiLogsEnabled: aiLogsEnabled ?? false,
            promptOptimizationEnabled: promptOptimizationEnabled ?? false,
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
        case keepSourceImages = "keep_source_images"
        case imageRetentionDays = "image_retention_days"
    }
}

private struct SettingsMutationRow: Decodable {
    let id: String
}
