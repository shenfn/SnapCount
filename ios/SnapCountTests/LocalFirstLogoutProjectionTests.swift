import XCTest
@testable import SnapCount

@MainActor
final class LocalFirstLogoutProjectionTests: XCTestCase {
    func testLOCALP1SPORT001LLoggedOutInboxAndDetailReloadFromLocalData() async throws {
        let databaseURL = temporaryDatabaseURL()
        let imageDirectory = temporaryImageDirectoryURL()
        defer {
            try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: imageDirectory)
        }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let useCase = LocalRecordUseCase(
            profileStore: profileStore,
            repository: try LocalRecordRepository(database: database),
            imageStore: try LocalImageStore(rootDirectory: imageDirectory)
        )
        let date = NativeLocalDate.dateKey(Date())
        let recordID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

        _ = try await useCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "退出登录后仍可见的运动",
            summary: "本地正式事实",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(30)
            ],
            recordDate: date,
            recordTime: "08:30",
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        _ = try await useCase.stage(LocalRecordCandidate(
            id: "logout-staging",
            domainKey: "sport",
            title: "退出登录后仍可见的候选",
            summary: "本地中转候选",
            payload: ["sport_type": AnyCodable("骑行")],
            confidence: 0.62,
            recordDate: date,
            recordTime: "09:00",
            imageData: nil,
            createdAt: Date()
        ))

        var sessionLookupCount = 0
        let state = AppState(
            localRecordUseCase: useCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )
        state.resetUserScopedState()

        await state.refreshInboxProjection()

        XCTAssertEqual(state.dashboard.stagingRecords.map(\.id), ["local-staging/logout-staging"])
        XCTAssertEqual(state.dashboard.pendingCount, 1)

        await state.loadRecordDetail(reference: "data/\(recordID.uuidString)")

        XCTAssertEqual(state.selectedRecordDetail?.title, "退出登录后仍可见的运动")
        XCTAssertEqual(state.selectedRecordDetail?.domainKey, "sport")
        XCTAssertEqual(sessionLookupCount, 0)
    }

    func testLOCALP1SPORT001LLocalExpenseDetailReloadsAfterLogoutWithoutSession() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent()) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date()
        ))
        let useCase = LocalExpenseUseCase(profileStore: profileStore, repository: repository)
        let outcome = try await useCase.create(LocalExpenseCommand(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            accountID: account.id,
            amountText: "12.30",
            currency: "CNY",
            merchantName: "退出登录后仍可见的消费",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: NativeLocalDate.dateKey(Date()),
            transactionTime: "12:00",
            note: nil,
            createdAt: Date()
        ))
        let expense = try XCTUnwrap(outcome.expense)

        var sessionLookupCount = 0
        let state = AppState(
            localExpenseUseCase: useCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )
        state.resetUserScopedState()

        await state.loadRecordDetail(reference: "expense/\(expense.id.uuidString)")

        XCTAssertEqual(state.selectedRecordDetail?.title, "退出登录后仍可见的消费")
        XCTAssertEqual(try XCTUnwrap(state.selectedRecordDetail?.amount), 12.30, accuracy: 0.001)
        XCTAssertEqual(sessionLookupCount, 0)
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-logout-projection-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func temporaryImageDirectoryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-logout-projection-images-\(UUID().uuidString)", isDirectory: true)
    }
}
