import Foundation

protocol UnboundRecordRepositoryProtocol {
    func fetch(monthKey: String, accessToken: String) async throws -> [NativeUnboundRecord]
    func bind(_ record: NativeUnboundRecord, accountId: String, accessToken: String) async throws
}

final class UnboundRecordRepository: UnboundRecordRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) {
        self.remoteClient = remoteClient
    }

    func fetch(monthKey: String, accessToken: String) async throws -> [NativeUnboundRecord] {
        let range = try monthRange(monthKey)
        async let expenses = remoteClient.get(
            [UnboundExpenseRow].self,
            path: "rest/v1/transactions",
            queryItems: [
                URLQueryItem(name: "select", value: "id,amount,merchant_name,platform,category,payment_method,transaction_date,transaction_time,note,source,image_url,image_hash,companion_message"),
                URLQueryItem(name: "status", value: "eq.done"),
                URLQueryItem(name: "account_id", value: "is.null"),
                URLQueryItem(name: "transaction_date", value: "gte.\(range.start)"),
                URLQueryItem(name: "transaction_date", value: "lte.\(range.end)"),
                URLQueryItem(name: "order", value: "transaction_date.desc,transaction_time.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            accessToken: accessToken
        )
        async let incomes = remoteClient.get(
            [UnboundIncomeRow].self,
            path: "rest/v1/income_records",
            queryItems: [
                URLQueryItem(name: "select", value: "id,amount,category,source_name,income_date,note,source,image_url,image_hash,companion_message"),
                URLQueryItem(name: "account_id", value: "is.null"),
                URLQueryItem(name: "income_date", value: "gte.\(range.start)"),
                URLQueryItem(name: "income_date", value: "lte.\(range.end)"),
                URLQueryItem(name: "order", value: "income_date.desc"),
                URLQueryItem(name: "limit", value: "100")
            ],
            accessToken: accessToken
        )

        let expenseRows = try await expenses
        let incomeRows = try await incomes
        let records = expenseRows.map(\.native) + incomeRows.map(\.native)
        return records.sorted {
            if $0.date == $1.date { return $0.id > $1.id }
            return $0.date > $1.date
        }
    }

    func bind(_ record: NativeUnboundRecord, accountId: String, accessToken: String) async throws {
        switch record.kind {
        case .expense:
            _ = try await remoteClient.rpc(
                BoundRecordResponse.self,
                name: "save_transaction_with_account",
                body: [
                    "p_id": AnyCodable(record.id),
                    "p_amount": AnyCodable(record.amount),
                    "p_merchant_name": AnyCodable(record.title),
                    "p_platform": AnyCodable(nullable(record.platform)),
                    "p_category": AnyCodable(nullable(record.category)),
                    "p_payment_method": AnyCodable(nullable(record.paymentMethod)),
                    "p_transaction_date": AnyCodable(record.date),
                    "p_transaction_time": AnyCodable(nullable(record.time)),
                    "p_note": AnyCodable(nullable(record.note)),
                    "p_is_large_transport": AnyCodable(record.category == "transport" && record.amount >= 200),
                    "p_transport_type": AnyCodable(NSNull()),
                    "p_source": AnyCodable(nullable(record.source)),
                    "p_image_url": AnyCodable(nullable(record.imagePath)),
                    "p_image_hash": AnyCodable(nullable(record.imageHash)),
                    "p_companion_message": AnyCodable(nullable(record.companionMessage)),
                    "p_account_id": AnyCodable(accountId)
                ],
                accessToken: accessToken
            )
        case .income:
            _ = try await remoteClient.rpc(
                BoundRecordResponse.self,
                name: "save_income_with_account",
                body: [
                    "p_id": AnyCodable(record.id),
                    "p_category": AnyCodable(record.category ?? "other"),
                    "p_source_name": AnyCodable(record.title),
                    "p_amount": AnyCodable(record.amount),
                    "p_income_date": AnyCodable(record.date),
                    "p_note": AnyCodable(nullable(record.note)),
                    "p_source": AnyCodable(nullable(record.source)),
                    "p_image_url": AnyCodable(nullable(record.imagePath)),
                    "p_image_hash": AnyCodable(nullable(record.imageHash)),
                    "p_companion_message": AnyCodable(nullable(record.companionMessage)),
                    "p_account_id": AnyCodable(accountId)
                ],
                accessToken: accessToken
            )
        }
    }

    private func monthRange(_ monthKey: String) throws -> (start: String, end: String) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: monthKey + "-01"),
              let nextMonth = Calendar(identifier: .gregorian).date(byAdding: .month, value: 1, to: start),
              let end = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: nextMonth) else {
            throw SupabaseRemoteError.requestFailed("月份格式无效")
        }
        return (formatter.string(from: start), formatter.string(from: end))
    }

    private func nullable(_ value: String?) -> Any {
        guard let value, !value.isEmpty, value != "?" else { return NSNull() }
        return value
    }
}

private struct BoundRecordResponse: Decodable { let id: String }

private struct UnboundExpenseRow: Decodable {
    let id: String
    let amount: Double?
    let merchantName: String?
    let platform: String?
    let category: String?
    let paymentMethod: String?
    let transactionDate: String?
    let transactionTime: String?
    let note: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, platform, category, note, source
        case merchantName = "merchant_name"
        case paymentMethod = "payment_method"
        case transactionDate = "transaction_date"
        case transactionTime = "transaction_time"
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
    }

    var native: NativeUnboundRecord {
        NativeUnboundRecord(
            id: id, kind: .expense, title: merchantName ?? "未命名支出", amount: amount ?? 0,
            date: transactionDate ?? "", time: transactionTime, platform: platform, category: category,
            paymentMethod: paymentMethod, note: note, source: source, imagePath: imageURL,
            imageHash: imageHash, companionMessage: companionMessage
        )
    }
}

private struct UnboundIncomeRow: Decodable {
    let id: String
    let amount: Double?
    let category: String?
    let sourceName: String?
    let incomeDate: String?
    let note: String?
    let source: String?
    let imageURL: String?
    let imageHash: String?
    let companionMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, amount, category, note, source
        case sourceName = "source_name"
        case incomeDate = "income_date"
        case imageURL = "image_url"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
    }

    var native: NativeUnboundRecord {
        NativeUnboundRecord(
            id: id, kind: .income, title: sourceName ?? "未命名收入", amount: amount ?? 0,
            date: incomeDate ?? "", time: nil, platform: nil, category: category,
            paymentMethod: nil, note: note, source: source, imagePath: imageURL,
            imageHash: imageHash, companionMessage: companionMessage
        )
    }
}
