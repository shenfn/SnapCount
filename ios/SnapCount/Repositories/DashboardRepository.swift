import Foundation

protocol DashboardRepositoryProtocol {
    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot
}

final class DashboardRepository: DashboardRepositoryProtocol {
    private let remoteService: NativeDataService

    init(remoteService: NativeDataService = NativeDataService()) {
        self.remoteService = remoteService
    }

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        try await remoteService.fetchDashboard(accessToken: accessToken)
    }
}
