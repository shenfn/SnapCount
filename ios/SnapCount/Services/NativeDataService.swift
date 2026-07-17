import Foundation

enum DashboardDataSection: Hashable {
    case expense
    case income
    case universal
    case staging
}

struct DashboardSnapshot {
    var todayCount = 0
    var pendingCount = 0
    var monthCount = 0
    var monthExpense = 0.0
    var monthIncome = 0.0
    var todayExpense = 0.0
    var todayIncome = 0.0
    var dailySummaries: [NativeDailySummary] = []
    var dayRecordGroups: [NativeDayRecordGroup] = []
    var loadWarnings: [String] = []
    var unavailableSections: Set<DashboardDataSection> = []
    var recordDetails: [String: NativeRecordDetail] = [:]
    var recentRecords: [NativeRecordSummary] = []
    var stagingRecords: [NativeStagingRecord] = []
    var pendingExpenses: [NativePendingExpense] = []
    var domains: [NativeDomainDefinition] = []
}

struct NativeDailySummary: Identifiable {
    let dateKey: String
    let expense: Double
    let income: Double
    let pendingCount: Int
    let recordCount: Int

    var id: String { dateKey }
}

struct NativeRecordSummary: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let value: String
    let systemImage: String
}

struct NativeRecordDetail: Identifiable {
    let id: String
    let rawId: String
    let kind: String
    let title: String
    let subtitle: String
    let value: String
    let detailRows: [NativeDetailRow]
    var imageURL: URL?
    var imageLoadError: Bool
    let imagePath: String?
    let imageHash: String?
    let amount: Double?
    let merchantName: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let recordDate: String?
    let note: String?
    let companionMessage: String?
    let accountId: String?
    let systemImage: String
    let payload: [String: AnyCodable]?
    var createdAt: String? = nil
    var occurredAt: String? = nil
    var transactionTime: String? = nil
    var domainKey: String? = nil
    var source: String? = nil
    var status: String? = nil
    var isLargeTransport: Bool = false
    var transportType: String? = nil
    var domainVersion: String? = nil
    var aiFeedback: NativeAIFeedback? = nil
    var aiSummary: String? = nil

    var isEditable: Bool {
        kind == "expense" || kind == "income" || kind == "data"
    }

    var isDeletable: Bool {
        kind == "expense" || kind == "income" || kind == "data"
    }
}

struct NativeDetailRow: Identifiable {
    let label: String
    let value: String

    var id: String { label }
}

struct NativeStagingRecord: Identifiable {
    let id: String
    let dateKey: String
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
    let imagePath: String?
    var imageURL: URL?
    var imageLoadError: Bool
    let recordType: String
    let domainKey: String?
    let domainName: String?
    let extracted: [String: AnyCodable]
    let companionMessage: String?
    let targetRecordId: String?
    let imageHash: String?
}

struct NativeArchiveDomain: Identifiable, Hashable {
    let id: String
    let title: String
    let systemImage: String
}

struct NativeRecordEditDraft: Identifiable, Equatable {
    let reference: String
    let rawId: String
    let kind: String
    var amountText: String
    var title: String
    var platform: String
    var category: String
    var paymentMethod: String
    var recordDate: String
    var note: String
    var imagePath: String?
    var imageHash: String?
    var companionMessage: String?
    var accountId: String?
    var transactionTime: String?
    var source: String?
    var isLargeTransport: Bool
    var transportType: String?

    var id: String { reference }

    init(detail: NativeRecordDetail) {
        reference = detail.id
        rawId = detail.rawId
        kind = detail.kind
        amountText = detail.amount.map { String(format: "%.2f", $0) } ?? ""
        title = detail.merchantName ?? detail.title
        platform = detail.platform ?? ""
        category = detail.category ?? ""
        paymentMethod = detail.paymentMethod ?? ""
        recordDate = detail.recordDate ?? String(detail.subtitle.prefix(10))
        note = detail.note ?? ""
        imagePath = detail.imagePath
        imageHash = detail.imageHash
        companionMessage = detail.companionMessage
        accountId = detail.accountId
        transactionTime = detail.transactionTime
        source = detail.source
        isLargeTransport = detail.isLargeTransport
        transportType = detail.transportType
    }
}

private struct NativeFetchResult<Value> {
    let value: Value?
    let error: Error?
}

private func capture<Value>(_ operation: () async throws -> Value) async -> NativeFetchResult<Value> {
    do {
        return NativeFetchResult(value: try await operation(), error: nil)
    } catch {
        return NativeFetchResult(value: nil, error: error)
    }
}

final class NativeDataService {
    private let remoteClient: SupabaseRemoteClientProtocol
    private let decoder = JSONDecoder()
    private let imageURLProvider: SupabaseImageURLProvider

    init(
        remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient(),
        imageURLProvider: SupabaseImageURLProvider = .shared
    ) {
        self.remoteClient = remoteClient
        self.imageURLProvider = imageURLProvider
    }

    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        guard !AppConfig.supabaseURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SupabaseRemoteError.missingConfig
        }

        let monthRange = try monthRange(for: localDateString(Date()).prefix(7).description)
        async let transactionsResult = capture { try await self.fetchTransactions(in: monthRange, accessToken: accessToken) }
        async let incomesResult = capture { try await self.fetchIncomes(in: monthRange, accessToken: accessToken) }
        async let universalResult = capture { try await self.fetchUniversalRecords(in: monthRange, accessToken: accessToken) }
        async let stagingResult = capture { try await self.fetchStagingRecords(accessToken: accessToken) }

        let (transactions, incomes, universal, staging) = await (transactionsResult, incomesResult, universalResult, stagingResult)
        let txRows = transactions.value ?? []
        let incomeRows = incomes.value ?? []
        let universalRows = universal.value ?? []
        let stagingRows = staging.value ?? []
        let errors = [transactions.error, incomes.error, universal.error, staging.error].compactMap { $0 }
        if errors.count == 4 {
            throw SupabaseRemoteError.requestFailed(errors.map(\.localizedDescription).joined(separator: "；"))
        }
        let today = localDateString(Date())
        let monthPrefix = String(today.prefix(7))

        var snapshot = DashboardSnapshot()
        snapshot.unavailableSections = Set([
            transactions.error == nil ? nil : DashboardDataSection.expense,
            incomes.error == nil ? nil : DashboardDataSection.income,
            universal.error == nil ? nil : DashboardDataSection.universal,
            staging.error == nil ? nil : DashboardDataSection.staging
        ].compactMap { $0 })
        snapshot.loadWarnings = [
            transactions.error.map { "消费数据暂未同步：\($0.localizedDescription)" },
            incomes.error.map { "收入数据暂未同步：\($0.localizedDescription)" },
            universal.error.map { "通用数据暂未同步：\($0.localizedDescription)" },
            staging.error.map { "中转站暂未同步：\($0.localizedDescription)" }
        ].compactMap { $0 }
        snapshot.todayCount =
            txRows.filter { $0.transactionDate == today }.count +
            incomeRows.filter { $0.incomeDate == today }.count +
            universalRows.filter { ($0.occurredAt ?? $0.createdAt)?.hasPrefix(today) == true }.count

        snapshot.pendingExpenses = txRows.filter { $0.status == "pending" }.compactMap { row in
            guard let dateKey = row.transactionDate else { return nil }
            return NativePendingExpense(id: row.id, title: row.merchantName ?? "待补全消费", amount: row.amount ?? 0, dateKey: dateKey, reference: "expense/\(row.id)")
        }

        snapshot.pendingCount =
            txRows.filter { $0.status == "pending" }.count +
            stagingRows.filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }.count

        snapshot.monthCount =
            txRows.filter { $0.transactionDate?.hasPrefix(monthPrefix) == true }.count +
            incomeRows.filter { $0.incomeDate?.hasPrefix(monthPrefix) == true }.count +
            universalRows.filter { ($0.occurredAt ?? $0.createdAt)?.hasPrefix(monthPrefix) == true }.count

        snapshot.monthExpense = txRows
            .filter { $0.transactionDate?.hasPrefix(monthPrefix) == true }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        snapshot.monthIncome = incomeRows
            .filter { $0.incomeDate?.hasPrefix(monthPrefix) == true }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        snapshot.todayExpense = txRows
            .filter { $0.transactionDate == today }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        snapshot.todayIncome = incomeRows
            .filter { $0.incomeDate == today }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        snapshot.dailySummaries = dailySummaries(
            transactions: txRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: stagingRows,
            monthPrefix: monthPrefix
        )

        snapshot.dayRecordGroups = dayRecordGroups(
            transactions: txRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: stagingRows,
            monthPrefix: monthPrefix
        )

        snapshot.recentRecords = recentRecords(
            transactions: txRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: stagingRows
        )

        let visibleTransactionRows = Array(txRows.prefix(8))
        let visibleIncomeRows = Array(incomeRows.prefix(4))
        let visibleUniversalRows = Array(universalRows.prefix(6))
        snapshot.recordDetails = cachedRecordDetails(
            transactions: visibleTransactionRows,
            incomes: visibleIncomeRows,
            universal: visibleUniversalRows,
            signedURLs: [:]
        )
        snapshot.stagingRecords = stagingRows
            .filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }
            .map { stagingRecord($0, signedImageURL: nil) }
        return snapshot
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        let paths = snapshot.recordDetails.values.compactMap(\.imagePath)
            + snapshot.stagingRecords.compactMap(\.imagePath)
        guard !paths.isEmpty else { return snapshot }
        let signedURLs = try await signedImageURLMap(paths: paths, accessToken: accessToken)
        return snapshot.applyingSignedImageURLs(signedURLs)
    }

    func fetchRecordGroups(monthKey: String, accessToken: String) async throws -> [NativeDayRecordGroup] {
        let range = try monthRange(for: monthKey)
        async let transactions = fetchTransactions(in: range, accessToken: accessToken)
        async let incomes = fetchIncomes(in: range, accessToken: accessToken)
        async let universal = fetchUniversalRecords(in: range, accessToken: accessToken)
        let (transactionRows, incomeRows, universalRows) = try await (transactions, incomes, universal)
        return dayRecordGroups(
            transactions: transactionRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: [],
            monthPrefix: monthKey
        )
    }

    private func fetchTransactions(in range: MonthRange, accessToken: String) async throws -> [TransactionRow] {
        try await pagedRows(
            [TransactionRow].self,
            path: "rest/v1/transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,transaction_date,transaction_time,type,amount,merchant_name,platform,category,payment_method,status,source,image_url,image_hash,companion_message,note,is_large_transport,transport_type,account_id,ai_feedback"),
                URLQueryItem(name: "transaction_date", value: "gte.\(range.startDate)"),
                URLQueryItem(name: "transaction_date", value: "lte.\(range.endDate)"),
                URLQueryItem(name: "order", value: "transaction_date.desc,transaction_time.desc.nullslast,created_at.desc")
            ],
            accessToken: accessToken
        )
    }

    private func fetchIncomes(in range: MonthRange, accessToken: String) async throws -> [IncomeRow] {
        try await pagedRows(
            [IncomeRow].self,
            path: "rest/v1/income_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,income_date,amount,category,source_name,source,image_url,image_hash,companion_message,note,account_id,ai_feedback"),
                URLQueryItem(name: "income_date", value: "gte.\(range.startDate)"),
                URLQueryItem(name: "income_date", value: "lte.\(range.endDate)"),
                URLQueryItem(name: "order", value: "income_date.desc,created_at.desc")
            ],
            accessToken: accessToken
        )
    }

    private func fetchUniversalRecords(in range: MonthRange, accessToken: String) async throws -> [DataRecordRow] {
        try await pagedRows(
            [DataRecordRow].self,
            path: "rest/v1/data_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary,payload_jsonb,source_image_path,source_image_hash,source"),
                URLQueryItem(name: "occurred_at", value: "gte.\(range.startTimestamp)"),
                URLQueryItem(name: "occurred_at", value: "lte.\(range.endTimestamp)"),
                URLQueryItem(name: "order", value: "occurred_at.desc.nullslast,created_at.desc")
            ],
            accessToken: accessToken
        )
    }

    private func pagedRows<Row: Decodable>(
        _ type: [Row].Type,
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String,
        pageSize: Int = 500
    ) async throws -> [Row] {
        var rows: [Row] = []
        var offset = 0
        while true {
            let page = try await decoded(
                type,
                path: path,
                queryItems: queryItems + [
                    URLQueryItem(name: "limit", value: String(pageSize)),
                    URLQueryItem(name: "offset", value: String(offset))
                ],
                accessToken: accessToken
            )
            rows.append(contentsOf: page)
            guard page.count == pageSize else { return rows }
            offset += pageSize
        }
    }

    private struct MonthRange {
        let startDate: String
        let endDate: String
        var startTimestamp: String { "\(startDate)T00:00:00+08:00" }
        var endTimestamp: String { "\(endDate)T23:59:59+08:00" }
    }

    private func monthRange(for monthKey: String) throws -> MonthRange {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let firstDate = formatter.date(from: "\(monthKey)-01"),
              let nextMonth = formatter.calendar.date(byAdding: .month, value: 1, to: firstDate),
              let lastDate = formatter.calendar.date(byAdding: .day, value: -1, to: nextMonth) else {
            throw SupabaseRemoteError.requestFailed("月份格式无效")
        }
        return MonthRange(startDate: formatter.string(from: firstDate), endDate: formatter.string(from: lastDate))
    }

    private func fetchStagingRecords(accessToken: String) async throws -> [StagingRow] {
        try await decoded(
            [StagingRow].self,
            path: "rest/v1/staging_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,status,detected_domain_key,detected_domain_name,record_type,occurred_at,confidence,ai_summary,last_error_message,retry_count,image_path,image_hash,image_type,extracted_json,companion_message,target_record_id"),
                URLQueryItem(name: "order", value: "created_at.desc"),
                URLQueryItem(name: "limit", value: "30")
            ],
            accessToken: accessToken
        )
    }

    func discardStagingRecord(id: String, accessToken: String) async throws {
        try await patch(
            path: "rest/v1/staging_records",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            body: [
                "status": AnyCodable("discarded"),
                "discard_reason": AnyCodable("user_discarded"),
                "resolved_action": AnyCodable("discarded"),
                "resolved_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ],
            accessToken: accessToken
        )
    }

    func retryStagingRecord(id: String, accessToken: String) async throws -> ShortcutUploadResult {
        let responseData = try await postMultipart(
            path: "functions/v1/ingest-receipt",
            fields: ["staging_record_id": id, "response_mode": "json"],
            accessToken: accessToken
        )
        if let payload = try? decoder.decode(ShortcutUploadPayload.self, from: responseData) {
            return ShortcutUploadResult(payload: payload)
        }
        let text = String(data: responseData, encoding: .utf8) ?? ""
        return ShortcutUploadResult(displayText: text.isEmpty ? "已重新识别，打开芥子查看结果。" : text)
    }

    func archiveStagingRecord(
        _ record: NativeStagingRecord,
        domainKey: String,
        accessToken: String
    ) async throws -> String {
        let payload = record.archivePayload
        let occurredAt = payload.string("occurred_at")
            ?? payload.string("order_finished_at")
            ?? ISO8601DateFormatter().string(from: Date())
        if ["expense", "income"].contains(domainKey), !(payload.double("amount").map { $0 > 0 } ?? false) {
            let title = domainKey == "expense" ? "消费" : "收入"
            throw SupabaseRemoteError.requestFailed("未识别到有效金额，请先重新识别或补全后再归档到\(title)")
        }
        let response = try await rpc(
            ArchiveStagingRPCResponse.self,
            name: "archive_staging_record",
            body: Self.stagingArchiveRPCBody(
                record: record,
                domainKey: domainKey,
                payload: payload,
                occurredAt: occurredAt
            ),
            accessToken: accessToken
        )
        return response.targetReference
    }

    func resolveImageURL(path: String, accessToken: String) async throws -> URL {
        await imageURLProvider.invalidate(path: path)
        let urls = try await signedImageURLMap(paths: [path], accessToken: accessToken)
        guard let url = urls[path] else {
            throw SupabaseRemoteError.requestFailed("截图文件暂时无法访问")
        }
        return url
    }

    func fetchRecordDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        let resolved = NativeRecordReference(reference)
        let kind = resolved.kind
        let id = resolved.rawId

        switch kind {
        case "expense":
            let rows = try await decoded(
                [TransactionDetailRow].self,
                path: "rest/v1/transactions",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,transaction_date,transaction_time,amount,merchant_name,platform,category,payment_method,status,source,image_url,image_hash,companion_message,note,is_large_transport,transport_type,account_id,ai_feedback"),
                    URLQueryItem(name: "id", value: "eq.\(id)"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                accessToken: accessToken
            )
            guard let row = rows.first else { throw SupabaseRemoteError.requestFailed("记录不存在或已被删除") }
            let signedURLs = try? await signedImageURLMap(paths: [row.imageURL].compactMap { $0 }, accessToken: accessToken)
            let imageURL = signedURLs?[row.imageURL ?? ""]
            return NativeRecordDetail(
                id: "expense/\(row.id)",
                rawId: row.id,
                kind: "expense",
                title: row.merchantName ?? row.category ?? "消费记录",
                subtitle: row.transactionDate ?? row.createdAt ?? "",
                value: currency(row.amount),
                detailRows: [
                    NativeDetailRow(label: "平台", value: row.platform ?? "未填写"),
                    NativeDetailRow(label: "分类", value: row.category ?? "未填写"),
                    NativeDetailRow(label: "支付方式", value: row.paymentMethod ?? "未填写"),
                    NativeDetailRow(label: "交易时间", value: row.transactionTime ?? ""),
                    NativeDetailRow(label: "关联账户", value: row.accountId ?? "未绑定"),
                    NativeDetailRow(label: "状态", value: row.status ?? "done"),
                    NativeDetailRow(label: "来源", value: row.source ?? ""),
                    NativeDetailRow(label: "备注", value: row.note ?? "")
                ].filter { !$0.value.isEmpty },
                imageURL: imageURL,
                imageLoadError: row.imageURL != nil && imageURL == nil,
                imagePath: row.imageURL,
                imageHash: row.imageHash,
                amount: row.amount,
                merchantName: row.merchantName,
                platform: row.platform,
                category: row.category,
                paymentMethod: row.paymentMethod,
                recordDate: row.transactionDate,
                note: row.note,
                companionMessage: row.companionMessage,
                accountId: row.accountId,
                systemImage: "creditcard",
                payload: nil,
                createdAt: row.createdAt,
                occurredAt: row.transactionDate,
                transactionTime: row.transactionTime,
                domainKey: "expense",
                source: row.source,
                status: row.status,
                isLargeTransport: row.isLargeTransport ?? false,
                transportType: row.transportType,
                aiFeedback: NativeAIFeedback(payload: row.aiFeedback)
            )

        case "income":
            let rows = try await decoded(
                [IncomeDetailRow].self,
                path: "rest/v1/income_records",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,income_date,amount,category,source_name,source,image_url,image_hash,companion_message,note,account_id,ai_feedback"),
                    URLQueryItem(name: "id", value: "eq.\(id)"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                accessToken: accessToken
            )
            guard let row = rows.first else { throw SupabaseRemoteError.requestFailed("记录不存在或已被删除") }
            let signedURLs = try? await signedImageURLMap(paths: [row.imageURL].compactMap { $0 }, accessToken: accessToken)
            let imageURL = signedURLs?[row.imageURL ?? ""]
            return NativeRecordDetail(
                id: "income/\(row.id)",
                rawId: row.id,
                kind: "income",
                title: row.sourceName ?? "收入记录",
                subtitle: row.incomeDate ?? row.createdAt ?? "",
                value: "+\(currency(row.amount))",
                detailRows: [
                    NativeDetailRow(label: "收入类型", value: row.category ?? "other"),
                    NativeDetailRow(label: "来源名称", value: row.sourceName ?? ""),
                    NativeDetailRow(label: "记录来源", value: row.source ?? ""),
                    NativeDetailRow(label: "关联账户", value: row.accountId ?? "未绑定"),
                    NativeDetailRow(label: "备注", value: row.note ?? ""),
                    NativeDetailRow(label: "AI 陪伴", value: row.companionMessage ?? "")
                ].filter { !$0.value.isEmpty },
                imageURL: imageURL,
                imageLoadError: row.imageURL != nil && imageURL == nil,
                imagePath: row.imageURL,
                imageHash: row.imageHash,
                amount: row.amount,
                merchantName: row.sourceName,
                platform: nil,
                category: row.category,
                paymentMethod: nil,
                recordDate: row.incomeDate,
                note: row.note,
                companionMessage: row.companionMessage,
                accountId: row.accountId,
                systemImage: "arrow.down.circle",
                payload: nil,
                createdAt: row.createdAt,
                occurredAt: row.incomeDate,
                domainKey: "income",
                source: row.source,
                aiFeedback: NativeAIFeedback(payload: row.aiFeedback)
            )

        default:
            let rows = try await decoded(
                [DataRecordDetailRow].self,
                path: "rest/v1/data_records",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,domain_version,title,summary,payload_jsonb,source_image_path,source_image_hash,source"),
                    URLQueryItem(name: "id", value: "eq.\(id)"),
                    URLQueryItem(name: "limit", value: "1")
                ],
                accessToken: accessToken
            )
            guard let row = rows.first else { throw SupabaseRemoteError.requestFailed("记录不存在或已被删除") }
            let signedURLs = try? await signedImageURLMap(paths: [row.sourceImagePath].compactMap { $0 }, accessToken: accessToken)
            let imageURL = signedURLs?[row.sourceImagePath ?? ""]
            let payloadRows = (row.payloadJSONB ?? [:])
                .filter { !$0.value.displayValue.isEmpty }
                .sorted { $0.key < $1.key }
                .prefix(12)
                .map { NativeDetailRow(label: $0.key, value: $0.value.displayValue) }
            return NativeRecordDetail(
                id: "data/\(row.id)",
                rawId: row.id,
                kind: "data",
                title: row.title ?? domainName(row.domainKey),
                subtitle: row.occurredAt ?? row.createdAt ?? "",
                value: "",
                detailRows: [
                    NativeDetailRow(label: "数据域", value: domainName(row.domainKey)),
                    NativeDetailRow(label: "领域 Key", value: row.domainKey ?? ""),
                    NativeDetailRow(label: "摘要", value: row.summary ?? "")
                ].filter { !$0.value.isEmpty } + payloadRows,
                imageURL: imageURL,
                imageLoadError: row.sourceImagePath != nil && imageURL == nil,
                imagePath: row.sourceImagePath,
                imageHash: row.sourceImageHash,
                amount: nil,
                merchantName: nil,
                platform: nil,
                category: row.domainKey,
                paymentMethod: nil,
                recordDate: row.occurredAt.map(dateOnly),
                note: row.summary,
                companionMessage: row.payloadJSONB?.string("companion_message"),
                accountId: row.payloadJSONB?.string("linked_account_id"),
                systemImage: "sparkles",
                payload: row.payloadJSONB,
                createdAt: row.createdAt,
                occurredAt: row.occurredAt,
                domainKey: row.domainKey,
                source: row.source,
                domainVersion: row.domainVersion,
                aiFeedback: NativeAIFeedback(payload: row.payloadJSONB?.dictionary("ai_feedback")),
                aiSummary: row.summary
            )
        }
    }

    func saveRecordDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        let amount = parseAmount(draft.amountText)
        guard amount > 0 else {
            throw SupabaseRemoteError.requestFailed("金额必须大于 0")
        }
        let recordDate = draft.recordDate.isEmpty ? localDateString(Date()) : draft.recordDate

        switch draft.kind {
        case "expense":
            let isLargeTransport = ["transport", "出行"].contains(draft.category) && amount >= 200
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_transaction_with_account",
                body: [
                    "p_id": AnyCodable(draft.rawId),
                    "p_amount": AnyCodable(amount),
                    "p_merchant_name": AnyCodable(emptyAsNull(draft.title) ?? "消费记录"),
                    "p_platform": AnyCodable(emptyAsNull(draft.platform) ?? "截图识别"),
                    "p_category": AnyCodable(emptyAsNull(draft.category) ?? "其他"),
                    "p_payment_method": AnyCodable(emptyAsNull(draft.paymentMethod) ?? "未知"),
                    "p_transaction_date": AnyCodable(recordDate),
                    "p_transaction_time": AnyCodable(nullable(draft.transactionTime)),
                    "p_note": AnyCodable(nullable(emptyAsNull(draft.note))),
                    "p_is_large_transport": AnyCodable(isLargeTransport),
                    "p_transport_type": AnyCodable(nullable(isLargeTransport ? (emptyAsNull(draft.transportType) ?? "交通") : nil)),
                    "p_source": AnyCodable(nullable(draft.source)),
                    "p_image_url": AnyCodable(nullable(draft.imagePath)),
                    "p_image_hash": AnyCodable(nullable(draft.imageHash)),
                    "p_companion_message": AnyCodable(nullable(draft.companionMessage)),
                    "p_account_id": AnyCodable(nullable(draft.accountId))
                ],
                accessToken: accessToken
            )
            return "expense/\(response.id)"

        case "income":
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_income_with_account",
                body: [
                    "p_id": AnyCodable(draft.rawId),
                    "p_category": AnyCodable(emptyAsNull(draft.category) ?? "other"),
                    "p_source_name": AnyCodable(emptyAsNull(draft.title) ?? "收入记录"),
                    "p_amount": AnyCodable(amount),
                    "p_income_date": AnyCodable(recordDate),
                    "p_note": AnyCodable(nullable(emptyAsNull(draft.note))),
                    "p_source": AnyCodable(nullable(draft.source)),
                    "p_image_url": AnyCodable(nullable(draft.imagePath)),
                    "p_image_hash": AnyCodable(nullable(draft.imageHash)),
                    "p_companion_message": AnyCodable(nullable(draft.companionMessage)),
                    "p_account_id": AnyCodable(nullable(draft.accountId))
                ],
                accessToken: accessToken
            )
            return "income/\(response.id)"

        default:
            throw SupabaseRemoteError.requestFailed("当前记录类型暂不支持原生编辑")
        }
    }

    func deleteRecord(reference: String, accessToken: String) async throws {
        let resolved = resolveReference(reference)
        switch resolved.kind {
        case "expense":
            _ = try await rpc(
                TransactionDetailRow.self,
                name: "delete_transaction_with_account",
                body: ["p_id": AnyCodable(resolved.id)],
                accessToken: accessToken
            )
        case "income":
            _ = try await rpc(
                IncomeDetailRow.self,
                name: "delete_income_with_account",
                body: ["p_id": AnyCodable(resolved.id)],
                accessToken: accessToken
            )
        case "data":
            try await delete(
                path: "rest/v1/data_records",
                queryItems: [URLQueryItem(name: "id", value: "eq.\(resolved.id)")],
                accessToken: accessToken
            )
        default:
            throw SupabaseRemoteError.requestFailed("当前记录类型暂不支持删除")
        }
    }

    private func decoded<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws -> T {
        try await remoteClient.get(
            type,
            path: path,
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    private func patch(
        path: String,
        queryItems: [URLQueryItem],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws {
        try await remoteClient.patch(
            path: path,
            queryItems: queryItems,
            body: body,
            accessToken: accessToken
        )
    }

    private func delete(
        path: String,
        queryItems: [URLQueryItem],
        accessToken: String
    ) async throws {
        try await remoteClient.delete(
            path: path,
            queryItems: queryItems,
            accessToken: accessToken
        )
    }

    private func postJSON<T: Decodable>(
        _ type: T.Type,
        path: String,
        queryItems: [URLQueryItem] = [],
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T {
        try await remoteClient.post(
            type,
            path: path,
            queryItems: queryItems,
            body: body,
            accessToken: accessToken
        )
    }

    private func rpc<T: Decodable>(
        _ type: T.Type,
        name: String,
        body: [String: AnyCodable],
        accessToken: String
    ) async throws -> T {
        try await remoteClient.rpc(
            type,
            name: name,
            body: body,
            accessToken: accessToken
        )
    }

    private func postMultipart(
        path: String,
        fields: [String: String],
        accessToken: String
    ) async throws -> Data {
        try await remoteClient.postMultipart(
            path: path,
            fields: fields,
            accessToken: accessToken
        )
    }

    private func signedImageURLMap(paths: [String], accessToken: String) async throws -> [String: URL] {
        _ = accessToken
        return try await imageURLProvider.signedURLMap(paths: paths)
    }

    private func fetchDataDomain(key: String, accessToken: String) async throws -> DataDomainRow {
        let rows = try await decoded(
            [DataDomainRow].self,
            path: "rest/v1/data_domains",
            queryItems: [
                URLQueryItem(name: "select", value: "id,key,version"),
                URLQueryItem(name: "key", value: "eq.\(key)"),
                URLQueryItem(name: "status", value: "eq.active"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        guard let row = rows.first else {
            throw SupabaseRemoteError.requestFailed("数据域未就绪：\(key)")
        }
        return row
    }

    static func stagingArchiveRPCBody(
        record: NativeStagingRecord,
        domainKey: String,
        payload: [String: AnyCodable],
        occurredAt: String
    ) -> [String: AnyCodable] {
        let amount: Any = payload.double("amount").map { $0 as Any } ?? NSNull()
        let accountId: Any = payload.string("account_id").map { $0 as Any } ?? NSNull()
        let recordTime: Any = payload.string("transaction_time").map { $0 as Any } ?? NSNull()
        let platform: Any = payload.string("platform").map { $0 as Any } ?? NSNull()
        let category: Any = payload.string("category").map { $0 as Any } ?? NSNull()
        let paymentMethod: Any = payload.string("payment_method").map { $0 as Any } ?? NSNull()
        let incomeCategory: Any = payload.string("income_category").map { $0 as Any } ?? NSNull()
        return [
            "p_staging_id": AnyCodable(record.id),
            "p_domain_key": AnyCodable(domainKey),
            "p_amount": AnyCodable(amount),
            "p_title": AnyCodable(payload.string("title") ?? payload.string("merchant_name") ?? payload.string("source_name") ?? record.title),
            "p_platform": AnyCodable(platform),
            "p_category": AnyCodable(category),
            "p_payment_method": AnyCodable(paymentMethod),
            "p_income_category": AnyCodable(incomeCategory),
            "p_record_date": AnyCodable(String(occurredAt.prefix(10))),
            "p_record_time": AnyCodable(recordTime),
            "p_occurred_at": AnyCodable(occurredAt),
            "p_summary": AnyCodable(record.summary),
            "p_payload": AnyCodable(payload.mapValues(\.value)),
            "p_account_id": AnyCodable(accountId)
        ]
    }

    private func dailySummaries(
        transactions: [TransactionRow],
        incomes: [IncomeRow],
        universal: [DataRecordRow],
        staging: [StagingRow],
        monthPrefix: String
    ) -> [NativeDailySummary] {
        var dates = Set<String>()
        transactions.compactMap(\.transactionDate).filter { $0.hasPrefix(monthPrefix) }.forEach { dates.insert($0) }
        incomes.compactMap(\.incomeDate).filter { $0.hasPrefix(monthPrefix) }.forEach { dates.insert($0) }
        universal.compactMap { ($0.occurredAt ?? $0.createdAt).map(dateOnly) }.filter { $0.hasPrefix(monthPrefix) }.forEach { dates.insert($0) }
        staging.compactMap { ($0.occurredAt ?? $0.createdAt).map(dateOnly) }.filter { $0.hasPrefix(monthPrefix) }.forEach { dates.insert($0) }

        return dates.sorted(by: >).map { date in
            let dayTransactions = transactions.filter { $0.transactionDate == date }
            let dayIncomes = incomes.filter { $0.incomeDate == date }
            let dayUniversal = universal.filter { ($0.occurredAt ?? $0.createdAt).map(dateOnly) == date }
            let dayStaging = staging.filter { ($0.occurredAt ?? $0.createdAt).map(dateOnly) == date && !["discarded", "archived", "assigned"].contains($0.status ?? "") }
            return NativeDailySummary(
                dateKey: date,
                expense: dayTransactions.reduce(0) { $0 + ($1.amount ?? 0) },
                income: dayIncomes.reduce(0) { $0 + ($1.amount ?? 0) },
                pendingCount: dayTransactions.filter { $0.status == "pending" }.count + dayStaging.count,
                recordCount: dayTransactions.count + dayIncomes.count + dayUniversal.count + dayStaging.count
            )
        }
    }

    private func dayRecordGroups(
        transactions: [TransactionRow], incomes: [IncomeRow], universal: [DataRecordRow], staging: [StagingRow], monthPrefix: String
    ) -> [NativeDayRecordGroup] {
        var records: [NativeDayRecord] = []
        transactions.filter { $0.transactionDate?.hasPrefix(monthPrefix) == true }.forEach { row in
            guard let dateKey = row.transactionDate else { return }
            records.append(NativeDayRecord(id: "expense-\(row.id)", reference: "expense/\(row.id)", dateKey: dateKey, kind: .expense, domainKey: "expense", title: row.merchantName ?? row.category ?? "消费记录", subtitle: [row.platform, row.category].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "), value: currency(row.amount), timeLabel: row.transactionTime, systemImage: row.status == "pending" ? "clock" : "creditcard"))
        }
        incomes.filter { $0.incomeDate?.hasPrefix(monthPrefix) == true }.forEach { row in
            guard let dateKey = row.incomeDate else { return }
            records.append(NativeDayRecord(id: "income-\(row.id)", reference: "income/\(row.id)", dateKey: dateKey, kind: .income, domainKey: "income", title: row.sourceName ?? "收入记录", subtitle: row.category ?? "收入", value: "+\(currency(row.amount))", timeLabel: nil, systemImage: "arrow.down.circle"))
        }
        universal.filter { ($0.occurredAt ?? $0.createdAt)?.hasPrefix(monthPrefix) == true }.forEach { row in
            guard let sourceDate = row.occurredAt ?? row.createdAt else { return }
            let kind = NativeDayRecordKind(rawValue: row.domainKey ?? "") ?? .all
            records.append(NativeDayRecord(id: "data-\(row.id)", reference: "data/\(row.id)", dateKey: dateOnly(sourceDate), kind: kind, domainKey: row.domainKey, title: row.title ?? row.summary ?? domainName(row.domainKey), subtitle: row.summary ?? domainName(row.domainKey), value: "", timeLabel: timeOnly(sourceDate), systemImage: kind == .all ? "sparkles" : kind.systemImage))
        }
        staging.filter { !["discarded", "archived", "assigned", "confirmed"].contains($0.status ?? "") && ($0.occurredAt ?? $0.createdAt)?.hasPrefix(monthPrefix) == true }.forEach { row in
            guard let sourceDate = row.occurredAt ?? row.createdAt else { return }
            records.append(NativeDayRecord(id: "staging-\(row.id)", reference: "staging-\(row.id)", dateKey: dateOnly(sourceDate), kind: .staging, domainKey: row.detectedDomainKey, title: row.detectedDomainName ?? domainName(row.detectedDomainKey), subtitle: row.aiSummary ?? row.lastErrorMessage ?? "待处理截图", value: row.recordType == "income" ? "+ 待确认" : row.recordType == "expense" ? "- 待确认" : "待分类", timeLabel: timeOnly(sourceDate), systemImage: stagingSystemImage(row.status ?? "unassigned")))
        }
        let groups = Dictionary(grouping: records) { $0.dateKey }
        return groups.keys.sorted(by: >).map { dateKey in NativeDayRecordGroup(dateKey: dateKey, records: (groups[dateKey] ?? []).sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }) }
    }

    func createManualRecord(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?,
        userId: String,
        accessToken: String
    ) async throws -> String {
        if let validationMessage = draft.validationMessage(domain: domain) {
            throw SupabaseRemoteError.requestFailed(validationMessage)
        }

        switch draft.kind {
        case .expense:
            let amount = draft.amount ?? 0
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_transaction_with_account",
                body: [
                    "p_id": AnyCodable(NSNull()),
                    "p_amount": AnyCodable(amount),
                    "p_merchant_name": AnyCodable(emptyAsNull(draft.title) ?? "\(draft.platform)消费"),
                    "p_platform": AnyCodable(draft.platform),
                    "p_category": AnyCodable(draft.category),
                    "p_payment_method": AnyCodable(draft.paymentMethod),
                    "p_transaction_date": AnyCodable(draft.dateKey),
                    "p_transaction_time": AnyCodable(nullable(draft.timeKey)),
                    "p_note": AnyCodable(nullable(emptyAsNull(draft.note))),
                    "p_is_large_transport": AnyCodable(draft.category == "transport" && amount >= 200),
                    "p_transport_type": AnyCodable(nullable(draft.category == "transport" && amount >= 200 ? "交通" : nil)),
                    "p_source": AnyCodable("manual"),
                    "p_image_url": AnyCodable(NSNull()),
                    "p_image_hash": AnyCodable(NSNull()),
                    "p_companion_message": AnyCodable(NSNull()),
                    "p_account_id": AnyCodable(nullable(draft.accountId))
                ],
                accessToken: accessToken
            )
            return "expense/\(response.id)"

        case .income:
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_income_with_account",
                body: [
                    "p_id": AnyCodable(NSNull()),
                    "p_category": AnyCodable(draft.category),
                    "p_source_name": AnyCodable(emptyAsNull(draft.title) ?? "收入记录"),
                    "p_amount": AnyCodable(draft.amount ?? 0),
                    "p_income_date": AnyCodable(draft.dateKey),
                    "p_note": AnyCodable(nullable(emptyAsNull(draft.note))),
                    "p_source": AnyCodable("manual"),
                    "p_image_url": AnyCodable(NSNull()),
                    "p_image_hash": AnyCodable(NSNull()),
                    "p_companion_message": AnyCodable(NSNull()),
                    "p_account_id": AnyCodable(nullable(draft.accountId))
                ],
                accessToken: accessToken
            )
            return "income/\(response.id)"

        case .universal:
            let domainRow = try await fetchDataDomain(key: draft.domainKey, accessToken: accessToken)
            let body: [String: AnyCodable] = [
                "domain_id": AnyCodable(domainRow.id),
                "domain_key": AnyCodable(domainRow.key),
                "domain_version": AnyCodable(domainRow.version ?? "1.0"),
                "occurred_at": AnyCodable(draft.occurredAt),
                "title": AnyCodable(draft.resolvedTitle(domain: domain)),
                "summary": AnyCodable(draft.resolvedSummary(domain: domain)),
                "payload_jsonb": AnyCodable(draft.universalPayload(domain: domain).mapValues(\.value)),
                "source": AnyCodable("manual"),
                "source_image_path": AnyCodable(nullable(draft.imagePath)),
                "source_image_hash": AnyCodable(nullable(draft.imageHash)),
                "user_id": AnyCodable(userId)
            ]
            if let existingRawId = draft.existingRawId {
                try await patch(
                    path: "rest/v1/data_records",
                    queryItems: [URLQueryItem(name: "id", value: "eq.\(existingRawId)")],
                    body: body,
                    accessToken: accessToken
                )
                return "data/\(existingRawId)"
            }
            let rows = try await postJSON(
                [InsertedRecordResponse].self,
                path: "rest/v1/data_records",
                queryItems: [URLQueryItem(name: "select", value: "id")],
                body: body,
                accessToken: accessToken
            )
            guard let row = rows.first else {
                throw SupabaseRemoteError.requestFailed("记录已保存，但没有返回记录 ID")
            }
            return "data/\(row.id)"
        }
    }

    private func timeOnly(_ value: String) -> String? {
        guard value.count >= 16 else { return nil }
        let start = value.index(value.startIndex, offsetBy: 11)
        let end = value.index(start, offsetBy: 5)
        return String(value[start..<end])
    }

    private func cachedRecordDetails(
        transactions: [TransactionRow],
        incomes: [IncomeRow],
        universal: [DataRecordRow],
        signedURLs: [String: URL]
    ) -> [String: NativeRecordDetail] {
        var details: [String: NativeRecordDetail] = [:]
        transactions.forEach { row in
            let reference = "expense/\(row.id)"
            details[reference] = NativeRecordDetail(
                id: reference, rawId: row.id, kind: "expense",
                title: row.merchantName ?? "消费记录", subtitle: row.transactionDate ?? row.createdAt ?? "", value: currency(row.amount),
                detailRows: [
                    NativeDetailRow(label: "平台", value: row.platform ?? "未填写"),
                    NativeDetailRow(label: "分类", value: row.category ?? "未填写"),
                    NativeDetailRow(label: "支付方式", value: row.paymentMethod ?? "未填写"),
                    NativeDetailRow(label: "状态", value: row.status ?? ""),
                    NativeDetailRow(label: "来源", value: row.source ?? "")
                ].filter { !$0.value.isEmpty },
                imageURL: signedURLs[row.imageURL ?? ""], imageLoadError: false, imagePath: row.imageURL, imageHash: row.imageHash,
                amount: row.amount, merchantName: row.merchantName, platform: row.platform, category: row.category, paymentMethod: row.paymentMethod, recordDate: row.transactionDate, note: row.note, companionMessage: row.companionMessage, accountId: row.accountId, systemImage: row.status == "pending" ? "clock" : "creditcard", payload: nil,
                createdAt: row.createdAt, occurredAt: row.transactionDate, transactionTime: row.transactionTime,
                domainKey: "expense", source: row.source, status: row.status,
                isLargeTransport: row.isLargeTransport ?? false, transportType: row.transportType,
                aiFeedback: NativeAIFeedback(payload: row.aiFeedback)
            )
        }
        incomes.forEach { row in
            let reference = "income/\(row.id)"
            details[reference] = NativeRecordDetail(
                id: reference, rawId: row.id, kind: "income", title: row.sourceName ?? "收入记录", subtitle: row.incomeDate ?? row.createdAt ?? "", value: "+\(currency(row.amount))",
                detailRows: [NativeDetailRow(label: "收入类型", value: row.category ?? "未填写"), NativeDetailRow(label: "来源", value: row.source ?? "")].filter { !$0.value.isEmpty },
                imageURL: signedURLs[row.imageURL ?? ""], imageLoadError: false, imagePath: row.imageURL, imageHash: row.imageHash,
                amount: row.amount, merchantName: row.sourceName, platform: nil, category: row.category, paymentMethod: nil, recordDate: row.incomeDate, note: row.note, companionMessage: row.companionMessage, accountId: row.accountId, systemImage: "arrow.down.circle", payload: nil,
                createdAt: row.createdAt, occurredAt: row.incomeDate, domainKey: "income", source: row.source,
                aiFeedback: NativeAIFeedback(payload: row.aiFeedback)
            )
        }
        universal.forEach { row in
            let reference = "data/\(row.id)"
            let payloadRows = (row.payloadJSONB ?? [:]).filter { !$0.value.displayValue.isEmpty }.sorted { $0.key < $1.key }.prefix(12).map { NativeDetailRow(label: $0.key, value: $0.value.displayValue) }
            details[reference] = NativeRecordDetail(
                id: reference, rawId: row.id, kind: "data", title: row.title ?? domainName(row.domainKey), subtitle: row.occurredAt ?? row.createdAt ?? "", value: "",
                detailRows: [NativeDetailRow(label: "摘要", value: row.summary ?? "")].filter { !$0.value.isEmpty } + payloadRows,
                imageURL: signedURLs[row.sourceImagePath ?? ""], imageLoadError: false, imagePath: row.sourceImagePath, imageHash: row.sourceImageHash,
                amount: nil, merchantName: nil, platform: nil, category: row.domainKey, paymentMethod: nil, recordDate: row.occurredAt.map(dateOnly), note: row.summary, companionMessage: row.payloadJSONB?.string("companion_message"), accountId: row.payloadJSONB?.string("linked_account_id"), systemImage: "sparkles", payload: row.payloadJSONB,
                createdAt: row.createdAt, occurredAt: row.occurredAt, domainKey: row.domainKey, source: row.source,
                aiFeedback: NativeAIFeedback(payload: row.payloadJSONB?.dictionary("ai_feedback")), aiSummary: row.summary
            )
        }
        return details
    }

    private func recentRecords(
        transactions: [TransactionRow],
        incomes: [IncomeRow],
        universal: [DataRecordRow],
        staging: [StagingRow]
    ) -> [NativeRecordSummary] {
        let txItems = transactions.prefix(8).map {
            NativeRecordSummary(
                id: "expense/\($0.id)",
                title: $0.merchantName ?? $0.category ?? "消费记录",
                subtitle: $0.transactionDate ?? "最近",
                value: currency($0.amount),
                systemImage: $0.status == "pending" ? "clock" : "creditcard"
            )
        }

        let incomeItems = incomes.prefix(4).map {
            NativeRecordSummary(
                id: "income/\($0.id)",
                title: $0.sourceName ?? "收入记录",
                subtitle: $0.incomeDate ?? "最近",
                value: "+\(currency($0.amount))",
                systemImage: "arrow.down.circle"
            )
        }

        let universalItems = universal.prefix(6).map {
            NativeRecordSummary(
                id: "data/\($0.id)",
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

    private func stagingRecord(_ row: StagingRow, signedImageURL: URL?) -> NativeStagingRecord {
        let status = row.status ?? "unassigned"
        let title = row.detectedDomainName ?? domainName(row.detectedDomainKey)
        return NativeStagingRecord(
            id: row.id,
            dateKey: String((row.occurredAt ?? row.createdAt ?? "").prefix(10)),
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
            systemImage: stagingSystemImage(status),
            imagePath: row.imagePath,
            imageURL: signedImageURL,
            imageLoadError: false,
            recordType: row.recordType ?? "uncertain",
            domainKey: row.detectedDomainKey,
            domainName: row.detectedDomainName,
            extracted: row.extractedJSON ?? [:],
            companionMessage: row.companionMessage,
            targetRecordId: row.targetRecordId,
            imageHash: row.imageHash
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

    private func dateOnly(_ value: String) -> String {
        if value.count >= 10 {
            return String(value.prefix(10))
        }
        return localDateString(Date())
    }

    private func resolveReference(_ reference: String) -> (kind: String, id: String) {
        let resolved = NativeRecordReference(reference)
        return (resolved.kind, resolved.rawId)
    }

    private func parseAmount(_ value: String) -> Double {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(normalized) ?? 0
    }

    private func emptyAsNull(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private func nullable(_ value: String?) -> Any {
        guard let value, !value.isEmpty else { return NSNull() }
        return value
    }

    private func nullable(_ value: Double?) -> Any {
        guard let value else { return NSNull() }
        return value
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
    let transactionTime: String?
    let type: String?
    let amount: Double?
    let merchantName: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let status: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?
    let note: String?
    let isLargeTransport: Bool?
    let transportType: String?
    let accountId: String?
    let aiFeedback: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case transactionDate = "transaction_date"
        case transactionTime = "transaction_time"
        case type
        case amount
        case merchantName = "merchant_name"
        case platform
        case category
        case paymentMethod = "payment_method"
        case status
        case source
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
        case note
        case isLargeTransport = "is_large_transport"
        case transportType = "transport_type"
        case accountId = "account_id"
        case aiFeedback = "ai_feedback"
    }
}

private struct IncomeRow: Decodable {
    let id: String
    let createdAt: String?
    let incomeDate: String?
    let amount: Double?
    let category: String?
    let sourceName: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?
    let note: String?
    let accountId: String?
    let aiFeedback: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case incomeDate = "income_date"
        case amount
        case category
        case sourceName = "source_name"
        case source
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
        case note
        case accountId = "account_id"
        case aiFeedback = "ai_feedback"
    }
}

private struct DataRecordRow: Decodable {
    let id: String
    let createdAt: String?
    let occurredAt: String?
    let domainKey: String?
    let title: String?
    let summary: String?
    let payloadJSONB: [String: AnyCodable]?
    let sourceImagePath: String?
    let sourceImageHash: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case occurredAt = "occurred_at"
        case domainKey = "domain_key"
        case title
        case summary
        case payloadJSONB = "payload_jsonb"
        case sourceImagePath = "source_image_path"
        case sourceImageHash = "source_image_hash"
        case source
    }
}

private struct TransactionDetailRow: Decodable {
    let id: String
    let createdAt: String?
    let transactionDate: String?
    let transactionTime: String?
    let amount: Double?
    let merchantName: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let status: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?
    let note: String?
    let isLargeTransport: Bool?
    let transportType: String?
    let accountId: String?
    let aiFeedback: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case transactionDate = "transaction_date"
        case transactionTime = "transaction_time"
        case amount
        case merchantName = "merchant_name"
        case platform
        case category
        case paymentMethod = "payment_method"
        case status
        case source
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
        case note
        case isLargeTransport = "is_large_transport"
        case transportType = "transport_type"
        case accountId = "account_id"
        case aiFeedback = "ai_feedback"
    }
}

private struct IncomeDetailRow: Decodable {
    let id: String
    let createdAt: String?
    let incomeDate: String?
    let amount: Double?
    let category: String?
    let sourceName: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?
    let note: String?
    let accountId: String?
    let aiFeedback: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case incomeDate = "income_date"
        case amount
        case category
        case sourceName = "source_name"
        case source
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
        case note
        case accountId = "account_id"
        case aiFeedback = "ai_feedback"
    }
}

private struct DataRecordDetailRow: Decodable {
    let id: String
    let createdAt: String?
    let occurredAt: String?
    let domainKey: String?
    let domainVersion: String?
    let title: String?
    let summary: String?
    let payloadJSONB: [String: AnyCodable]?
    let sourceImagePath: String?
    let sourceImageHash: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case occurredAt = "occurred_at"
        case domainKey = "domain_key"
        case domainVersion = "domain_version"
        case title
        case summary
        case payloadJSONB = "payload_jsonb"
        case sourceImagePath = "source_image_path"
        case sourceImageHash = "source_image_hash"
        case source
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
    let imagePath: String?
    let imageHash: String?
    let imageType: String?
    let extractedJSON: [String: AnyCodable]?
    let companionMessage: String?
    let targetRecordId: String?

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
        case imagePath = "image_path"
        case imageHash = "image_hash"
        case imageType = "image_type"
        case extractedJSON = "extracted_json"
        case companionMessage = "companion_message"
        case targetRecordId = "target_record_id"
    }
}

private struct RPCRecordResponse: Decodable {
    let id: String
}

private struct ArchiveStagingRPCResponse: Decodable {
    let targetRecordId: String
    let targetReference: String
    let idempotentRetry: Bool

    enum CodingKeys: String, CodingKey {
        case targetRecordId = "target_record_id"
        case targetReference = "target_reference"
        case idempotentRetry = "idempotent_retry"
    }
}

private struct InsertedRecordResponse: Decodable {
    let id: String
}

private struct DataDomainRow: Decodable {
    let id: String
    let key: String
    let version: String?
}

struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            value = NSNull()
        } else if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map(\.value)
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            value = dictionary.mapValues(\.value)
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NSNull:
            try container.encodeNil()
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues(AnyCodable.init))
        default:
            try container.encode(String(describing: value))
        }
    }

    var stringValue: String? {
        value as? String
    }

    var displayValue: String {
        switch value {
        case is NSNull:
            return ""
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return String(describing: value)
        }
    }
}

extension Dictionary where Key == String, Value == AnyCodable {
    func string(_ key: String) -> String? {
        self[key]?.stringValue
    }

    func double(_ key: String) -> Double? {
        guard let value = self[key]?.value else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    func dictionary(_ key: String) -> [String: AnyCodable]? {
        guard let value = self[key]?.value else { return nil }
        if let dictionary = value as? [String: AnyCodable] { return dictionary }
        if let dictionary = value as? [String: Any] { return dictionary.mapValues(AnyCodable.init) }
        return nil
    }

    func array(_ key: String) -> [Any]? {
        self[key]?.value as? [Any]
    }
}

extension DashboardSnapshot {
    func applyingSignedImageURLs(
        _ signedURLs: [String: URL],
        markMissingAsFailure: Bool = true
    ) -> DashboardSnapshot {
        var snapshot = self
        snapshot.recordDetails = recordDetails.mapValues { detail in
            guard let path = detail.imagePath else { return detail }
            var hydrated = detail
            hydrated.imageURL = signedURLs[path]
            hydrated.imageLoadError = markMissingAsFailure && signedURLs[path] == nil
            return hydrated
        }
        snapshot.stagingRecords = stagingRecords.map { record in
            guard let path = record.imagePath else { return record }
            var hydrated = record
            hydrated.imageURL = signedURLs[path]
            hydrated.imageLoadError = markMissingAsFailure && signedURLs[path] == nil
            return hydrated
        }
        return snapshot
    }
}

private extension NativeStagingRecord {
    var archivePayload: [String: AnyCodable] {
        var payload = extracted
        payload["image_type"] = AnyCodable(recordType)
        payload["record_type"] = AnyCodable(recordType)
        payload["ai_summary"] = AnyCodable(summary)
        if let companionMessage {
            payload["companion_message"] = AnyCodable(companionMessage)
        }
        return payload
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
