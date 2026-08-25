import XCTest
@testable import SnapCount

final class LocalBindingPreviewUseCaseTests: XCTestCase {
    func testFreshWorkspaceStartsUnboundAndSyncDisabled() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }

        let profile = try fixture.store.activeProfile()
        let state = try fixture.store.syncState(profileID: profile.id)

        XCTAssertEqual(state.binding, .unbound)
        XCTAssertEqual(state.status, .disabled)
        XCTAssertEqual(state.conflictState, .none)
        XCTAssertEqual(state.syncGeneration, 0)
        XCTAssertNil(state.pullCursor)
        XCTAssertNil(profile.cloudUserID)
        XCTAssertFalse(profile.syncEnabled)
    }

    func testPreviewUsesCurrentWorkspaceAndDoesNotBind() async throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        let account = try fixture.repository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 10_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        _ = try fixture.repository.createExpense(LocalExpenseDraft(
            id: UUID(),
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 1_230,
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: "2026-08-25",
            transactionTime: "08:30",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        ), operationID: UUID())

        let useCase = LocalBindingPreviewUseCase(
            repository: fixture.store,
            scopeProvider: StubRemoteScopeProvider(scopes: ["expense", "accounts"])
        )
        let preview = try await useCase.makePreview(
            cloudUserID: "cloud-a",
            email: "a@example.com"
        )

        XCTAssertEqual(preview.workspaceID, profile.id)
        XCTAssertEqual(preview.candidateCloudUserID, "cloud-a")
        XCTAssertEqual(preview.localExpenseCount, 1)
        XCTAssertEqual(preview.localAccountCount, 1)
        XCTAssertEqual(preview.remoteScope, ["expense", "accounts"])
        XCTAssertTrue(preview.options.contains(.deferSync))
        XCTAssertTrue(preview.options.contains(.mergeAndEnable))
        XCTAssertNil(try fixture.store.activeProfile().cloudUserID)
        XCTAssertFalse(try fixture.store.activeProfile().syncEnabled)
    }

    func testConfirmBindingPersistsBindingAndAdvancesGeneration() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()

        let state = try fixture.store.confirmBinding(
            profileID: profile.id,
            cloudUserID: "cloud-a"
        )

        XCTAssertEqual(state.binding, .bound("cloud-a"))
        XCTAssertEqual(state.status, .ready)
        XCTAssertEqual(state.syncGeneration, 1)
        let persisted = try fixture.store.activeProfile()
        XCTAssertEqual(persisted.cloudUserID, "cloud-a")
        XCTAssertTrue(persisted.syncEnabled)
    }

    func testMismatchedBindingCannotBeReassigned() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")

        XCTAssertThrowsError(try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-b")) { error in
            XCTAssertEqual(error as? LocalSyncError, .bindingMismatch(boundUserID: "cloud-a", candidateUserID: "cloud-b"))
        }
        let persisted = try fixture.store.activeProfile()
        XCTAssertEqual(persisted.cloudUserID, "cloud-a")
    }

    func testDisablingSyncOnLogoutAdvancesGenerationAndKeepsBinding() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")

        let state = try fixture.store.disableSync(profileID: profile.id)

        XCTAssertEqual(state.binding, .bound("cloud-a"))
        XCTAssertEqual(state.status, .disabled)
        XCTAssertEqual(state.syncGeneration, 2)
        XCTAssertFalse(try fixture.store.activeProfile().syncEnabled)
    }

    func testCheckpointAndOutboxGateAreScopedToWorkspace() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()

        let checkpoint = try fixture.store.updateCheckpoint(
            profileID: profile.id,
            pullCursor: "global-42",
            attemptID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            lastSuccessfulSyncAt: Date(timeIntervalSince1970: 1_700_000_200)
        )
        XCTAssertEqual(checkpoint.pullCursor, "global-42")
        XCTAssertTrue(try fixture.store.canUploadOutbox(profileID: profile.id, cloudUserID: "cloud-a") == false)

        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")
        XCTAssertTrue(try fixture.store.canUploadOutbox(profileID: profile.id, cloudUserID: "cloud-a"))
        XCTAssertFalse(try fixture.store.canUploadOutbox(profileID: profile.id, cloudUserID: "cloud-b"))
    }

    func testUnresolvedConflictBlocksOutboxWithoutChangingSyncStatus() throws {
        let fixture = try LocalSyncFixture()
        defer { fixture.cleanup() }
        let profile = try fixture.store.activeProfile()
        _ = try fixture.store.confirmBinding(profileID: profile.id, cloudUserID: "cloud-a")

        try fixture.database.writer.write { db in
            try db.execute(
                sql: "UPDATE local_sync_state SET conflict_status = 'unresolved' WHERE profile_id = ?",
                arguments: [profile.id.uuidString]
            )
        }

        let state = try fixture.store.syncState(profileID: profile.id)
        XCTAssertEqual(state.status, .ready)
        XCTAssertEqual(state.conflictState, .unresolved)
        XCTAssertFalse(try fixture.store.canUploadOutbox(profileID: profile.id, cloudUserID: "cloud-a"))
    }
}

private struct LocalSyncFixture {
    let url: URL
    let database: LocalDatabase
    let store: LocalProfileStore
    let repository: LocalExpenseRepository

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("local-sync-(UUID().uuidString)")
            .appendingPathExtension("sqlite")
        database = try LocalDatabase(databaseURL: url)
        store = LocalProfileStore(database: database)
        repository = try LocalExpenseRepository(database: database)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: url)
    }
}

private struct StubRemoteScopeProvider: LocalBindingScopeProvider {
    let scopes: [String]

    func fetchScopes(cloudUserID: String) async throws -> [String] { scopes }
}
