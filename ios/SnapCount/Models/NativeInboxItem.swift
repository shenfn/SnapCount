import Foundation

enum NativeInboxItemKind: String {
    case pendingExpense
    case staging
}

enum NativeInboxFilter: String, CaseIterable, Identifiable, Hashable {
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

    var galleryTitle: String {
        switch self {
        case .all: return "全部待处理"
        default: return title
        }
    }

    var gallerySubtitle: String {
        switch self {
        case .all: return "把还没落定的记录集中看一遍"
        case .pendingExpense: return "金额、渠道或支付方式还差一点"
        case .failed: return "识别没有完成，可以重新试一次"
        case .repair: return "有几项信息需要补上"
        case .routing: return "选择它应该归到哪个地方"
        case .review: return "快速看一眼，确认识别结果"
        }
    }

    var gallerySystemImage: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .pendingExpense: return "creditcard"
        case .failed: return "arrow.clockwise.circle"
        case .repair: return "wrench.and.screwdriver"
        case .routing: return "folder"
        case .review: return "checkmark.circle"
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

struct NativeInboxCategory: Identifiable {
    let filter: NativeInboxFilter
    let items: [NativeInboxItem]

    var id: String { filter.rawValue }
    var title: String { filter.galleryTitle }
    var subtitle: String { filter.gallerySubtitle }
    var systemImage: String { filter.gallerySystemImage }
    var count: Int { items.count }
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

    static func categories(from items: [NativeInboxItem]) -> [NativeInboxCategory] {
        let order: [NativeInboxFilter] = [.pendingExpense, .routing, .review, .failed, .repair]
        let categories: [NativeInboxCategory] = order.compactMap { (filter: NativeInboxFilter) -> NativeInboxCategory? in
            let categoryItems = filtered(items, by: filter)
            guard !categoryItems.isEmpty else { return nil }
            return NativeInboxCategory(filter: filter, items: categoryItems)
        }

        let categorizedIDs = Set(categories.flatMap { $0.items.map(\.id) })
        let uncategorizedItems = items.filter { !categorizedIDs.contains($0.id) }
        guard !uncategorizedItems.isEmpty else { return categories }
        return categories + [NativeInboxCategory(filter: .all, items: items)]
    }

    static func sections(from items: [NativeInboxItem], today: String, yesterday: String) -> [NativeInboxSection] {
        Dictionary(grouping: items, by: \.dateKey).sorted { $0.key > $1.key }.map { dateKey, groupedItems in
            let title = dateKey == today ? "今天" : (dateKey == yesterday ? "昨天" : dateKey)
            return NativeInboxSection(id: dateKey, title: title, items: groupedItems)
        }
    }
}
