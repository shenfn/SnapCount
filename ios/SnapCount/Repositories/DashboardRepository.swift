import Foundation

protocol DashboardRepositoryProtocol {
    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot
}

protocol DashboardRemoteServiceProtocol {
    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot
}

final class DashboardRemoteService: DashboardRemoteServiceProtocol {
    private let legacyService: NativeDataService

    init(legacyService: NativeDataService = NativeDataService()) {
        self.legacyService = legacyService
    }

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        try await legacyService.fetchDashboard(accessToken: accessToken)
    }
}

final class DashboardRepository: DashboardRepositoryProtocol {
    private let remoteService: DashboardRemoteServiceProtocol

    init(remoteService: DashboardRemoteServiceProtocol = DashboardRemoteService()) {
        self.remoteService = remoteService
    }

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
        try await remoteService.fetchDashboard(accessToken: accessToken)
    }
}
