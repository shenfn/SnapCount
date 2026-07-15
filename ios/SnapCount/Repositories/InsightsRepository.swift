import Foundation

protocol InsightsRepositoryProtocol {
    func fetchDailySummary(
        range: NativeInsightRange,
        accessToken: String
    ) async throws -> NativeInsightSnapshot
    func fetchLatestAIInsight(
        range: NativeInsightRange,
        accessToken: String
    ) async throws -> NativeAIInsight?
    func generateAIInsight(
        range: NativeInsightRange,
        force: Bool,
        question: String,
        accessToken: String
    ) async throws -> NativeAIInsightResponse
}

final class InsightsRepository: InsightsRepositoryProtocol {
    private let remoteClient: SupabaseRemoteClientProtocol

    init(remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()) {
        self.remoteClient = remoteClient
    }

    func fetchDailySummary(
        range: NativeInsightRange,
        accessToken: String
    ) async throws -> NativeInsightSnapshot {
        let calendar = Calendar(identifier: .gregorian)
        let since = calendar.date(byAdding: .day, value: -range.rawValue, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = try await remoteClient.get(
            [NativeDailyDomainSummary].self,
            path: "rest/v1/daily_domain_summary",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "date", value: "gte.\(formatter.string(from: since))"),
                URLQueryItem(name: "order", value: "date.asc")
            ],
            accessToken: accessToken
        )
        return NativeInsightSnapshot(range: range, rows: rows)
    }

    func fetchLatestAIInsight(
        range: NativeInsightRange,
        accessToken: String
    ) async throws -> NativeAIInsight? {
        let rows = try await remoteClient.get(
            [NativeAIInsight].self,
            path: "rest/v1/ai_insights",
            queryItems: [
                URLQueryItem(name: "select", value: "id,generated_at,days_range,maturity_stage,active_days,content_md,payload_jsonb,status"),
                URLQueryItem(name: "days_range", value: "eq.\(range.rawValue)"),
                URLQueryItem(name: "status", value: "eq.success"),
                URLQueryItem(name: "order", value: "generated_at.desc"),
                URLQueryItem(name: "limit", value: "1")
            ],
            accessToken: accessToken
        )
        return rows.first
    }

    func generateAIInsight(
        range: NativeInsightRange,
        force: Bool,
        question: String,
        accessToken: String
    ) async throws -> NativeAIInsightResponse {
        try await remoteClient.postFunction(
            NativeAIInsightResponse.self,
            path: "generate-insights",
            body: [
                "days": AnyCodable(range.rawValue),
                "force": AnyCodable(force),
                "question": AnyCodable(String(question.prefix(500)))
            ],
            accessToken: accessToken
        )
    }
}
