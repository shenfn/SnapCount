import XCTest
import GRDB
@testable import SnapCount

final class LocalExpenseAppUseCaseTests: XCTestCase {
    func testLocalAppBoundaryTypesExistBeforeImplementation() {
        XCTAssertNotNil(LocalProfileStoreProtocol.self)
        XCTAssertNotNil(LocalExpenseUseCaseProtocol.self)
    }

    func testLocalProfileIsResolvedWithoutCloudSession() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = LocalProfileStore(database: try LocalDatabase(databaseURL: databaseURL))
        let profile = try store.activeProfile()

        XCTAssertNil(profile.cloudUserID)
        XCTAssertFalse(profile.syncEnabled)
    }

    func testLocalProfilePersistsAcrossDatabaseReopen() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let first = try LocalProfileStore(
            database: LocalDatabase(databaseURL: databaseURL)
        ).activeProfile()
        let reopened = try LocalProfileStore(
            database: LocalDatabase(databaseURL: databaseURL)
        ).activeProfile()

        XCTAssertEqual(reopened.id, first.id)
        XCTAssertEqual(reopened.cloudUserID, first.cloudUserID)
        XCTAssertEqual(reopened.syncEnabled, first.syncEnabled)
        XCTAssertEqual(
            reopened.createdAt.timeIntervalSince1970,
            first.createdAt.timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testAmountMapperUsesDecimalMinorUnits() throws {
        XCTAssertEqual(try LocalExpenseMapper.amountMinor("10.235"), 1_024)
        XCTAssertEqual(try LocalExpenseMapper.amountMinor("0.01"), 1)
        XCTAssertThrowsError(try LocalExpenseMapper.amountMinor("0"))
    }

    func testUseCaseCreatesAndProjectsExpenseWithoutNetworkDependency() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let store = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try store.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 10_000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let useCase = LocalExpenseUseCase(
            profileStore: store,
            repository: repository,
            operationIDProvider: { UUID(uuidString: "11111111-1111-1111-1111-111111111111")! }
        )

        let outcome = try await useCase.create(LocalExpenseCommand(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            accountID: account.id,
            amountText: "12.30",
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: "2026-08-23",
            transactionTime: "08:30",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100)
        ))
        let month = try await useCase.month("2026-08")
        let groups = LocalExpenseReadModel.groups(from: month)

        XCTAssertEqual(outcome.profileID, profile.id)
        XCTAssertEqual(outcome.expense?.amountMinor, 1_230)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 8_770)
        XCTAssertEqual(groups.first?.records.first?.reference, "local-expense/22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(groups.first?.records.first?.value, "¥12.30")
    }

    @MainActor
    func testLF01401LoadsBasicInsightWithoutSessionOrRemoteAI() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        _ = try LocalProfileStore(database: database).activeProfile()
        let state = AppState(
            localFactReader: try LocalFactReader(database: database),
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )

        await state.loadInsights(range: .seven)

        XCTAssertNotNil(state.insightsSnapshot)
        XCTAssertEqual(state.insightsSnapshot?.range, .seven)
        XCTAssertNil(state.insightsMessage)
        XCTAssertNil(state.aiInsight)
    }

    @MainActor
    func testLF03738AccountFormCreatesAndReadsLiabilityOffline() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let debitAccount = try repository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 20_000, createdAt: Date()
        ))
        let useCase = LocalExpenseUseCase(profileStore: profileStore, repository: repository)
        let state = AppState(
            localExpenseUseCase: useCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        var draft = NativeAccountDraft()
        draft.name = "示例信用卡"
        draft.type = .creditCard
        draft.institution = "示例银行"
        draft.last4 = "1234"
        draft.initialBalanceText = "500.00"
        draft.billDayText = "15"
        draft.paymentDueDayText = "25"
        draft.gracePeriodDaysText = "3"
        draft.autoDebitAccountId = debitAccount.id.uuidString

        let didSave = await state.saveAccount(draft)
        XCTAssertTrue(didSave)
        let saved = try XCTUnwrap(state.accounts.first { $0.type == .creditCard })
        XCTAssertEqual(saved.institution, "示例银行")
        XCTAssertEqual(saved.last4, "1234")
        XCTAssertEqual(saved.currentBalance, 500, accuracy: 0.001)
        XCTAssertEqual(saved.billDay, 15)
        XCTAssertEqual(saved.paymentDueDay, 25)
        XCTAssertEqual(saved.autoDebitAccountId, debitAccount.id.uuidString)
        XCTAssertEqual(saved.gracePeriodDays, 3)
        XCTAssertEqual(state.accountMessage, "账户已保存在此设备")

        await state.loadAccountDetail(saved)
        XCTAssertEqual(state.selectedAccountDetail?.account.id, saved.id)
        XCTAssertNil(state.accountMessage)
        let archived = await state.setAccountArchived(saved, archived: true)
        XCTAssertTrue(archived)
        let archivedAccount = try XCTUnwrap(state.accounts.first { $0.id == saved.id })
        XCTAssertTrue(archivedAccount.isArchived)
        XCTAssertEqual(archivedAccount.currentBalance, 500, accuracy: 0.001)
        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let reopenedAccount = try XCTUnwrap(reopened.accounts(profileID: profile.id).first { $0.kind == "credit_card" })
        XCTAssertEqual(reopenedAccount.last4, "1234")
        XCTAssertTrue(reopenedAccount.isArchived)
    }

    @MainActor
    func testLF03711OfflineAccountDetailConfirmsAndRevokesRepaymentLocally() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let current = Date()
        let currentMonth = NativeLocalDate.monthKey(from: NativeLocalDate.dateKey(current))!
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: current))!
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonthStart)!
        let expenseDate = calendar.date(bySetting: .day, value: 20, of: previousMonth)!
        let liabilityID = UUID(), debitID = UUID()
        _ = try repository.createAccount(LocalAccountDraft(
            id: debitID, profileID: profile.id, name: "本机现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 20_000, createdAt: current
        ))
        _ = try repository.createAccount(LocalAccountDraft(
            id: liabilityID, profileID: profile.id, name: "本机信用卡", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: current, billDay: 15, paymentDueDay: 25,
            autoDebitAccountID: debitID
        ))
        _ = try repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: liabilityID, amountMinor: 5_000,
            currency: "CNY", merchantName: "合成账单消费", platform: "", category: "other",
            paymentMethod: "credit_card", transactionDate: NativeLocalDate.dateKey(expenseDate),
            transactionTime: nil, note: nil, createdAt: current
        ), operationID: UUID())
        let useCase = LocalExpenseUseCase(profileStore: profileStore, repository: repository)
        let state = AppState(
            localExpenseUseCase: useCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        await state.prepareLocalWorkspace()
        await state.loadAccounts()
        let account = try XCTUnwrap(state.accounts.first { $0.id == liabilityID.uuidString })
        await state.loadAccountDetail(account)
        let cycle = try XCTUnwrap(state.selectedAccountDetail?.repaymentCycles.first { $0.cycleMonth == currentMonth })
        XCTAssertEqual(cycle.statementAmount, 50, accuracy: 0.001)

        let confirmed = await state.confirmRepayment(
            cycle: cycle, paidAmount: 30, debitAccountId: debitID.uuidString, status: .partialPaid, note: "离线测试"
        )
        XCTAssertTrue(confirmed)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 15_000 - 3_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 17_000)
        let payment = try XCTUnwrap(state.selectedAccountDetail?.payments.first { $0.status == "confirmed" })

        let revoked = await state.revokeLiabilityPayment(payment: payment, accountId: liabilityID.uuidString)
        XCTAssertTrue(revoked)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 15_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 20_000)
        XCTAssertEqual(state.selectedAccountDetail?.payments.first?.status, "voided")
    }

    @MainActor
    func testLF03201ManualIncomePersistsAndCreditsItsLocalAccountWithoutSession() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 10_000,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        ))
        let localUseCase = LocalExpenseUseCase(profileStore: profileStore, repository: repository)
        let state = AppState(
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        var draft = NativeManualRecordDraft(kind: .income)
        draft.amountText = "20.00"
        draft.title = "薪资"
        draft.category = "salary"
        draft.accountId = account.id.uuidString
        draft.date = Date(timeIntervalSince1970: 1_800_000_000)

        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved, "未登录收入应在本地保存")
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 12_000)
        XCTAssertEqual(try repository.accountEntries(accountID: account.id).filter { $0.voidedAt == nil }.map(\.direction), ["in"])
        XCTAssertEqual(state.manualRecordMessage, "收入已记录（本机）")
        let entry = try XCTUnwrap(repository.accountEntries(accountID: account.id).first)
        XCTAssertNil(entry.occurredAt, "未记录时间时账务事实必须保留 nil")
    }

    @MainActor
    func testLF03202LocalIncomeEditAndDeleteVoidLedgerExactlyOnce() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: Date()
        ))
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: repository),
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        var draft = NativeManualRecordDraft(kind: .income)
        draft.amountText = "20.00"
        draft.title = "薪资"
        draft.category = "salary"
        draft.accountId = account.id.uuidString
        draft.date = Date(timeIntervalSince1970: 1_800_000_000)
        let created = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(created)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 12_000)

        let reference = try XCTUnwrap(state.recordGroups(monthKey: NativeLocalDate.monthKey(from: NativeLocalDate.dateKey(draft.date))!).flatMap(\.records).first?.reference)
        await state.loadRecordDetail(reference: reference)
        var edit = NativeRecordEditDraft(detail: try XCTUnwrap(state.selectedRecordDetail))
        edit.amountText = "30.00"
        let updated = await state.saveRecordDetail(edit)
        XCTAssertTrue(updated)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 13_000)
        let staleRetry = await state.saveRecordDetail(edit)
        XCTAssertFalse(staleRetry)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 13_000)

        let deleted = await state.deleteRecord(reference: reference)
        XCTAssertTrue(deleted)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 10_000)
        let deleteRetry = await state.deleteRecord(reference: reference)
        XCTAssertFalse(deleteRetry)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 10_000)
        let entries = try repository.accountEntries(accountID: account.id)
        XCTAssertEqual(entries.count, 2, "陈旧版本重试不应留下第三笔账务流水")
        XCTAssertTrue(entries.allSatisfy { $0.voidedAt != nil })
    }

    @MainActor
    func testLF03203IncomeAndExpenseRemainSeparateOnSameDay() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 0, createdAt: Date()
        ))
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: repository),
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        let day = ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z")!
        var expense = NativeManualRecordDraft(kind: .expense)
        expense.accountId = account.id.uuidString
        expense.amountText = "5.00"
        expense.title = "午餐"
        expense.category = "food"
        expense.paymentMethod = "现金"
        expense.date = day
        let expenseSaved = await state.createManualRecord(expense, domain: nil)
        XCTAssertTrue(expenseSaved)

        var income = NativeManualRecordDraft(kind: .income)
        income.accountId = account.id.uuidString
        income.amountText = "20.00"
        income.title = "报销"
        income.category = "other"
        income.date = day
        let incomeSaved = await state.createManualRecord(income, domain: nil)
        XCTAssertTrue(incomeSaved)

        let monthKey = String(NativeLocalDate.dateKey(day).prefix(7))
        let dayRecords = try XCTUnwrap(state.recordGroups(monthKey: monthKey).first(where: { $0.dateKey == NativeLocalDate.dateKey(day) }))
        XCTAssertEqual(Set(dayRecords.records.map(\.kind)), Set([.expense, .income]))
        let snapshot = state.reportSnapshot(monthKey: monthKey)
        XCTAssertEqual(snapshot.monthExpense, 5, accuracy: 0.001)
        XCTAssertEqual(snapshot.monthIncome, 20, accuracy: 0.001)
    }

    @MainActor
    func testLF03301OfflineWalletSnapshotIsSavedWithoutChangingDerivedBalance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-snapshot-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("local.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profileStore = LocalProfileStore(database: database)
        let repository = try LocalExpenseRepository(database: database)
        let profile = try profileStore.activeProfile()
        let account = try repository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: Date()
        ))
        let imageStore = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images", isDirectory: true))
        let localRecords = try LocalRecordRepository(database: database)
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: repository),
            localRecordUseCase: LocalRecordUseCase(profileStore: profileStore, repository: localRecords, imageStore: imageStore),
            localImageStore: imageStore,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "wallet")
        draft.primaryValueText = "500.00"
        draft.dimension = "微信"
        draft.title = "微信零钱"
        draft.walletRecordKind = "cash_snapshot"
        draft.walletAccountType = "wechat"
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z"))
        draft.time = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T06:30:00Z"))
        draft.includesTime = true

        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved, "离线手工钱包快照应保存在本地")
        guard saved else { return }
        let occurredAtText = try await database.writer.read { db -> String? in
            guard let row = try Row.fetchOne(db, sql: "SELECT occurred_at FROM local_wallet_snapshots ORDER BY id LIMIT 1") else {
                return nil
            }
            return row["occurred_at"]
        }
        let occurredAt = try XCTUnwrap(occurredAtText.flatMap(ISO8601DateFormatter().date(from:)))
        XCTAssertEqual(occurredAt.timeIntervalSince1970, 1_792_909_800, accuracy: 1)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 10_000)
        XCTAssertTrue(try repository.accountEntries(accountID: account.id).isEmpty)
    }

    func testLocalExpenseDetailUsesStableReferenceAndLocalOnlyFields() {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let detail = LocalExpenseReadModel.detail(from: localExpense(profileID: profileID))

        XCTAssertEqual(detail.id, "local-expense/22222222-2222-2222-2222-222222222222")
        XCTAssertEqual(detail.kind, "expense")
        XCTAssertEqual(detail.status, "local")
        XCTAssertEqual(detail.value, "¥12.30")
        XCTAssertNil(detail.imagePath)
        XCTAssertNil(detail.companionMessage)
    }

    @MainActor
    func testAppStateLoadsLocalDetailWithoutSessionOrRemoteRepository() async {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expense = localExpense(profileID: profileID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense]),
            expenseResult: expense
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [], details: [:])
        )
        var sessionLookupCount = 0
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )

        await state.loadRecordDetail(reference: "local-expense/22222222-2222-2222-2222-222222222222")

        XCTAssertEqual(sessionLookupCount, 0)
        XCTAssertTrue(repository.fetchDetailReferences.isEmpty)
        XCTAssertEqual(state.selectedRecordDetail?.title, "全家便利店")
    }

    @MainActor
    func testSignedInLocalEditAndDeleteStayLocal() async {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expense = localExpense(profileID: profileID)
        var updated = expense
        updated = LocalExpense(
            id: expense.id,
            profileID: expense.profileID,
            accountID: expense.accountID,
            amountMinor: 2_000,
            currency: expense.currency,
            merchantName: "瑞幸咖啡",
            platform: expense.platform,
            category: expense.category,
            paymentMethod: expense.paymentMethod,
            transactionDate: expense.transactionDate,
            transactionTime: expense.transactionTime,
            note: expense.note,
            localVersion: 2,
            createdAt: expense.createdAt,
            updatedAt: Date()
        )
        let tombstone = LocalExpenseTombstone(
            id: expense.id,
            profileID: profileID,
            localVersion: 3,
            deletedAt: Date()
        )
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false),
            month: LocalExpenseMonth(profileID: profileID, expenses: [updated]),
            expenseResult: expense,
            updateResult: LocalExpenseOutcome(expense: updated, tombstone: nil, profileID: profileID),
            deleteResult: LocalExpenseOutcome(expense: nil, tombstone: tombstone, profileID: profileID)
        )
        var sessionLookupCount = 0
        let state = AppState(
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )
        state.isSignedIn = true
        state.currentUserId = "cloud-user"

        var draft = NativeRecordEditDraft(detail: LocalExpenseReadModel.detail(from: expense))
        draft.amountText = "20.00"
        draft.title = "瑞幸咖啡"

        let saveSucceeded = await state.saveRecordDetail(draft)
        let deleteSucceeded = await state.deleteRecord(reference: draft.reference)
        XCTAssertTrue(saveSucceeded)
        XCTAssertTrue(deleteSucceeded)
        XCTAssertEqual(sessionLookupCount, 0)
        XCTAssertEqual(localUseCase.updateCommands.count, 1)
        XCTAssertEqual(localUseCase.deleteCommands.count, 1)
    }

    @MainActor
    func testSignedInManualExpenseStaysLocalWhenCloudSessionIsUnavailable() async {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let accountID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let expense = localExpense(profileID: profileID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense]),
            createResult: LocalExpenseOutcome(expense: expense, tombstone: nil, profileID: profileID)
        )
        var sessionLookupCount = 0
        let state = AppState(
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )
        state.isSignedIn = true
        state.currentUserId = "cloud-user"

        var draft = NativeManualRecordDraft(kind: .expense)
        draft.accountId = accountID.uuidString
        draft.amountText = "12.30"
        draft.platform = "线下消费"
        draft.category = "food"
        draft.paymentMethod = "现金"
        draft.title = "全家便利店"
        draft.date = Date(timeIntervalSince1970: 1_700_000_100)

        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved)
        XCTAssertEqual(localUseCase.createCommands.count, 1)
        XCTAssertEqual(localUseCase.createCommands.first?.accountID, accountID)
        XCTAssertEqual(sessionLookupCount, 0)
        XCTAssertEqual(state.manualRecordMessage, "记录已保存（本机）")
    }

    @MainActor
    func testAppStateLoadsSignedOutMonthFromLocalUseCaseWithoutSessionLookup() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expense = localExpense(profileID: profileID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(
                id: profileID,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                cloudUserID: nil,
                syncEnabled: false
            ),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense])
        )
        var sessionLookupCount = 0
        let state = AppState(
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in
                sessionLookupCount += 1
                throw SupabaseRemoteError.missingSession
            }
        )

        await state.loadRecordMonth("2026-07", force: true)

        XCTAssertEqual(localUseCase.monthKeys, ["2026-07"])
        XCTAssertEqual(sessionLookupCount, 0)
        XCTAssertEqual(state.recordGroups(monthKey: "2026-07").first?.records.first?.title, "全家便利店")
        XCTAssertNil(state.recordMonthMessages["2026-07"])
    }

    @MainActor
    func testAppStateFallsBackToRemoteWhenSignedInLocalMonthIsEmpty() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userID = LocalShellRecordRepositorySpy.session.user.id
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: userID, syncEnabled: true),
            month: LocalExpenseMonth(profileID: profileID, expenses: [])
        )
        let remoteGroup = NativeDayRecordGroup(
            dateKey: "2026-07-20",
            records: [NativeDayRecord(
                id: "remote-1",
                reference: "expense/remote-1",
                dateKey: "2026-07-20",
                kind: .expense,
                domainKey: nil,
                title: "云端记录",
                subtitle: "food",
                value: "¥8.00",
                timeLabel: "08:00",
                systemImage: "creditcard"
            )]
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [remoteGroup], details: [:])
        )
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            localBindingRepository: LocalShellBindingRepositoryStub(userID: userID),
            sessionProvider: { _ in LocalShellRecordRepositorySpy.session }
        )
        state.isSignedIn = true
        state.currentUserId = LocalShellRecordRepositorySpy.session.user.id
        state.localSyncState = syncState(for: state.currentUserId)

        await state.loadRecordMonth("2026-07", force: true)

        XCTAssertEqual(repository.fetchMonthKeys, ["2026-07"])
        XCTAssertEqual(localUseCase.monthKeys, ["2026-07", "2026-07"])
        XCTAssertEqual(state.recordGroups(monthKey: "2026-07").first?.records.first?.title, "云端记录")
    }

    @MainActor
    func testAppStateMergesRemoteMonthWhenLocalMonthIsNonEmpty() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let userID = LocalShellRecordRepositorySpy.session.user.id
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: userID, syncEnabled: true),
            month: LocalExpenseMonth(profileID: profileID, expenses: [localExpense(profileID: profileID)])
        )
        let remoteGroup = NativeDayRecordGroup(
            dateKey: "2026-07-20",
            records: [NativeDayRecord(
                id: "remote-sleep-1",
                reference: "data/remote-sleep-1",
                dateKey: "2026-07-20",
                kind: .sleep,
                domainKey: "sleep",
                title: "云端睡眠",
                subtitle: "",
                value: "",
                timeLabel: nil,
                systemImage: "moon"
            )]
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [remoteGroup], details: [:])
        )
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            localBindingRepository: LocalShellBindingRepositoryStub(userID: userID),
            sessionProvider: { _ in LocalShellRecordRepositorySpy.session }
        )
        state.isSignedIn = true
        state.currentUserId = LocalShellRecordRepositorySpy.session.user.id
        state.localSyncState = syncState(for: state.currentUserId)

        await state.loadRecordMonth("2026-07", force: true)

        let records = state.recordGroups(monthKey: "2026-07").flatMap(\.records)
        XCTAssertEqual(repository.fetchMonthKeys, ["2026-07"])
        XCTAssertEqual(Set(records.map(\.id)), Set(["22222222-2222-2222-2222-222222222222", "remote-sleep-1"]))
    }

    @MainActor
    func testAppStateDeduplicatesLocalAndRemoteExpenseWithSameAggregateID() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expense = localExpense(profileID: profileID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense])
        )
        let remoteGroup = NativeDayRecordGroup(
            dateKey: "2026-07-20",
            records: [NativeDayRecord(
                id: "expense-22222222-2222-2222-2222-222222222222",
                reference: "expense/22222222-2222-2222-2222-222222222222",
                dateKey: "2026-07-20",
                kind: .expense,
                domainKey: "expense",
                title: "全家便利店",
                subtitle: "线下消费 · food",
                value: "¥12.30",
                timeLabel: "08:30",
                systemImage: "creditcard",
                transactionType: "expense",
                status: "done"
            )]
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [remoteGroup], details: [:])
        )
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in LocalShellRecordRepositorySpy.session }
        )
        state.isSignedIn = true
        state.currentUserId = LocalShellRecordRepositorySpy.session.user.id

        await state.loadRecordMonth("2026-07", force: true)

        let records = state.recordGroups(monthKey: "2026-07").flatMap(\.records)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.reference, "local-expense/22222222-2222-2222-2222-222222222222")
    }

    @MainActor
    func testAppStateDeduplicatesUUIDReferencesIgnoringCase() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let expenseID = UUID(uuidString: "a1b2c3d4-e5f6-4789-aaaa-bbbbbbbbbbbb")!
        let expense = localExpense(profileID: profileID, id: expenseID)
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(id: profileID, createdAt: Date(), cloudUserID: nil, syncEnabled: false),
            month: LocalExpenseMonth(profileID: profileID, expenses: [expense])
        )
        let remoteID = expenseID.uuidString.lowercased()
        let remoteGroup = NativeDayRecordGroup(
            dateKey: "2026-07-20",
            records: [NativeDayRecord(
                id: "expense-\(remoteID)",
                reference: "expense/\(remoteID)",
                dateKey: "2026-07-20",
                kind: .expense,
                domainKey: "expense",
                title: "全家便利店",
                subtitle: "线下消费 · food",
                value: "¥12.30",
                timeLabel: "08:30",
                systemImage: "creditcard",
                transactionType: "expense",
                status: "done"
            )]
        )
        let repository = LocalShellRecordRepositorySpy(
            monthSnapshot: NativeRecordMonthSnapshot(groups: [remoteGroup], details: [:])
        )
        let state = AppState(
            recordRepository: repository,
            localExpenseUseCase: localUseCase,
            sessionProvider: { _ in LocalShellRecordRepositorySpy.session }
        )
        state.isSignedIn = true
        state.currentUserId = LocalShellRecordRepositorySpy.session.user.id

        await state.loadRecordMonth("2026-07", force: true)

        let records = state.recordGroups(monthKey: "2026-07").flatMap(\.records)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.reference, "local-expense/\(expenseID.uuidString)")
    }

    @MainActor
    func testSignedOutStateCanRestoreLocalMonthAfterCloudStateReset() async throws {
        let profileID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let localUseCase = LocalShellExpenseUseCaseStub(
            profile: LocalProfile(
                id: profileID,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000),
                cloudUserID: nil,
                syncEnabled: false
            ),
            month: LocalExpenseMonth(profileID: profileID, expenses: [localExpense(profileID: profileID)])
        )
        let state = AppState(localExpenseUseCase: localUseCase)
        state.isSignedIn = true
        state.currentUserId = "cloud-user"
        state.presentedOverlay = .settings

        state.isSignedIn = false
        state.currentUserId = ""
        state.resetUserScopedState()
        state.presentedOverlay = .records
        await state.loadRecordMonth("2026-07", force: true)

        XCTAssertEqual(state.presentedOverlay, .records)
        XCTAssertEqual(localUseCase.monthKeys, ["2026-07"])
        XCTAssertEqual(state.recordGroups(monthKey: "2026-07").first?.records.first?.reference, "local-expense/22222222-2222-2222-2222-222222222222")
    }

    private func localExpense(
        profileID: UUID,
        id: UUID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    ) -> LocalExpense {
        LocalExpense(
            id: id,
            profileID: profileID,
            accountID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            amountMinor: 1_230,
            currency: "CNY",
            merchantName: "全家便利店",
            platform: "线下消费",
            category: "food",
            paymentMethod: "现金",
            transactionDate: "2026-07-20",
            transactionTime: "08:30",
            note: nil,
            localVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1_700_000_100),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
    }

    private func syncState(for userID: String) -> LocalSyncState {
        LocalSyncState(
            workspaceID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            binding: .bound(userID),
            status: .synced,
            conflictState: .none,
            syncGeneration: 1,
            pullCursor: nil,
            lastSuccessfulSyncAt: Date(),
            activeAttemptID: nil,
            pendingMutationCount: 0
        )
    }
}

private final class LocalShellExpenseUseCaseStub: LocalExpenseUseCaseProtocol {
    let profile: LocalProfile
    let monthResult: LocalExpenseMonth
    let expenseResult: LocalExpense?
    let createResult: LocalExpenseOutcome?
    let updateResult: LocalExpenseOutcome?
    let deleteResult: LocalExpenseOutcome?
    private(set) var monthKeys: [String] = []
    private(set) var createCommands: [LocalExpenseCommand] = []
    private(set) var updateCommands: [LocalExpenseUpdateCommand] = []
    private(set) var deleteCommands: [LocalExpenseDeleteCommand] = []

    init(
        profile: LocalProfile,
        month: LocalExpenseMonth,
        expenseResult: LocalExpense? = nil,
        createResult: LocalExpenseOutcome? = nil,
        updateResult: LocalExpenseOutcome? = nil,
        deleteResult: LocalExpenseOutcome? = nil
    ) {
        self.profile = profile
        self.monthResult = month
        self.expenseResult = expenseResult
        self.createResult = createResult
        self.updateResult = updateResult
        self.deleteResult = deleteResult
    }

    func prepareProfile() async throws -> LocalProfile { profile }
    func create(_ command: LocalExpenseCommand) async throws -> LocalExpenseOutcome {
        createCommands.append(command)
        guard let createResult else { throw LocalDataError.invalidRecord }
        return createResult
    }
    func expense(id: UUID) async throws -> LocalExpense? { expenseResult?.id == id ? expenseResult : nil }
    func update(_ command: LocalExpenseUpdateCommand) async throws -> LocalExpenseOutcome {
        updateCommands.append(command)
        guard let updateResult else { throw LocalDataError.invalidRecord }
        return updateResult
    }
    func delete(_ command: LocalExpenseDeleteCommand) async throws -> LocalExpenseOutcome {
        deleteCommands.append(command)
        guard let deleteResult else { throw LocalDataError.invalidRecord }
        return deleteResult
    }

    func month(_ monthKey: String) async throws -> LocalExpenseMonth {
        monthKeys.append(monthKey)
        return monthResult
    }
}

private final class LocalShellRecordRepositorySpy: RecordRepositoryProtocol {
    static let session = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresIn: nil,
        expiresAt: nil,
        tokenType: "bearer",
        user: SupabaseUser(id: "user-1", email: "test@example.com")
    )

    let monthSnapshot: NativeRecordMonthSnapshot
    private(set) var fetchMonthKeys: [String] = []
    private(set) var fetchDetailReferences: [String] = []

    init(monthSnapshot: NativeRecordMonthSnapshot) {
        self.monthSnapshot = monthSnapshot
    }

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        fetchMonthKeys.append(monthKey)
        return monthSnapshot
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        fetchDetailReferences.append(reference)
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail { detail }
    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup {
        .unavailable(reason: "unused")
    }

    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func create(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?,
        userId: String,
        accessToken: String
    ) async throws -> String {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        throw SupabaseRemoteError.requestFailed("unused")
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

private final class LocalShellBindingRepositoryStub: LocalBindingRepository {
    private let userID: String
    private let profile = LocalProfile(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        createdAt: Date(),
        cloudUserID: nil,
        syncEnabled: false
    )

    init(userID: String) { self.userID = userID }

    func activeProfile() throws -> LocalProfile { profile }
    func workspaceSummary(profileID: UUID) throws -> LocalWorkspaceSummary {
        LocalWorkspaceSummary(workspaceID: profileID, expenseCount: 0, accountCount: 0, pendingOutboxCount: 0)
    }
    func syncState(profileID: UUID) throws -> LocalSyncState {
        LocalSyncState(
            workspaceID: profileID, binding: .bound(userID), status: .synced, conflictState: .none,
            syncGeneration: 1, pullCursor: nil, lastSuccessfulSyncAt: Date(), activeAttemptID: nil,
            pendingMutationCount: 0
        )
    }
    func confirmBinding(profileID: UUID, cloudUserID: String) throws -> LocalSyncState { try syncState(profileID: profileID) }
    func disableSync(profileID: UUID) throws -> LocalSyncState { try syncState(profileID: profileID) }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapCountTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("jiezi.sqlite")
}

private func removeDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
