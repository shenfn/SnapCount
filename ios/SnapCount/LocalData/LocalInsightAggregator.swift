import Foundation

enum LocalInsightAggregator {
    static func rows(from facts: [LocalFact]) -> [NativeDailyDomainSummary] {
        let grouped = Dictionary(grouping: facts, by: \.businessDate)
        return grouped.keys.sorted().map { date in
            let day = grouped[date] ?? []
            var expenseTotal = 0.0
            var expenseCount = 0
            var incomeTotal = 0.0
            var incomeCount = 0
            var sleepMinutes = 0.0
            var sleepScores: [Double] = []
            var sleepCount = 0
            var sportMinutes = 0.0
            var sportCount = 0
            var readingMinutes = 0.0
            var readingCount = 0
            var foodCalories = 0.0
            var foodMeals = 0

            for fact in day {
                switch fact.kind {
                case .expense:
                    let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                    expenseTotal += (payload.double("amount_minor") ?? 0) / 100
                    expenseCount += 1
                case .income:
                    let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                    incomeTotal += (payload.double("amount_minor") ?? 0) / 100
                    incomeCount += 1
                case .record:
                    let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                    switch fact.domainKey {
                    case "sleep":
                        sleepCount += 1
                        sleepMinutes += payload.double("sleep_minutes") ?? ((payload.double("sleep_hours") ?? 0) * 60)
                        if let score = payload.double("quality_score") { sleepScores.append(score) }
                    case "sport":
                        sportCount += 1
                        sportMinutes += payload.double("duration_minutes") ?? 0
                    case "reading":
                        readingCount += 1
                        readingMinutes += payload.double("reading_minutes") ?? 0
                    case "food":
                        foodMeals += 1
                        foodCalories += payload.double("total_calorie_kcal") ?? 0
                    default:
                        break
                    }
                }
            }

            return NativeDailyDomainSummary(
                date: date,
                expenseTotal: expenseTotal, expenseCount: expenseCount,
                incomeTotal: incomeTotal, incomeCount: incomeCount,
                sleepMinutes: sleepMinutes,
                sleepScoreAverage: sleepScores.isEmpty ? nil : sleepScores.reduce(0, +) / Double(sleepScores.count),
                sleepCount: sleepCount,
                sportMinutes: sportMinutes, sportCount: sportCount,
                readingMinutes: readingMinutes, readingCount: readingCount,
                foodCalories: foodCalories, foodMeals: foodMeals,
                hasAnyData: !day.isEmpty
            )
        }
    }
}
