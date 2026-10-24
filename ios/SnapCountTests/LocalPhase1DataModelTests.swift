import Foundation
import XCTest
@testable import SnapCount

final class LocalPhase1DataModelTests: XCTestCase {
    func testLF03726BillDay31ClampsLeapAndNonLeapFebruaryAndKeepsStableCycles() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let liabilityID = UUID()
        let now = ISO8601DateFormatter().date(from: "2025-02-10T00:00:00+08:00")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: liabilityID, profileID: profile.id, name: "月底账单", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 0, createdAt: now, billDay: 31, paymentDueDay: 31
        ))
        for day in ["2024-01-31", "2024-02-01", "2024-02-29", "2025-01-31", "2025-02-01", "2025-02-28"] {
            _ = try repository.createExpense(LocalExpenseDraft(
                id: UUID(), profileID: profile.id, accountID: liabilityID, amountMinor: 100, currency: "CNY",
                merchantName: "合成消费", platform: "", category: "other", paymentMethod: "credit_card",
                transactionDate: day, transactionTime: nil, note: nil, createdAt: now
            ), operationID: UUID())
        }

        let leap = try XCTUnwrap(repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2024-02", now: now).first)
        XCTAssertEqual(leap.statementStartDate, "2024-02-01")
        XCTAssertEqual(leap.statementEndDate, "2024-02-29")
        XCTAssertEqual(leap.dueDate, "2024-02-29")
        XCTAssertEqual(leap.statementAmountMinor, 200)

        let nonLeap = try XCTUnwrap(repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2025-02", now: now).first)
        XCTAssertEqual(nonLeap.statementStartDate, "2025-02-01")
        XCTAssertEqual(nonLeap.statementEndDate, "2025-02-28")
        XCTAssertEqual(nonLeap.dueDate, "2025-02-28")
        XCTAssertEqual(nonLeap.statementAmountMinor, 200)
        XCTAssertEqual(try repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2025-02", now: now).count, 1)
    }

    func testLF03725And30ReconciliationCutoffAndHistoricalGraceTransitionPersistLocally() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let accountID = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-03-20T00:00:00+08:00")!
        let reconciledAt = ISO8601DateFormatter().date(from: "2026-02-20T00:00:00+08:00")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: accountID, profileID: profile.id, name: "已对账账户", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 0, createdAt: now, billDay: 15, paymentDueDay: 20,
            gracePeriodDays: 2, lastReconciledAt: reconciledAt
        ))
        for (day, amount) in [("2026-02-20", 700), ("2026-02-21", 200)] {
            let createdAt = ISO8601DateFormatter().date(from: "\(day)T00:00:00+08:00")!
            _ = try repository.createExpense(LocalExpenseDraft(
                id: UUID(), profileID: profile.id, accountID: accountID, amountMinor: Int64(amount), currency: "CNY",
                merchantName: "合成消费", platform: "", category: "other", paymentMethod: "credit_card",
                transactionDate: day, transactionTime: nil, note: nil, createdAt: createdAt
            ), operationID: UUID())
        }
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO local_repayment_cycles (
                    id, profile_id, account_id, cycle_month, due_date, status, source, created_at, updated_at
                ) VALUES (?, ?, ?, '2026-02', '2026-03-17', 'overdue_unconfirmed', 'system', ?, ?)
                """, arguments: [UUID().uuidString, profile.id.uuidString, accountID.uuidString, now, now])
        }

        let march = try XCTUnwrap(repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2026-03", now: now).first)
        XCTAssertEqual(march.statementAmountMinor, 200)
        XCTAssertEqual(try repository.accounts(profileID: profile.id).first?.lastReconciledAt, reconciledAt)
        let february = try XCTUnwrap(repository.repaymentCycles(accountID: accountID).first { $0.cycleMonth == "2026-02" })
        XCTAssertEqual(february.status, "historical_unconfirmed")
    }

    func testLF03719And46RevocationRecalculatesRemainingPaymentAndDueDateStatus() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let accountID = UUID()
        let now = ISO8601DateFormatter().date(from: "2026-03-20T00:00:00+08:00")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: accountID, profileID: profile.id, name: "撤销边界", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 0, createdAt: now, billDay: 15, paymentDueDay: 20
        ))
        _ = try repository.createExpense(LocalExpenseDraft(
            id: UUID(), profileID: profile.id, accountID: accountID, amountMinor: 10_000, currency: "CNY",
            merchantName: "合成消费", platform: "", category: "other", paymentMethod: "credit_card",
            transactionDate: "2026-03-01", transactionTime: nil, note: nil, createdAt: now
        ), operationID: UUID())
        let cycle = try XCTUnwrap(repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2026-03", now: now).first)

        let firstPaymentID = UUID()
        let secondPaymentID = UUID()
        try database.writer.write { db in
            for (id, amount) in [(firstPaymentID, 3_000), (secondPaymentID, 1_000)] {
                try db.execute(sql: """
                    INSERT INTO local_liability_payments (
                        id, profile_id, account_id, statement_id, amount_minor, overpayment_amount_minor,
                        paid_at, source, status, note, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, 0, ?, 'manual', 'confirmed', '', ?, ?)
                    """, arguments: [id.uuidString, profile.id.uuidString, accountID.uuidString,
                                      cycle.id.uuidString, Int64(amount), now, now, now])
            }
            try db.execute(sql: "UPDATE local_repayment_cycles SET min_payment_amount_minor = 1_000 WHERE id = ?", arguments: [cycle.id.uuidString])
        }

        let afterFirst = try XCTUnwrap(repository.revokeLiabilityPayment(
            id: firstPaymentID, profileID: profile.id, reason: "撤销较大付款", now: now
        ))
        XCTAssertEqual(afterFirst.paidAmountMinor, 1_000)
        XCTAssertEqual(afterFirst.remainingAmountMinor, 9_000)
        XCTAssertEqual(afterFirst.status, "minimum_paid")

        let afterLast = try XCTUnwrap(repository.revokeLiabilityPayment(
            id: secondPaymentID, profileID: profile.id, reason: "撤销最后付款", now: now
        ))
        XCTAssertEqual(afterLast.paidAmountMinor, 0)
        XCTAssertEqual(afterLast.remainingAmountMinor, 10_000)
        XCTAssertEqual(afterLast.status, "due_today")

        for (dueDate, expectedStatus) in [("2026-03-19", "overdue_unconfirmed"), ("2026-03-20", "due_today"), ("2026-03-21", "pending")] {
            try database.writer.write { db in
                try db.execute(sql: "UPDATE local_repayment_cycles SET due_date = ? WHERE id = ?", arguments: [dueDate, cycle.id.uuidString])
            }
            let payment = try repository.confirmRepayment(
                cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 500,
                debitAccountID: nil, status: nil, note: "状态合成样本", paidAt: now
            )
            XCTAssertEqual(payment.status, "partial_paid")
            let revoked = try XCTUnwrap(repository.revokeLiabilityPayment(
                id: try XCTUnwrap(repository.liabilityPayments(accountID: accountID).first { $0.status == "confirmed" }).id,
                profileID: profile.id, reason: "状态合成撤销", now: now
            ))
            XCTAssertEqual(revoked.paidAmountMinor, 0)
            XCTAssertEqual(revoked.remainingAmountMinor, 10_000)
            XCTAssertEqual(revoked.status, expectedStatus)
        }
    }

    func testLF03711To18LocalRepaymentReconfirmationAndRevocationAreAtomicAndIdempotent() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let debitID = UUID(), liabilityID = UUID()
        let date = ISO8601DateFormatter().date(from: "2026-03-10T00:00:00+08:00")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: debitID, profileID: profile.id, name: "扣款账户", kind: "cash", currency: "CNY",
            openingBalanceMinor: 20_000, createdAt: date
        ))
        _ = try repository.createAccount(LocalAccountDraft(
            id: liabilityID, profileID: profile.id, name: "信用卡", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 0, createdAt: date, billDay: 15, paymentDueDay: 20,
            autoDebitAccountID: debitID
        ))
        for (id, day, amount) in [
            (UUID(), "2026-02-15", 1_000), (UUID(), "2026-02-16", 2_000),
            (UUID(), "2026-03-15", 6_000), (UUID(), "2026-03-16", 4_000)
        ] {
            _ = try repository.createExpense(LocalExpenseDraft(
                id: id, profileID: profile.id, accountID: liabilityID, amountMinor: Int64(amount), currency: "CNY",
                merchantName: "合成消费", platform: "", category: "other", paymentMethod: "credit_card",
                transactionDate: day, transactionTime: nil, note: nil, createdAt: date
            ), operationID: UUID())
        }

        let cycles = try repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2026-03", now: date)
        let cycle = try XCTUnwrap(cycles.first { $0.accountID == liabilityID })
        XCTAssertEqual(cycle.statementStartDate, "2026-02-16")
        XCTAssertEqual(cycle.statementEndDate, "2026-03-15")
        XCTAssertEqual(cycle.dueDate, "2026-03-20")
        XCTAssertEqual(cycle.statementAmountMinor, 8_000)
        XCTAssertEqual(try repository.ensureRepaymentCycles(profileID: profile.id, monthKey: "2026-03", now: date).count, 1)

        try database.writer.write { db in
            try db.execute(sql: """
                CREATE TRIGGER fail_synthetic_repayment_entry BEFORE INSERT ON local_account_entries
                WHEN NEW.entry_kind = 'transfer'
                BEGIN SELECT RAISE(ABORT, 'synthetic repayment entry failure'); END;
                """)
        }
        XCTAssertThrowsError(try repository.confirmRepayment(
            cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 3_000,
            debitAccountID: nil, status: nil, note: "原子性失败注入", paidAt: date
        ))
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 13_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 20_000)
        XCTAssertTrue(try repository.liabilityPayments(accountID: liabilityID).isEmpty)
        XCTAssertEqual(try XCTUnwrap(repository.repaymentCycles(accountID: liabilityID).first).status, "pending")
        try database.writer.write { db in try db.execute(sql: "DROP TRIGGER fail_synthetic_repayment_entry") }

        let first = try repository.confirmRepayment(
            cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 3_000,
            debitAccountID: nil, status: nil, note: "第一次", paidAt: date
        )
        XCTAssertEqual(first.paidAmountMinor, 3_000)
        XCTAssertEqual(first.remainingAmountMinor, 5_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 10_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 17_000)

        _ = try repository.confirmRepayment(
            cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 4_000,
            debitAccountID: nil, status: nil, note: "替代金额", paidAt: date.addingTimeInterval(1)
        )
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 9_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 16_000)

        let overpaid = try repository.confirmRepayment(
            cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 16_000,
            debitAccountID: nil, status: nil, note: "溢缴", paidAt: date.addingTimeInterval(2)
        )
        XCTAssertEqual(overpaid.paidAmountMinor, 16_000)
        XCTAssertEqual(overpaid.remainingAmountMinor, 0)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 0)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 4_000)
        let confirmed = try XCTUnwrap(repository.liabilityPayments(accountID: liabilityID).first { $0.status == "confirmed" })
        XCTAssertEqual(confirmed.overpaymentAmountMinor, 7_000)

        let revoked = try XCTUnwrap(repository.revokeLiabilityPayment(
            id: confirmed.id, profileID: profile.id, reason: "测试撤销", now: date.addingTimeInterval(3)
        ))
        XCTAssertEqual(revoked.paidAmountMinor, 0)
        XCTAssertEqual(revoked.remainingAmountMinor, 8_000)
        XCTAssertEqual(revoked.status, "pending")
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 13_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 20_000)
        XCTAssertEqual(try repository.revokeLiabilityPayment(
            id: confirmed.id, profileID: profile.id, reason: "重复撤销", now: date.addingTimeInterval(4)
        ), revoked)
        XCTAssertEqual(try repository.liabilityPayments(accountID: liabilityID).filter { $0.status == "voided" }.count, 3)
        XCTAssertEqual(try repository.accountEntries(accountID: liabilityID).filter { $0.voidedAt == nil }.count, 4)

        try database.writer.write { db in
            try db.execute(sql: "UPDATE local_accounts SET auto_debit_account_id = NULL WHERE id = ?", arguments: [liabilityID.uuidString])
            try db.execute(sql: "UPDATE local_repayment_cycles SET auto_debit_account_id = NULL WHERE id = ?", arguments: [cycle.id.uuidString])
        }
        _ = try repository.confirmRepayment(
            cycleID: cycle.id, profileID: profile.id, paidAmountMinor: 5_000,
            debitAccountID: nil, status: nil, note: "无扣款账户仍可还款", paidAt: date.addingTimeInterval(5)
        )
        let unlinkedPayment = try XCTUnwrap(repository.liabilityPayments(accountID: liabilityID).first { $0.status == "confirmed" })
        XCTAssertNil(unlinkedPayment.debitAccountID)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liabilityID), 8_000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: debitID), 20_000)
    }

    func testLF03738LiabilityAccountConfigurationPersistsAcrossDatabaseReopen() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let debitAccountID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: debitAccountID, profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 20_000, createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let liabilityID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        _ = try repository.createAccount(LocalAccountDraft(
            id: liabilityID, profileID: profile.id, name: "示例信用卡", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 50_000, createdAt: Date(timeIntervalSince1970: 2_000),
            institution: "示例银行", last4: "1234", billDay: 15, paymentDueDay: 25,
            autoDebitAccountID: debitAccountID, autoConfirmRepayment: false, gracePeriodDays: 3,
            isDefaultExpense: false, isDefaultIncome: false, isArchived: false, sortOrder: 1
        ))
        _ = try repository.createExpense(LocalExpenseDraft(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            profileID: profile.id, accountID: liabilityID, amountMinor: 3_000, currency: "CNY",
            merchantName: "示例消费", platform: "", category: "other", paymentMethod: "credit_card",
            transactionDate: "2026-10-25", transactionTime: nil, note: nil,
            createdAt: Date(timeIntervalSince1970: 3_000)
        ), operationID: UUID())

        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: databaseURL))
        let saved = try XCTUnwrap(reopened.accounts(profileID: profile.id).first { $0.id == liabilityID })
        XCTAssertEqual(saved.kind, "credit_card")
        XCTAssertEqual(saved.openingBalanceMinor, 50_000)
        XCTAssertEqual(saved.institution, "示例银行")
        XCTAssertEqual(saved.last4, "1234")
        XCTAssertEqual(saved.billDay, 15)
        XCTAssertEqual(saved.paymentDueDay, 25)
        XCTAssertEqual(saved.autoDebitAccountID, debitAccountID)
        XCTAssertEqual(saved.gracePeriodDays, 3)
        XCTAssertFalse(saved.isArchived)
        XCTAssertEqual(try reopened.accountBalanceMinor(accountID: liabilityID), 53_000, "信用消费增加待还金额")
        XCTAssertEqual(try reopened.accountEntries(sourceID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!).first?.direction, "in")
        _ = try reopened.createIncome(LocalIncomeDraft(
            id: UUID(), profileID: profile.id, accountID: liabilityID, amountMinor: 500, currency: "CNY",
            sourceName: "按既有流水合同记入账户", category: "other", incomeDate: "2026-10-25",
            occurredAt: nil, note: nil, createdAt: Date()
        ))
        XCTAssertEqual(try reopened.accountBalanceMinor(accountID: liabilityID), 53_500)
    }

    func testLF03739LocalDefaultsArchiveAndAutoDebitCleanupAreTransactional() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let assetID = UUID(), secondAssetID = UUID(), liabilityID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_000)
        _ = try repository.createAccount(LocalAccountDraft(
            id: assetID, profileID: profile.id, name: "现金", kind: "cash", currency: "CNY",
            openingBalanceMinor: 20_000, createdAt: createdAt,
            isDefaultExpense: true, isDefaultIncome: true
        ))
        _ = try repository.createAccount(LocalAccountDraft(
            id: secondAssetID, profileID: profile.id, name: "银行卡", kind: "debit_card", currency: "CNY",
            openingBalanceMinor: 10_000, createdAt: createdAt
        ))
        _ = try repository.createAccount(LocalAccountDraft(
            id: liabilityID, profileID: profile.id, name: "信用卡", kind: "credit_card", currency: "CNY",
            openingBalanceMinor: 50_000, createdAt: createdAt, autoDebitAccountID: assetID,
            isDefaultIncome: true
        ))
        let asset = try XCTUnwrap(repository.accounts(profileID: profile.id).first { $0.id == assetID })
        _ = try repository.updateAccount(LocalAccountUpdate(
            id: secondAssetID, profileID: profile.id, expectedVersion: 1, name: "银行卡", kind: "debit_card",
            institution: "", last4: "", billDay: nil, paymentDueDay: nil, autoDebitAccountID: nil,
            autoConfirmRepayment: false, gracePeriodDays: 0, isDefaultExpense: true, isDefaultIncome: false,
            isArchived: false, sortOrder: 1, updatedAt: Date()
        ))
        var accounts = try repository.accounts(profileID: profile.id)
        XCTAssertFalse(try XCTUnwrap(accounts.first { $0.id == assetID }).isDefaultExpense)
        XCTAssertTrue(try XCTUnwrap(accounts.first { $0.id == secondAssetID }).isDefaultExpense)
        XCTAssertTrue(try XCTUnwrap(accounts.first { $0.id == liabilityID }).isDefaultIncome)

        _ = try repository.updateAccount(LocalAccountUpdate(
            id: asset.id, profileID: profile.id, expectedVersion: asset.localVersion, name: "现金", kind: "cash",
            institution: "", last4: "", billDay: nil, paymentDueDay: nil, autoDebitAccountID: nil,
            autoConfirmRepayment: false, gracePeriodDays: 0, isDefaultExpense: true, isDefaultIncome: true,
            isArchived: true, sortOrder: 0, updatedAt: Date()
        ))
        accounts = try repository.accounts(profileID: profile.id)
        let archivedAsset = try XCTUnwrap(accounts.first { $0.id == assetID })
        let liability = try XCTUnwrap(accounts.first { $0.id == liabilityID })
        XCTAssertTrue(archivedAsset.isArchived)
        XCTAssertFalse(archivedAsset.isDefaultExpense)
        XCTAssertFalse(archivedAsset.isDefaultIncome)
        XCTAssertNil(liability.autoDebitAccountID, "归档扣款资产时清除仍有效的扣款配置")
    }

    func testIOSV2POLISH003F10WakeDateRoutesLegacyLocalFactAcrossMonthsWithoutRewriting() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalRecordRepository(database: database)
        let payload = ["sleep_minutes": AnyCodable(420), "wake_at": AnyCodable("2026-09-30T16:30:00Z")]
        let legacy = try repository.createRecord(LocalRecordDraft(
            id: UUID(), profileID: profile.id, domainKey: "sleep", title: "补录睡眠", summary: "",
            payloadJSON: try LocalRecordCodec.encode(payload), recordDate: "2026-11-10", recordTime: nil,
            note: nil, imagePath: nil, imageHash: nil, createdAt: Date()
        ))
        let reader = try LocalFactReader(database: database)
        let wakeMonth = try reader.month(profileID: profile.id, monthKey: "2026-10")
        let queuedWakeMonth = try await reader.activeMonth(monthKey: "2026-10")
        XCTAssertEqual(queuedWakeMonth, wakeMonth, "异步队列读取与原事实语义一致，不改业务日期或历史行")
        XCTAssertEqual(wakeMonth.facts.first?.businessDate, "2026-10-01")
        XCTAssertTrue(try reader.month(profileID: profile.id, monthKey: "2026-11").facts.isEmpty)
        XCTAssertEqual(try repository.record(id: legacy.id)?.recordDate, "2026-11-10", "不静默重写历史行")
        XCTAssertEqual(try repository.records(profileID: profile.id, monthKey: "2026-10").count, 1)
        XCTAssertEqual(NativeSleepFacts.businessDate(domainKey: "sleep", payload: ["sleep_minutes": AnyCodable(420)], fallback: "2026-09-28"), "2026-09-28")
        let useCase = LocalRecordUseCase(profileStore: LocalProfileStore(database: database), repository: repository)
        let created = try await useCase.create(LocalRecordCommand(
            id: UUID(), domainKey: "sleep", title: "补录睡眠", summary: "", payload: payload,
            recordDate: "2026-11-10", recordTime: nil, note: nil, imageData: nil, createdAt: Date()
        ))
        XCTAssertEqual(created.record.recordDate, "2026-10-01")
        XCTAssertNil(created.record.recordTime)
        let staged = try await useCase.stage(LocalRecordCandidate(
            id: "wake-date-candidate", domainKey: "sleep", title: "候选睡眠", summary: "", payload: payload,
            confidence: 0.4, recordDate: "2026-11-10", recordTime: nil, imageData: nil, createdAt: Date()
        ))
        XCTAssertEqual(staged.record.recordDate, "2026-10-01")
        let confirmed = try await useCase.confirmStaging(id: staged.record.id, recordID: UUID())
        XCTAssertEqual(confirmed.record.recordDate, "2026-10-01")
    }

    func testLOCALP1DM002IntakePreservesCandidateAndFormalSourceKinds() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )

        let archived = try await useCase.ingest(
            LocalRecordCandidate(
                id: "candidate-source-auto",
                domainKey: "sport",
                title: "自动归档运动",
                summary: "高置信度候选",
                payload: [
                    "sport_type": AnyCodable("跑步"),
                    "duration_minutes": AnyCodable(30)
                ],
                confidence: 0.90,
                recordDate: "2026-09-19",
                recordTime: nil,
                imageData: nil,
                createdAt: Date()
            ),
            recordID: UUID()
        )
        guard case .archived(let archived) = archived else {
            return XCTFail("高置信度候选应自动归档")
        }
        XCTAssertEqual(archived.record.sourceKind, .aiAutoArchive)
        XCTAssertEqual(archived.record.domainVersion, 1)

        let staged = try await useCase.ingest(
            LocalRecordCandidate(
                id: "candidate-source-review",
                domainKey: "sport",
                title: "待确认运动",
                summary: "低置信度候选",
                payload: [
                    "sport_type": AnyCodable("游泳"),
                    "duration_minutes": AnyCodable(25)
                ],
                confidence: 0.40,
                recordDate: "2026-09-19",
                recordTime: nil,
                imageData: nil,
                createdAt: Date()
            ),
            recordID: nil
        )
        guard case .staged(let staged) = staged else {
            return XCTFail("低置信度候选应进入中转站")
        }
        XCTAssertEqual(staged.record.sourceKind, .aiCandidate)
        XCTAssertEqual(staged.record.domainVersion, 1)

        let confirmed = try await useCase.confirmStaging(
            id: staged.record.id,
            recordID: UUID()
        )
        XCTAssertEqual(confirmed.record.sourceKind, .aiConfirmed)
        XCTAssertEqual(confirmed.record.domainVersion, 1)
    }

    func testLOCALP1DM001GenericRepositoryRejectsExpenseDomain() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalRecordRepository(database: database)

        XCTAssertThrowsError(try repository.createRecord(LocalRecordDraft(
            id: UUID(),
            profileID: profile.id,
            domainKey: "expense",
            title: "不应进入通用记录",
            summary: "消费必须走 local_expenses",
            payloadJSON: "{}",
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date()
        ))) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidRecord)
        }
    }

    func testLOCALP1DM003DomainThresholdsRequireDomainFactsAndNormalizeSleepMinutes() throws {
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.75,
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)]
            ),
            .autoArchive
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.74,
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)]
            ),
            .staging
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "food",
                confidence: 0.79,
                payload: ["meal_type": AnyCodable("lunch"), "total_calorie_kcal": AnyCodable(520)]
            ),
            .staging
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(
                domainKey: "sport",
                confidence: 0.99,
                payload: ["sport_type": AnyCodable("跑步")]
            ),
            .staging
        )

        let normalized = try LocalRecordCodec.normalizedPayload(
            domainKey: "sleep",
            payload: [
                "sleep_hours": AnyCodable(6.5),
                "quality_level": AnyCodable("良好")
            ]
        )
        XCTAssertEqual(normalized["sleep_minutes"]?.value as? Int, 390)
        XCTAssertNil(normalized["sleep_hours"])
    }

    func testLOCALP1DM009MalformedTimeFailsAndMissingTimeRemainsMissing() async throws {
        XCTAssertThrowsError(try LocalRecordValidation.validate(
            domainKey: "reading",
            title: "阅读",
            recordDate: "2026-09-19",
            recordTime: "上传时刻"
        )) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidRecord)
        }

        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )

        let result = try await useCase.create(LocalRecordCommand(
            id: UUID(),
            domainKey: "reading",
            title: "阅读",
            summary: "没有完整发生时间",
            payload: [
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(25)
            ],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        XCTAssertNil(result.record.recordTime)
    }

    func testLOCALP1DM006ConfirmingStagingTwiceReturnsSameFormalRecord() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let staging = try await useCase.stage(LocalRecordCandidate(
            id: "staging-idempotent-1",
            domainKey: "sport",
            title: "待确认运动",
            summary: "用户确认后归档",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            confidence: 0.62,
            recordDate: "2026-09-19",
            recordTime: nil,
            imageData: nil,
            createdAt: Date()
        ))

        let recordID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let first = try await useCase.confirmStaging(id: staging.record.id, recordID: recordID)
        let retry = try await useCase.confirmStaging(
            id: staging.record.id,
            recordID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        )

        XCTAssertEqual(first.record.id, recordID)
        XCTAssertEqual(retry.record.id, recordID)
        let records = try await useCase.records(monthKey: "2026-09")
        XCTAssertEqual(records.map(\.id), [recordID])
    }

    func testLOCALP1DM008StaleVersionCannotOverwriteFormalFact() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let recordID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: recordID,
            domainKey: "sport",
            title: "原始运动",
            summary: "原始摘要",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(30)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date()
        ))
        _ = try await useCase.update(LocalRecordUpdateCommand(
            id: recordID,
            expectedVersion: 1,
            title: "第一次编辑",
            summary: "已保存",
            payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(35)],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            updatedAt: Date()
        ))

        do {
            _ = try await useCase.update(LocalRecordUpdateCommand(
                id: recordID,
                expectedVersion: 1,
                title: "旧版本覆盖",
                summary: "不应保存",
                payload: ["sport_type": AnyCodable("跑步"), "duration_minutes": AnyCodable(99)],
                recordDate: "2026-09-19",
                recordTime: nil,
                note: nil,
                updatedAt: Date()
            ))
            XCTFail("旧版本更新不应成功")
        } catch let error as LocalDataError {
            XCTAssertEqual(error, .versionConflict(expected: 1, actual: 2))
        }
        let savedRecord = try await useCase.record(id: recordID)
        XCTAssertEqual(savedRecord?.title, "第一次编辑")
    }

    func testLOCALP1DM004DM005SleepAndReadingConfidenceBoundariesFollowDomainThresholds() {
        let sleepPayload: [String: AnyCodable] = [
            "sleep_hours": AnyCodable(6.5),
            "quality_level": AnyCodable("良好")
        ]
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "sleep", confidence: 0.75, payload: sleepPayload),
            .autoArchive,
            "DM-004：sleep 达到分域阈值 0.75 应自动归档"
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "sleep", confidence: 0.74, payload: sleepPayload),
            .staging,
            "DM-005：sleep 低于分域阈值应进本地 Inbox"
        )
        let readingPayload: [String: AnyCodable] = [
            "book_name": AnyCodable("原则"),
            "reading_minutes": AnyCodable(25)
        ]
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "reading", confidence: 0.75, payload: readingPayload),
            .autoArchive
        )
        XCTAssertEqual(
            LocalRecordIntakeRouter.route(domainKey: "reading", confidence: 0.74, payload: readingPayload),
            .staging
        )
    }

    func testLOCALP1DM011FactReaderMergesFormalDomainsAndExcludesStagingAndTombstones() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()

        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 1_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 1_980,
            currency: "CNY",
            merchantName: "本地咖啡店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: "08:30",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 1_100)
        ), operationID: UUID())
        let incomeID = UUID()
        _ = try expenseRepository.createIncome(LocalIncomeDraft(
            id: incomeID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 3_000,
            currency: "CNY",
            sourceName: "稿费",
            category: "other",
            incomeDate: "2026-09-19",
            occurredAt: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 3_150)
        ))

        let useCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalRecordRepository(database: database)
        )
        let activeSportID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: activeSportID,
            domainKey: "sport",
            title: "晨跑",
            summary: "30 分钟",
            payload: [
                "sport_type": AnyCodable("跑步"),
                "duration_minutes": AnyCodable(30)
            ],
            recordDate: "2026-09-19",
            recordTime: "10:30",
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_200)
        ))

        let deletedReadingID = UUID()
        _ = try await useCase.create(LocalRecordCommand(
            id: deletedReadingID,
            domainKey: "reading",
            title: "已删除阅读",
            summary: "不应出现在正式事实层",
            payload: [
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(20)
            ],
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_300)
        ))
        _ = try await useCase.delete(LocalRecordDeleteCommand(
            id: deletedReadingID,
            expectedVersion: 1,
            deletedAt: Date(timeIntervalSince1970: 1_400)
        ))

        _ = try await useCase.stage(LocalRecordCandidate(
            id: "staging-not-a-fact",
            domainKey: "food",
            title: "待确认餐食",
            summary: "中转站内容",
            payload: ["meal_type": AnyCodable("lunch")],
            confidence: 0.50,
            recordDate: "2026-09-19",
            recordTime: nil,
            imageData: nil,
            createdAt: Date(timeIntervalSince1970: 1_500)
        ))

        let reader = try LocalFactReader(database: database)
        let month = try reader.month(profileID: profile.id, monthKey: "2026-09")

        XCTAssertEqual(month.facts.map(\.reference), [
            "data/\(activeSportID.uuidString)",
            "expense/\(expenseID.uuidString)",
            "income/\(incomeID.uuidString)"
        ])
        XCTAssertEqual(month.facts.map(\.domainKey), ["sport", "expense", "income"])
        XCTAssertEqual(month.facts.map(\.kind), [.record, .expense, .income])
        XCTAssertEqual(month.facts.last?.payloadJSON.contains("amount_minor"), true)
        XCTAssertFalse(month.facts.contains { $0.id == deletedReadingID })
        let stagingRecords = try await useCase.stagingRecords()
        XCTAssertEqual(stagingRecords.count, 1)
    }

    func testLOCALP1DM011FactReadModelProjectsSeparateTodayAndRecordsGroups() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 2_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 680,
            currency: "CNY",
            merchantName: "早餐店",
            platform: "线下",
            category: "餐饮",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: "08:00",
            note: nil,
            createdAt: Date(timeIntervalSince1970: 2_100)
        ), operationID: UUID())

        let recordID = UUID()
        let recordRepository = try LocalRecordRepository(database: database)
        _ = try recordRepository.createRecord(LocalRecordDraft(
            id: recordID,
            profileID: profile.id,
            domainKey: "sport",
            title: "散步",
            summary: "20 分钟",
            payloadJSON: try LocalRecordCodec.encode([
                "sport_type": AnyCodable("散步"),
                "duration_minutes": AnyCodable(20)
            ]),
            recordDate: "2026-09-19",
            recordTime: "18:00",
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date(timeIntervalSince1970: 2_200)
        ))

        let month = try LocalFactReader(database: database).month(
            profileID: profile.id,
            monthKey: "2026-09"
        )
        let expenseGroups = LocalFactReadModel.groups(from: month, including: [.expense])
        let recordGroups = LocalFactReadModel.groups(from: month, including: [.record])
        let details = LocalFactReadModel.details(from: month)

        XCTAssertEqual(expenseGroups.flatMap(\.records).map(\.reference), [
            "expense/\(expenseID.uuidString)"
        ])
        XCTAssertEqual(recordGroups.flatMap(\.records).map(\.reference), [
            "data/\(recordID.uuidString)"
        ])
        XCTAssertEqual(details["expense/\(expenseID.uuidString)"]?.amount ?? 0, 6.8, accuracy: 0.001)
        XCTAssertEqual(details["data/\(recordID.uuidString)"]?.domainKey, "sport")
    }

    func testLOCALP1DM010UnifiedExportCoversExpenseAndNonFinancialFacts() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let expenseRepository = try LocalExpenseRepository(database: database)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: Date(timeIntervalSince1970: 3_000)
        ))
        let expenseID = UUID()
        _ = try expenseRepository.createExpense(LocalExpenseDraft(
            id: expenseID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 1_200,
            currency: "CNY",
            merchantName: "书店",
            platform: "线下",
            category: "阅读",
            paymentMethod: "现金",
            transactionDate: "2026-09-19",
            transactionTime: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 3_100)
        ), operationID: UUID())
        let incomeID = UUID()
        _ = try expenseRepository.createIncome(LocalIncomeDraft(
            id: incomeID,
            profileID: profile.id,
            accountID: account.id,
            amountMinor: 3_000,
            currency: "CNY",
            sourceName: "稿费",
            category: "other",
            incomeDate: "2026-09-19",
            occurredAt: nil,
            note: nil,
            createdAt: Date(timeIntervalSince1970: 3_150)
        ))
        let recordID = UUID()
        let recordRepository = try LocalRecordRepository(database: database)
        _ = try recordRepository.createRecord(LocalRecordDraft(
            id: recordID,
            profileID: profile.id,
            domainKey: "reading",
            title: "原则",
            summary: "25 分钟",
            payloadJSON: try LocalRecordCodec.encode([
                "book_name": AnyCodable("原则"),
                "reading_minutes": AnyCodable(25)
            ]),
            recordDate: "2026-09-19",
            recordTime: nil,
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date(timeIntervalSince1970: 3_200)
        ))

        let portability = LocalFactPortability(database: database)
        var request = NativeDataExportRequest()
        request.content = .universal
        request.range = .all
        request.format = .json
        request.includeFullPayload = true
        let json = try portability.exportArchive(
            request: request,
            exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        let archive = try JSONDecoder.iso8601.decode(LocalFactArchive.self, from: json)
        XCTAssertEqual(archive.format, LocalFactArchive.currentFormat)
        XCTAssertEqual(Set(archive.facts.map(\.reference)), [
            "expense/\(expenseID.uuidString)",
            "income/\(incomeID.uuidString)",
            "data/\(recordID.uuidString)"
        ])
        XCTAssertTrue(archive.facts.contains { $0.payloadJSON.contains("reading_minutes") })
        XCTAssertEqual(archive.facts.first(where: { $0.kind == "income" })?.occurredAt, nil)
        XCTAssertTrue(archive.facts.first(where: { $0.kind == "income" })?.payloadJSON.contains("amount_minor") == true)

        request.format = .csv
        request.includeFullPayload = false
        let csv = String(
            decoding: try portability.exportArchive(
                request: request,
                exportedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            as: UTF8.self
        )
        XCTAssertTrue(csv.contains("expense/\(expenseID.uuidString)"))
        XCTAssertTrue(csv.contains("income/\(incomeID.uuidString)"))
        XCTAssertTrue(csv.contains("data/\(recordID.uuidString)"))
        XCTAssertTrue(csv.contains(",{}"))
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-phase1-model-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
    }
}

private extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
