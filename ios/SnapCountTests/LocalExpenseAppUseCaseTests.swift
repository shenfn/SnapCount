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
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: repository),
            localRecordUseCase: LocalRecordUseCase(profileStore: profileStore, repository: localRecords, imageStore: imageStore),
            localWalletSnapshotUseCase: LocalWalletSnapshotUseCase(
                profileStore: profileStore,
                repository: walletRepository,
                imageStore: imageStore
            ),
            localImageStore: imageStore,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "wallet")
        draft.primaryValueText = "500.00"
        draft.dimension = "微信"
        draft.title = "微信零钱"
        draft.walletRecordKind = "cash_snapshot"
        draft.walletAccountType = "wechat"
        draft.imageData = Data("synthetic wallet snapshot image".utf8)
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T04:00:00Z"))
        draft.time = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-25T06:30:00Z"))
        draft.includesTime = true

        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved, "离线手工钱包快照应保存在本地")
        guard saved else { return }
        let snapshot = try XCTUnwrap(walletRepository.unlinked(profileID: profile.id).first)
        await state.loadWalletSnapshots()
        XCTAssertEqual(state.localWalletSnapshots.map(\.id), [snapshot.id])
        let imageData = try XCTUnwrap(draft.imageData)
        XCTAssertEqual(snapshot.balanceMinor, 50_000)
        XCTAssertEqual(snapshot.recordTime, draft.timeKey)
        XCTAssertEqual(snapshot.occurredAt, draft.occurredAt)
        XCTAssertEqual(snapshot.imageHash, LocalImageStore.sha256(imageData))
        XCTAssertEqual(try imageStore.data(at: try XCTUnwrap(snapshot.imagePath)), imageData)
        let occurredAtText = try await database.writer.read { db -> String? in
            guard let row = try Row.fetchOne(db, sql: "SELECT occurred_at FROM local_wallet_snapshots ORDER BY id LIMIT 1") else {
                return nil
            }
            return row["occurred_at"]
        }
        let occurredAt = try XCTUnwrap(occurredAtText)
        XCTAssertEqual(occurredAt, draft.occurredAt)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 10_000)
        XCTAssertTrue(try repository.accountEntries(accountID: account.id).isEmpty)

        let backup = LocalCompleteBackupPortability(database: database, imageStore: imageStore)
        let data = try backup.exportBackup()
        let preview = try backup.preview(data)
        XCTAssertEqual(preview.tableCounts["local_wallet_snapshots"], 1)
        XCTAssertEqual(preview.imageCount, 1)
        XCTAssertTrue(preview.confirmationText.contains("钱包快照 1"))

        let restoredDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: restoredDirectory) }
        let restoredDatabase = try LocalDatabase(databaseURL: restoredDirectory.appendingPathComponent("local.sqlite"))
        let restoredProfile = try LocalProfileStore(database: restoredDatabase).activeProfile()
        let restoredImages = try LocalImageStore(rootDirectory: restoredDirectory.appendingPathComponent("images", isDirectory: true))
        let restored = try LocalCompleteBackupPortability(database: restoredDatabase, imageStore: restoredImages)
            .importBackup(data, into: restoredProfile.id)
        XCTAssertEqual(restored.insertedRows, preview.totalRows)
        XCTAssertEqual(restored.restoredImages, 1)
        let restoredSnapshot = try XCTUnwrap(
            LocalWalletSnapshotRepository(database: restoredDatabase).unlinked(profileID: restoredProfile.id).first
        )
        XCTAssertEqual(restoredSnapshot.id, snapshot.id)
        XCTAssertEqual(restoredSnapshot.profileID, restoredProfile.id)
        XCTAssertEqual(restoredSnapshot.title, snapshot.title)
        XCTAssertEqual(restoredSnapshot.summary, snapshot.summary)
        XCTAssertEqual(restoredSnapshot.payloadJSON, snapshot.payloadJSON)
        XCTAssertEqual(restoredSnapshot.recordDate, snapshot.recordDate)
        XCTAssertEqual(restoredSnapshot.recordTime, snapshot.recordTime)
        XCTAssertEqual(restoredSnapshot.balanceMinor, snapshot.balanceMinor)
        XCTAssertEqual(restoredSnapshot.occurredAt, snapshot.occurredAt)
        XCTAssertEqual(restoredSnapshot.imageHash, snapshot.imageHash)
        XCTAssertEqual(try restoredImages.data(at: try XCTUnwrap(snapshot.imagePath)), imageData)
        XCTAssertEqual(try LocalExpenseRepository(database: restoredDatabase).accountBalanceMinor(accountID: account.id), 10_000)
    }

    @MainActor
    func testLF03302OfflineCreateFromSnapshotIsAtomicAndIdempotent() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-create-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "微信零钱", summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: expenseRepository),
            localWalletSnapshotUseCase: useCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )

        let saved = await state.createLocalAccountFromWalletSnapshot(snapshot)
        let replay = try await useCase.createAccount(from: snapshot)
        let accounts = try expenseRepository.accounts(profileID: profile.id)
        let entries = try expenseRepository.accountEntries(sourceID: snapshot.id)

        XCTAssertTrue(saved)
        XCTAssertEqual(replay.kind, .replayed)
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0].kind, "wallet_balance")
        XCTAssertEqual(accounts[0].openingBalanceMinor, 50_000)
        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: accounts[0].id), 50_000)
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].entryKind, "snapshot_initialization")
        XCTAssertEqual(try walletRepository.unlinked(profileID: profile.id), [])
        XCTAssertEqual(try expenseRepository.pendingOutboxOperations().filter { $0.aggregateKind == "account" }.count, 1)
    }

    func testLF03302LinkOnlyAdoptsSnapshotIntoEmptyCompatibleAccountOnce() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "备用钱包", kind: "cash", currency: "CNY",
            openingBalanceMinor: 0, createdAt: Date()
        ))
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "微信零钱", summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))

        let linked = try await useCase.link(snapshot, to: account.id)
        let replay = try await useCase.link(snapshot, to: account.id)

        XCTAssertEqual(linked.kind, .linked)
        XCTAssertEqual(replay.kind, .replayed)
        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: account.id), 50_000)
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id).count, 1)
        do {
            _ = try await useCase.createAccount(from: snapshot)
            XCTFail("create after explicit link must conflict")
        } catch {
            XCTAssertEqual(error as? LocalWalletSnapshotActionError, .conflict)
        }
        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id).count, 1)
    }

    func testLF03302LinkToNonemptyAccountDoesNotChangeDerivedBalance() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-nonempty-link-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: Date()
        ))
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "微信零钱", summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))

        _ = try await useCase.link(snapshot, to: account.id)

        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: account.id), 10_000)
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id), [])
        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id).count, 1)
    }

    func testLF03302FailedAccountCreationLeavesSnapshotUnlinkedAndWritesNothing() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-create-rollback-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: String(repeating: "长", count: 31), summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))

        do {
            _ = try await useCase.createAccount(from: snapshot)
            XCTFail("invalid account name must abort the action")
        } catch {
            XCTAssertEqual(error as? LocalDataError, .invalidRecord)
        }

        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id), [])
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id), [])
        XCTAssertEqual(try expenseRepository.pendingOutboxOperations(), [])
        XCTAssertEqual(try walletRepository.unlinked(profileID: profile.id).map(\.id), [snapshot.id])
    }

    func testLF03302LiabilitySnapshotCreatesDebtAccountWithoutGuessingRepaymentCycle() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-liability-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "信用卡待还", summary: "账单快照",
            payload: [
                "account_type": AnyCodable("credit_card"),
                "snapshot_balance": AnyCodable(125.0),
                "bill_day": AnyCodable(12),
                "due_date": AnyCodable("2026-11-05")
            ],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 12_500, currency: "CNY", kind: .liability,
            imageData: nil, createdAt: Date()
        ))

        let result = try await useCase.createAccount(from: snapshot)
        let cycles = try expenseRepository.repaymentCycles(accountID: result.account.id)
        let payments = try expenseRepository.liabilityPayments(accountID: result.account.id)

        XCTAssertEqual(result.kind, .created)
        XCTAssertEqual(result.account.kind, "credit_card")
        XCTAssertEqual(result.account.openingBalanceMinor, 12_500)
        XCTAssertEqual(result.account.billDay, 12)
        XCTAssertEqual(result.account.paymentDueDay, 5)
        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: result.account.id), 12_500)
        XCTAssertTrue(cycles.isEmpty, "未识别显式账期身份，不猜测生成账期")
        XCTAssertTrue(payments.isEmpty, "待还快照不能伪造还款流水")
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id).map(\.entryKind), ["snapshot_initialization"])
        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id).count, 1)
    }

    @MainActor
    func testLF03302AcceptedLocalActionIsNotRepeatedWhenListRefreshFails() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-refresh-failure-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let baseWalletRepository = LocalWalletSnapshotRepository(database: database)
        let flakyWalletRepository = LocalWalletSnapshotRepositoryRefreshFailure(base: baseWalletRepository)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: flakyWalletRepository)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "微信零钱", summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))
        flakyWalletRepository.failUnlinkedReads = true
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: expenseRepository),
            localWalletSnapshotUseCase: useCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )

        let accepted = await state.createLocalAccountFromWalletSnapshot(snapshot)
        XCTAssertTrue(accepted)
        XCTAssertTrue(state.walletSnapshotMessage?.contains("列表刷新失败") == true)
        let retry = try await useCase.createAccount(from: snapshot)

        XCTAssertEqual(retry.kind, .replayed)
        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id).count, 1)
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id).count, 1)
    }

    func testLF03303FutureWalletSnapshotCannotBeUsedAsCurrentAccountEvidence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-future-evidence-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 0, createdAt: Date()
        ))
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "未来账单", summary: "未来来源不能建账",
            payload: ["account_type": AnyCodable("wechat")],
            recordDate: "2999-01-01", recordTime: nil, occurredAt: nil,
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))

        do {
            _ = try await useCase.createAccount(from: snapshot)
            XCTFail("未来快照不能作为当前账户余额证据")
        } catch {
            XCTAssertEqual(error as? LocalWalletSnapshotActionError, .futureEvidence)
        }
        do {
            _ = try await useCase.link(snapshot, to: account.id)
            XCTFail("未来快照不能初始化或关联本地账户")
        } catch {
            XCTAssertEqual(error as? LocalWalletSnapshotActionError, .futureEvidence)
        }

        XCTAssertEqual(try expenseRepository.accounts(profileID: profile.id).map(\.id), [account.id])
        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: account.id), 0)
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: snapshot.id), [])
        XCTAssertEqual(try walletRepository.unlinked(profileID: profile.id).map(\.id), [snapshot.id])
    }

    func testLF03303HistoryEditAndDeleteKeepSourceTimeRelationAndAccountLedger() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let profile = try profileStore.activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "储蓄账户", kind: "cash", currency: "CNY",
            openingBalanceMinor: 0, createdAt: Date()
        ))
        let older = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "旧余额", summary: "来源A",
            payload: ["account_type": AnyCodable("cash"), "snapshot_balance": AnyCodable(500.0)],
            recordDate: "2026-10-24", recordTime: "08:30", occurredAt: "2026-10-24T00:30:00Z",
            balanceMinor: 50_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let newer = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "新余额", summary: "来源B",
            payload: ["account_type": AnyCodable("cash"), "snapshot_balance": AnyCodable(800.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 80_000, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))

        _ = try await useCase.link(older, to: account.id)
        let initialHistory = try await useCase.history()
        XCTAssertEqual(initialHistory.map(\.id), [newer.id, older.id])
        XCTAssertEqual(initialHistory[1].linkedAccountID, account.id)
        XCTAssertEqual(initialHistory[1].occurredAt, older.occurredAt)

        let linkedSnapshot = try XCTUnwrap(initialHistory.first(where: { $0.id == older.id }))
        let edited = try await useCase.update(
            linkedSnapshot,
            title: "已核对余额",
            summary: "人工核对",
            balanceMinor: 70_000
        )
        XCTAssertEqual(edited.localVersion, linkedSnapshot.localVersion + 1)
        XCTAssertEqual(edited.recordDate, older.recordDate)
        XCTAssertEqual(edited.recordTime, older.recordTime)
        XCTAssertEqual(edited.occurredAt, older.occurredAt)
        XCTAssertEqual(edited.linkedAccountID, account.id)
        XCTAssertEqual(edited.balanceMinor, 70_000)

        do {
            _ = try await useCase.update(linkedSnapshot, title: "陈旧编辑", summary: "", balanceMinor: 1)
            XCTFail("stale snapshot edit must fail its local version check")
        } catch {
            XCTAssertEqual(error as? LocalDataError, .versionConflict(expected: linkedSnapshot.localVersion, actual: edited.localVersion))
        }

        let deleted = try await useCase.delete(edited)
        XCTAssertNotNil(deleted.deletedAt)
        XCTAssertEqual(deleted.linkedAccountID, account.id)
        do {
            _ = try await useCase.createAccount(from: deleted)
            XCTFail("deleted snapshot cannot be replayed as current evidence")
        } catch {
            XCTAssertEqual(error as? LocalDataError, .recordNotFound)
        }
        XCTAssertEqual(try walletRepository.unlinked(profileID: profile.id).map(\.id), [newer.id])
        let historyAfterDelete = try await useCase.history()
        XCTAssertEqual(historyAfterDelete.map(\.id), [newer.id, older.id])
        XCTAssertNotNil(historyAfterDelete.last?.deletedAt)
        XCTAssertEqual(try expenseRepository.accountEntries(sourceID: older.id).map(\.entryKind), ["snapshot_initialization"])
        XCTAssertEqual(try expenseRepository.accountBalanceMinor(accountID: account.id), 50_000)
    }

    func testLF03303DeletedWalletSnapshotImageRemainsInLocalBackup() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-deleted-image-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let imageStore = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images", isDirectory: true))
        let repository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: repository, imageStore: imageStore)
        let image = Data("synthetic deleted wallet snapshot image".utf8)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "历史快照", summary: "保留原图",
            payload: ["account_type": AnyCodable("cash")],
            recordDate: "2026-10-24", recordTime: nil, occurredAt: nil,
            balanceMinor: 500, currency: "CNY", kind: .asset,
            imageData: image, createdAt: Date()
        ))
        _ = try await useCase.delete(snapshot)

        XCTAssertTrue(imageStore.contains(path: snapshot.imagePath))
        XCTAssertEqual(try imageStore.data(at: try XCTUnwrap(snapshot.imagePath)), image)

        let backup = LocalCompleteBackupPortability(database: database, imageStore: imageStore)
        let data = try backup.exportBackup()
        let preview = try backup.preview(data)
        XCTAssertEqual(preview.imageCount, 1)
        let restoreDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-deleted-restore-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: restoreDirectory) }
        let restoredDatabase = try LocalDatabase(databaseURL: restoreDirectory.appendingPathComponent("local.sqlite"))
        let restoredProfile = try LocalProfileStore(database: restoredDatabase).activeProfile()
        let restoredImages = try LocalImageStore(rootDirectory: restoreDirectory.appendingPathComponent("images", isDirectory: true))
        _ = try LocalCompleteBackupPortability(database: restoredDatabase, imageStore: restoredImages)
            .importBackup(data, into: restoredProfile.id)
        let restoredSnapshot = try XCTUnwrap(try LocalWalletSnapshotRepository(database: restoredDatabase)
            .history(profileID: restoredProfile.id).first)
        XCTAssertNotNil(restoredSnapshot.deletedAt)
        XCTAssertEqual(try restoredImages.data(at: try XCTUnwrap(restoredSnapshot.imagePath)), image)
    }

    @MainActor
    func testLF03303AppStateRefreshesSnapshotHistoryAfterEditAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-wallet-appstate-history-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let profileStore = LocalProfileStore(database: database)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let walletRepository = LocalWalletSnapshotRepository(database: database)
        let useCase = LocalWalletSnapshotUseCase(profileStore: profileStore, repository: walletRepository)
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "原始快照", summary: "",
            payload: ["account_type": AnyCodable("cash"), "snapshot_balance": AnyCodable(25.0)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 2_500, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))
        let state = AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: expenseRepository),
            localWalletSnapshotUseCase: useCase,
            sessionProvider: { _ in throw SupabaseRemoteError.missingSession }
        )

        await state.loadWalletSnapshots()
        XCTAssertEqual(state.localWalletSnapshots.map(\.id), [snapshot.id])
        XCTAssertEqual(state.localWalletSnapshotHistory.map(\.id), [snapshot.id])
        let updated = await state.updateLocalWalletSnapshot(snapshot, title: "已编辑", summary: "核对", balanceMinor: 3_000)
        XCTAssertTrue(updated)
        XCTAssertEqual(state.localWalletSnapshotHistory.first?.title, "已编辑")
        XCTAssertEqual(state.localWalletSnapshotHistory.first?.balanceMinor, 3_000)
        let currentSnapshot = try XCTUnwrap(state.localWalletSnapshotHistory.first)
        let deleted = await state.deleteLocalWalletSnapshot(currentSnapshot)
        XCTAssertTrue(deleted)
        XCTAssertTrue(state.localWalletSnapshots.isEmpty)
        XCTAssertNotNil(state.localWalletSnapshotHistory.first?.deletedAt)
        XCTAssertTrue(state.walletSnapshotMessage?.contains("删除历史") == true)
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

private final class LocalWalletSnapshotRepositoryRefreshFailure: LocalWalletSnapshotRepositoryProtocol {
    private let base: LocalWalletSnapshotRepositoryProtocol
    var failUnlinkedReads = false

    init(base: LocalWalletSnapshotRepositoryProtocol) { self.base = base }

    func create(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot {
        try base.create(draft)
    }

    func unlinked(profileID: UUID) throws -> [LocalWalletSnapshot] {
        if failUnlinkedReads { throw SupabaseRemoteError.requestFailed("wallet_snapshot_refresh_failed") }
        return try base.unlinked(profileID: profileID)
    }

    func history(profileID: UUID) throws -> [LocalWalletSnapshot] {
        try base.history(profileID: profileID)
    }

    func update(_ draft: LocalWalletSnapshotUpdateDraft) throws -> LocalWalletSnapshot {
        try base.update(draft)
    }

    func delete(id: UUID, profileID: UUID, expectedVersion: Int64, deletedAt: Date) throws -> LocalWalletSnapshot {
        try base.delete(id: id, profileID: profileID, expectedVersion: expectedVersion, deletedAt: deletedAt)
    }

    func createAccountFromSnapshot(
        _ snapshot: LocalWalletSnapshot,
        account: LocalAccountDraft
    ) throws -> LocalWalletSnapshotActionResult {
        try base.createAccountFromSnapshot(snapshot, account: account)
    }

    func link(_ snapshot: LocalWalletSnapshot, to accountID: UUID) throws -> LocalWalletSnapshotActionResult {
        try base.link(snapshot, to: accountID)
    }
}

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("SnapCountTests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("jiezi.sqlite")
}

private func removeDatabase(at url: URL) {
    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
}
