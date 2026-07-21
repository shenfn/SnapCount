import Foundation

enum NativeInboxItemKind: String {
    case pendingExpense
    case staging
}

enum NativeInboxFilter: String, CaseIterable, Identifiable {
    case all
    case pendingExpense
    case failed
    case repair
    case routing
    case review

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .pendingExpense: return "待补全账单"
        case .failed: return "需重试"
        case .repair: return "待修补"
        case .routing: return "待分类"
        case .review: return "待确认"
        }
    }
}

struct NativePendingExpense: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let dateKey: String
    let reference: String
    let imagePath: String?
    var imageURL: URL?
    var imageLoadError: Bool
    let occurredAtLabel: String?
    let createdAtLabel: String

    init(
        id: String,
        title: String,
        amount: Double,
        dateKey: String,
        reference: String,
        imagePath: String? = nil,
        imageURL: URL? = nil,
        imageLoadError: Bool = false,
        occurredAtLabel: String? = nil,
        createdAtLabel: String = "最近上传"
    ) {
        self.id = id
        self.title = title
        self.amount = amount
        self.dateKey = dateKey
        self.reference = reference
        self.imagePath = imagePath
        self.imageURL = imageURL
        self.imageLoadError = imageLoadError
        self.occurredAtLabel = occurredAtLabel
        self.createdAtLabel = createdAtLabel
    }
}

struct NativeInboxItem: Identifiable {
    let id: String
    let kind: NativeInboxItemKind
    let dateKey: String
    let title: String
    let subtitle: String
    let status: String
    let statusLabel: String
    let systemImage: String
    let pendingExpense: NativePendingExpense?
    let stagingRecord: NativeStagingRecord?
}

struct NativeInboxSection: Identifiable {
    let id: String
    let title: String
    let items: [NativeInboxItem]
}

enum NativeInboxPresentation {
    private static let failedStatuses = ["ai_error", "failed", "extraction_failed"]
    private static let repairStatuses = ["schema_failed"]
    private static let routingStatuses = ["routing_failed", "unrouted", "unassigned"]
    private static let reviewStatuses = ["pending_review", "routed", "extracted"]
    private static let resolvedStatuses = ["confirmed", "archived", "discarded", "assigned"]

    static func items(pendingExpenses: [NativePendingExpense], stagingRecords: [NativeStagingRecord]) -> [NativeInboxItem] {
        let pendingItems = pendingExpenses.map { pending in
            NativeInboxItem(
                id: "pending-\(pending.id)", kind: .pendingExpense, dateKey: pending.dateKey,
                title: pending.title, subtitle: String(format: "¥%.2f", pending.amount),
                status: "pending", statusLabel: "待补全", systemImage: "clock.badge.exclamationmark",
                pendingExpense: pending, stagingRecord: nil
            )
        }
        let stagingItems = stagingRecords.filter { !resolvedStatuses.contains($0.status) }.map { record in
            NativeInboxItem(
                id: "staging-\(record.id)", kind: .staging, dateKey: record.dateKey,
                title: record.title, subtitle: record.summary, status: record.status,
                statusLabel: record.statusLabel, systemImage: record.systemImage,
                pendingExpense: nil, stagingRecord: record
            )
        }
        return (pendingItems + stagingItems).sorted {
            if $0.dateKey == $1.dateKey { return $0.id > $1.id }
            return $0.dateKey > $1.dateKey
        }
    }

    static func filtered(_ items: [NativeInboxItem], by filter: NativeInboxFilter) -> [NativeInboxItem] {
        switch filter {
        case .all: return items
        case .pendingExpense: return items.filter { $0.kind == .pendingExpense }
        case .failed: return items.filter { failedStatuses.contains($0.status) }
        case .repair: return items.filter { repairStatuses.contains($0.status) }
        case .routing: return items.filter { routingStatuses.contains($0.status) }
        case .review: return items.filter { reviewStatuses.contains($0.status) }
        }
    }

    static func sections(from items: [NativeInboxItem], today: String, yesterday: String) -> [NativeInboxSection] {
        Dictionary(grouping: items, by: \.dateKey).sorted { $0.key > $1.key }.map { dateKey, groupedItems in
            let title = dateKey == today ? "今天" : (dateKey == yesterday ? "昨天" : dateKey)
            return NativeInboxSection(id: dateKey, title: title, items: groupedItems)
        }
    }
}
