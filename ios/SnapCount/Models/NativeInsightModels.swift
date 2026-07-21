import Foundation

enum NativeInsightRange: Int, CaseIterable, Identifiable, Hashable {
    case seven = 7
    case fourteen = 14
    case thirty = 30

    var id: Int { rawValue }
    var title: String { "\(rawValue) 天" }
}

struct NativeDailyDomainSummary: Decodable, Identifiable {
    let date: String
    let expenseTotal: Double
    let expenseCount: Int
    let incomeTotal: Double
    let incomeCount: Int
    let sleepMinutes: Double
    let sleepScoreAverage: Double?
    let sleepCount: Int
    let sportMinutes: Double
    let sportCount: Int
    let readingMinutes: Double
    let readingCount: Int
    let foodCalories: Double
    let foodMeals: Int
    let hasAnyData: Bool

    var id: String { date }

    enum CodingKeys: String, CodingKey {
        case date
        case expenseTotal = "expense_total"
        case expenseCount = "expense_count"
        case incomeTotal = "income_total"
        case incomeCount = "income_count"
        case sleepMinutes = "sleep_minutes"
        case sleepScoreAverage = "sleep_score_avg"
        case sleepCount = "sleep_count"
        case sportMinutes = "sport_minutes"
        case sportCount = "sport_count"
        case readingMinutes = "reading_minutes"
        case readingCount = "reading_count"
        case foodCalories = "food_calories"
        case foodMeals = "food_meals"
        case hasAnyData = "has_any_data"
    }
}

enum NativeInsightDomain: String, CaseIterable, Identifiable {
    case expense, income, sleep, sport, food, reading

    var id: String { rawValue }
    var title: String {
        switch self {
        case .expense: return "消费"
        case .income: return "收入"
        case .sleep: return "睡眠"
        case .sport: return "运动"
        case .food: return "饮食"
        case .reading: return "阅读"
        }
    }
}

struct NativeMaturityStage: Equatable {
    enum Key: String, Equatable { case seed, sprout, growing, mature, rich }

    let key: Key
    let label: String
    let days: Int
    let nextTarget: Int?

    var remainingToNext: Int { max((nextTarget ?? days) - days, 0) }
    var isMaximum: Bool { nextTarget == nil }
    var progress: Double {
        guard let nextTarget, nextTarget > 0 else { return 1 }
        return min(Double(days) / Double(nextTarget), 1)
    }

    static func resolve(days: Int) -> NativeMaturityStage {
        let days = max(days, 0)
        switch days {
        case 0..<3: return NativeMaturityStage(key: .seed, label: "萌芽", days: days, nextTarget: 3)
        case 3..<7: return NativeMaturityStage(key: .sprout, label: "抽芽", days: days, nextTarget: 7)
        case 7..<14: return NativeMaturityStage(key: .growing, label: "成长", days: days, nextTarget: 14)
        case 14..<30: return NativeMaturityStage(key: .mature, label: "成熟", days: days, nextTarget: 30)
        default: return NativeMaturityStage(key: .rich, label: "丰盈", days: days, nextTarget: nil)
        }
    }
}

struct NativeInsightDomainGrowth: Identifiable {
    let domain: NativeInsightDomain
    let maturity: NativeMaturityStage

    var id: String { domain.id }
    var hint: String {
        if maturity.isMaximum { return "已积累 \(maturity.days) 天数据" }
        if maturity.days == 0 { return "尚未开始记录" }
        return "已记录 \(maturity.days) 天，再记 \(maturity.remainingToNext) 天解锁下一阶段"
    }
}

struct NativeInsightSnapshot {
    let range: NativeInsightRange
    let rows: [NativeDailyDomainSummary]
    let activeDays: Int
    let expenseTotal: Double
    let incomeTotal: Double
    let sleepMinutes: Double
    let sleepDays: Int
    let foodCalories: Double
    let foodMeals: Int
    let growth: [NativeInsightDomainGrowth]

    var netBalance: Double { incomeTotal - expenseTotal }
    var averageSleepHours: Double { sleepDays > 0 ? sleepMinutes / Double(sleepDays) / 60 : 0 }
    var maturity: NativeMaturityStage { .resolve(days: activeDays) }

    init(range: NativeInsightRange, rows: [NativeDailyDomainSummary]) {
        self.range = range
        self.rows = rows.sorted { $0.date < $1.date }
        activeDays = rows.filter(\.hasAnyData).count
        expenseTotal = rows.reduce(0) { $0 + $1.expenseTotal }
        incomeTotal = rows.reduce(0) { $0 + $1.incomeTotal }
        sleepMinutes = rows.reduce(0) { $0 + $1.sleepMinutes }
        sleepDays = rows.filter { $0.sleepCount > 0 }.count
        foodCalories = rows.reduce(0) { $0 + $1.foodCalories }
        foodMeals = rows.reduce(0) { $0 + $1.foodMeals }

        growth = NativeInsightDomain.allCases.map { domain in
            let days = rows.filter { row in
                switch domain {
                case .expense: return row.expenseCount > 0
                case .income: return row.incomeCount > 0
                case .sleep: return row.sleepCount > 0
                case .sport: return row.sportCount > 0
                case .food: return row.foodMeals > 0
                case .reading: return row.readingCount > 0
                }
            }.count
            return NativeInsightDomainGrowth(domain: domain, maturity: .resolve(days: days))
        }
    }
}

struct NativeAIInsight: Decodable, Identifiable {
    let remoteId: String?
    let generatedAt: String
    let daysRange: Int?
    let maturityStage: String?
    let activeDays: Int?
    let contentMarkdown: String
    let payload: [String: AnyCodable]
    let status: String?

    var id: String { remoteId ?? generatedAt }
    var parsedPayload: NativeAIInsightPayload { NativeAIInsightPayload(payload) }

    func scoped(to range: NativeInsightRange) -> NativeAIInsight {
        NativeAIInsight(
            remoteId: remoteId,
            generatedAt: generatedAt,
            daysRange: daysRange ?? range.rawValue,
            maturityStage: maturityStage,
            activeDays: activeDays,
            contentMarkdown: contentMarkdown,
            payload: payload,
            status: status
        )
    }

    enum CodingKeys: String, CodingKey {
        case remoteId = "id"
        case generatedAt = "generated_at"
        case daysRange = "days_range"
        case maturityStage = "maturity_stage"
        case activeDays = "active_days"
        case contentMarkdown = "content_md"
        case payload = "payload_jsonb"
        case status
    }
}

struct NativeAIInsightPayload {
    let headline: String
    let question: String
    let answer: String
    let observations: [String]
    let patterns: [String]
    let risks: [String]
    let suggestions: [String]
    let actionPlan: [String]
    let uncertainty: [String]
    let encouragement: String
    let followupQuestions: [String]
    let modeLabel: String

    init(_ payload: [String: AnyCodable]) {
        headline = payload.string("headline") ?? ""
        question = payload.string("question") ?? ""
        answer = payload.string("answer") ?? ""
        observations = Self.strings(payload["observations"])
        patterns = Self.strings(payload["patterns"])
        risks = Self.strings(payload["risks"])
        suggestions = Self.strings(payload["suggestions"])
        actionPlan = Self.strings(payload["action_plan"])
        uncertainty = Self.strings(payload["uncertainty"])
        encouragement = payload.string("encouragement") ?? ""
        followupQuestions = Self.strings(payload["followup_questions"])
        if let route = payload["route"]?.value as? [String: Any],
           let label = route["mode_label"] as? String {
            modeLabel = label
        } else if let route = payload["route"]?.value as? [String: String] {
            modeLabel = route["mode_label"] ?? ""
        } else {
            modeLabel = payload.string("mode_label") ?? ""
        }
    }

    private static func strings(_ value: AnyCodable?) -> [String] {
        guard let values = value?.value as? [Any] else { return [] }
        return values.compactMap { $0 as? String }.filter { !$0.isEmpty }
    }
}

struct NativeAIInsightResponse: Decodable {
    let cached: Bool
    let insight: NativeAIInsight
}
