import Foundation

enum HistoryMigrationIssueCategory: String, CaseIterable, Codable, Identifiable {
    case missingDate = "缺少日期信息"
    case uncertainType = "尚未确定数据类型"
    case unknownStatus = "历史状态无法识别"
    case missingRelation = "已归档但缺少关联记录"
    case compatibility = "内容需要兼容转换"
    case pendingCompletion = "待补全账单"
    case recognitionFailed = "识别失败"

    var id: String { rawValue }
}

struct HistoryMigrationDiagnosticItem: Identifiable, Codable {
    let id: String
    let category: HistoryMigrationIssueCategory
    let title: String
    let summary: String
    let uploadDate: String
    let businessDate: String
    let imageStatus: String
    let status: String
    let raw: [String: AnyCodable]
}

struct HistoryMigrationDiagnosticSummary: Codable {
    let readableRecords: Int
    let pendingExpenses: Int
    let pendingReview: Int
    let cachedImages: Int
    let missingImages: Int
    let loadWarnings: Int
}

struct HistoryMigrationDiagnosticPackage: Codable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let scope: String
    let summary: HistoryMigrationDiagnosticSummary
    let rules: [String]
    let warnings: [String]
    let items: [HistoryMigrationDiagnosticItem]

    enum CodingKeys: String, CodingKey {
        case format
        case schemaVersion = "schema_version"
        case exportedAt = "exported_at"
        case scope
        case summary
        case rules
        case warnings
        case items
    }
}

enum HistoryMigrationExportFormat: String {
    case markdown = "md"
    case json
}

enum HistoryMigrationExportBuilder {
    static func package(
        from snapshot: DashboardSnapshot,
        exportedAt: Date = Date()
    ) -> HistoryMigrationDiagnosticPackage {
        let items = diagnosticItems(from: snapshot)
        let cachedImages = items.filter { $0.imageStatus == "已缓存" }.count
        let missingImages = items.filter { $0.imageStatus != "已缓存" }.count

        return HistoryMigrationDiagnosticPackage(
            format: "jiezi-migration-diagnostic",
            schemaVersion: 1,
            exportedAt: exportedAt,
            scope: "当前已读取的本机/云端投影；不是完整线上迁移结果",
            summary: HistoryMigrationDiagnosticSummary(
                readableRecords: snapshot.monthCount,
                pendingExpenses: snapshot.pendingExpenses.count,
                pendingReview: snapshot.stagingRecords.count,
                cachedImages: cachedImages,
                missingImages: missingImages,
                loadWarnings: snapshot.loadWarnings.count
            ),
            rules: [
                "用户修改时间 > occurred_at > 业务日期 > created_at/上传时间",
                "无效 occurred_at 不参与日期决策",
                "当前页面只读取和导出，不修改本机数据",
                "原始字段只读，未知状态不强行映射",
                "导出默认不包含图片二进制、认证信息和临时签名 URL"
            ],
            warnings: snapshot.loadWarnings,
            items: items
        )
    }

    static func write(
        format: HistoryMigrationExportFormat,
        snapshot: DashboardSnapshot,
        exportedAt: Date = Date()
    ) throws -> NativeExportedFile {
        let package = package(from: snapshot, exportedAt: exportedAt)
        let data: Data
        switch format {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(package)
        case .markdown:
            data = Data(markdown(package).utf8)
        }

        let date = NativeLocalDate.dateKey(exportedAt)
        let filename = "jiezi-migration-diagnostic-\(date).\(format.rawValue)"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return NativeExportedFile(url: url)
    }

    private static func diagnosticItems(from snapshot: DashboardSnapshot) -> [HistoryMigrationDiagnosticItem] {
        let pending = snapshot.pendingExpenses.map { item in
            HistoryMigrationDiagnosticItem(
                id: "pending/\(item.id)",
                category: item.dateKey.isEmpty ? .missingDate : .pendingCompletion,
                title: item.title,
                summary: "待补全消费 · ¥\(String(format: "%.2f", item.amount))",
                uploadDate: item.createdAtLabel,
                businessDate: item.dateKey.isEmpty ? "未确定" : item.dateKey,
                imageStatus: item.imagePath == nil || item.imageLoadError ? "缺失" : "已缓存",
                status: "pending",
                raw: [
                    "source": AnyCodable("transactions"),
                    "id": AnyCodable(item.id),
                    "title": AnyCodable(item.title),
                    "amount": AnyCodable(item.amount),
                    "record_date": AnyCodable(item.dateKey.isEmpty ? NSNull() : item.dateKey),
                    "uploaded_at": AnyCodable(item.createdAtLabel),
                    "image_available": AnyCodable(item.imagePath != nil && !item.imageLoadError)
                ]
            )
        }

        let staging = snapshot.stagingRecords.map { item in
            HistoryMigrationDiagnosticItem(
                id: "staging/\(item.id)",
                category: category(for: item.status),
                title: item.title,
                summary: item.summary,
                uploadDate: item.createdAtLabel,
                businessDate: item.dateKey.isEmpty ? "未确定" : item.dateKey,
                imageStatus: item.imagePath == nil || item.imageLoadError ? "缺失" : "已缓存",
                status: item.status,
                raw: stagingRaw(item)
            )
        }

        return (pending + staging).sorted {
            if $0.category.rawValue == $1.category.rawValue { return $0.id < $1.id }
            return $0.category.rawValue < $1.category.rawValue
        }
    }

    private static func category(for status: String) -> HistoryMigrationIssueCategory {
        switch status {
        case "ai_error", "failed", "extraction_failed": return .recognitionFailed
        case "routing_failed", "unrouted", "unassigned": return .uncertainType
        case "schema_failed": return .compatibility
        case "pending_review", "routed", "extracted": return .uncertainType
        case "confirmed", "archived", "discarded", "assigned": return .missingRelation
        default: return .unknownStatus
        }
    }

    private static func stagingRaw(_ item: NativeStagingRecord) -> [String: AnyCodable] {
        var raw = sanitizedDictionary(item.extracted)
        raw["source"] = AnyCodable("staging_records")
        raw["id"] = AnyCodable(item.id)
        raw["status"] = AnyCodable(item.status)
        raw["detected_domain_key"] = AnyCodable(item.domainKey ?? NSNull())
        raw["occurred_at"] = AnyCodable(item.occurredAtLabel ?? NSNull())
        raw["created_at"] = AnyCodable(item.createdAtLabel)
        raw["image_available"] = AnyCodable(item.imagePath != nil && !item.imageLoadError)
        if let imageHash = item.imageHash { raw["image_hash"] = AnyCodable(imageHash) }
        return raw
    }

    private static let sensitiveKeys: Set<String> = [
        "access_token", "authorization", "api_key", "apikey", "token",
        "signed_url", "signedurl", "temporary_url", "temp_url",
        "image_url", "source_image_url", "upload_url"
    ]

    private static func sanitizedDictionary(_ source: [String: AnyCodable]) -> [String: AnyCodable] {
        source.reduce(into: [:]) { result, entry in
            guard !isSensitiveKey(entry.key), let value = sanitizedValue(entry.value.value, key: entry.key) else { return }
            result[entry.key] = value
        }
    }

    private static func sanitizedValue(_ value: Any, key: String? = nil) -> AnyCodable? {
        if let key, isSensitiveKey(key) { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return nil }
            return AnyCodable(string)
        }
        if value is NSNull { return AnyCodable(NSNull()) }
        if let dictionary = value as? [String: Any] {
            return AnyCodable(sanitizedDictionary(dictionary.mapValues(AnyCodable.init)).mapValues(\.value))
        }
        if let array = value as? [Any] {
            return AnyCodable(array.compactMap { sanitizedValue($0)?.value })
        }
        return AnyCodable(value)
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        return sensitiveKeys.contains(normalized)
            || normalized.contains("access_token")
            || normalized.contains("signed_url")
            || normalized.contains("authorization")
    }

    private static func markdown(_ package: HistoryMigrationDiagnosticPackage) -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rawJSON = (try? encoder.encode(package.items))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        var lines = [
            "# 芥子历史迁移诊断文档",
            "",
            "- 导出时间：\(iso8601(package.exportedAt))",
            "- 数据范围：\(package.scope)",
            "- 用途：交给 AI 分析当前历史记录、待核对材料和时间字段问题",
            "",
            "## 请 AI 先回答",
            "",
            "1. 哪些记录属于日期问题，哪些属于状态、类型、关联或兼容转换问题？",
            "2. 每类问题最可能的根因是什么，证据字段有哪些？",
            "3. 哪些记录可以安全处理，哪些必须人工确认？",
            "4. 是否存在把上传时间误当发生时间、把未知状态强行映射、或静默归到今天的风险？",
            "5. 请给出修复优先级，不要直接修改数据。",
            "",
            "## 当前读取摘要",
            "",
            "- 当前月已读取正式记录：\(package.summary.readableRecords)",
            "- 待补全账单：\(package.summary.pendingExpenses)",
            "- 历史待核对：\(package.summary.pendingReview)",
            "- 已缓存图片：\(package.summary.cachedImages)",
            "- 缺失图片：\(package.summary.missingImages)",
            "- 读取警告：\(package.summary.loadWarnings)",
            "",
            "## 当前确认规则",
            "",
            package.rules.map { "- \($0)" }.joined(separator: "\n"),
            ""
        ]

        if !package.warnings.isEmpty {
            lines += ["## 读取警告", "", package.warnings.map { "- \($0)" }.joined(separator: "\n"), ""]
        }

        lines += [
            "## 待分析记录",
            "",
            "| 问题类别 | 记录摘要 | 上传/创建时间 | 有效业务日期 | 图片状态 | 当前状态 |",
            "| --- | --- | --- | --- | --- | --- |"
        ]
        lines += package.items.map {
            "| \(escape($0.category.rawValue)) | \(escape($0.title)) | \(escape($0.uploadDate)) | \(escape($0.businessDate)) | \(escape($0.imageStatus)) | \(escape($0.status)) |"
        }
        lines += ["", "## 原始字段（只读）", "", "```json", rawJSON, "```", ""]
        return lines.joined(separator: "\n")
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
