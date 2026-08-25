import Foundation
import XCTest
@testable import SnapCount

final class LocalSyncCoordinatorTests: XCTestCase {
    func testLOCAL003D1UploadsPendingOutboxOnlyAfterMatchingBindingAndMarksSent() async throws {
        let fixture = try LocalSyncCoordinatorFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        let account = try fixture.repository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: fixture.fixedDate
        ))
        _ = try fixture.repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: account.id, amountMinor: 123,
            currency: "CNY", merchantName: "早餐", platform: "manual", category: "food",
            paymentMethod: "现金", transactionDate: "2026-08-25", transactionTime: nil,
            note: nil, createdAt: fixture.fixedDate
        ), operationID: UUID())
        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")

        let coordinator = fixture.coordinator(transport: StubSyncTransport(result: .init(remoteArchive: nil, nextPullCursor: "cursor-1")))
        let result = try await coordinator.synchronize(profileID: profile.id, cloudUserID: "cloud-a")

        XCTAssertEqual(result.uploadedOperationCount, 1)
        XCTAssertEqual(result.state.status, .synced)
        XCTAssertEqual(result.state.pullCursor, "cursor-1")
        XCTAssertTrue(try fixture.repository.pendingOutboxOperations().isEmpty)
    }

    func testLOCAL003D2TransportFailureKeepsLocalFactAndLeavesFailedOutbox() async throws {
        let fixture = try LocalSyncCoordinatorFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        let account = try fixture.repository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: fixture.fixedDate
        ))
        let expenseID = UUID()
        _ = try fixture.repository.createExpense(LocalExpenseDraft(
            id: expenseID, profileID: profile.id, accountID: account.id, amountMinor: 123,
            currency: "CNY", merchantName: "早餐", platform: "manual", category: "food",
            paymentMethod: "现金", transactionDate: "2026-08-25", transactionTime: nil,
            note: nil, createdAt: fixture.fixedDate
        ), operationID: UUID())
        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")

        let coordinator = fixture.coordinator(transport: StubSyncTransport(error: StubSyncError.offline))
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.synchronize(profileID: profile.id, cloudUserID: "cloud-a")
        }

        XCTAssertNotNil(try fixture.repository.expense(id: expenseID))
        XCTAssertEqual(try fixture.store.syncState(profileID: profile.id).status, .failed)
        XCTAssertEqual(try fixture.repository.pendingOutboxUploads(profileID: profile.id).count, 1)
        XCTAssertEqual(try fixture.repository.pendingOutboxUploads(profileID: profile.id).first?.attemptCount ?? -1, 1)
    }

    func testLOCAL003D3MismatchedOrUnboundWorkspaceCannotStartSync() async throws {
        let fixture = try LocalSyncCoordinatorFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        let coordinator = fixture.coordinator(transport: StubSyncTransport(result: .init(remoteArchive: nil, nextPullCursor: nil)))

        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.synchronize(profileID: profile.id, cloudUserID: "cloud-a")
        }
        XCTAssertEqual(try fixture.store.syncState(profileID: profile.id).status, .disabled)

        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")
        await XCTAssertThrowsErrorAsync {
            _ = try await coordinator.synchronize(profileID: profile.id, cloudUserID: "cloud-b")
        }
        XCTAssertEqual(try fixture.store.syncState(profileID: profile.id).status, .ready)
    }

    func testLOCAL003D4RemoteArchiveMergesIntoCurrentWorkspaceWithoutCreatingOutbox() async throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-sync-source-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let sourceDatabase = try LocalDatabase(databaseURL: sourceURL)
        let sourceRepository = try LocalExpenseRepository(database: sourceDatabase)
        let profileID = UUID()
        _ = try sourceRepository.createProfile(id: profileID, createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let sourceAccount = try sourceRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profileID, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        _ = try sourceRepository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profileID, accountID: sourceAccount.id, amountMinor: 456,
            currency: "CNY", merchantName: "午餐", platform: "manual", category: "food",
            paymentMethod: "现金", transactionDate: "2026-08-25", transactionTime: nil,
            note: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ), operationID: UUID())
        let archive = try LocalExpensePortability(database: sourceDatabase).exportArchive(profileID: profileID)

        let fixture = try LocalSyncCoordinatorFixture(profileID: profileID)
        defer { fixture.cleanup() }
        _ = try fixture.store.confirmBinding(profileID: profileID, cloudUserID: "cloud-a")
        let coordinator = fixture.coordinator(transport: StubSyncTransport(
            result: .init(remoteArchive: archive, nextPullCursor: "cursor-remote")
        ))

        let result = try await coordinator.synchronize(profileID: profileID, cloudUserID: "cloud-a")

        XCTAssertEqual(result.importedRecordCount, 2)
        XCTAssertEqual(try fixture.repository.expenseCount(), 1)
        XCTAssertTrue(try fixture.repository.pendingOutboxOperations().isEmpty)
    }
}

private enum StubSyncError: Error { case offline }

private final class StubSyncTransport: LocalSyncTransport {
    let result: LocalSyncTransportResult?
    let error: Error?
    var uploads: [LocalOutboxUpload] = []

    init(result: LocalSyncTransportResult) { self.result = result; error = nil }
    init(error: Error) { result = nil; self.error = error }

    func synchronize(
        cloudUserID: String,
        profileID: UUID,
        pullCursor: String?,
        uploads: [LocalOutboxUpload]
    ) async throws -> LocalSyncTransportResult {
        self.uploads = uploads
        if let error { throw error }
        return result!
    }
}

private final class LocalSyncCoordinatorFixture {
    let url: URL
    let database: LocalDatabase
    let store: LocalProfileStore
    let repository: LocalExpenseRepository
    let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    init(profileID: UUID? = nil) throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-sync-coordinator-\(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        database = try LocalDatabase(databaseURL: url)
        store = LocalProfileStore(database: database)
        repository = try LocalExpenseRepository(database: database)
        if let profileID {
            _ = try repository.createProfile(id: profileID, createdAt: fixedDate)
        }
    }

    func coordinator(transport: StubSyncTransport) -> LocalSyncCoordinator {
        return LocalSyncCoordinator(
            stateStore: store,
            repository: repository,
            portability: LocalExpensePortability(database: database),
            transport: transport,
            now: { self.fixedDate },
            attemptID: { UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")! }
        )
    }

    func cleanup() { try? FileManager.default.removeItem(at: url) }
}

private extension XCTestCase {
    func XCTAssertThrowsErrorAsync<T>(
        _ expression: @escaping () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await expression()
            XCTFail("Expected error", file: file, line: line)
        } catch {}
    }
}
