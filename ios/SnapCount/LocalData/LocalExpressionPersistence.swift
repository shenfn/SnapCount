import Foundation
import GRDB

struct LocalExpressionSettings: Equatable {
    let companionEnabled: Bool
    let memoryEnabled: Bool
}

/// Persists deterministic Planner output after a local fact write.
///
/// This is deliberately best-effort: a failed expression refresh never changes
/// the result of the fact transaction. Provider output can be added later and
/// remains separate from this local deterministic fallback.
final class LocalExpressionPersistence {
    private static let projectionSourceTable = "local_expression_projection"
    private static let projectionWindowDays = 30
    private static let plannerRecentFactLimit = 12

    private let database: LocalDatabase
    private let memoryRepository: LocalCompanionMemoryRepository
    private let factReader: LocalFactReader?
    private let settingsProvider: () -> LocalExpressionSettings

    init(
        database: LocalDatabase,
        memoryRepository: LocalCompanionMemoryRepository? = nil,
        settingsProvider: @escaping () -> LocalExpressionSettings = {
            let settings = LocalUserSettingsStore().load()
            return LocalExpressionSettings(
                companionEnabled: settings.companionEnabled,
                memoryEnabled: settings.companionMemoryEnabled
            )
        }
    ) {
        self.database = database
        self.memoryRepository = memoryRepository ?? LocalCompanionMemoryRepository(database: database)
        self.factReader = try? LocalFactReader(database: database)
        self.settingsProvider = settingsProvider
    }

    func refresh(record: LocalRecord) {
        refreshMemoryProjection(profileID: record.profileID)
        guard let feedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: record.id.uuidString,
                domainKey: record.domainKey,
                title: record.title,
                summary: record.summary,
                recordDate: record.businessDate,
                recordTime: record.recordTime,
                amount: nil,
                category: nil
            ),
            profileID: record.profileID
        ) else { return }
        do {
            var payload = (try? LocalRecordCodec.decode(record.payloadJSON)) ?? [:]
            let feedbackPayload = feedback.localPayload.mapValues(\.value)
            payload["planner_ai_feedback"] = AnyCodable(feedbackPayload)
            if payload.dictionary("ai_feedback") == nil {
                payload["ai_feedback"] = AnyCodable(feedbackPayload)
            }
            let payloadJSON = try LocalRecordCodec.encode(payload)
            try database.writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE local_records
                        SET payload_json = ?
                        WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [payloadJSON, record.id.uuidString, record.profileID.uuidString]
                )
            }
        } catch {
            return
        }
    }

    func refresh(staging: LocalStagingRecord) {
        guard let feedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: staging.id,
                domainKey: staging.domainKey,
                title: staging.title,
                summary: staging.summary,
                recordDate: staging.recordDate,
                recordTime: staging.recordTime,
                amount: ((try? LocalRecordCodec.decode(staging.payloadJSON)) ?? [:])
                    .double("amount_minor")
                    .map { $0 / 100 },
                category: ((try? LocalRecordCodec.decode(staging.payloadJSON)) ?? [:])
                    .string("category")
            ),
            profileID: staging.profileID
        ) else { return }
        do {
            var payload = (try? LocalRecordCodec.decode(staging.payloadJSON)) ?? [:]
            guard payload.dictionary("ai_feedback") == nil else { return }
            payload["ai_feedback"] = AnyCodable(feedback.localPayload.mapValues(\.value))
            let payloadJSON = try LocalRecordCodec.encode(payload)
            try database.writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE local_staging_records
                        SET payload_json = ?
                        WHERE id = ? AND profile_id = ? AND status = 'pending_review'
                        """,
                    arguments: [payloadJSON, staging.id, staging.profileID.uuidString]
                )
            }
        } catch {
            return
        }
    }

    func refresh(expense: LocalExpense) {
        refreshMemoryProjection(profileID: expense.profileID)
        guard let feedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: expense.id.uuidString,
                domainKey: "expense",
                title: expense.merchantName,
                summary: expense.category,
                recordDate: expense.transactionDate,
                recordTime: expense.transactionTime,
                amount: Double(expense.amountMinor) / 100,
                category: expense.category
            ),
            profileID: expense.profileID
        ) else { return }
        persistFinancialFeedback(
            table: "local_expenses",
            id: expense.id,
            profileID: expense.profileID,
            existingJSON: expense.aiFeedbackJSON,
            feedback: feedback
        )
    }

    func refresh(income: LocalIncome) {
        refreshMemoryProjection(profileID: income.profileID)
        guard let feedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: income.id.uuidString,
                domainKey: "income",
                title: income.sourceName,
                summary: income.category,
                recordDate: income.incomeDate,
                recordTime: income.occurredAt.map { NativeLocalDate.timeKey($0) },
                amount: Double(income.amountMinor) / 100,
                category: income.category
            ),
            profileID: income.profileID
        ) else { return }
        persistFinancialFeedback(
            table: "local_income_records",
            id: income.id,
            profileID: income.profileID,
            existingJSON: income.aiFeedbackJSON,
            feedback: feedback
        )
    }

    func refresh(wallet: LocalWalletSnapshot) {
        guard let feedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: wallet.id.uuidString,
                domainKey: "wallet",
                title: wallet.title,
                summary: wallet.summary,
                recordDate: wallet.recordDate,
                recordTime: wallet.recordTime,
                amount: wallet.balance,
                category: nil
            ),
            profileID: wallet.profileID
        ) else { return }
        do {
            var payload = (try? LocalRecordCodec.decode(wallet.payloadJSON)) ?? [:]
            payload["planner_ai_feedback"] = AnyCodable(feedback.localPayload.mapValues(\.value))
            if payload.dictionary("ai_feedback") == nil {
                payload["ai_feedback"] = AnyCodable(feedback.localPayload.mapValues(\.value))
            }
            let payloadJSON = try LocalRecordCodec.encode(payload)
            try database.writer.write { db in
                try db.execute(
                    sql: """
                        UPDATE local_wallet_snapshots
                        SET payload_json = ?
                        WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                        """,
                    arguments: [payloadJSON, wallet.id.uuidString, wallet.profileID.uuidString]
                )
            }
        } catch {
            return
        }
    }

    /// Adds a deterministic feedback payload before a pending financial row is
    /// staged or converted, so the same payload follows the fact into its
    /// formal expense or income row.
    func enrich(pending: LocalPendingFinancialRecord) -> LocalPendingFinancialRecord {
        guard let plannerFeedback = plannerFeedback(
            fact: LocalExpressionFact(
                id: pending.id.uuidString,
                domainKey: pending.preferredKind == .income ? "income" : "expense",
                title: pending.merchantName,
                summary: pending.category ?? pending.incomeCategory ?? "",
                recordDate: pending.transactionDate,
                recordTime: pending.transactionTime,
                amount: Double(pending.amountMinor) / 100,
                category: pending.category ?? pending.incomeCategory
            ),
            profileID: pending.profileID
        ) else { return pending }
        guard let existing = pending.aiFeedbackJSON,
              let payload = LocalPendingFinancialRepository.feedbackPayload(from: existing),
              let existingFeedback = NativeAIFeedback(payload: payload),
              existingFeedback.source != "expression_planner" else {
            var enriched = pending
            enriched.aiFeedbackJSON = encode(plannerFeedback.localPayload)
            return enriched
        }
        return pending
    }

    /// Persists a provider result without touching the Planner fallback. The
    /// raw prompt and raw provider response are never stored.
    func persist(companion result: LocalCompanionResult, for detail: NativeRecordDetail) {
        let settings = settingsProvider()
        guard settings.companionEnabled else { return }
        let message: String?
        if let candidate = result.companionMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
           !candidate.isEmpty {
            message = candidate
        } else {
            message = nil
        }
        let feedbackJSON = result.aiFeedback.flatMap(encode)
        guard message != nil || feedbackJSON != nil else { return }
        do {
            switch detail.kind {
            case "expense", "income":
                let table = detail.kind == "expense" ? "local_expenses" : "local_income_records"
                try database.writer.write { db in
                    try db.execute(
                        sql: """
                            UPDATE \(table)
                            SET companion_message = COALESCE(?, companion_message),
                                ai_feedback = COALESCE(?, ai_feedback)
                            WHERE id = ? AND profile_id = (
                                SELECT profile_id FROM \(table) WHERE id = ? AND deleted_at IS NULL
                            ) AND deleted_at IS NULL
                            """,
                        arguments: [message, feedbackJSON, detail.rawId, detail.rawId]
                    )
                }
            case "data", "wallet":
                var payload = detail.payload ?? [:]
                if let message {
                    payload["companion_message"] = AnyCodable(message)
                }
                if let feedbackJSON,
                   let data = feedbackJSON.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    payload["ai_feedback"] = AnyCodable(object)
                }
                let payloadJSON = try LocalRecordCodec.encode(payload)
                if detail.kind == "wallet" {
                    try database.writer.write { db in
                        try db.execute(
                            sql: "UPDATE local_wallet_snapshots SET payload_json = ? WHERE id = ? AND deleted_at IS NULL",
                            arguments: [payloadJSON, detail.rawId]
                        )
                    }
                } else {
                    try database.writer.write { db in
                        try db.execute(
                            sql: "UPDATE local_records SET payload_json = ? WHERE id = ? AND deleted_at IS NULL",
                            arguments: [payloadJSON, detail.rawId]
                        )
                    }
                }
            default:
                return
            }
        } catch {
            return
        }
    }

    func deleteSource(sourceTable: String, sourceID: String, profileID: UUID) {
        let settings = settingsProvider()
        _ = try? memoryRepository.deleteSource(sourceTable: sourceTable, sourceID: sourceID, profileID: profileID)
        if settings.memoryEnabled {
            refreshMemoryProjection(profileID: profileID)
        }
    }

    private func plannerFeedback(fact: LocalExpressionFact, profileID: UUID) -> NativeAIFeedback? {
        let settings = settingsProvider()
        guard settings.companionEnabled else { return nil }
        let memoryContext = settings.memoryEnabled
            ? try? memoryRepository.compactContextJSON(profileID: profileID, domainKey: fact.domainKey)
            : nil
        return LocalPlannerCandidateEngine.selectedCandidate(
            for: fact,
            memoryContextJSON: memoryContext
        )
    }

    private func persistFinancialFeedback(
        table: String,
        id: UUID,
        profileID: UUID,
        existingJSON: String?,
        feedback: NativeAIFeedback
    ) {
        if let existingJSON,
           let payload = LocalPendingFinancialRepository.feedbackPayload(from: existingJSON),
           let existing = NativeAIFeedback(payload: payload),
           existing.source != "expression_planner" {
            return
        }
        guard let json = encode(feedback.localPayload) else { return }
        try? database.writer.write { db in
            try db.execute(
                sql: "UPDATE \(table) SET ai_feedback = ? WHERE id = ? AND profile_id = ? AND deleted_at IS NULL",
                arguments: [json, id.uuidString, profileID.uuidString]
            )
        }
    }

    func refreshMemoryProjection(profileID: UUID) {
        let settings = settingsProvider()
        guard settings.memoryEnabled,
              let factReader,
              let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -Self.projectionWindowDays, to: Date()) else {
            return
        }
        let endDate = NativeLocalDate.dateKey(Date())
        let startDate = NativeLocalDate.dateKey(start)
        guard let month = try? factReader.range(
            profileID: profileID,
            from: startDate,
            to: endDate
        ) else { return }

        let now = Date()
        let sourceID = profileID.uuidString
        let drafts = Self.projectionDrafts(
            facts: month.facts,
            profileID: profileID,
            sourceID: sourceID,
            now: now
        )
        do {
            _ = try memoryRepository.deleteSource(
                sourceTable: Self.projectionSourceTable,
                sourceID: sourceID,
                profileID: profileID,
                at: now
            )
        } catch {
            return
        }
        for draft in drafts {
            _ = try? memoryRepository.upsert(draft)
        }
    }

    /// Builds the one-record Companion request context. Memory reads and recent
    /// line reads are kept behind both the persisted consent and the current
    /// settings snapshot so an off toggle cannot leak context through a caller.
    func makeCompositionContext(
        for detail: NativeRecordDetail,
        profileID: UUID,
        settings: NativeUserSettings,
        providerMode: LocalExpressionProviderMode,
        now: Date = Date()
    ) -> LocalExpressionContext? {
        let persistedSettings = settingsProvider()
        guard settings.companionEnabled, persistedSettings.companionEnabled else { return nil }
        let memoryEnabled = settings.companionMemoryEnabled && persistedSettings.memoryEnabled
        var memoryContextJSON: String?
        var recentLines: [String] = []
        if memoryEnabled {
            refreshMemoryProjection(profileID: profileID)
            memoryContextJSON = try? memoryRepository.compactContextJSON(
                profileID: profileID,
                domainKey: detail.domainKey ?? detail.kind
            )
            recentLines = (try? memoryRepository.recentCompanionLines(
                profileID: profileID,
                domainKey: detail.domainKey ?? detail.kind,
                limit: 5,
                now: now
            )) ?? []
        }
        let recentFacts = recentFormalFacts(
            profileID: profileID,
            currentFactID: detail.rawId,
            domainKey: detail.domainKey ?? detail.kind,
            now: now
        )
        return LocalPlannerCandidateEngine.makeContext(
            for: detail,
            recentFacts: recentFacts,
            memoryContextJSON: memoryContextJSON,
            providerMode: providerMode,
            expressionPreferences: LocalCompanionExpressionPreferences(settings: settings),
            recentCompanionLines: recentLines,
            now: now
        )
    }

    private func recentFormalFacts(
        profileID: UUID,
        currentFactID: String,
        domainKey: String,
        now: Date
    ) -> [LocalExpressionFact] {
        guard let factReader,
              let start = Calendar(identifier: .gregorian).date(byAdding: .day, value: -Self.projectionWindowDays, to: now) else {
            return []
        }
        let startDate = NativeLocalDate.dateKey(start)
        let endDate = NativeLocalDate.dateKey(now)
        guard let facts = try? factReader.range(profileID: profileID, from: startDate, to: endDate).facts else {
            return []
        }
        return facts
            .filter { $0.id.uuidString != currentFactID && $0.domainKey == domainKey }
            .prefix(Self.plannerRecentFactLimit)
            .map(LocalExpressionFact.init(fact:))
    }

    private static func projectionDrafts(
        facts: [LocalFact],
        profileID: UUID,
        sourceID: String,
        now: Date
    ) -> [LocalCompanionMemoryDraft] {
        let grouped = Dictionary(grouping: facts, by: \.domainKey)
        let domains = ["expense", "income", "food", "sleep", "sport", "reading"]
        let aggregateDrafts: [LocalCompanionMemoryDraft] = domains.compactMap { domain -> LocalCompanionMemoryDraft? in
            guard let domainFacts = grouped[domain], !domainFacts.isEmpty else { return nil }
            let count = domainFacts.count
            let totalMinor = domain == "expense" || domain == "income"
                ? domainFacts.reduce(Int64(0)) { $0 + amountMinor(from: $1) }
                : 0
            let value: String
            if domain == "expense" || domain == "income" {
                let amount = String(format: "¥%.2f", Double(totalMinor) / 100)
                let label = domain == "expense" ? "消费" : "收入"
                value = "近30天有\(count)条\(label)记录，合计\(amount)。"
            } else {
                value = "近30天有\(count)条\(domainLabel(domain))记录。"
            }
            let content: [String: Any] = [
                "value": value,
                "count": count,
                "window_days": projectionWindowDays
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: content, options: [.sortedKeys]),
                  let contentJSON = String(data: data, encoding: .utf8) else { return nil }
            return LocalCompanionMemoryDraft(
                id: UUID(),
                profileID: profileID,
                memoryKey: "local_ai.\(domain).recent_30d",
                memoryType: "derived_trend",
                contentJSON: contentJSON,
                sourceTable: projectionSourceTable,
                sourceID: sourceID,
                confidence: min(0.9, 0.55 + Double(count) / 20),
                createdAt: now,
                updatedAt: now
            )
        }
        let patternDrafts = ["expense", "income"].flatMap { domain in
            recurringFinancialPatternDrafts(
                facts: grouped[domain] ?? [],
                domain: domain,
                profileID: profileID,
                sourceID: sourceID,
                now: now
            )
        }
        return aggregateDrafts + patternDrafts
    }

    private static func recurringFinancialPatternDrafts(
        facts: [LocalFact],
        domain: String,
        profileID: UUID,
        sourceID: String,
        now: Date
    ) -> [LocalCompanionMemoryDraft] {
        guard !facts.isEmpty else { return [] }
        var values: [(type: String, entity: String, count: Int)] = []
        let entities = [
            (type: "merchant", values: Dictionary(grouping: facts, by: { canonical($0.title) })),
            (type: "category", values: Dictionary(grouping: facts, by: { fact in
                let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                return canonical(payload.string("category") ?? payload.string("income_category") ?? "")
            }))
        ]
        for entityGroup in entities {
            for (key, group) in entityGroup.values where !key.isEmpty && group.count >= 2 {
                guard let display = entityGroup.type == "merchant"
                    ? group.first?.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    : group.first.flatMap({ fact in
                        let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                        return payload.string("category") ?? payload.string("income_category")
                    }) else { continue }
                guard display.count >= 2, !isGenericEntity(display, domain: domain) else { continue }
                values.append((entityGroup.type, display, group.count))
            }
        }
        return values
            .sorted { left, right in
                left.count == right.count
                    ? (left.type, canonical(left.entity)) < (right.type, canonical(right.entity))
                    : left.count > right.count
            }
            .prefix(4)
            .compactMap { item in
                let normalizedEntity = canonical(item.entity)
                let digest = LocalImageStore.sha256(Data(normalizedEntity.utf8)).prefix(16)
                let confidence = min(0.95, 0.65 + Double(max(0, item.count - 1)) * 0.08)
                let display = String(item.entity.prefix(40))
                let summary = item.type == "merchant"
                    ? "近30天在「\(display)」有重复\(domain == "income" ? "收入" : "消费")记录。"
                    : "近30天「\(display)」类别多次出现在\(domain == "income" ? "收入" : "消费")记录中。"
                let content: [String: Any] = [
                    "value": summary,
                    "entity_type": item.type,
                    "entity_value": display,
                    "sample_count": item.count,
                    "window_days": projectionWindowDays
                ]
                guard let data = try? JSONSerialization.data(withJSONObject: content, options: [.sortedKeys]),
                      let contentJSON = String(data: data, encoding: .utf8) else { return nil }
                return LocalCompanionMemoryDraft(
                    id: UUID(),
                    profileID: profileID,
                    memoryKey: "local_ai.\(domain).\(item.type)_repeat.\(digest)",
                    memoryType: item.type == "merchant" ? "merchant_pattern" : "category_pattern",
                    contentJSON: contentJSON,
                    sourceTable: projectionSourceTable,
                    sourceID: sourceID,
                    confidence: confidence,
                    createdAt: now,
                    updatedAt: now
                )
            }
    }

    private static func canonical(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .filter { !$0.isWhitespace && !$0.isPunctuation }
    }

    private static func isGenericEntity(_ value: String, domain: String) -> Bool {
        let normalized = canonical(value)
        let generic = ["expense", "income", "支出", "收入", "其他", "无分类", "未分类", "unknown"]
        return generic.contains(normalized) || normalized == canonical(domainLabel(domain))
    }

    private static func amountMinor(from fact: LocalFact) -> Int64 {
        let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
        return Int64((payload.double("amount_minor") ?? 0).rounded())
    }

    private static func domainLabel(_ domain: String) -> String {
        switch domain {
        case "food": return "饮食"
        case "sleep": return "睡眠"
        case "sport": return "运动"
        case "reading": return "阅读"
        default: return "本地"
        }
    }

    private func encode(_ payload: [String: AnyCodable]) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
