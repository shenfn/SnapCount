import Foundation

struct NativeDomainDefinition: Identifiable {
    let id: String
    let name: String
    let description: String
    let icon: String
    let isSystem: Bool
    let schema: [String: AnyCodable]
    let display: [String: AnyCodable]
    let recordCount: Int

    var shortName: String {
        switch id { case "expense": return "消费"; case "income": return "收入"; case "sport": return "运动"; case "sleep": return "睡眠"; case "reading": return "阅读"; case "food": return "饮食"; case "wallet": return "钱包"; default: return name }
    }

    var systemImage: String { NativeDayRecordKind(rawValue: id)?.systemImage ?? "square.stack.3d.up" }
}
