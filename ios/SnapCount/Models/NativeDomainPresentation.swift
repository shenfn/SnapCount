import Foundation

struct NativeDomainMetric: Identifiable {
    let label: String
    let value: String
    var id: String { label }
}

struct NativeDomainPresentation {
    let definition: NativeDomainDefinition
    let metrics: [NativeDomainMetric]
    let recentRecords: [NativeDayRecord]
}

enum NativeDomainPresentationAdapter {
    static func presentation(for definition: NativeDomainDefinition, groups: [NativeDayRecordGroup]) -> NativeDomainPresentation {
        let records = groups.flatMap(\.records).filter { ($0.domainKey ?? $0.kind.rawValue) == definition.id && $0.kind != .staging }
        let metrics = [
            NativeDomainMetric(label: "本月记录", value: "\(records.count) 条"),
            NativeDomainMetric(label: "活跃天数", value: "\(Set(records.map(\.dateKey)).count) 天"),
            NativeDomainMetric(label: primaryLabel(for: definition), value: primaryValue(for: definition, records: records))
        ]
        return NativeDomainPresentation(definition: definition, metrics: metrics, recentRecords: Array(records.prefix(12)))
    }

    private static func primaryLabel(for definition: NativeDomainDefinition) -> String {
        definition.display.string("primary_label") ?? definition.schema.string("primary_label") ?? "最近记录"
    }

    private static func primaryValue(for definition: NativeDomainDefinition, records: [NativeDayRecord]) -> String {
        guard let first = records.first else { return "暂无" }
        if definition.id == "expense" || definition.id == "income" { return first.value }
        return first.title
    }
}
