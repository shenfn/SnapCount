import Foundation

protocol DashboardRepositoryProtocol {
    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot
    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot
}

protocol DashboardRemoteServiceProtocol {
    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot
    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot
}

final class DashboardRemoteService: DashboardRemoteServiceProtocol {
    private let legacyService: NativeDataService

    init(legacyService: NativeDataService = NativeDataService()) {
        self.legacyService = legacyService
    }

    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        try await legacyService.fetchDashboardCore(accessToken: accessToken)
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        try await legacyService.hydrateDashboardImages(snapshot, accessToken: accessToken)
    }
}

final class DashboardRepository: DashboardRepositoryProtocol {
    private let remoteService: DashboardRemoteServiceProtocol

    init(remoteService: DashboardRemoteServiceProtocol = DashboardRemoteService()) {
        self.remoteService = remoteService
    }

    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        try await remoteService.fetchDashboardCore(accessToken: accessToken)
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        try await remoteService.hydrateDashboardImages(snapshot, accessToken: accessToken)
    }
}
