import Foundation

enum NativeDayRecordKind: String, CaseIterable, Identifiable {
    case all, expense, income, sport, sleep, food, reading, wallet, staging
    var id: String { rawValue }
    var title: String { switch self { case .all: return "全部"; case .expense: return "支出"; case .income: return "收入"; case .sport: return "运动"; case .sleep: return "睡眠"; case .food: return "饮食"; case .reading: return "阅读"; case .wallet: return "钱包"; case .staging: return "待处理" } }
    var systemImage: String { switch self { case .all: return "square.grid.2x2"; case .expense: return "creditcard"; case .income: return "arrow.down.circle"; case .sport: return "figure.run"; case .sleep: return "moon"; case .food: return "fork.knife"; case .reading: return "book"; case .wallet: return "wallet.pass"; case .staging: return "tray" } }
}

struct NativeDayRecord: Identifiable {
    let id: String
    let reference: String
    let dateKey: String
    let kind: NativeDayRecordKind
    let domainKey: String?
    let title: String
    let subtitle: String
    let value: String
    let timeLabel: String?
    let systemImage: String
}

struct NativeDayRecordGroup: Identifiable {
    let dateKey: String
    let records: [NativeDayRecord]
    var id: String { dateKey }
    func records(for kind: NativeDayRecordKind) -> [NativeDayRecord] { kind == .all ? records : records.filter { $0.kind == kind } }
    var availableKinds: [NativeDayRecordKind] { let present = Set(records.map(\.kind)); return [.all] + NativeDayRecordKind.allCases.filter { $0 != .all && present.contains($0) } }
}

struct NativeDayDetailRoute: Hashable {
    let dateKey: String
    let kind: NativeDayRecordKind
}
