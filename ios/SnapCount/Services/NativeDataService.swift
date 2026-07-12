import Foundation

struct DashboardSnapshot {
    var todayCount = 0
    var pendingCount = 0
    var monthCount = 0
    var monthExpense = 0.0
    var monthIncome = 0.0
    var todayExpense = 0.0
    var todayIncome = 0.0
    var dailySummaries: [NativeDailySummary] = []
    var loadWarnings: [String] = []
    var recordDetails: [String: NativeRecordDetail] = [:]
    var recentRecords: [NativeRecordSummary] = []
    var stagingRecords: [NativeStagingRecord] = []
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
    let imageURL: URL?
    let imageLoadError: Bool
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

    var isEditable: Bool {
        kind == "expense" || kind == "income"
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
    let imageURL: URL?
    let imageLoadError: Bool
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

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        guard !AppConfig.supabaseURL.isEmpty, !AppConfig.supabaseAnonKey.isEmpty else {
            throw SupabaseRemoteError.missingConfig
        }

        async let transactionsResult = capture { try await self.fetchTransactions(accessToken: accessToken) }
        async let incomesResult = capture { try await self.fetchIncomes(accessToken: accessToken) }
        async let universalResult = capture { try await self.fetchUniversalRecords(accessToken: accessToken) }
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
        snapshot.loadWarnings = errors.map(\.localizedDescription)
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

        snapshot.recentRecords = recentRecords(
            transactions: txRows,
            incomes: incomeRows,
            universal: universalRows,
            staging: stagingRows
        )

        let visibleTransactionRows = Array(txRows.prefix(8))
        let visibleIncomeRows = Array(incomeRows.prefix(4))
        let visibleUniversalRows = Array(universalRows.prefix(6))
        let recordImagePaths = visibleTransactionRows.compactMap(\.imageURL)
            + visibleIncomeRows.compactMap(\.imageURL)
            + visibleUniversalRows.compactMap(\.sourceImagePath)
        let recordSignedURLs = (try? await signedImageURLMap(paths: recordImagePaths, accessToken: accessToken)) ?? [:]
        snapshot.recordDetails = cachedRecordDetails(
            transactions: visibleTransactionRows,
            incomes: visibleIncomeRows,
            universal: visibleUniversalRows,
            signedURLs: recordSignedURLs
        )
        snapshot.stagingRecords = stagingRows
            .filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }
            .map { stagingRecord($0, signedImageURL: nil) }

        let signedURLs = try? await signedImageURLMap(
            paths: stagingRows.compactMap(\.imagePath),
            accessToken: accessToken
        )
        if let signedURLs {
            snapshot.stagingRecords = stagingRows
                .filter { !["discarded", "archived", "assigned"].contains($0.status ?? "") }
                .map { row in
                    stagingRecord(row, signedImageURL: signedURLs[row.imagePath ?? ""])
                }
        }
        return snapshot
    }

    private func fetchTransactions(accessToken: String) async throws -> [TransactionRow] {
        try await decoded(
            [TransactionRow].self,
            path: "rest/v1/transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "id,created_at,transaction_date,transaction_time,type,amount,merchant_name,platform,category,payment_method,status,source,image_url,image_hash,companion_message,note,account_id"),
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
                URLQueryItem(name: "select", value: "id,created_at,income_date,amount,category,source_name,source,image_url,image_hash,companion_message,note,account_id"),
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
                URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary,payload_jsonb,source_image_path,source_image_hash"),
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

    func archiveStagingRecord(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String {
        let payload = record.archivePayload
        let occurredAt = payload.string("occurred_at")
            ?? payload.string("order_finished_at")
            ?? ISO8601DateFormatter().string(from: Date())

        let targetRecordId: String
        let targetDomainId: String?
        let targetReference: String

        switch domainKey {
        case "expense":
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_transaction_with_account",
                body: [
                    "p_id": AnyCodable(NSNull()),
                    "p_amount": AnyCodable(max(payload.double("amount") ?? 0.01, 0.01)),
                    "p_merchant_name": AnyCodable(payload.string("merchant_name") ?? payload.string("source_name") ?? record.title),
                    "p_platform": AnyCodable(payload.string("platform") ?? "截图识别"),
                    "p_category": AnyCodable(payload.string("category") ?? "其他"),
                    "p_payment_method": AnyCodable(payload.string("payment_method") ?? "未知"),
                    "p_transaction_date": AnyCodable(dateOnly(occurredAt)),
                    "p_transaction_time": AnyCodable(NSNull()),
                    "p_note": AnyCodable(record.summary),
                    "p_is_large_transport": AnyCodable(false),
                    "p_transport_type": AnyCodable(NSNull()),
                    "p_source": AnyCodable("ai_scan"),
                    "p_image_url": AnyCodable(nullable(record.imagePath)),
                    "p_image_hash": AnyCodable(nullable(record.imageHash)),
                    "p_companion_message": AnyCodable(nullable(record.companionMessage)),
                    "p_account_id": AnyCodable(NSNull())
                ],
                accessToken: accessToken
            )
            targetRecordId = response.id
            targetDomainId = nil
            targetReference = "expense/\(response.id)"

        case "income":
            let response = try await rpc(
                RPCRecordResponse.self,
                name: "save_income_with_account",
                body: [
                    "p_id": AnyCodable(NSNull()),
                    "p_category": AnyCodable(payload.string("income_category") ?? "other"),
                    "p_source_name": AnyCodable(payload.string("source_name") ?? payload.string("merchant_name") ?? record.title),
                    "p_amount": AnyCodable(max(payload.double("amount") ?? 0.01, 0.01)),
                    "p_income_date": AnyCodable(dateOnly(occurredAt)),
                    "p_note": AnyCodable(record.summary),
                    "p_source": AnyCodable("ai_scan"),
                    "p_image_url": AnyCodable(nullable(record.imagePath)),
                    "p_image_hash": AnyCodable(nullable(record.imageHash)),
                    "p_companion_message": AnyCodable(nullable(record.companionMessage)),
                    "p_account_id": AnyCodable(NSNull())
                ],
                accessToken: accessToken
            )
            targetRecordId = response.id
            targetDomainId = nil
            targetReference = "income/\(response.id)"

        default:
            let domain = try await fetchDataDomain(key: domainKey, accessToken: accessToken)
            let inserted = try await insertDataRecord(
                domain: domain,
                record: record,
                payload: payload,
                occurredAt: occurredAt,
                accessToken: accessToken
            )
            targetRecordId = inserted.id
            targetDomainId = domain.id
            targetReference = "data/\(inserted.id)"
        }

        try await finishStagingArchive(
            record: record,
            targetRecordId: targetRecordId,
            targetDomainId: targetDomainId,
            domainKey: domainKey,
            payload: payload,
            accessToken: accessToken
        )
        return targetReference
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
        let parts = reference.split(separator: "/").map(String.init)
        let kind: String
        let id: String
        if parts.count >= 2 {
            kind = parts[0]
            id = parts[1]
        } else if reference.hasPrefix("tx-") {
            kind = "expense"
            id = String(reference.dropFirst(3))
        } else if reference.hasPrefix("income-") {
            kind = "income"
            id = String(reference.dropFirst(7))
        } else if reference.hasPrefix("data-") {
            kind = "data"
            id = String(reference.dropFirst(5))
        } else {
            kind = "data"
            id = reference
        }

        switch kind {
        case "expense":
            let rows = try await decoded(
                [TransactionDetailRow].self,
                path: "rest/v1/transactions",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,transaction_date,transaction_time,amount,merchant_name,platform,category,payment_method,status,source,image_url,image_hash,companion_message,note,account_id"),
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
                systemImage: "creditcard"
            )

        case "income":
            let rows = try await decoded(
                [IncomeDetailRow].self,
                path: "rest/v1/income_records",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,income_date,amount,category,source_name,source,image_url,image_hash,companion_message,note,account_id"),
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
                    NativeDetailRow(label: "来源", value: row.source ?? ""),
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
                systemImage: "arrow.down.circle"
            )

        default:
            let rows = try await decoded(
                [DataRecordDetailRow].self,
                path: "rest/v1/data_records",
                queryItems: [
                    URLQueryItem(name: "select", value: "id,created_at,occurred_at,domain_key,title,summary,payload_jsonb,source_image_path,source_image_hash"),
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
                detailRows: [NativeDetailRow(label: "摘要", value: row.summary ?? "")].filter { !$0.value.isEmpty } + payloadRows,
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
                accountId: nil,
                systemImage: "sparkles"
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
                    "p_transaction_time": AnyCodable(NSNull()),
                    "p_note": AnyCodable(nullable(emptyAsNull(draft.note))),
                    "p_is_large_transport": AnyCodable(false),
                    "p_transport_type": AnyCodable(NSNull()),
                    "p_source": AnyCodable("ai_scan"),
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
                    "p_source": AnyCodable("ai_scan"),
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

    private func insertDataRecord(
        domain: DataDomainRow,
        record: NativeStagingRecord,
        payload: [String: AnyCodable],
        occurredAt: String,
        accessToken: String
    ) async throws -> InsertedRecordResponse {
        let rows = try await postJSON(
            [InsertedRecordResponse].self,
            path: "rest/v1/data_records",
            queryItems: [URLQueryItem(name: "select", value: "id")],
            body: [
                "domain_id": AnyCodable(domain.id),
                "domain_key": AnyCodable(domain.key),
                "domain_version": AnyCodable(domain.version ?? "1.0"),
                "occurred_at": AnyCodable(occurredAt),
                "title": AnyCodable(payload.string("title") ?? payload.string("summary") ?? record.title),
                "summary": AnyCodable(record.summary),
                "payload_jsonb": AnyCodable(payload.mapValues(\.value)),
                "source": AnyCodable("staging"),
                "source_image_path": AnyCodable(nullable(record.imagePath)),
                "source_image_hash": AnyCodable(nullable(record.imageHash)),
                "staging_record_id": AnyCodable(record.id)
            ],
            accessToken: accessToken
        )
        guard let row = rows.first else {
            throw SupabaseRemoteError.requestFailed("归档成功但没有返回记录 ID")
        }
        return row
    }

    private func finishStagingArchive(
        record: NativeStagingRecord,
        targetRecordId: String,
        targetDomainId: String?,
        domainKey: String,
        payload: [String: AnyCodable],
        accessToken: String
    ) async throws {
        try await patch(
            path: "rest/v1/staging_records",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(record.id)")],
            body: [
                "status": AnyCodable("archived"),
                "target_domain_id": AnyCodable(nullable(targetDomainId)),
                "target_record_id": AnyCodable(targetRecordId),
                "resolved_action": AnyCodable("archived"),
                "resolved_at": AnyCodable(ISO8601DateFormatter().string(from: Date()))
            ],
            accessToken: accessToken
        )

        _ = try? await postJSON(
            [InsertedRecordResponse].self,
            path: "rest/v1/user_routing_feedback",
            queryItems: [URLQueryItem(name: "select", value: "id")],
            body: [
                "staging_record_id": AnyCodable(record.id),
                "image_hash": AnyCodable(nullable(record.imageHash)),
                "original_domain_key": AnyCodable(nullable(record.domainKey)),
                "corrected_domain_key": AnyCodable(domainKey),
                "action": AnyCodable("archive"),
                "confidence": AnyCodable(nullable(record.confidencePercent.map { Double($0) / 100.0 })),
                "payload_jsonb": AnyCodable(payload.mapValues(\.value))
            ],
            accessToken: accessToken
        )
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

    private func cachedRecordDetails(
        transactions: [TransactionRow],
        incomes: [IncomeRow],
        universal: [DataRecordRow],
        signedURLs: [String: URL]
    ) -> [String: NativeRecordDetail] {
        var details: [String: NativeRecordDetail] = [:]
        transactions.forEach { row in
            let reference = "tx-\(row.id)"
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
                imageURL: signedURLs[row.imageURL ?? ""], imageLoadError: row.imageURL != nil && signedURLs[row.imageURL ?? ""] == nil, imagePath: row.imageURL, imageHash: row.imageHash,
                amount: row.amount, merchantName: row.merchantName, platform: row.platform, category: row.category, paymentMethod: row.paymentMethod, recordDate: row.transactionDate, note: row.note, companionMessage: row.companionMessage, accountId: row.accountId, systemImage: row.status == "pending" ? "clock" : "creditcard"
            )
        }
        incomes.forEach { row in
            let reference = "income-\(row.id)"
            details[reference] = NativeRecordDetail(
                id: reference, rawId: row.id, kind: "income", title: row.sourceName ?? "收入记录", subtitle: row.incomeDate ?? row.createdAt ?? "", value: "+\(currency(row.amount))",
                detailRows: [NativeDetailRow(label: "收入类型", value: row.category ?? "未填写"), NativeDetailRow(label: "来源", value: row.source ?? "")].filter { !$0.value.isEmpty },
                imageURL: signedURLs[row.imageURL ?? ""], imageLoadError: row.imageURL != nil && signedURLs[row.imageURL ?? ""] == nil, imagePath: row.imageURL, imageHash: row.imageHash,
                amount: row.amount, merchantName: row.sourceName, platform: nil, category: row.category, paymentMethod: nil, recordDate: row.incomeDate, note: row.note, companionMessage: row.companionMessage, accountId: row.accountId, systemImage: "arrow.down.circle"
            )
        }
        universal.forEach { row in
            let reference = "data-\(row.id)"
            let payloadRows = (row.payloadJSONB ?? [:]).filter { !$0.value.displayValue.isEmpty }.sorted { $0.key < $1.key }.prefix(12).map { NativeDetailRow(label: $0.key, value: $0.value.displayValue) }
            details[reference] = NativeRecordDetail(
                id: reference, rawId: row.id, kind: "data", title: row.title ?? domainName(row.domainKey), subtitle: row.occurredAt ?? row.createdAt ?? "", value: "",
                detailRows: [NativeDetailRow(label: "摘要", value: row.summary ?? "")].filter { !$0.value.isEmpty } + payloadRows,
                imageURL: signedURLs[row.sourceImagePath ?? ""], imageLoadError: row.sourceImagePath != nil && signedURLs[row.sourceImagePath ?? ""] == nil, imagePath: row.sourceImagePath, imageHash: row.sourceImageHash,
                amount: nil, merchantName: nil, platform: nil, category: row.domainKey, paymentMethod: nil, recordDate: row.occurredAt.map(dateOnly), note: row.summary, companionMessage: row.payloadJSONB?.string("companion_message"), accountId: nil, systemImage: "sparkles"
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

    private func stagingRecord(_ row: StagingRow, signedImageURL: URL?) -> NativeStagingRecord {
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
            systemImage: stagingSystemImage(status),
            imagePath: row.imagePath,
            imageURL: signedImageURL,
            imageLoadError: row.imagePath != nil && signedImageURL == nil,
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
        let parts = reference.split(separator: "/").map(String.init)
        if parts.count >= 2 {
            return (parts[0], parts[1])
        }
        if reference.hasPrefix("tx-") {
            return ("expense", String(reference.dropFirst(3)))
        }
        if reference.hasPrefix("income-") {
            return ("income", String(reference.dropFirst(7)))
        }
        if reference.hasPrefix("data-") {
            return ("data", String(reference.dropFirst(5)))
        }
        return ("data", reference)
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
    let accountId: String?

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
        case accountId = "account_id"
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
    let accountId: String?

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
        case accountId = "account_id"
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
    }
}

private struct DataRecordDetailRow: Decodable {
    let id: String
    let createdAt: String?
    let occurredAt: String?
    let domainKey: String?
    let title: String?
    let summary: String?
    let payloadJSONB: [String: AnyCodable]?
    let sourceImagePath: String?
    let sourceImageHash: String?

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
