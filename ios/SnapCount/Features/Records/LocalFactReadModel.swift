import Foundation

enum LocalFactReadModel {
    static func groups(
        from month: LocalFactMonth,
        including kinds: Set<LocalFactKind>? = nil
    ) -> [NativeDayRecordGroup] {
        let facts = month.facts.filter { kinds?.contains($0.kind) ?? true }
        let grouped = Dictionary(grouping: facts, by: \.businessDate)
        return grouped.map { dateKey, facts in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: facts.sorted(by: isNewer).map { fact in
                    let kind: NativeDayRecordKind
                    let value: String
                    let domainKey: String?
                    if fact.kind == .expense {
                        kind = .expense
                        value = expenseValue(from: fact)
                        domainKey = nil
                    } else {
                        kind = NativeDayRecordKind(rawValue: fact.domainKey) ?? .all
                        value = ""
                        domainKey = fact.domainKey
                    }
                    return NativeDayRecord(
                        id: fact.id.uuidString,
                        reference: fact.reference,
                        dateKey: fact.businessDate,
                        kind: kind,
                        domainKey: domainKey,
                        title: fact.title,
                        subtitle: fact.summary,
                        value: value,
                        timeLabel: fact.recordTime,
                        systemImage: kind == .expense ? "creditcard" : kind.systemImage,
                        transactionType: fact.domainKey,
                        status: "local"
                    )
                }
            )
        }.sorted { $0.dateKey > $1.dateKey }
    }

    static func details(
        from month: LocalFactMonth,
        imageStore: LocalImageStore? = nil
    ) -> [String: NativeRecordDetail] {
        Dictionary(uniqueKeysWithValues: month.facts.map { fact in
            let detail = detail(from: fact, imageStore: imageStore)
            return (detail.id, detail)
        })
    }

    static func detail(
        from fact: LocalFact,
        imageStore: LocalImageStore? = nil
    ) -> NativeRecordDetail {
        let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
        let amount = fact.kind == .expense
            ? payload.double("amount_minor").map { $0 / 100 }
            : nil
        let imageURL = localImageURL(fact.imagePath, imageStore: imageStore)
        let base = NativeRecordDetail(
            id: fact.reference,
            rawId: fact.id.uuidString,
            kind: fact.kind == .expense ? "expense" : "data",
            title: fact.title,
            subtitle: fact.recordTime.map { "\(fact.businessDate) \($0)" } ?? fact.businessDate,
            value: fact.kind == .expense ? expenseValue(from: fact) : fact.summary,
            detailRows: [],
            imageURL: imageURL,
            imageLoadError: fact.imagePath != nil && imageURL == nil,
            imagePath: fact.imagePath,
            imageHash: fact.imageHash,
            amount: amount,
            merchantName: fact.kind == .expense ? fact.title : nil,
            platform: payload.string("platform"),
            category: fact.kind == .expense ? payload.string("category") : nil,
            paymentMethod: payload.string("payment_method"),
            recordDate: fact.businessDate,
            note: fact.note,
            companionMessage: nil,
            accountId: payload.string("account_id"),
            systemImage: fact.kind == .expense
                ? "creditcard"
                : NativeDayRecordKind(rawValue: fact.domainKey)?.systemImage ?? "square.grid.2x2",
            payload: payload,
            createdAt: iso8601(fact.createdAt),
            occurredAt: fact.occurredAt,
            transactionTime: fact.recordTime,
            domainKey: fact.kind == .expense ? nil : fact.domainKey,
            source: fact.sourceKind,
            status: "local",
            domainVersion: fact.domainVersion
        )
        return NativeRecordDetail(
            id: base.id,
            rawId: base.rawId,
            kind: base.kind,
            title: base.title,
            subtitle: base.subtitle,
            value: base.value,
            detailRows: NativeRecordDetailPresentationAdapter.extractedRows(for: base),
            imageURL: base.imageURL,
            imageLoadError: base.imageLoadError,
            imagePath: base.imagePath,
            imageHash: base.imageHash,
            amount: base.amount,
            merchantName: base.merchantName,
            platform: base.platform,
            category: base.category,
            paymentMethod: base.paymentMethod,
            recordDate: base.recordDate,
            note: base.note,
            companionMessage: base.companionMessage,
            accountId: base.accountId,
            systemImage: base.systemImage,
            payload: base.payload,
            createdAt: base.createdAt,
            occurredAt: base.occurredAt,
            transactionTime: base.transactionTime,
            domainKey: base.domainKey,
            source: base.source,
            status: base.status,
            domainVersion: base.domainVersion
        )
    }

    private static func expenseValue(from fact: LocalFact) -> String {
        let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
        let amount = (payload.double("amount_minor") ?? 0) / 100
        return String(format: "¥%.2f", amount)
    }

    private static func isNewer(_ lhs: LocalFact, _ rhs: LocalFact) -> Bool {
        if lhs.recordTime != rhs.recordTime {
            return (lhs.recordTime ?? "") > (rhs.recordTime ?? "")
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private static func localImageURL(_ path: String?, imageStore: LocalImageStore?) -> URL? {
        guard let path, let imageStore, imageStore.contains(path: path) else { return nil }
        return imageStore.url(for: path)
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
