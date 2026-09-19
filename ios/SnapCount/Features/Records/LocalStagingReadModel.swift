import Foundation

enum LocalStagingReadModel {
    static let idPrefix = "local-staging/"

    static func native(
        from record: LocalStagingRecord,
        imageStore: LocalImageStore?,
        domainName: String? = nil
    ) -> NativeStagingRecord {
        let payload = (try? LocalRecordCodec.decode(record.payloadJSON)) ?? [:]
        let occurredAt = NativeLocalDate.financeOccurredAt(
            dateKey: record.recordDate,
            timeKey: record.recordTime
        )
        let createdAt = iso8601(record.createdAt)
        let imageURL = localImageURL(record.imagePath, imageStore: imageStore)

        return NativeStagingRecord(
            id: id(for: record.id),
            dateKey: record.recordDate,
            title: record.title,
            summary: record.summary,
            status: record.status.rawValue,
            statusLabel: statusLabel(for: record.status),
            recordTypeLabel: "本地候选",
            createdAtLabel: NativeLocalDate.dateTimeLabel(createdAt) ?? record.recordDate,
            occurredAtLabel: occurredAt.flatMap(NativeLocalDate.dateTimeLabel),
            confidencePercent: record.confidence.map { max(0, min(100, Int(($0 * 100).rounded()))) },
            lastErrorMessage: record.status == .failed ? "本地候选处理失败" : nil,
            retryCount: 0,
            systemImage: NativeDayRecordKind(rawValue: record.domainKey)?.systemImage ?? "sparkles",
            imagePath: record.imagePath,
            imageURL: imageURL,
            imageLoadError: record.imagePath != nil && imageURL == nil,
            recordType: "local_candidate",
            domainKey: record.domainKey,
            domainName: domainName ?? fallbackDomainName(for: record.domainKey),
            extracted: payload,
            companionMessage: nil,
            targetRecordId: record.targetRecordID?.uuidString,
            imageHash: record.imageHash
        )
    }

    static func id(for localID: String) -> String {
        idPrefix + localID
    }

    static func localID(from nativeID: String) -> String? {
        guard nativeID.hasPrefix(idPrefix) else { return nil }
        return String(nativeID.dropFirst(idPrefix.count))
    }

    private static func localImageURL(_ path: String?, imageStore: LocalImageStore?) -> URL? {
        guard let path, let imageStore, imageStore.contains(path: path) else { return nil }
        return imageStore.url(for: path)
    }

    private static func statusLabel(for status: LocalStagingRecordStatus) -> String {
        switch status {
        case .pendingReview: return "待确认"
        case .archived: return "已归档"
        case .discarded: return "已销毁"
        case .failed: return "处理失败"
        }
    }

    private static func fallbackDomainName(for domainKey: String) -> String {
        switch domainKey {
        case "food": return "饮食"
        case "sleep": return "睡眠"
        case "sport": return "运动"
        case "reading": return "阅读"
        default: return "本地记录"
        }
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}
