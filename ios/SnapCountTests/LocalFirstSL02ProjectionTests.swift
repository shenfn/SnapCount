import XCTest
@testable import SnapCount

/// SL-02（投影刷新收敛与特征测试加固）特征测试。
/// 覆盖场景编号：LF-001、LF-002、DM-014、SL-02-C4（写后投影刷新收敛）、SL-02-D3（三套引用前缀路由）。
/// DM-004/DM-005 阈值具名测试见 LocalPhase1DataModelTests，D6 死 API 改写见 LocalSportRecordTests。
@MainActor
final class LocalFirstSL02ProjectionTests: XCTestCase {

    func testIOSV2POLISH006F17ForegroundReadsExternalWritesWithoutCloudSession() async throws {
        try await assertForegroundReadsExternalWrites(signedIn: false)
    }

    func testIOSV2POLISH006F17ForegroundReadsExternalWritesWhenSignedIn() async throws {
        try await assertForegroundReadsExternalWrites(signedIn: true)
    }

    private func assertForegroundReadsExternalWrites(signedIn: Bool) async throws {
        let harness = try Self.makeHarness(session: signedIn ? Self.stubSession() : nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        state.isSignedIn = signedIn
        state.currentUserId = signedIn ? "cloud-user" : ""
        state.selectedDateKey = "2000-01-05"
        state.selectedDomain = .food
        let todayKey = NativeLocalDate.dateKey(Date())
        let todayMonth = NativeMonthKey.current()
        await state.loadRecordDateWindow(around: state.selectedDateKey)
        await state.loadRecordMonth(todayMonth)
        XCTAssertTrue(state.recordGroups(monthKey: "2000-01").flatMap(\.records).isEmpty)
        XCTAssertTrue(state.recordGroups(monthKey: todayMonth).flatMap(\.records).isEmpty)

        // 独立连接模拟 Intent 所属进程提交，存活 AppState 不参与此次写入。
        let externalDatabase = try LocalDatabase(databaseURL: harness.databaseURL)
        let externalUseCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: externalDatabase),
            repository: try LocalRecordRepository(database: externalDatabase)
        )
        let samples = [("2000-01-05", 430.0), (todayKey, 610.0)]
        for (dateKey, calories) in samples {
            _ = try await externalUseCase.create(LocalRecordCommand(
                id: UUID(), domainKey: "food", title: "外部合成餐食", summary: "",
                payload: ["meal_type": AnyCodable("午餐"), "total_calorie_kcal": AnyCodable(calories)],
                recordDate: dateKey, recordTime: "12:30", note: nil, imageData: nil,
                createdAt: Date(), sourceKind: .aiAutoArchive
            ))
        }
        XCTAssertTrue(state.recordGroups(monthKey: "2000-01").flatMap(\.records).isEmpty,
                      "先证明热缓存未被测试中的外部提交直接改动")

        await state.refreshDashboardIfStale(minInterval: 1, force: true)

        for (dateKey, calories) in samples {
            let monthKey = String(dateKey.prefix(7))
            let page = NativeDomainScenePresentation.make(
                domain: .food, dateKey: dateKey, weekGroups: state.recordGroups(monthKey: monthKey),
                details: state.recordDetails(from: dateKey, through: dateKey),
                isSignedIn: signedIn, isLoading: false, errorMessage: nil, todayKey: todayKey
            )
            XCTAssertEqual(page.records.count, 1, "回前台后当前月和已读历史月都应出现外部新增")
            XCTAssertEqual(page.knownPrimaryTotal, calories, "列表与详情指标必须同步重读")
        }
        XCTAssertEqual(state.selectedDateKey, "2000-01-05")
        XCTAssertEqual(state.selectedDomain, .food)
        if !signedIn {
            XCTAssertEqual(harness.sessionCounter.current, 0, "本机前台刷新不依赖云端会话")
        } else {
            XCTAssertGreaterThan(harness.sessionCounter.current, 0, "保留登录态远端刷新入口")
        }
    }

    func testIOSV2POLISH006F17NewExpensePreservesAllDomainFactsAndDetailsInWarmMonth() async throws {
        try await assertNewExpensePreservesDomainFacts(date: Date())
    }

    func testIOSV2POLISH006F17NewExpensePreservesHistoricalMonthDomainDetails() async throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-01-05T12:00:00+08:00"))
        try await assertNewExpensePreservesDomainFacts(date: date)
    }

    private func assertNewExpensePreservesDomainFacts(date: Date) async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        var food = NativeManualRecordDraft(kind: .universal, domainKey: "food")
        food.date = date
        food.time = date
        food.primaryValueText = "450"
        food.dimension = "午餐"
        let foodSaved = await state.createManualRecord(food, domain: nil)
        XCTAssertTrue(foodSaved)
        let dateKey = food.dateKey
        let monthKey = String(dateKey.prefix(7))
        let meal = try XCTUnwrap(state.recordGroups(monthKey: monthKey).flatMap(\.records).first { $0.domainKey == "food" })
        XCTAssertEqual(state.recordDetails(from: dateKey, through: dateKey)[meal.reference]?.payload?.double("total_calorie_kcal"), 450)
        let account = try harness.expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: harness.profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: food.date
        ))

        let saved = await state.createLocalExpense(
            amountText: "12.50", accountID: account.id, merchantName: "合成便利店",
            platform: "线下", category: "food", paymentMethod: "现金", date: food.date, note: ""
        )
        XCTAssertTrue(saved, state.manualRecordMessage ?? "新增支出应成功")
        let records = state.recordGroups(monthKey: monthKey).flatMap(\.records)
        XCTAssertEqual(records.count, 2)
        let expense = try XCTUnwrap(records.first { $0.kind == .expense })
        XCTAssertTrue(expense.reference.hasPrefix("expense/"), "FactReader 模式使用统一事实引用")
        let details = state.recordDetails(from: dateKey, through: dateKey)
        XCTAssertNotNil(details[expense.reference])
        XCTAssertEqual(details[meal.reference]?.payload?.double("total_calorie_kcal"), 450, "新增支出不能清掉其他域详情")
        let foodPage = NativeDomainScenePresentation.make(
            domain: .food, dateKey: dateKey, weekGroups: state.recordGroups(monthKey: monthKey),
            details: details, isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: dateKey
        )
        XCTAssertEqual(foodPage.knownPrimaryTotal, 450)
        if monthKey == NativeMonthKey.current() {
            XCTAssertTrue(state.dashboard.dayRecordGroups.flatMap(\.records).contains { $0.reference == meal.reference })
        }
        XCTAssertEqual(state.localAccountBalances[account.id], 8_750)

        await state.loadRecordMonth(monthKey)
        XCTAssertEqual(state.recordGroups(monthKey: monthKey).flatMap(\.records).count, 2)
        XCTAssertEqual(state.recordDetails(from: dateKey, through: dateKey)[meal.reference]?.payload?.double("total_calorie_kcal"), 450)
        XCTAssertEqual(harness.sessionCounter.current, 0, "本地新增及读取无需云端会话")
    }

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
        // 绑定状态走真实链路：localBindingRepository → refreshLocalSyncState
        // （validSession→apply 每次会重读绑定状态，手工塞 localSyncState 会被覆盖）
        state.refreshLocalSyncState()
        guard case .unbound = state.localSyncState?.binding else {
            throw SL02TestError.unexpectedFailure("新工作区默认应为未绑定")
        }

        await state.loadRecordMonth(monthKey, force: true)

        XCTAssertEqual(harness.recordSpy.fetchMonthKeys, [monthKey])
        XCTAssertTrue(harness.expenseStub.importRemoteExpenseCalls.isEmpty, "未绑定时不得把云端消费写入本地")
        XCTAssertTrue(harness.expenseStub.importRemoteAccountCalls.isEmpty)

        _ = try harness.bindingRepository.confirmBinding(
            profileID: harness.profile.id,
            cloudUserID: "cloud-user"
        )
        state.refreshLocalSyncState()
        guard case .bound = state.localSyncState?.binding else {
            throw SL02TestError.unexpectedFailure("确认绑定后 syncState 应为 bound")
        }
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

    // IOS-V2-SHELL-005A：通过实际本地写入与重开数据库验证域页，不能手填领域计数。
    func testIOSV2SHELL005ALocalDomainPagesFollowCreateReopenAndDelete() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()

        func presentation(for domain: AppDomain, in state: AppState) -> NativeDomainScenePresentation {
            let dateKey = NativeLocalDate.dateKey(Date())
            return NativeDomainScenePresentation.make(
                domain: domain, dateKey: dateKey,
                weekGroups: state.recordGroups(monthKey: NativeMonthKey.current()),
                details: state.recordDetails(from: dateKey, through: dateKey),
                isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: dateKey
            )
        }

        var sport = NativeManualRecordDraft(kind: .universal, domainKey: "sport")
        sport.primaryValueText = "30"
        sport.dimension = "跑步"
        for draft in Self.manualUniversalDrafts() + [sport] {
            let saved = await state.createManualRecord(draft, domain: nil)
            XCTAssertTrue(saved, "\(draft.domainKey) 创建应成功")
        }

        let domains: [AppDomain] = [.sleep, .food, .sport, .reading]
        for domain in domains {
            let model = presentation(for: domain, in: state)
            XCTAssertFalse(model.records.isEmpty, "\(domain.title) 已有本地事实，不应显示空态")
            XCTAssertEqual(model.records.count, 1)
        }

        let reopenedDatabase = try LocalDatabase(databaseURL: harness.databaseURL)
        let reopenedStore = LocalProfileStore(database: reopenedDatabase)
        let reopenedUseCase = LocalRecordUseCase(
            profileStore: reopenedStore,
            repository: try LocalRecordRepository(database: reopenedDatabase)
        )
        let reopenedState = AppState(
            localExpenseUseCase: harness.expenseUseCase,
            localRecordUseCase: reopenedUseCase,
            localFactReader: try LocalFactReader(database: reopenedDatabase),
            localBindingRepository: reopenedStore,
            sessionProvider: { _ in throw SL02TestError.missingSession }
        )
        let monthKey = NativeMonthKey.current()
        await reopenedState.loadRecordMonth(monthKey, force: true)

        for domain in domains {
            let reopenedModel = presentation(for: domain, in: reopenedState)
            XCTAssertFalse(reopenedModel.records.isEmpty, "重开数据库后\(domain.title)仍应非空")
            XCTAssertEqual(reopenedModel.records.count, 1)

            let record = try XCTUnwrap(reopenedState.recordGroups(monthKey: monthKey)
                .flatMap(\.records).first { $0.domainKey == domain.rawValue })
            let deleted = await reopenedState.deleteRecord(reference: record.reference)
            XCTAssertTrue(deleted)
            XCTAssertFalse(reopenedState.recordGroups(monthKey: monthKey)
                .flatMap(\.records).contains { $0.reference == record.reference },
                "正式列表也必须移除已删除记录，不能只改域页计数")
            let emptyModel = presentation(for: domain, in: reopenedState)
            XCTAssertTrue(emptyModel.records.isEmpty, "删除最后一条\(domain.title)记录后应显示空态")
            XCTAssertEqual(emptyModel.records.count, 0)
        }
        XCTAssertEqual(harness.sessionCounter.current, 0)
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
    let bindingRepository: LocalBindingRepository
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
            localBindingRepository: profileStore,
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
            bindingRepository: profileStore,
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
