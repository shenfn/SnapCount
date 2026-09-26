import Foundation

enum LocalRecordReadModel {
    static func detail(from record: LocalRecord, imageStore: LocalImageStore? = nil) -> NativeRecordDetail {
        let payload = (try? LocalRecordCodec.decode(record.payloadJSON)) ?? [:]
        let reference = "local-data/\(record.id.uuidString)"
        let subtitle = record.recordTime.map { "\(record.recordDate) \($0)" } ?? record.recordDate
        let imageURL = localImageURL(record.imagePath, imageStore: imageStore)
        let base = NativeRecordDetail(
            id: reference,
            rawId: record.id.uuidString,
            kind: "data",
            title: record.title,
            subtitle: subtitle,
            value: record.summary,
            detailRows: [],
            imageURL: imageURL,
            imageLoadError: record.imagePath != nil && imageURL == nil,
            imagePath: record.imagePath,
            imageHash: record.imageHash,
            amount: nil,
            merchantName: nil,
            platform: nil,
            category: nil,
            paymentMethod: nil,
            recordDate: record.recordDate,
            note: record.note,
            companionMessage: nil,
            accountId: nil,
            systemImage: NativeDayRecordKind(rawValue: record.domainKey)?.systemImage ?? "square.grid.2x2",
            payload: payload,
            createdAt: iso8601(record.createdAt),
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: record.recordDate,
                timeKey: record.recordTime
            ),
            transactionTime: record.recordTime,
            domainKey: record.domainKey,
            source: record.sourceKind.rawValue,
            status: "local",
            domainVersion: "local-v\(record.domainVersion)"
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

    static func groups(from month: LocalRecordMonth, imageStore: LocalImageStore? = nil) -> [NativeDayRecordGroup] {
        let grouped = Dictionary(grouping: month.records, by: \.recordDate)
        return grouped.map { dateKey, records in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: records.sorted {
                    ($0.recordTime ?? "") > ($1.recordTime ?? "")
                }.map { record in
                    let kind = NativeDayRecordKind(rawValue: record.domainKey) ?? .all
                    return NativeDayRecord(
                        id: record.id.uuidString,
                        reference: "local-data/\(record.id.uuidString)",
                        dateKey: record.recordDate,
                        kind: kind,
                        domainKey: record.domainKey,
                        title: record.title,
                        subtitle: record.summary,
                        value: "",
                        timeLabel: record.recordTime,
                        systemImage: kind.systemImage,
                        transactionType: record.domainKey,
                        status: "local"
                    )
                }
            )
        }.sorted { $0.dateKey > $1.dateKey }
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
