import Foundation

enum NativeInboxItemKind: String {
    case pendingExpense
    case staging
}

struct NativePendingExpense: Identifiable {
    let id: String
    let title: String
    let amount: Double
    let dateKey: String
    let reference: String
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
