import XCTest
@testable import SnapCount

/// SL-02（投影刷新收敛与特征测试加固）特征测试。
/// 覆盖场景编号：LF-001、LF-002、DM-014、SL-02-C4（写后投影刷新收敛）、SL-02-D3（三套引用前缀路由）。
/// DM-004/DM-005 阈值具名测试见 LocalPhase1DataModelTests，D6 死 API 改写见 LocalSportRecordTests。
@MainActor
final class LocalFirstSL02ProjectionTests: XCTestCase {
    func testIOSV2POLISH006F17ForcedLocalReadCannotBeOverwrittenByOlderSnapshot() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: true)
        defer { harness.cleanup() }
        let gate = SL02DashboardGate()
        let expense = LocalExpense(id: UUID(), profileID: harness.profile.id, accountID: UUID(), amountMinor: 1250,
            currency: "CNY", merchantName: "写后事实", platform: "线下", category: "food", paymentMethod: "现金",
            transactionDate: "2000-01-05", transactionTime: nil, note: nil, localVersion: 1, createdAt: Date(), updatedAt: Date())
        harness.expenseStub.monthProvider = { _ in
            if await gate.nextCallNumber() == 1 {
                await gate.enterAndWait()
                return LocalExpenseMonth(profileID: expense.profileID, expenses: [])
            }
            return LocalExpenseMonth(profileID: expense.profileID, expenses: [expense])
        }
        let counter = harness.sessionCounter
        let state = AppState(localExpenseUseCase: harness.expenseStub, localRecordUseCase: harness.recordUseCase,
            localBindingRepository: harness.bindingRepository,
            sessionProvider: { _ in counter.increment(); throw SL02TestError.missingSession })
        state.resetUserScopedState()
        let first = Task { @MainActor in await state.loadRecordMonth("2000-01") }
        await gate.waitUntilEntered()
        await state.loadRecordMonth("2000-01", force: true)
        XCTAssertEqual(state.recordGroups(monthKey: "2000-01").flatMap(\.records).map(\.title), ["写后事实"])
        await gate.release()
        await first.value
        XCTAssertEqual(state.recordGroups(monthKey: "2000-01").flatMap(\.records).map(\.title), ["写后事实"])
        XCTAssertFalse(state.isLoadingRecordMonth("2000-01"))
        XCTAssertEqual(counter.current, 0)
    }

    func testIOSV2POLISH002AF03CurrentMonthCancellationReentryAwaitsSharedDashboard() async throws {
        let gate = SL02DashboardGate()
        let day = NativeLocalDate.dateKey(Date())
        let month = NativeMonthKey.current()
        let record = NativeDayRecord(id: "cloud-meal", reference: "data/cloud-meal", dateKey: day, kind: .food,
            domainKey: "food", title: "云端餐食", subtitle: "", value: "", timeLabel: nil, systemImage: "fork.knife", status: "done")
        let repository = SL02DashboardRepositoryStub(gate: gate, snapshot: DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: day, records: [record])
        ]))
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: false, dashboard: repository)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        _ = try harness.bindingRepository.confirmBinding(profileID: harness.profile.id, cloudUserID: "cloud-user")
        state.refreshLocalSyncState()
        let first = Task { @MainActor in await state.loadRecordMonth(month, force: true) }
        await gate.waitUntilEntered()
        XCTAssertTrue(state.isLoadingRecordMonth(month))
        first.cancel()
        let early = expectation(description: "重入不得在共享请求完成前返回")
        early.isInverted = true
        var released = false
        let second = Task { @MainActor in
            await state.loadRecordMonth(month)
            if !released { early.fulfill() }
        }
        await fulfillment(of: [early], timeout: 0.1)
        released = true
        await gate.release()
        await first.value
        await second.value
        XCTAssertEqual(repository.fetchCount, 1)
        XCTAssertTrue(state.recordGroups(monthKey: month).flatMap(\.records).contains { $0.reference == record.reference })
        XCTAssertFalse(state.isLoadingRecordMonth(month))
        XCTAssertNil(state.dashboardMessage)
    }

    func testIOSV2POLISH006F17RemoteHistoricalWritesRefreshBothMonthSnapshots() async throws {
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        state.selectedDateKey = "2000-01-05"
        _ = try harness.bindingRepository.confirmBinding(profileID: harness.profile.id, cloudUserID: "cloud-user")
        state.refreshLocalSyncState()
        let original = harness.recordSpy.seedFood(date: "2000-01-05", calories: 430)
        await state.loadRecordMonth("2000-01")
        XCTAssertEqual(state.recordGroups(monthKey: "2000-01").flatMap(\.records).count, 1)
        var fullForm = NativeManualRecordDraft(detail: original)
        fullForm.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-02-06T12:30:00+08:00"))
        fullForm.primaryValueText = "610"
        let moved = await state.createManualRecord(fullForm, domain: nil)
        XCTAssertTrue(moved)
        XCTAssertTrue(state.recordGroups(monthKey: "2000-01").flatMap(\.records).isEmpty)
        XCTAssertEqual(state.recordGroups(monthKey: "2000-02").flatMap(\.records).count, 1)
        let detail = try XCTUnwrap(state.recordDetails(from: "2000-02-06", through: "2000-02-06")[original.id])
        XCTAssertEqual(detail.payload?.double("total_calorie_kcal"), 610)
        var editor = NativeRecordEditDraft(detail: detail)
        editor.recordDate = "2000-03-07"
        let edited = await state.saveRecordDetail(editor)
        XCTAssertTrue(edited)
        XCTAssertTrue(state.recordGroups(monthKey: "2000-02").flatMap(\.records).isEmpty)
        XCTAssertEqual(state.recordGroups(monthKey: "2000-03").flatMap(\.records).count, 1)
        let deleted = await state.deleteRecord(reference: original.id)
        XCTAssertTrue(deleted)
        XCTAssertTrue(state.recordGroups(monthKey: "2000-03").flatMap(\.records).isEmpty)
    }

    func testIOSV2POLISH002AF07HomeDetailsAndDrillsPreserveSourceContext() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        state.selectedDateKey = "2000-01-05"
        state.selectedDomain = .food
        let record = NativeDayRecord(id: "meal", reference: "data/meal", dateKey: "2000-01-05", kind: .food,
            domainKey: "food", title: "餐食", subtitle: "", value: "", timeLabel: nil, systemImage: "fork.knife")
        state.openDayRecord(record)
        XCTAssertEqual(state.presentedOverlay, .none)
        XCTAssertEqual(state.recordsPath.count, 0)
        XCTAssertEqual(state.homePath.count, 1)
        state.homePath.removeLast()
        state.openDomainDrill(.sport, dateKey: "1999-12-31")
        XCTAssertEqual(state.homePath.count, 1)
        XCTAssertEqual(state.selectedDateKey, "2000-01-05")
        XCTAssertEqual(state.selectedDomain, .food)
        state.homePath.removeLast()
        XCTAssertEqual(state.selectedDateKey, "2000-01-05")
        state.resetUserScopedState()
        XCTAssertEqual(state.homePath.count, 0)
    }

    func testIOSV2POLISH006F17FullFormMoveRefreshesOldAndNewMonths() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "food")
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-01-05T12:00:00+08:00"))
        draft.primaryValueText = "430"
        draft.dimension = "午餐"
        let created = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(created)
        let original = try XCTUnwrap(state.recordGroups(monthKey: "2000-01").flatMap(\.records).first)
        draft.existingRawId = original.id
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-02-06T12:00:00+08:00"))
        draft.primaryValueText = "610"
        let saved = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(saved)
        XCTAssertTrue(state.recordGroups(monthKey: "2000-01").flatMap(\.records).isEmpty)
        XCTAssertEqual(state.recordGroups(monthKey: "2000-02").flatMap(\.records).count, 1)
        XCTAssertEqual(state.recordDetails(from: "2000-02-06", through: "2000-02-06")[original.reference]?.payload?.double("total_calorie_kcal"), 610)
    }

    func testIOSV2POLISH006F17CandidateCompletionPersistsEditedFactsAtomically() async throws {
        let harness = try Self.makeHarness(session: nil, expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.resetUserScopedState()
        let staged = try await harness.recordUseCase.stage(LocalRecordCandidate(
            id: "edited-meal", domainKey: "food", title: "原候选", summary: "原摘要",
            payload: ["meal_type": AnyCodable("午餐"), "total_calorie_kcal": AnyCodable(100)],
            confidence: 0.4, recordDate: "2000-01-05", recordTime: "12:30", imageData: nil, createdAt: Date()
        ))
        let candidate = LocalStagingReadModel.native(from: staged.record, imageStore: nil)
        var draft = NativeManualRecordDraft(stagingRecord: candidate, domainKey: "food")
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2000-02-06T08:00:00+08:00"))
        draft.title = "已补全早餐"
        draft.primaryValueText = "610"
        draft.dimension = "早餐"
        draft.includesTime = false
        draft.note = "用户补全"
        let reference = await state.archiveStagingRecord(candidate, draft: draft, domain: nil)
        XCTAssertNotNil(reference, state.inboxActionMessage ?? "")
        let records = try await harness.recordUseCase.records(monthKey: "2000-02")
        let saved = try XCTUnwrap(records.first)
        XCTAssertEqual(saved.recordDate, "2000-02-06")
        XCTAssertNil(saved.recordTime, "明确移除时间不能回退为候选旧时间")
        XCTAssertEqual(saved.title, "已补全早餐")
        XCTAssertEqual(saved.note, "用户补全")
        XCTAssertEqual(try LocalRecordCodec.decode(saved.payloadJSON).double("total_calorie_kcal"), 610)
        let old = try await harness.recordUseCase.records(monthKey: "2000-01")
        XCTAssertTrue(old.isEmpty)
        let retry = try await harness.recordUseCase.confirmStaging(id: staged.record.id, recordID: UUID())
        XCTAssertEqual(retry.record.id, saved.id, "重试仍返回首次正式事实，不重复落库")
    }

    func testIOSV2POLISH006F17ForegroundReadsExternalWritesWithoutCloudSession() async throws {
        try await assertForegroundReadsExternalWrites(signedIn: false)
    }

    func testLF03402ForegroundReadsExternalLocalWritesWhenSignedInWithoutSync() async throws {
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
        // 此场景的前提是外部提交已经成功；预热本地缓存不启动并发云端补充写入。
        await state.refreshLocalRecognitionProjection(monthKey: "2000-01")
        await state.refreshLocalRecognitionProjection(monthKey: todayMonth)
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
            XCTAssertEqual(harness.sessionCounter.current, 0, "同步关闭时登录态前台刷新仍仅读取本地")
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

    // MARK: - LF-034.03：登录不改变四域手动创建的本地事实路径

    func testLF03403SignedInManualUniversalRecordWritesLocalFactsWithoutCloudCreation() async throws {
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
        XCTAssertEqual(state.manualRecordMessage, "记录已保存（本机）")
        XCTAssertTrue(harness.recordSpy.createDrafts.isEmpty)

        let monthKey = NativeMonthKey.current()
        let facts = try harness.factReader.month(profileID: harness.profile.id, monthKey: monthKey)
        XCTAssertEqual(facts.facts.map(\.domainKey), ["sport"])
        XCTAssertTrue(state.recordGroups(monthKey: monthKey).flatMap(\.records).contains { $0.domainKey == "sport" })
        XCTAssertEqual(harness.sessionCounter.current, 0, "登录态本地新建不应读取会话或触发云端写入")
    }

    func testLF03402SignedInWithoutSyncDoesNotReadRemoteBusinessRecords() async throws {
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: false)
        defer { harness.cleanup() }
        let state = harness.state
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        state.refreshLocalSyncState()

        await state.loadRecordMonth(NativeMonthKey.current(), force: true)

        XCTAssertTrue(harness.recordSpy.fetchMonthKeys.isEmpty, "登录本身不能触发云端业务读取")
        XCTAssertTrue(state.recordGroups(monthKey: NativeMonthKey.current()).flatMap(\.records).isEmpty)
    }

    func testLF03402SignedInWithoutSyncBuildsDashboardFromLocalFacts() async throws {
        let dashboardRepository = SL02DashboardRepositoryStub()
        let harness = try Self.makeHarness(
            session: Self.stubSession(),
            expenseStub: false,
            dashboard: dashboardRepository
        )
        defer { harness.cleanup() }
        let dateKey = NativeLocalDate.dateKey(Date())
        _ = try await harness.recordUseCase.create(LocalRecordCommand(
            id: UUID(),
            domainKey: "food",
            title: "本地早餐",
            summary: "本地事实",
            payload: [
                "meal_type": AnyCodable("早餐"),
                "total_calorie_kcal": AnyCodable(320)
            ],
            recordDate: dateKey,
            recordTime: "08:00",
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        harness.state.isSignedIn = true
        harness.state.currentUserId = "cloud-user"
        harness.state.refreshLocalSyncState()

        await harness.state.refreshDashboard()

        XCTAssertEqual(dashboardRepository.fetchCount, 0, "同步关闭时首页不应请求远端")
        XCTAssertEqual(harness.state.dashboard.todayCount, 1)
        XCTAssertTrue(harness.state.dashboard.dayRecordGroups.flatMap(\.records).contains { $0.title == "本地早餐" })
        XCTAssertFalse(harness.state.isShowingCachedDashboard)
        XCTAssertEqual(harness.sessionCounter.current, 0)
    }

    func testLF03404SignedInWithoutSyncReadsLocalAccountAndLedger() async throws {
        let harness = try Self.makeHarness(session: Self.stubSession(), expenseStub: false)
        defer { harness.cleanup() }
        let accountID = UUID()
        _ = try await harness.expenseUseCase.createAccount(LocalAccountSetupCommand(
            id: accountID,
            name: "本地现金账户",
            kind: "cash",
            openingBalanceText: "100",
            createdAt: Date()
        ))
        _ = try await harness.expenseUseCase.create(LocalExpenseCommand(
            id: UUID(),
            accountID: accountID,
            amountText: "15.00",
            currency: "CNY",
            merchantName: "本地流水",
            platform: "线下",
            category: "food",
            paymentMethod: "现金",
            transactionDate: NativeLocalDate.dateKey(Date()),
            transactionTime: nil,
            note: nil,
            createdAt: Date()
        ))
        let state = harness.state
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        state.refreshLocalSyncState()

        await state.loadAccounts()
        let account = try XCTUnwrap(state.accounts.first { $0.id == accountID.uuidString })
        await state.loadAccountDetail(account)

        XCTAssertEqual(state.selectedAccountDetail?.account.id, accountID.uuidString)
        XCTAssertEqual(state.selectedAccountDetail?.entries.count, 1)
        XCTAssertEqual(state.selectedAccountDetail?.account.currentBalance, 85)
        XCTAssertTrue(harness.accountRepository.fetchAccountsCalls.isEmpty)
        XCTAssertEqual(harness.accountRepository.fetchDetailCalls, 0)
        XCTAssertEqual(harness.sessionCounter.current, 0)
    }

    // MARK: - LF-034.02 / DM-014：登录本身不拉取云端业务事实，绑定后按授权读取

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

        XCTAssertTrue(harness.recordSpy.fetchMonthKeys.isEmpty, "未绑定时不得读取云端业务记录")
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

        XCTAssertEqual(harness.recordSpy.fetchMonthKeys, [monthKey])
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
        XCTAssertEqual(recordDraft.localVersion, recordOutcome.record.localVersion)
        recordDraft.note = "编辑后备注"
        let recordSaved = await state.saveRecordDetail(recordDraft)
        XCTAssertTrue(recordSaved)
        let staleRecordSaved = await state.saveRecordDetail(recordDraft)
        XCTAssertFalse(staleRecordSaved, "陈旧详情版本不得覆盖已保存的本地记录")

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
    let accountRepository: SL02AccountRepositoryStub
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
        expenseStub: Bool,
        dashboard: SL02DashboardRepositoryStub = SL02DashboardRepositoryStub()
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

        let accountRepository = SL02AccountRepositoryStub()
        let state = AppState(
            dashboardRepository: dashboard,
            recordRepository: recordSpy,
            localExpenseUseCase: resolvedExpenseUseCase,
            localRecordUseCase: recordUseCase,
            localFactReader: factReader,
            domainRepository: SL02DomainRepositoryStub(),
            snapshotStore: SL02SnapshotStoreStub(),
            accountRepository: accountRepository,
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
            accountRepository: accountRepository,
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
    private var mutableFood: [String: NativeRecordDetail]?

    func seedFood(date: String, calories: Double) -> NativeRecordDetail {
        let detail = foodDetail(reference: "data/\(UUID().uuidString)", title: "云端合成餐食", date: date,
                                payload: ["meal_type": AnyCodable("午餐"), "total_calorie_kcal": AnyCodable(calories)])
        mutableFood = [detail.id: detail]
        return detail
    }

    private func foodDetail(reference: String, title: String, date: String, payload: [String: AnyCodable]) -> NativeRecordDetail {
        NativeRecordDetail(id: reference, rawId: NativeRecordReference(reference).rawId, kind: "data",
            title: title, subtitle: date, value: "", detailRows: [], imageURL: nil, imageLoadError: false,
            imagePath: nil, imageHash: nil, amount: nil, merchantName: nil, platform: nil, category: nil,
            paymentMethod: nil, recordDate: date, note: nil, companionMessage: nil, accountId: nil,
            systemImage: "fork.knife", payload: payload, domainKey: "food")
    }

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        fetchMonthKeys.append(monthKey)
        if let mutableFood {
            let details = mutableFood.values.filter { $0.recordDate?.hasPrefix(monthKey) == true }
            let records = details.map { detail in
                NativeDayRecord(id: detail.rawId, reference: detail.id, dateKey: detail.recordDate!, kind: .food,
                    domainKey: "food", title: detail.title, subtitle: "", value: "", timeLabel: nil, systemImage: "fork.knife")
            }
            let groups = Dictionary(grouping: records, by: \.dateKey).map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value) }
            return NativeRecordMonthSnapshot(groups: groups, details: Dictionary(uniqueKeysWithValues: details.map { ($0.id, $0) }))
        }
        return NativeRecordMonthSnapshot(
            groups: [],
            details: [SL02RemoteExpenseFixture.detail().id: SL02RemoteExpenseFixture.detail()]
        )
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        if let detail = mutableFood?[reference] { return detail }
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
        if mutableFood != nil {
            let reference = "data/\(draft.existingRawId ?? UUID().uuidString)"
            mutableFood?[reference] = foodDetail(reference: reference, title: draft.resolvedTitle(domain: domain), date: draft.dateKey,
                                                  payload: draft.universalPayload(domain: domain))
            return reference
        }
        return "data/\(UUID().uuidString)"
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        if let current = mutableFood?[draft.reference] {
            mutableFood?[draft.reference] = foodDetail(reference: draft.reference, title: draft.title, date: draft.recordDate,
                                                       payload: current.payload ?? [:])
        }
        return draft.reference
    }

    func delete(reference: String, accessToken: String) async throws { _ = mutableFood?.removeValue(forKey: reference) }

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {}
}

private final class SL02DashboardRepositoryStub: DashboardRepositoryProtocol {
    private let gate: SL02DashboardGate?
    private let snapshot: DashboardSnapshot
    private(set) var fetchCount = 0

    init(gate: SL02DashboardGate? = nil, snapshot: DashboardSnapshot = DashboardSnapshot()) {
        self.gate = gate
        self.snapshot = snapshot
    }

    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        fetchCount += 1
        if let gate { await gate.enterAndWait() }
        return snapshot
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }
}

private actor SL02DashboardGate {
    private var callNumber = 0
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func nextCallNumber() -> Int { callNumber += 1; return callNumber }

    func enterAndWait() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
    }

    func waitUntilEntered() async {
        if !entered { await withCheckedContinuation { enteredWaiters.append($0) } }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private final class SL02DomainRepositoryStub: DomainRepositoryProtocol {
    func fetchDefinitions(accessToken: String) async throws -> [NativeDomainDefinition] {
        []
    }
}

private final class SL02AccountRepositoryStub: AccountRepositoryProtocol {
    private(set) var fetchAccountsCalls: [String] = []
    private(set) var fetchDetailCalls = 0
    func fetchAccounts(accessToken: String) async throws -> [NativeAccount] {
        fetchAccountsCalls.append(accessToken)
        return []
    }
    func fetchDetail(account: NativeAccount, accessToken: String) async -> NativeAccountDetail {
        fetchDetailCalls += 1
        return NativeAccountDetail(account: account, entries: [], repaymentCycles: [], payments: [], loadErrors: [:])
    }
    func fetchOpenRepaymentCycles(accessToken: String) async throws -> [NativeRepaymentCycle] { [] }
    func save(_ draft: NativeAccountDraft, userId: String, accessToken: String) async throws -> [NativeAccount] {
        throw SL02TestError.unexpectedFailure("测试不应修改账户")
    }
    func setArchived(accountId: String, archived: Bool, accessToken: String) async throws -> [NativeAccount] {
        throw SL02TestError.unexpectedFailure("测试不应归档账户")
    }
    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws {
        throw SL02TestError.unexpectedFailure("测试不应创建还款周期")
    }
    func confirmRepayment(cycleId: String, paidAmount: Double, debitAccountId: String?, status: NativeRepaymentStatus,
                          note: String, accessToken: String) async throws -> NativeRepaymentCycle {
        throw SL02TestError.unexpectedFailure("测试不应还款")
    }
    func revokePayment(paymentId: String, accessToken: String) async throws -> NativeRepaymentCycle? {
        throw SL02TestError.unexpectedFailure("测试不应撤销还款")
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
    var monthProvider: ((String) async throws -> LocalExpenseMonth)?
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
        if let monthProvider { return try await monthProvider(monthKey) }
        return LocalExpenseMonth(profileID: profile.id, expenses: [])
    }

    func importRemoteExpenses(_ expenses: [LocalExpenseDraft]) async throws {
        importRemoteExpenseCalls.append(expenses)
    }

    func importRemoteAccounts(_ accounts: [LocalAccount]) async throws {
        importRemoteAccountCalls.append(accounts)
    }
}
