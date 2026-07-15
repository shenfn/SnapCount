import Foundation

protocol InsightsRepositoryProtocol {
    func fetchDailySummary(
        range: NativeInsightRange,
        accessToken: String
    ) async throws -> NativeInsightSnapshot
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
}
