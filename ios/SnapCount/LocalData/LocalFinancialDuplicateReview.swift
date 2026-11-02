import Foundation
import GRDB

/// 一次识别得到的记账事实，用于跟历史记录比对。
struct LocalFinancialDuplicateFacts {
    let recordType: String
    let amountMinor: Int64
    let merchantOrSource: String?
    let platform: String?
    let paymentMethod: String?
    let occurredAt: Date?
    /// `yyyy-MM-dd`，与库里的 `transaction_date` / `income_date` 同格式。
    let occurredDate: String?
    let perceptualHash: String?
}

/// 已存在的历史记录，作为判重候选。`referenceTable` 只用于排序优先级，
/// 取值 `expense` / `income` / `pending`，与后端 `staging_records` 优先口径相反：
/// 正式记录优先于待确认记录。
struct LocalFinancialDuplicateCandidate {
    let id: UUID
    let facts: LocalFinancialDuplicateFacts
    let referenceTable: String
    let createdAt: Date?
}

struct LocalFinancialDuplicateMatch {
    let candidate: LocalFinancialDuplicateCandidate
    let distance: Int
}

/// 复刻后端 `findLikelyFinancialDuplicate`（`duplicate-review.ts:137`）：
/// 汉明距离 ≤ 5、同记录类型、同金额、同身份、同发生时间，四关全过才算重复。
/// 判定是纯函数，不碰数据库，便于单测覆盖边界。
enum LocalFinancialDuplicateRule {
    static let maxDistance = 5
    /// 后端 `timeWindowMs` 是 10 分钟（`duplicate-review.ts:144`）。
    /// 注意后端给用户的 `detail_reason` 写的是「3 分钟内」，文案与实现不一致，这里按实现走。
    static let timeWindow: TimeInterval = 10 * 60
    /// 业务层判重的窗口（`index.ts:7546`），与感知判重的 10 分钟是两条独立规则。
    static let businessWindow: TimeInterval = 3 * 60

    private static let genericIncomeNames: Set<String> = ["income", "截图识别收入", "收入", "收入记录"]

    static func findLikelyDuplicate(
        _ current: LocalFinancialDuplicateFacts,
        candidates: [LocalFinancialDuplicateCandidate],
        maxDistance: Int = LocalFinancialDuplicateRule.maxDistance,
        timeWindow: TimeInterval = LocalFinancialDuplicateRule.timeWindow
    ) -> LocalFinancialDuplicateMatch? {
        guard let currentHash = current.perceptualHash else { return nil }

        let ranked = candidates.compactMap { candidate -> LocalFinancialDuplicateMatch? in
            guard let distance = LocalPerceptualHash.hammingDistance(
                currentHash, candidate.facts.perceptualHash
            ), distance <= maxDistance else {
                return nil
            }
            return LocalFinancialDuplicateMatch(candidate: candidate, distance: distance)
        }.sorted { left, right in
            if left.distance != right.distance { return left.distance < right.distance }
            let leftPriority = left.candidate.referenceTable == "pending" ? 1 : 0
            let rightPriority = right.candidate.referenceTable == "pending" ? 1 : 0
            if leftPriority != rightPriority { return leftPriority < rightPriority }
            return (left.candidate.createdAt ?? .distantPast) > (right.candidate.createdAt ?? .distantPast)
        }

        for match in ranked {
            let reference = match.candidate.facts
            guard reference.recordType == current.recordType else { continue }
            guard sameAmount(current.amountMinor, reference.amountMinor) else { continue }
            guard sameIdentity(current, reference) else { continue }
            guard sameOccurrence(current, reference, timeWindow: timeWindow) else { continue }
            return match
        }
        return nil
    }

    /// 复刻后端第二道判重（`index.ts:7546`）：3 分钟内、同金额、同支付方式、同商家（识别到才比）。
    /// 这一道**不阻断入库**，只给通知加「疑似 3 分钟内重复」后缀，允许用户真实的重复消费。
    /// 后端只在支出分支做，收入不判，这里保持一致。
    static func findBusinessDuplicate(
        _ current: LocalFinancialDuplicateFacts,
        candidates: [LocalFinancialDuplicateCandidate],
        now: Date,
        timeWindow: TimeInterval = LocalFinancialDuplicateRule.businessWindow
    ) -> LocalFinancialDuplicateCandidate? {
        guard current.recordType == "expense" else { return nil }
        let currentPayment = normalizedLabel(current.paymentMethod)
        guard !currentPayment.isEmpty else { return nil }
        let currentMerchant = normalizedLabel(current.merchantOrSource)

        return candidates.first { candidate in
            guard candidate.facts.recordType == "expense" else { return false }
            guard candidate.facts.occurredDate == current.occurredDate else { return false }
            guard sameAmount(current.amountMinor, candidate.facts.amountMinor) else { return false }
            guard normalizedLabel(candidate.facts.paymentMethod) == currentPayment else { return false }
            if !currentMerchant.isEmpty {
                guard normalizedLabel(candidate.facts.merchantOrSource) == currentMerchant else { return false }
            }
            if let currentTime = current.occurredAt {
                guard let referenceTime = candidate.facts.occurredAt else { return false }
                return abs(currentTime.timeIntervalSince(referenceTime)) <= timeWindow
            }
            // 没有账单时刻时后端改用录入时间（`created_at >= now - 3min`）。
            guard let createdAt = candidate.createdAt else { return false }
            return createdAt >= now.addingTimeInterval(-timeWindow)
        }
    }

    private static func sameAmount(_ current: Int64, _ reference: Int64) -> Bool {
        // 后端按元比较，容差 0.01；这里用分，等价于相差不超过 1 分。
        (current - reference).magnitude <= 1
    }

    private static func normalizedLabel(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .lowercased()
    }

    private static func sameIdentity(
        _ current: LocalFinancialDuplicateFacts,
        _ reference: LocalFinancialDuplicateFacts
    ) -> Bool {
        let currentName = normalizedLabel(current.merchantOrSource)
        let referenceName = normalizedLabel(reference.merchantOrSource)

        if current.recordType == "income" {
            if !currentName.isEmpty, !referenceName.isEmpty, currentName == referenceName { return true }
            // 收入名的占位值（如「截图识别收入」）彼此视为同一方，否则同名收入的重复永远漏判。
            return genericIncomeNames.contains(currentName) && genericIncomeNames.contains(referenceName)
        }

        if !currentName.isEmpty, !referenceName.isEmpty {
            return currentName == referenceName
        }

        let currentPlatform = normalizedLabel(current.platform)
        let referencePlatform = normalizedLabel(reference.platform)
        let currentPayment = normalizedLabel(current.paymentMethod)
        let referencePayment = normalizedLabel(reference.paymentMethod)
        return !currentPlatform.isEmpty && !referencePlatform.isEmpty && currentPlatform == referencePlatform
            && !currentPayment.isEmpty && !referencePayment.isEmpty && currentPayment == referencePayment
    }

    private static func sameOccurrence(
        _ current: LocalFinancialDuplicateFacts,
        _ reference: LocalFinancialDuplicateFacts,
        timeWindow: TimeInterval
    ) -> Bool {
        // 只有两边都带精确时间才走时间窗；否则退到同日比较，这点与后端一致。
        if let currentTime = current.occurredAt, let referenceTime = reference.occurredAt {
            return abs(currentTime.timeIntervalSince(referenceTime)) <= timeWindow
        }
        if let currentDate = current.occurredDate, let referenceDate = reference.occurredDate {
            return currentDate == referenceDate
        }
        // 两边都没有可用时间信息时后端返回 true，不做否决。
        return true
    }
}

/// 只读查本地三张表的判重候选。查询范围收在 `recordDate` 前后一天，
/// 精度判断留给 `LocalFinancialDuplicateRule`，避免 SQL 里重复一套业务规则。
final class LocalFinancialDuplicateReviewRepository {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func candidates(profileID: UUID, recordDate: String) throws -> [LocalFinancialDuplicateCandidate] {
        let (from, to) = Self.neighborDates(recordDate)
        return try database.writer.read { db in
            var result: [LocalFinancialDuplicateCandidate] = []

            result += try Self.expenseCandidates(db, profileID: profileID, from: from, to: to)
            result += try Self.incomeCandidates(db, profileID: profileID, from: from, to: to)
            result += try Self.pendingCandidates(db, profileID: profileID, from: from, to: to)
            return result
        }
    }

    private static func expenseCandidates(
        _ db: Database, profileID: UUID, from: String, to: String
    ) throws -> [LocalFinancialDuplicateCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, amount_minor, merchant_name, platform, payment_method,
                   transaction_date, transaction_time, perceptual_hash, created_at
            FROM local_expenses
            WHERE profile_id = ? AND deleted_at IS NULL AND perceptual_hash IS NOT NULL
              AND transaction_date BETWEEN ? AND ?
            """, arguments: [profileID.uuidString, from, to])
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return LocalFinancialDuplicateCandidate(
                id: id,
                facts: LocalFinancialDuplicateFacts(
                    recordType: "expense",
                    amountMinor: row["amount_minor"],
                    merchantOrSource: row["merchant_name"],
                    platform: row["platform"],
                    paymentMethod: row["payment_method"],
                    occurredAt: Self.combinedOccurrence(
                        date: row["transaction_date"], time: row["transaction_time"]
                    ),
                    occurredDate: row["transaction_date"],
                    perceptualHash: row["perceptual_hash"]
                ),
                referenceTable: "expense",
                createdAt: row["created_at"]
            )
        }
    }

    private static func incomeCandidates(
        _ db: Database, profileID: UUID, from: String, to: String
    ) throws -> [LocalFinancialDuplicateCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, amount_minor, source_name, occurred_at, income_date,
                   perceptual_hash, created_at
            FROM local_income_records
            WHERE profile_id = ? AND deleted_at IS NULL AND perceptual_hash IS NOT NULL
              AND income_date BETWEEN ? AND ?
            """, arguments: [profileID.uuidString, from, to])
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return LocalFinancialDuplicateCandidate(
                id: id,
                facts: LocalFinancialDuplicateFacts(
                    recordType: "income",
                    amountMinor: row["amount_minor"],
                    merchantOrSource: row["source_name"],
                    platform: nil,
                    paymentMethod: nil,
                    occurredAt: row["occurred_at"],
                    occurredDate: row["income_date"],
                    perceptualHash: row["perceptual_hash"]
                ),
                referenceTable: "income",
                createdAt: row["created_at"]
            )
        }
    }

    private static func pendingCandidates(
        _ db: Database, profileID: UUID, from: String, to: String
    ) throws -> [LocalFinancialDuplicateCandidate] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT id, amount_minor, merchant_name, preferred_kind, platform, payment_method,
                   occurred_at, transaction_date, transaction_time, perceptual_hash, created_at
            FROM local_pending_transactions
            WHERE profile_id = ? AND status = 'pending' AND perceptual_hash IS NOT NULL
              AND transaction_date BETWEEN ? AND ?
            """, arguments: [profileID.uuidString, from, to])
        return rows.compactMap { row in
            guard let id = UUID(uuidString: row["id"]) else { return nil }
            return LocalFinancialDuplicateCandidate(
                id: id,
                facts: LocalFinancialDuplicateFacts(
                    recordType: row["preferred_kind"] ?? "expense",
                    amountMinor: row["amount_minor"],
                    merchantOrSource: row["merchant_name"],
                    platform: row["platform"],
                    paymentMethod: row["payment_method"],
                    occurredAt: row["occurred_at"] ?? Self.combinedOccurrence(
                        date: row["transaction_date"], time: row["transaction_time"]
                    ),
                    occurredDate: row["transaction_date"],
                    perceptualHash: row["perceptual_hash"]
                ),
                referenceTable: "pending",
                createdAt: row["created_at"]
            )
        }
    }

    /// 记账表只存日期和时刻两列，拼回 `Date` 才能参与 10 分钟窗口判定。
    private static func combinedOccurrence(date: String?, time: String?) -> Date? {
        guard let date, let time, !time.isEmpty else { return nil }
        return occurrenceFormatter.date(from: "\(date) \(time)")
    }

    private static func neighborDates(_ recordDate: String) -> (String, String) {
        guard let center = dateFormatter.date(from: recordDate) else { return (recordDate, recordDate) }
        let from = Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: center) ?? center
        let to = Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: center) ?? center
        return (dateFormatter.string(from: from), dateFormatter.string(from: to))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let occurrenceFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
