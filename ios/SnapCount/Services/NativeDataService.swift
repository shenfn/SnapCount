import Foundation

enum NativeDataServiceError: LocalizedError {
    case missingConfig
    case invalidURL
    case missingSession
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingConfig:
            return "缺少 iOS Supabase 配置。"
        case .invalidURL:
            return "数据接口地址无效。"
        case .missingSession:
            return "登录状态已失效，请重新登录。"
        case .requestFailed(let message):
            return message
        }
    }
}

struct DashboardSnapshot {
    var todayCount = 0
    var pendingCount = 0
    var monthCount = 0
    var recentRecords: [NativeRecordSummary] = []
    var stagingRecords: [NativeStagingRecord] = []
}

struct NativeRecordSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
}

struct NativeStagingRecord: Identifiable {
    let id: String
    let title: String
    let summary: String
    let status: String
    let statusLabel: String
    let recordTypeLabel: String
    let createdAtLabel: String
    let occurredAtLabel: String?
    let confidencePercent: Int?
    let lastErrorMessage: String?
    let retryCount: Int
    let systemImage: String
}

final class NativeDataService {
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        guard !AppConfig.supabaseURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw NativeDataServiceError.missingConfig
        }

        async let transactions = fetchTransactions(accessToken: accessToken)
        async let incomes = fetchIncomes(accessToken: accessToken)
        async let universal = fetchUniversalRecords(accessToken: accessToken)
        async let staging = fetchStagingRecords(accessToken: accessToken)

        let (txRows, incomeRows, universalRows, stagingRows) = try await (transactions, incomes, universal, staging)
        let today = localDateString(Date())
        let monthPrefix = String(today.prefix(7))

        var snapshot = DashboardSnapshot()
        snapshot.todayCount =
            txRows.filter { $0.transactionDate == today }.count +
            incomeRows.filter { $0.incomeDate == today }.count +
            universalRows.filter { ($0.occurredAt ?? $0.createdAt)?.hasPrefix(today) == true }.count

        snapshot.pendingCount =
            txRows.filter { $0.status == "pending" }.count +
            stagingRows.filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }.count

        snapshot.monthCount =
            txRows.filter { $0.transactionDate?.hasPrefix(monthPrefix) == true }.count +
            incomeRows.filter { $0.incomeDate?.hasPrefix(monthPrefix) == true }.count +
            universalRows.filter { ($0.occurredAt ?? $0.createdAt)?.hasPrefix(monthPrefix) == true }.count

        snapshot.recentRecords = recentRecords(
            transactions: txRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: stagingRows
        )
        snapshot.stagingRecords = stagingRows
            .filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }
            .map(stagingRecord)
        return snapshot
    }

    private func fetchTransactions(accessToken: String) async throws -> [TransactionRow] {
        try await decoded(
            [TransactionRow].self,
            path: "rest/v1/transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,transaction_date,type,amount,merchant_name,category,status"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "80")
            ],
            accessToken: accessToken
        )
    }

    private func fetchIncomes(accessToken: String) async throws -> [IncomeRow] {
        try await decoded(
            [IncomeRow].self,
            path: "rest/v1/income_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,income_date,amount,category,source_name"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "40")
            ],
            accessToken: accessToken
        )
    }

    private func fetchUniversalRecords(accessToken: String) async throws -> [DataRecordRow] {
        try await decoded(
            [DataRecordRow].self,
            path: "rest/v1/data_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "40")
            ],
            accessToken: accessToken
        )
    }

    private func fetchStagingRecords(accessToken: String) async throws -> [StagingRow] {
        try await decoded(
            [StagingRow].self,
            path: "rest/v1/staging_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,status,detected_domain_key,detected_domain_name,record_type,occurred_at,confidence,ai_summary,last_error_message,retry_count"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "30")
            ],
            accessToken: accessToken
        )
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> T {
        guard let baseURL = URL(string: AppConfig.supabaseURL) else {
            throw NativeDataServiceError.invalidURL
        }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw NativeDataServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? "HTTP \(statusCode)"
            throw NativeDataServiceError.requestFailed(text)
        }
        return try decoder.decode(type, from: data)
    }

    private func recentRecords(
        transactions: [TransactionRow],
        incomes: [IncomeRow],
        universal: [DataRecordRow],
        staging: [StagingRow]
    ) -> [NativeRecordSummary] {
        let txItems = transactions.prefix(8).map {
            NativeRecordSummary(
                id: "tx-\($0.id)",
                title: $0.merchantName ?? $0.category ?? "消费记录",
                subtitle: $0.transactionDate ?? "最近",
                value: currency($0.amount),
                systemImage: $0.status == "pending" ? "clock" : "creditcard"
            )
        }

        let incomeItems = incomes.prefix(4).map {
            NativeRecordSummary(
                id: "income-\($0.id)",
                title: $0.sourceName ?? "收入记录",
                subtitle: $0.incomeDate ?? "最近",
                value: "+\(currency($0.amount))",
                systemImage: "arrow.down.circle"
            )
        }

        let universalItems = universal.prefix(6).map {
            NativeRecordSummary(
                id: "data-\($0.id)",
                title: $0.title ?? $0.summary ?? domainName($0.domainKey),
                subtitle: ($0.occurredAt ?? $0.createdAt) ?? "最近",
                value: "",
                systemImage: "sparkles"
            )
        }

        let stagingItems = staging.prefix(4).map {
            NativeRecordSummary(
                id: "staging-\($0.id)",
                title: $0.aiSummary ?? $0.detectedDomainName ?? "待处理识别",
                subtitle: $0.status ?? "待处理",
                value: "",
                systemImage: "tray"
            )
        }

        return Array((txItems + incomeItems + universalItems + stagingItems).prefix(16))
    }

    private func stagingRecord(_ row: StagingRow) -> NativeStagingRecord {
        let status = row.status ?? "unassigned"
        let title = row.detectedDomainName ?? domainName(row.detectedDomainKey)
        return NativeStagingRecord(
            id: row.id,
            title: title,
            summary: row.aiSummary ?? row.lastErrorMessage ?? "这条截图需要你打开收件箱确认或补全。",
            status: status,
            statusLabel: stagingStatusLabel(status),
            recordTypeLabel: recordTypeLabel(row.recordType),
            createdAtLabel: dateTimeLabel(row.createdAt) ?? "最近上传",
            occurredAtLabel: dateTimeLabel(row.occurredAt),
            confidencePercent: row.confidence.map { max(0, min(100, Int(($0 * 100).rounded()))) },
            lastErrorMessage: row.lastErrorMessage,
            retryCount: row.retryCount ?? 0,
            systemImage: stagingSystemImage(status)
        )
    }

    private func currency(_ amount: Double?) -> String {
        guard let amount else { return "" }
        return "¥\(String(format: "%.2f", amount))"
    }

    private func domainName(_ key: String?) -> String {
        switch key {
        case "sport": return "运动记录"
        case "sleep": return "睡眠记录"
        case "reading": return "阅读记录"
        case "food": return "饮食记录"
        case "income": return "收入记录"
        case "expense": return "消费记录"
        default: return "数据记录"
        }
    }

    private func recordTypeLabel(_ type: String?) -> String {
        switch type {
        case "expense": return "消费截图"
        case "income": return "收入截图"
        case "transfer": return "转账截图"
        case "repayment": return "还款截图"
        case "photo": return "照片识别"
        default: return "截图识别"
        }
    }

    private func stagingStatusLabel(_ status: String) -> String {
        switch status {
        case "routing_failed", "unrouted", "unassigned": return "待分类"
        case "pending_review", "routed", "extracted": return "待确认"
        case "ai_error", "failed", "extraction_failed", "schema_failed": return "识别失败"
        case "confirmed": return "已确认"
        default: return "待处理"
        }
    }

    private func stagingSystemImage(_ status: String) -> String {
        switch status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return "exclamationmark.triangle"
        case "routing_failed", "unrouted", "unassigned": return "questionmark.folder"
        case "pending_review", "routed", "extracted": return "checklist"
        default: return "tray"
        }
    }

    private func dateTimeLabel(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }

    private func localDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct TransactionRow: Decodable {
    let id: String
    let createdAt: String?
    let transactionDate: String?
    let type: String?
    let amount: Double?
    let merchantName: String?
    let category: String?
    let status: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case transactionDate = "transaction_date"
        case type
        case amount
        case merchantName = "merchant_name"
        case category
        case status
    }
}

private struct IncomeRow: Decodable {
    let id: String
    let createdAt: String?
    let incomeDate: String?
    let amount: Double?
    let category: String?
    let sourceName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case incomeDate = "income_date"
        case amount
        case category
        case sourceName = "source_name"
    }
}

private struct DataRecordRow: Decodable {
    let id: String
    let createdAt: String?
    let occurredAt: String?
    let domainKey: String?
    let title: String?
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case occurredAt = "occurred_at"
        case domainKey = "domain_key"
        case title
        case summary
    }
}

private struct StagingRow: Decodable {
    let id: String
    let createdAt: String?
    let status: String?
    let detectedDomainKey: String?
    let detectedDomainName: String?
    let recordType: String?
    let occurredAt: String?
    let confidence: Double?
    let aiSummary: String?
    let lastErrorMessage: String?
    let retryCount: Int?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case status
        case detectedDomainKey = "detected_domain_key"
        case detectedDomainName = "detected_domain_name"
        case recordType = "record_type"
        case occurredAt = "occurred_at"
        case confidence
        case aiSummary = "ai_summary"
        case lastErrorMessage = "last_error_message"
        case retryCount = "retry_count"
    }
}
