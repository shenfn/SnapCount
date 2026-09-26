import XCTest
@testable import SnapCount

/// SL-02（投影刷新收敛与特征测试加固）特征测试。
/// 覆盖场景编号：LF-001、LF-002、DM-014、SL-02-C4（写后投影刷新收敛）、SL-02-D3（三套引用前缀路由）。
/// DM-004/DM-005 阈值具名测试见 LocalPhase1DataModelTests，D6 死 API 改写见 LocalSportRecordTests。
@MainActor
final class LocalFirstSL02ProjectionTests: XCTestCase {

    // MARK: - LF-001：未登录四域手动创建 → 本地事实层 + 当月投影刷新

    func testLOCALP1LF001SignedOutManualCreationWritesLocalFactsAndRefreshesCurrentMonthProjection() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()

        for draft in Self.manualUniversalDrafts() {
            let saved = await state.createManualRecord(draft, domain: nil)
            XCTAssertTrue(saved, "\(draft.domainKey) 创建应成功")
            XCTAssertEqual(state.manualRecordMessage, "记录已保存（本机）")
        }

        let monthKey = NativeMonthKey.current()
        let facts = try harness.factReader.month(profileID: harness.profile.id, monthKey: monthKey)
        let recordFacts = facts.facts.filter { $0.kind == .record }
        XCTAssertEqual(Set(recordFacts.map(\.domainKey)), Set(["food", "sleep", "reading"]))
        XCTAssertTrue(recordFacts.allSatisfy { $0.reference.hasPrefix("data/") })

        let references = Set(state.recordGroups(monthKey: monthKey).flatMap(\.records).map(\.reference))
        XCTAssertEqual(references, Set(recordFacts.map(\.reference)))
        XCTAssertEqual(harness.sessionCounter.current, 0, "未登录手动创建不应触发任何会话查询")
    }

    // MARK: - LF-002（Q-08）：登录态四域手动创建 → 走云端，不落本地事实层

    func testLOCALP1LF002SignedInManualUniversalRecordRoutesToCloudInsteadOfLocalFacts() async throws {
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "sport")
        draft.primaryValueText = "30"
        draft.dimension = "跑步"

        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved)
        XCTAssertEqual(state.manualRecordMessage, "记录已保存")
        XCTAssertEqual(harness.recordSpy.createDrafts.count, 1)
        XCTAssertEqual(harness.recordSpy.createDrafts.first?.domainKey, "sport")

        let monthKey = NativeMonthKey.current()
        let facts = try harness.factReader.month(profileID: harness.profile.id, monthKey: monthKey)
        XCTAssertTrue(facts.facts.isEmpty, "登录态新建不应写入本地事实层")
        XCTAssertTrue(state.recordGroups(monthKey: monthKey).flatMap(\.records).isEmpty)
        XCTAssertGreaterThanOrEqual(harness.sessionCounter.current, 1, "登录态新建应走云端链路")
    }

    // MARK: - DM-014：已登录但未确认绑定 → 不发生云端与本地静默拼接

    func testLOCALP1DM014RemoteExpenseProjectionRequiresConfirmedBinding() async throws {
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: true)
        defer { harness.cleanup() }
        let state = harness.state
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        let monthKey = "2000-01"
        state.localSyncState = Self.syncState(binding: .unbound)

        await state.loadRecordMonth(monthKey, force: true)

        XCTAssertEqual(harness.recordSpy.fetchMonthKeys, [monthKey])
        XCTAssertTrue(harness.expenseStub.importRemoteExpenseCalls.isEmpty, "未绑定时不得把云端消费写入本地")
        XCTAssertTrue(harness.expenseStub.importRemoteAccountCalls.isEmpty)

        state.localSyncState = Self.syncState(binding: .bound("cloud-user"))
        await state.loadRecordMonth(monthKey, force: true)

        XCTAssertEqual(harness.recordSpy.fetchMonthKeys.count, 2)
        XCTAssertEqual(harness.expenseStub.importRemoteExpenseCalls.count, 1)
        XCTAssertEqual(harness.expenseStub.importRemoteExpenseCalls.first?.first?.amountMinor, 1_250)
        XCTAssertTrue(harness.expenseStub.importRemoteAccountCalls.isEmpty)
    }

    // MARK: - SL-02-D3：三套引用前缀路由（expense/data、local-expense/local-data、local-staging）

    func testLOCALP1SL02RecordDetailRoutingCoversThreeReferencePrefixSystems() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()

        let account = try harness.expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: harness.profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let expenseOutcome = try await harness.expenseUseCase.create(LocalExpenseCommand(
            id: UUID(),
            accountID: account.id,
            amountText: "19.80",
            currency: "CNY",
            merchantName: "本地咖啡店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-01-19",
            transactionTime: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_100)
        ))
        guard let expense = expenseOutcome.expense else {
            throw SL02TestError.unexpectedFailure("本地消费创建失败")
        }
        let recordOutcome = try await harness.recordUseCase.create(LocalRecordCommand(
            id: UUID(),
            domainKey: "sport",
            title: "晨跑",
            summary: "30 分钟",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            recordDate: "2026-01-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_200)
        ))

        let cases: [(reference: String, rawId: String, title: String)] = [
            ("local-expense/\(expense.id.uuidString)", expense.id.uuidString, "本地咖啡店"),
            ("expense/\(expense.id.uuidString)", expense.id.uuidString, "本地咖啡店"),
            ("local-data/\(recordOutcome.record.id.uuidString)", recordOutcome.record.id.uuidString, "晨跑"),
            ("data/\(recordOutcome.record.id.uuidString)", recordOutcome.record.id.uuidString, "晨跑")
        ]
        for item in cases {
            await state.loadRecordDetail(reference: item.reference)
            XCTAssertEqual(state.selectedRecordDetail?.rawId, item.rawId, "\(item.reference) 应路由到本地详情")
            XCTAssertEqual(state.selectedRecordDetail?.title, item.title)
            XCTAssertNil(state.recordDetailMessage, "\(item.reference) 不应产生会话查询报错")
        }
        XCTAssertEqual(harness.sessionCounter.current, 0, "本地前缀路由不应查询会话")

        await state.loadRecordDetail(reference: "local-staging/stage-001")
        XCTAssertNil(state.selectedRecordDetail, "local-staging 引用不应进入正式详情路由")
        XCTAssertNotNil(state.recordDetailMessage, "local-staging 引用只应触发会话查询失败")
        XCTAssertEqual(harness.sessionCounter.current, 1)
    }

    // MARK: - SL-02-C4（红灯先行）：FactReader 模式编辑后投影引用保持权威前缀

    func testLOCALP1SL02FactReaderModeEditRefreshesFactMonthProjectionWithCanonicalReferences() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()

        let monthKey = "2026-01"
        let account = try harness.expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: harness.profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let expenseOutcome = try await harness.expenseUseCase.create(LocalExpenseCommand(
            id: UUID(),
            accountID: account.id,
            amountText: "12.30",
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-01-19",
            transactionTime: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_100)
        ))
        guard let expense = expenseOutcome.expense else {
            throw SL02TestError.unexpectedFailure("本地消费创建失败")
        }
        let recordOutcome = try await harness.recordUseCase.create(LocalRecordCommand(
            id: UUID(),
            domainKey: "sport",
            title: "晨跑",
            summary: "30 分钟",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            recordDate: "2026-01-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_200)
        ))
        _ = await state.loadRecordMonth(monthKey, force: true)

        var expenseDraft = NativeRecordEditDraft(detail: LocalExpenseReadModel.detail(from: expense))
        expenseDraft.amountText = "20.00"
        let expenseSaved = await state.saveRecordDetail(expenseDraft)
        XCTAssertTrue(expenseSaved)
        _ = await state.loadRecordMonth(monthKey, force: true)

        var recordDraft = NativeRecordEditDraft(detail: LocalRecordReadModel.detail(
            from: recordOutcome.record,
            imageStore: nil
        ))
        recordDraft.note = "编辑后备注"
        let recordSaved = await state.saveRecordDetail(recordDraft)
        XCTAssertTrue(recordSaved)

        let references = Set(state.recordGroups(monthKey: monthKey).flatMap(\.records).map(\.reference))
        XCTAssertEqual(references, Set([
            "expense/\(expense.id.uuidString)",
            "data/\(recordOutcome.record.id.uuidString)"
        ]))
    }

    // MARK: - Fixtures

    private static func manualUniversalDrafts() -> [NativeManualRecordDraft] {
        var food = NativeManualRecordDraft(kind: .universal, domainKey: "food")
        food.primaryValueText = "520"
        food.dimension = "午餐"
        var sleep = NativeManualRecordDraft(kind: .universal, domainKey: "sleep")
        sleep.primaryValueText = "390"
        sleep.dimension = "良好"
        var reading = NativeManualRecordDraft(kind: .universal, domainKey: "reading")
        reading.primaryValueText = "25"
        reading.dimension = "原则"
        return [food, sleep, reading]
    }

    private static func stubSession() -> SupabaseAuthSession {
        SupabaseAuthSession(
            accessToken: "test-token",
            refreshToken: "refresh-token",
            expiresIn: 3_600,
            expiresAt: Int(Date().addingTimeInterval(3_600).timeIntervalSince1970),
            tokenType: "bearer",
            user: SupabaseUser(id: "cloud-user", email: "user@example.com")
        )
    }

    private static func syncState(binding: LocalWorkspaceBinding) -> LocalSyncState {
        LocalSyncState(
            workspaceID: UUID(),
            binding: binding,
            status: .disabled,
            conflictState: .none,
            syncGeneration: 0,
            pullCursor: nil,
            lastSuccessfulSyncAt: nil,
            activeAttemptID: nil,
            pendingMutationCount: 0
        )
    }
}

/// 文件级 fixture：从非隔离的测试替身中构造 NativeRecordDetail，
/// 避免调用 @MainActor 测试类静态方法导致隐式异步。
private enum SL02RemoteExpenseFixture {
    static func detail() -> NativeRecordDetail {
        NativeRecordDetail(
            id: "expense/11111111-1111-1111-1111-111111111111",
            rawId: "11111111-1111-1111-1111-111111111111",
            kind: "expense",
            title: "云端便利店",
            subtitle: "",
            value: "¥12.50",
            detailRows: [],
            imageURL: nil,
            imageLoadError: false,
            imagePath: nil,
            imageHash: nil,
            amount: 12.5,
            merchantName: "云端便利店",
            platform: "线上",
            category: "餐饮",
            paymentMethod: "微信支付",
            recordDate: "2026-08-20",
            note: nil,
            companionMessage: nil,
            accountId: "22222222-2222-2222-2222-222222222222",
            systemImage: "creditcard",
            payload: nil
        )
    }
}

private final class SL02Counter {
    private(set) var value = 0
    var current: Int { value }
    func increment() { value += 1 }
}

private struct SL02Harness {
    let state: AppState
    let databaseURL: URL
    let factReader: LocalFactReader
    let recordSpy: SL02RecordRepositorySpy
    let expenseStub: SL02ExpenseUseCaseStub
    let expenseRepository: LocalExpenseRepository
    let expenseUseCase: LocalExpenseUseCaseProtocol
    let recordUseCase: LocalRecordUseCase
    let profile: LocalProfile
    let sessionCounter: SL02Counter

    func cleanup() {
        try? FileManager.default.removeItem(at: databaseURL.deletingLastPathComponent())
    }
}

private enum SL02TestError: Error {
    case missingSession
    case unexpectedFailure(String)
}

extension LocalFirstSL02ProjectionTests {

    fileprivate static func makeHarness(
        session: SupabaseAuthSession?,
        expenseStub: Bool
    ) throws -> SL02Harness {
        let databaseURL = try temporaryDatabaseURL()
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = try LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let recordRepository = try LocalRecordRepository(database: database)

        let resolvedExpenseUseCase: LocalExpenseUseCaseProtocol
        let stub = SL02ExpenseUseCaseStub()
        if expenseStub {
            resolvedExpenseUseCase = stub
        } else {
            resolvedExpenseUseCase = LocalExpenseUseCase(profileStore: profileStore, repository: expenseRepository)
        }
        let recordUseCase = LocalRecordUseCase(profileStore: profileStore, repository: recordRepository)
        let factReader = try LocalFactReader(database: database)

        let recordSpy = SL02RecordRepositorySpy()
        let sessionCounter = SL02Counter()
        let sessionProvider: NativeSessionProvider
        if let session {
            sessionProvider = { _ in
                sessionCounter.increment()
                return session
            }
        } else {
            sessionProvider = { _ in
                sessionCounter.increment()
                throw SL02TestError.missingSession
            }
        }

        let state = AppState(
            dashboardRepository: SL02DashboardRepositoryStub(),
            recordRepository: recordSpy,
            localExpenseUseCase: resolvedExpenseUseCase,
            localRecordUseCase: recordUseCase,
            localFactReader: factReader,
            domainRepository: SL02DomainRepositoryStub(),
            snapshotStore: SL02SnapshotStoreStub(),
            financeVocabularyRepository: SL02FinanceVocabularyRepositoryStub(),
            sessionProvider: sessionProvider
        )

        return SL02Harness(
            state: state,
            databaseURL: databaseURL,
            factReader: factReader,
            recordSpy: recordSpy,
            expenseStub: stub,
            expenseRepository: expenseRepository,
            expenseUseCase: resolvedExpenseUseCase,
            recordUseCase: recordUseCase,
            profile: profile,
            sessionCounter: sessionCounter
        )
    }

    fileprivate static func temporaryDatabaseURL() throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SL02-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        return directoryURL.appendingPathComponent("local.sqlite")
    }
}

// MARK: - 测试替身

private final class SL02RecordRepositorySpy: RecordRepositoryProtocol {
    private(set) var fetchMonthKeys: [String] = []
    private(set) var createDrafts: [NativeManualRecordDraft] = []

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        fetchMonthKeys.append(monthKey)
        return NativeRecordMonthSnapshot(
            groups: [],
            details: [SL02RemoteExpenseFixture.detail().id: SL02RemoteExpenseFixture.detail()]
        )
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        throw LocalDataError.recordNotFound
    }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail {
        detail
    }

    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup {
        .unavailable(reason: "测试桩不提供表达计划")
    }

    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback {
        throw LocalDataError.invalidRecord
    }

    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String {
        createDrafts.append(draft)
        return "data/\(UUID().uuidString)"
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        draft.reference
    }

    func delete(reference: String, accessToken: String) async throws {}

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {}
}

private final class SL02DashboardRepositoryStub: DashboardRepositoryProtocol {
    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        DashboardSnapshot()
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }
}

private final class SL02DomainRepositoryStub: DomainRepositoryProtocol {
    func fetchDefinitions(accessToken: String) async throws -> [NativeDomainDefinition] {
        []
    }
}

private final class SL02FinanceVocabularyRepositoryStub: FinanceVocabularyRepositoryProtocol {
    func fetch(accessToken: String) async throws -> [NativeFinanceVocabularyEntry] {
        []
    }

    func record(
        kind: NativeFinanceVocabularyKind,
        displayName: String,
        primaryCategory: String?,
        linkedAccountId: String?,
        accessToken: String
    ) async throws -> NativeFinanceVocabularyEntry {
        throw LocalDataError.invalidRecord
    }
}

private struct SL02SnapshotStoreStub: DashboardSnapshotStoreProtocol {
    func load(userId: String) throws -> PersistedDashboardSnapshot? { nil }
    func save(_ snapshot: DashboardSnapshot, userId: String) throws {}
    func remove(userId: String) throws {}
}

private final class SL02ExpenseUseCaseStub: LocalExpenseUseCaseProtocol {
    private let profile = LocalProfile(id: UUID(), createdAt: Date(), cloudUserID: nil, syncEnabled: false)
    private(set) var importRemoteExpenseCalls: [[LocalExpenseDraft]] = []
    private(set) var importRemoteAccountCalls: [[LocalAccount]] = []

    func prepareProfile() async throws -> LocalProfile { profile }

    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome {
        throw LocalDataError.invalidRecord
    }

    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome {
        throw LocalDataError.invalidRecord
    }

    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome {
        throw LocalDataError.invalidRecord
    }

    func month(_ monthKey: String) async throws -> LocalExpenseMonth {
        LocalExpenseMonth(profileID: profile.id, expenses: [])
    }

    func importRemoteExpenses(_ expenses: [LocalExpenseDraft]) async throws {
        importRemoteExpenseCalls.append(expenses)
    }

    func importRemoteAccounts(_ accounts: [LocalAccount]) async throws {
        importRemoteAccountCalls.append(accounts)
    }
}
