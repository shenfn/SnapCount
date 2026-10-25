import Foundation
import GRDB

protocol LocalExpenseRepositoryProtocol {
    func createProfile(id: UUID, createdAt: Date) throws -> LocalProfile
    func createAccount(_ draft: LocalAccountDraft) throws -> LocalAccount
    func updateAccount(_ update: LocalAccountUpdate) throws -> LocalAccount
    func importRemoteAccounts(_ drafts: [LocalAccountDraft]) throws
    func accounts(profileID: UUID) throws -> [LocalAccount]
    func ensureRepaymentCycles(profileID: UUID, monthKey: String, now: Date) throws -> [LocalRepaymentCycle]
    func confirmRepayment(cycleID: UUID, profileID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, status: String?, note: String, paidAt: Date) throws -> LocalRepaymentCycle
    func confirmScreenshotRepayment(stagingID: String, cycleID: UUID, profileID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, note: String, paidAt: Date) throws -> LocalRepaymentCycle
    func revokeLiabilityPayment(id: UUID, profileID: UUID, reason: String, now: Date) throws -> LocalRepaymentCycle?
    func repaymentCycles(accountID: UUID) throws -> [LocalRepaymentCycle]
    func liabilityPayments(accountID: UUID) throws -> [LocalLiabilityPayment]
    func createExpense(_ draft: LocalExpenseDraft, operationID: UUID) throws -> LocalExpense
    func importRemoteExpenses(_ drafts: [LocalExpenseDraft]) throws
    func updateExpense(_ update: LocalExpenseUpdate, operationID: UUID) throws -> LocalExpense
    func deleteExpense(
        id: UUID,
        expectedVersion: Int64,
        deletedAt: Date,
        operationID: UUID
    ) throws -> LocalExpenseTombstone
    func expense(id: UUID) throws -> LocalExpense?
    func expenses(profileID: UUID, monthKey: String) throws -> [LocalExpense]
    func createIncome(_ draft: LocalIncomeDraft) throws -> LocalIncome
    func updateIncome(_ update: LocalIncomeUpdate) throws -> LocalIncome
    func deleteIncome(id: UUID, profileID: UUID, expectedVersion: Int64, deletedAt: Date) throws -> LocalIncomeTombstone
    func income(id: UUID) throws -> LocalIncome?
    func incomes(profileID: UUID, monthKey: String) throws -> [LocalIncome]
    func expenseTombstone(id: UUID) throws -> LocalExpenseTombstone?
    func expenseCount() throws -> Int
    func accountEntryCount() throws -> Int
    func accountEntries(sourceID: UUID) throws -> [LocalAccountEntry]
    func accountEntries(accountID: UUID) throws -> [LocalAccountEntry]
    func pendingOutboxOperations() throws -> [LocalOutboxOperation]
    @discardableResult
    func ensureAccountOutboxForPendingExpenses(profileID: UUID) throws -> Int
    func pendingOutboxUploads(profileID: UUID) throws -> [LocalOutboxUpload]
    func markOutboxSent(operationIDs: [UUID]) throws
    func discardOutboxOperations(operationIDs: [UUID], reason: String) throws
    func markOutboxFailed(operationIDs: [UUID], error: String) throws
    func accountBalanceMinor(accountID: UUID) throws -> Int64
    func applyRemoteSnapshot(
        _ snapshot: LocalRemoteSnapshot,
        profileID: UUID,
        excludingExpenseIDs: Set<UUID>,
        excludingAccountIDs: Set<UUID>
    ) throws -> Int
}

extension LocalExpenseRepositoryProtocol {
    func ensureRepaymentCycles(profileID: UUID, monthKey: String, now: Date) throws -> [LocalRepaymentCycle] { throw LocalDataError.invalidRecord }
    func confirmRepayment(cycleID: UUID, profileID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, status: String?, note: String, paidAt: Date) throws -> LocalRepaymentCycle { throw LocalDataError.invalidRecord }
    func confirmScreenshotRepayment(stagingID: String, cycleID: UUID, profileID: UUID, paidAmountMinor: Int64, debitAccountID: UUID?, note: String, paidAt: Date) throws -> LocalRepaymentCycle { throw LocalDataError.invalidRecord }
    func revokeLiabilityPayment(id: UUID, profileID: UUID, reason: String, now: Date) throws -> LocalRepaymentCycle? { throw LocalDataError.invalidRecord }
    func repaymentCycles(accountID: UUID) throws -> [LocalRepaymentCycle] { [] }
    func liabilityPayments(accountID: UUID) throws -> [LocalLiabilityPayment] { [] }
}

final class LocalExpenseRepository: LocalExpenseRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func createProfile(id: UUID, createdAt: Date) throws -> LocalProfile {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_profiles (id, created_at, cloud_user_id, sync_enabled)
                    VALUES (?, ?, NULL, 0)
                    """,
                arguments: [id.uuidString, createdAt]
            )
        }
        return LocalProfile(id: id, createdAt: createdAt, cloudUserID: nil, syncEnabled: false)
    }

    func createAccount(_ draft: LocalAccountDraft) throws -> LocalAccount {
        try database.writer.write { db in
            try Self.insertAccount(draft, database: db)
        }
    }

    static func insertAccount(_ draft: LocalAccountDraft, database db: Database) throws -> LocalAccount {
        guard draft.openingBalanceMinor >= 0 else { throw LocalDataError.invalidAmount }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { throw LocalDataError.invalidRecord }
        try Self.validateAccountConfiguration(
            kind: draft.kind, last4: draft.last4, billDay: draft.billDay,
            paymentDueDay: draft.paymentDueDay, autoDebitAccountID: draft.autoDebitAccountID,
            autoConfirmRepayment: draft.autoConfirmRepayment, gracePeriodDays: draft.gracePeriodDays,
            isDefaultExpense: draft.isDefaultExpense, isDefaultIncome: draft.isDefaultIncome,
            isArchived: draft.isArchived, profileID: draft.profileID, accountID: draft.id, database: db
        )
        if draft.isDefaultExpense {
            try db.execute(sql: "UPDATE local_accounts SET is_default_expense = 0 WHERE profile_id = ?", arguments: [draft.profileID.uuidString])
        }
        if draft.isDefaultIncome {
            try db.execute(sql: "UPDATE local_accounts SET is_default_income = 0 WHERE profile_id = ?", arguments: [draft.profileID.uuidString])
        }
        try db.execute(
            sql: """
                INSERT INTO local_accounts (
                    id, profile_id, name, kind, currency, opening_balance_minor, created_at, origin,
                    institution, last4, bill_day, payment_due_day, auto_debit_account_id,
                    auto_confirm_repayment, grace_period_days, last_reconciled_at, is_default_expense, is_default_income,
                    is_archived, sort_order
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 'local', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                draft.id.uuidString,
                draft.profileID.uuidString,
                name,
                draft.kind,
                draft.currency,
                draft.openingBalanceMinor,
                draft.createdAt,
                draft.institution,
                draft.last4,
                draft.billDay,
                draft.paymentDueDay,
                draft.autoDebitAccountID?.uuidString,
                draft.autoConfirmRepayment,
                draft.gracePeriodDays,
                draft.lastReconciledAt,
                draft.isDefaultExpense,
                draft.isDefaultIncome,
                draft.isArchived,
                draft.sortOrder
            ]
        )
        try Self.insertOutbox(
            operationID: UUID(),
            profileID: draft.profileID,
            aggregateKind: "account",
            aggregateID: draft.id,
            operationKind: "upsert",
            aggregateVersion: 1,
            payload: try Self.outboxPayload(account: draft),
            createdAt: draft.createdAt,
            database: db
        )
        return LocalAccount(
            id: draft.id,
            profileID: draft.profileID,
            name: name,
            kind: draft.kind,
            currency: draft.currency,
            openingBalanceMinor: draft.openingBalanceMinor,
            createdAt: draft.createdAt,
            institution: draft.institution,
            last4: draft.last4,
            billDay: draft.billDay,
            paymentDueDay: draft.paymentDueDay,
            autoDebitAccountID: draft.autoDebitAccountID,
            autoConfirmRepayment: draft.autoConfirmRepayment,
            gracePeriodDays: draft.gracePeriodDays,
            lastReconciledAt: draft.lastReconciledAt,
            isDefaultExpense: draft.isDefaultExpense,
            isDefaultIncome: draft.isDefaultIncome,
            isArchived: draft.isArchived,
            sortOrder: draft.sortOrder
        )
    }

    func updateAccount(_ update: LocalAccountUpdate) throws -> LocalAccount {
        let name = update.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { throw LocalDataError.invalidRecord }
        try database.writer.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_accounts WHERE id = ? AND profile_id = ?",
                arguments: [update.id.uuidString, update.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            let currentVersion: Int64 = row["local_version"]
            guard currentVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(expected: update.expectedVersion, actual: currentVersion)
            }
            let currentKind: String = row["kind"]
            let liabilityKinds: Set<String> = ["credit_card", "credit_line"]
            if liabilityKinds.contains(currentKind) != liabilityKinds.contains(update.kind) {
                let hasEntries = try Row.fetchOne(db, sql: """
                    SELECT 1 FROM local_account_entries WHERE account_id = ? LIMIT 1
                    """, arguments: [update.id.uuidString]) != nil
                let hasExpenses = try Row.fetchOne(db, sql: "SELECT 1 FROM local_expenses WHERE account_id = ? LIMIT 1", arguments: [update.id.uuidString]) != nil
                let hasIncome = try Row.fetchOne(db, sql: "SELECT 1 FROM local_income_records WHERE account_id = ? LIMIT 1", arguments: [update.id.uuidString]) != nil
                let hasCycleReference = try Row.fetchOne(db, sql: """
                    SELECT 1 FROM local_repayment_cycles
                    WHERE profile_id = ? AND (account_id = ? OR auto_debit_account_id = ?) LIMIT 1
                    """, arguments: [update.profileID.uuidString, update.id.uuidString, update.id.uuidString]) != nil
                let hasPaymentReference = try Row.fetchOne(db, sql: """
                    SELECT 1 FROM local_liability_payments
                    WHERE profile_id = ? AND (account_id = ? OR debit_account_id = ?) LIMIT 1
                    """, arguments: [update.profileID.uuidString, update.id.uuidString, update.id.uuidString]) != nil
                let hasAutoDebitReference = try Row.fetchOne(db, sql: """
                    SELECT 1 FROM local_accounts
                    WHERE profile_id = ? AND id != ? AND auto_debit_account_id = ? LIMIT 1
                    """, arguments: [update.profileID.uuidString, update.id.uuidString, update.id.uuidString]) != nil
                guard !(hasEntries || hasExpenses || hasIncome || hasCycleReference || hasPaymentReference || hasAutoDebitReference) else {
                    throw LocalDataError.invalidAccountKind
                }
            }
            try Self.validateAccountConfiguration(
                kind: update.kind, last4: update.last4, billDay: update.billDay,
                paymentDueDay: update.paymentDueDay, autoDebitAccountID: update.autoDebitAccountID,
                autoConfirmRepayment: update.autoConfirmRepayment, gracePeriodDays: update.gracePeriodDays,
                isDefaultExpense: update.isArchived ? false : update.isDefaultExpense,
                isDefaultIncome: update.isArchived ? false : update.isDefaultIncome,
                isArchived: update.isArchived, profileID: update.profileID, accountID: update.id, database: db
            )
            if update.isDefaultExpense {
                try db.execute(sql: "UPDATE local_accounts SET is_default_expense = 0 WHERE profile_id = ? AND id != ?", arguments: [update.profileID.uuidString, update.id.uuidString])
            }
            if update.isDefaultIncome {
                try db.execute(sql: "UPDATE local_accounts SET is_default_income = 0 WHERE profile_id = ? AND id != ?", arguments: [update.profileID.uuidString, update.id.uuidString])
            }
            if update.isArchived {
                try db.execute(sql: """
                    UPDATE local_accounts
                    SET auto_debit_account_id = NULL, auto_confirm_repayment = 0, local_version = local_version + 1
                    WHERE profile_id = ? AND auto_debit_account_id = ?
                    """, arguments: [update.profileID.uuidString, update.id.uuidString])
            }
            try db.execute(sql: """
                UPDATE local_accounts SET name = ?, kind = ?, institution = ?, last4 = ?, bill_day = ?,
                    payment_due_day = ?, auto_debit_account_id = ?, auto_confirm_repayment = ?,
                    grace_period_days = ?, is_default_expense = ?, is_default_income = ?, is_archived = ?,
                    sort_order = ?, local_version = local_version + 1
                WHERE id = ? AND profile_id = ? AND local_version = ?
                """, arguments: [
                    name, update.kind, update.institution, update.last4, update.billDay,
                    update.paymentDueDay, update.autoDebitAccountID?.uuidString, update.autoConfirmRepayment,
                    update.gracePeriodDays, update.isArchived ? false : update.isDefaultExpense,
                    update.isArchived ? false : update.isDefaultIncome, update.isArchived,
                    update.sortOrder, update.id.uuidString, update.profileID.uuidString, update.expectedVersion
                ])
            guard db.changesCount == 1 else {
                let actual = try Int64.fetchOne(db, sql: "SELECT local_version FROM local_accounts WHERE id = ?", arguments: [update.id.uuidString]) ?? 0
                throw LocalDataError.versionConflict(expected: update.expectedVersion, actual: actual)
            }
        }
        guard let saved = try accounts(profileID: update.profileID).first(where: { $0.id == update.id }) else {
            throw LocalDataError.recordNotFound
        }
        return saved
    }

    /// Mirrors already-authoritative cloud accounts without enqueueing uploads.
    /// The local workspace is a projection here; a user-created local account
    /// still goes through createAccount and produces an outbox operation.
    func importRemoteAccounts(_ drafts: [LocalAccountDraft]) throws {
        guard !drafts.isEmpty else { return }
        let orderedDrafts = drafts.sorted { left, right in
            let liabilities: Set<String> = ["credit_card", "credit_line"]
            return liabilities.contains(left.kind) == false && liabilities.contains(right.kind)
        }
        try database.writer.write { db in
            for draft in orderedDrafts {
                if draft.isDefaultExpense {
                    try db.execute(sql: "UPDATE local_accounts SET is_default_expense = 0 WHERE profile_id = ? AND id != ?", arguments: [draft.profileID.uuidString, draft.id.uuidString])
                }
                if draft.isDefaultIncome {
                    try db.execute(sql: "UPDATE local_accounts SET is_default_income = 0 WHERE profile_id = ? AND id != ?", arguments: [draft.profileID.uuidString, draft.id.uuidString])
                }
                try db.execute(sql: """
                    INSERT INTO local_accounts (
                        id, profile_id, name, kind, currency, opening_balance_minor, created_at, origin,
                        institution, last4, bill_day, payment_due_day, auto_debit_account_id,
                        auto_confirm_repayment, grace_period_days, last_reconciled_at, is_default_expense, is_default_income,
                        is_archived, sort_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'remote', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name,
                        kind = excluded.kind,
                        currency = excluded.currency,
                        opening_balance_minor = excluded.opening_balance_minor,
                        institution = excluded.institution,
                        last4 = excluded.last4,
                        bill_day = excluded.bill_day,
                        payment_due_day = excluded.payment_due_day,
                        auto_debit_account_id = excluded.auto_debit_account_id,
                        auto_confirm_repayment = excluded.auto_confirm_repayment,
                        grace_period_days = excluded.grace_period_days,
                        last_reconciled_at = excluded.last_reconciled_at,
                        is_default_expense = excluded.is_default_expense,
                        is_default_income = excluded.is_default_income,
                        is_archived = excluded.is_archived,
                        sort_order = excluded.sort_order,
                        origin = CASE WHEN EXISTS (
                            SELECT 1 FROM local_outbox_operations
                            WHERE aggregate_kind = 'account'
                              AND aggregate_id = local_accounts.id
                              AND profile_id = local_accounts.profile_id
                              AND status IN ('pending', 'failed')
                        ) THEN local_accounts.origin ELSE 'remote' END
                    """, arguments: [
                        draft.id.uuidString, draft.profileID.uuidString, draft.name,
                        draft.kind, draft.currency, draft.openingBalanceMinor, draft.createdAt,
                        draft.institution, draft.last4, draft.billDay, draft.paymentDueDay,
                        draft.autoDebitAccountID?.uuidString, draft.autoConfirmRepayment,
                        draft.gracePeriodDays, draft.lastReconciledAt, draft.isDefaultExpense, draft.isDefaultIncome,
                        draft.isArchived, draft.sortOrder
                    ])
            }
        }
    }

    func accounts(profileID: UUID) throws -> [LocalAccount] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, name, kind, currency, opening_balance_minor, created_at, origin,
                           institution, last4, bill_day, payment_due_day, auto_debit_account_id,
                           auto_confirm_repayment, grace_period_days, last_reconciled_at, is_default_expense, is_default_income,
                           is_archived, sort_order, local_version
                    FROM local_accounts
                    WHERE profile_id = ?
                    ORDER BY created_at ASC, id ASC
                    """,
                arguments: [profileID.uuidString]
            ).map { row in
                guard let id = UUID(uuidString: row["id"]),
                      let storedProfileID = UUID(uuidString: row["profile_id"]),
                      let createdAt: Date = row["created_at"] else {
                    throw LocalDataError.invalidRecord
                }
                return LocalAccount(
                    id: id,
                    profileID: storedProfileID,
                    name: row["name"],
                    kind: row["kind"],
                    currency: row["currency"],
                    openingBalanceMinor: row["opening_balance_minor"],
                    createdAt: createdAt,
                    origin: row["origin"] ?? "local",
                    institution: row["institution"],
                    last4: row["last4"],
                    billDay: row["bill_day"],
                    paymentDueDay: row["payment_due_day"],
                    autoDebitAccountID: (row["auto_debit_account_id"] as String?).flatMap(UUID.init(uuidString:)),
                    autoConfirmRepayment: row["auto_confirm_repayment"],
                    gracePeriodDays: row["grace_period_days"],
                    lastReconciledAt: row["last_reconciled_at"],
                    isDefaultExpense: row["is_default_expense"],
                    isDefaultIncome: row["is_default_income"],
                    isArchived: row["is_archived"],
                    sortOrder: row["sort_order"],
                    localVersion: row["local_version"]
                )
            }
        }
    }

    func ensureRepaymentCycles(profileID: UUID, monthKey: String, now: Date) throws -> [LocalRepaymentCycle] {
        guard Self.isMonthKey(monthKey), let monthStart = Self.financeDate("\(monthKey)-01") else {
            throw LocalDataError.invalidRecord
        }
        let today = Self.financeDateKey(now)
        try database.writer.write { db in
            try db.execute(sql: """
                UPDATE local_repayment_cycles
                SET status = 'historical_unconfirmed', local_version = local_version + 1, updated_at = ?
                WHERE profile_id = ? AND source = 'system' AND status = 'overdue_unconfirmed'
                  AND paid_amount_minor = 0 AND due_date IS NOT NULL
                  AND date(due_date, printf('%+d days', COALESCE((
                      SELECT grace_period_days FROM local_accounts
                      WHERE local_accounts.id = local_repayment_cycles.account_id
                        AND local_accounts.profile_id = local_repayment_cycles.profile_id
                  ), 0))) < ?
                """, arguments: [now, profileID.uuidString, today])
            let liabilityAccounts = try Row.fetchAll(db, sql: """
                SELECT * FROM local_accounts
                WHERE profile_id = ? AND kind IN ('credit_card', 'credit_line')
                  AND is_archived = 0 AND bill_day IS NOT NULL AND payment_due_day IS NOT NULL
                """, arguments: [profileID.uuidString])
            for account in liabilityAccounts {
                guard let accountID = UUID(uuidString: account["id"]),
                      let billDay: Int = account["bill_day"], let dueDay: Int = account["payment_due_day"],
                      let cycleStart = Self.billDate(day: billDay, monthStart: monthStart, offsetMonths: -1),
                      let cycleEnd = Self.billDate(day: billDay, monthStart: monthStart, offsetMonths: 0),
                      let dueDate = Self.billDate(day: dueDay, monthStart: monthStart, offsetMonths: 0),
                      let statementStart = Self.shiftedFinanceDate(cycleStart, component: .day, value: 1) else {
                    throw LocalDataError.invalidRecord
                }
                let lastReconciledAt: Date? = account["last_reconciled_at"]
                let amount = try Int64.fetchOne(db, sql: """
                    SELECT COALESCE(SUM(expense.amount_minor), 0)
                    FROM local_expenses AS expense
                    JOIN local_account_entries AS entry
                      ON entry.source_kind = 'expense' AND entry.source_id = expense.id
                     AND entry.account_id = expense.account_id AND entry.voided_at IS NULL AND entry.is_voided = 0
                    WHERE expense.profile_id = ? AND expense.account_id = ?
                      AND expense.deleted_at IS NULL
                      AND (? IS NULL OR entry.occurred_at > ?)
                      AND expense.transaction_date > ? AND expense.transaction_date <= ?
                    """, arguments: [profileID.uuidString, accountID.uuidString, lastReconciledAt, lastReconciledAt,
                                      Self.financeDateKey(cycleStart), Self.financeDateKey(cycleEnd)]) ?? 0
                let existing = try Row.fetchOne(db, sql: """
                    SELECT * FROM local_repayment_cycles WHERE account_id = ? AND cycle_month = ?
                    """, arguments: [accountID.uuidString, monthKey])
                if amount <= 0 {
                    if let existing, (existing["source"] as String) == "system",
                       ["pending", "due_today", "overdue_unconfirmed"].contains(existing["status"] as String),
                       (existing["paid_amount_minor"] as Int64) == 0 {
                        try db.execute(sql: "DELETE FROM local_repayment_cycles WHERE id = ?", arguments: [existing["id"] as String])
                    }
                    continue
                }
                let proposedStatus = today == Self.financeDateKey(dueDate) ? "due_today"
                    : (Self.financeDateKey(dueDate) < today ? "overdue_unconfirmed" : "pending")
                let currentAutoDebit = (account["auto_debit_account_id"] as String?).flatMap(UUID.init(uuidString:))
                let autoConfirm: Bool = account["auto_confirm_repayment"]
                if let existing {
                    let oldStatus: String = existing["status"]
                    let oldSource: String = existing["source"]
                    let oldPaid: Int64 = existing["paid_amount_minor"]
                    let canRefresh = oldSource == "system"
                        && ["pending", "due_today", "overdue_unconfirmed"].contains(oldStatus)
                        && oldPaid == 0
                    guard canRefresh else { continue }
                    try db.execute(sql: """
                        UPDATE local_repayment_cycles SET statement_start_date = ?, statement_end_date = ?, due_date = ?,
                            statement_amount_minor = ?, remaining_amount_minor = ?, status = ?, auto_debit_account_id = ?,
                            auto_confirm_repayment = ?, note = '按已绑定消费流水估算', local_version = local_version + 1, updated_at = ?
                        WHERE id = ?
                        """, arguments: [Self.financeDateKey(statementStart), Self.financeDateKey(cycleEnd),
                                          Self.financeDateKey(dueDate), amount, amount, proposedStatus,
                                          currentAutoDebit?.uuidString, autoConfirm, now, existing["id"] as String])
                } else {
                    try db.execute(sql: """
                        INSERT INTO local_repayment_cycles (
                            id, profile_id, account_id, cycle_month, statement_start_date, statement_end_date, due_date,
                            statement_amount_minor, remaining_amount_minor, status, auto_debit_account_id,
                            auto_confirm_repayment, source, note, created_at, updated_at
                        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'system', '按已绑定消费流水估算', ?, ?)
                        """, arguments: [UUID().uuidString, profileID.uuidString, accountID.uuidString, monthKey,
                                          Self.financeDateKey(statementStart), Self.financeDateKey(cycleEnd),
                                          Self.financeDateKey(dueDate), amount, amount, proposedStatus,
                                          currentAutoDebit?.uuidString, autoConfirm, now, now])
                }
            }
        }
        return try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM local_repayment_cycles WHERE profile_id = ? AND cycle_month = ?
                ORDER BY due_date ASC, created_at DESC
                """, arguments: [profileID.uuidString, monthKey]).map { try Self.repaymentCycle(from: $0) }
        }
    }

    func repaymentCycles(accountID: UUID) throws -> [LocalRepaymentCycle] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM local_repayment_cycles WHERE account_id = ? ORDER BY cycle_month DESC, created_at DESC
                """, arguments: [accountID.uuidString]).map { try Self.repaymentCycle(from: $0) }
        }
    }

    func liabilityPayments(accountID: UUID) throws -> [LocalLiabilityPayment] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT * FROM local_liability_payments WHERE account_id = ? ORDER BY paid_at DESC, created_at DESC
                """, arguments: [accountID.uuidString]).map { try Self.liabilityPayment(from: $0) }
        }
    }

    func confirmRepayment(
        cycleID: UUID,
        profileID: UUID,
        paidAmountMinor: Int64,
        debitAccountID: UUID?,
        status requestedStatus: String?,
        note: String,
        paidAt: Date
    ) throws -> LocalRepaymentCycle {
        return try confirmRepayment(
            cycleID: cycleID, profileID: profileID, paidAmountMinor: paidAmountMinor,
            debitAccountID: debitAccountID, status: requestedStatus, note: note,
            paidAt: paidAt, screenshotStagingID: nil
        )
    }

    func confirmScreenshotRepayment(
        stagingID: String,
        cycleID: UUID,
        profileID: UUID,
        paidAmountMinor: Int64,
        debitAccountID: UUID?,
        note: String,
        paidAt: Date
    ) throws -> LocalRepaymentCycle {
        guard paidAmountMinor > 0 else { throw LocalDataError.invalidAmount }
        return try confirmRepayment(
            cycleID: cycleID, profileID: profileID, paidAmountMinor: paidAmountMinor,
            debitAccountID: debitAccountID, status: nil, note: note,
            paidAt: paidAt, screenshotStagingID: stagingID
        )
    }

    private func confirmRepayment(
        cycleID: UUID,
        profileID: UUID,
        paidAmountMinor: Int64,
        debitAccountID: UUID?,
        status requestedStatus: String?,
        note: String,
        paidAt: Date,
        screenshotStagingID: String?
    ) throws -> LocalRepaymentCycle {
        guard paidAmountMinor >= 0 else { throw LocalDataError.invalidAmount }
        guard requestedStatus.map({ ["partial_paid", "minimum_paid", "carried_over", "paid", "ignored"].contains($0) }) ?? true else {
            throw LocalDataError.invalidRecord
        }
        try database.writer.write { db in
            guard let cycleRow = try Row.fetchOne(db, sql: "SELECT * FROM local_repayment_cycles WHERE id = ? AND profile_id = ?", arguments: [cycleID.uuidString, profileID.uuidString]),
                  let accountRow = try Row.fetchOne(db, sql: "SELECT * FROM local_accounts WHERE id = ? AND profile_id = ?", arguments: [cycleRow["account_id"] as String, profileID.uuidString]) else {
                throw LocalDataError.recordNotFound
            }
            let kind: String = accountRow["kind"]
            guard ["credit_card", "credit_line"].contains(kind) else { throw LocalDataError.invalidAccountKind }
            if let screenshotStagingID {
                guard let staging = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM local_staging_records WHERE id = ? AND profile_id = ?",
                    arguments: [screenshotStagingID, profileID.uuidString]
                ) else { throw LocalDataError.recordNotFound }
                let domainKey: String = staging["domain_key"]
                let stagingStatus: String = staging["status"]
                let action: String? = staging["resolved_action"]
                let targetID: String? = staging["target_record_id"]
                guard domainKey == "wallet" else { throw LocalDataError.invalidRecord }
                if stagingStatus == "archived" {
                    guard action == "liability_repayment_confirmed",
                          targetID == cycleID.uuidString,
                          let payment = try Row.fetchOne(
                              db,
                              sql: "SELECT * FROM local_liability_payments WHERE evidence_staging_id = ? AND profile_id = ?",
                              arguments: [screenshotStagingID, profileID.uuidString]
                          ) else { throw LocalDataError.invalidRecord }
                    let paymentCycleID: String? = payment["statement_id"]
                    let paymentAmount: Int64 = payment["amount_minor"]
                    let paymentDebitID: String? = payment["debit_account_id"]
                    let paymentStatus: String = payment["status"]
                    let cycleDebitID: String? = cycleRow["auto_debit_account_id"]
                    let accountDebitID: String? = accountRow["auto_debit_account_id"]
                    let expectedDebitID = debitAccountID?.uuidString ?? cycleDebitID ?? accountDebitID
                    guard paymentCycleID == cycleID.uuidString,
                          paymentAmount == paidAmountMinor,
                          paymentDebitID == expectedDebitID,
                          paymentStatus == "confirmed" else { throw LocalDataError.invalidRecord }
                    return
                }
                guard stagingStatus == "pending_review" else { throw LocalDataError.invalidRecord }
                let payloadJSON: String = staging["payload_json"]
                let payload = try LocalRecordCodec.decode(payloadJSON)
                try LocalRecordValidation.validateWalletRepaymentCandidate(payload)
                let cycleStatus: String = cycleRow["status"]
                guard ["pending", "due_today", "overdue_unconfirmed", "partial_paid", "minimum_paid", "carried_over"].contains(cycleStatus) else {
                    throw LocalDataError.invalidRecord
                }
            }
            let effectiveDebitID: UUID? = try {
                if let debitAccountID {
                    try Self.validateActiveDebitAccount(id: debitAccountID, profileID: profileID, database: db)
                    return debitAccountID
                }
                let cycleDebit = (cycleRow["auto_debit_account_id"] as String?).flatMap(UUID.init(uuidString:))
                let accountDebit = (accountRow["auto_debit_account_id"] as String?).flatMap(UUID.init(uuidString:))
                guard let resolved = cycleDebit ?? accountDebit else { return nil }
                try Self.validateActiveDebitAccount(id: resolved, profileID: profileID, database: db)
                return resolved
            }()
            // Older cloud repayments used a cycle directly as the ledger
            // source. A cumulative reconfirmation replaces those entries too.
            try db.execute(sql: """
                UPDATE local_account_entries SET voided_at = ?
                WHERE profile_id = ? AND source_kind = 'repayment_cycle' AND source_id = ?
                  AND voided_at IS NULL AND is_voided = 0
                """, arguments: [paidAt, profileID.uuidString, cycleID.uuidString])
            try db.execute(sql: """
                UPDATE local_liability_payments SET status = 'voided',
                    note = COALESCE(note, '') || CASE WHEN note IS NULL OR note = '' THEN '' ELSE '；' END || '重新确认还款时作废',
                    updated_at = ? WHERE statement_id = ? AND profile_id = ? AND status != 'voided'
                """, arguments: [paidAt, cycleID.uuidString, profileID.uuidString])
            try db.execute(sql: """
                UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?)
                WHERE profile_id = ? AND source_kind = 'liability_payment' AND voided_at IS NULL AND is_voided = 0
                  AND source_id IN (SELECT id FROM local_liability_payments WHERE statement_id = ?)
                """, arguments: [paidAt, profileID.uuidString, cycleID.uuidString])

            let liabilityBalance = try Self.accountBalanceMinor(accountID: UUID(uuidString: accountRow["id"])!, database: db)
            let overpayment = paidAmountMinor > liabilityBalance ? paidAmountMinor - liabilityBalance : 0
            let effectiveLiabilityPayment = max(paidAmountMinor - overpayment, 0)
            let statementAmount: Int64 = cycleRow["statement_amount_minor"]
            let remaining = max(statementAmount - min(paidAmountMinor, statementAmount), 0)
            let minimum: Int64? = cycleRow["min_payment_amount_minor"]
            let cycleStatus = requestedStatus ?? (paidAmountMinor <= 0 ? "pending"
                : (remaining <= 0 ? "paid"
                    : (minimum.map { paidAmountMinor >= $0 } == true ? "minimum_paid" : "partial_paid")))
            let finalRemaining = cycleStatus == "paid" ? 0 : remaining
            if paidAmountMinor > 0 && cycleStatus != "ignored" {
                let id = UUID()
                try db.execute(sql: """
                    INSERT INTO local_liability_payments (
                        id, profile_id, account_id, statement_id, debit_account_id, amount_minor,
                        overpayment_amount_minor, paid_at, source, evidence_staging_id, status, note, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'confirmed', ?, ?, ?)
                    """, arguments: [id.uuidString, profileID.uuidString, cycleRow["account_id"] as String,
                                      cycleID.uuidString, effectiveDebitID?.uuidString, paidAmountMinor,
                                      overpayment, paidAt, screenshotStagingID == nil ? "manual" : "screenshot",
                                      screenshotStagingID, note, paidAt, paidAt])
                if effectiveLiabilityPayment > 0 {
                    try Self.insertRepaymentEntry(id: UUID(), profileID: profileID, accountID: UUID(uuidString: accountRow["id"])!,
                                                  paymentID: id, amountMinor: effectiveLiabilityPayment, occurredAt: paidAt, database: db)
                }
                if let effectiveDebitID {
                    try Self.insertRepaymentEntry(id: UUID(), profileID: profileID, accountID: effectiveDebitID,
                                                  paymentID: id, amountMinor: paidAmountMinor, occurredAt: paidAt, database: db)
                }
            }
            let currentSource: String = cycleRow["source"]
            let updatedSource = screenshotStagingID == nil
                ? (currentSource == "system" ? "manual" : currentSource)
                : "screenshot"
            try db.execute(sql: """
                UPDATE local_repayment_cycles SET paid_amount_minor = ?, remaining_amount_minor = ?,
                    carried_over_amount_minor = ?, status = ?,
                    source = ?, note = COALESCE(?, note), confirmed_at = ?,
                    local_version = local_version + 1, updated_at = ?
                WHERE id = ? AND profile_id = ?
                """, arguments: [paidAmountMinor, finalRemaining,
                                  cycleStatus == "carried_over" ? remaining : 0, cycleStatus,
                                  updatedSource,
                                  note.isEmpty ? nil : note,
                                  (paidAmountMinor > 0 || ["paid", "ignored"].contains(cycleStatus)) ? paidAt : nil,
                                  paidAt, cycleID.uuidString, profileID.uuidString])
            if let screenshotStagingID {
                try db.execute(sql: """
                    UPDATE local_staging_records
                    SET status = 'archived', target_record_id = ?,
                        resolved_action = 'liability_repayment_confirmed', resolved_at = ?, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND status = 'pending_review'
                    """, arguments: [cycleID.uuidString, paidAt, paidAt, screenshotStagingID, profileID.uuidString])
                guard db.changesCount == 1 else { throw LocalDataError.invalidRecord }
            }
        }
        guard let cycle = try database.writer.read({ db in
            try Row.fetchOne(db, sql: "SELECT * FROM local_repayment_cycles WHERE id = ? AND profile_id = ?", arguments: [cycleID.uuidString, profileID.uuidString]).map { try Self.repaymentCycle(from: $0) }
        }) else { throw LocalDataError.recordNotFound }
        return cycle
    }

    func revokeLiabilityPayment(id: UUID, profileID: UUID, reason: String, now: Date) throws -> LocalRepaymentCycle? {
        try database.writer.write { db in
            guard let payment = try Row.fetchOne(db, sql: "SELECT * FROM local_liability_payments WHERE id = ? AND profile_id = ?", arguments: [id.uuidString, profileID.uuidString]) else {
                throw LocalDataError.recordNotFound
            }
            let cycleID = (payment["statement_id"] as String?).flatMap(UUID.init(uuidString:))
            let status: String = payment["status"]
            if status != "voided" {
                try db.execute(sql: "UPDATE local_liability_payments SET status = 'voided', note = COALESCE(note, '') || CASE WHEN note IS NULL OR note = '' THEN '' ELSE '；' END || ?, updated_at = ? WHERE id = ?", arguments: [reason, now, id.uuidString])
                try db.execute(sql: "UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?) WHERE profile_id = ? AND source_kind = 'liability_payment' AND source_id = ? AND voided_at IS NULL AND is_voided = 0", arguments: [now, profileID.uuidString, id.uuidString])
            }
            guard let cycleID,
                  let cycle = try Row.fetchOne(db, sql: "SELECT * FROM local_repayment_cycles WHERE id = ? AND profile_id = ?", arguments: [cycleID.uuidString, profileID.uuidString]) else {
                return nil
            }
            if status != "voided" {
                let paid = try Int64.fetchOne(db, sql: "SELECT COALESCE(SUM(amount_minor), 0) FROM local_liability_payments WHERE statement_id = ? AND profile_id = ? AND status = 'confirmed'", arguments: [cycleID.uuidString, profileID.uuidString]) ?? 0
                let statementAmount: Int64 = cycle["statement_amount_minor"]
                let remaining = max(statementAmount - min(paid, statementAmount), 0)
                let dueDate: String? = cycle["due_date"]
                let today = Self.financeDateKey(now)
                let derivedStatus = paid <= 0
                    ? ((dueDate == nil || dueDate! > today) ? "pending" : (dueDate! == today ? "due_today" : "overdue_unconfirmed"))
                    : (remaining <= 0 ? "paid"
                        : (((cycle["min_payment_amount_minor"] as Int64?).map { paid >= $0 }) == true ? "minimum_paid" : "partial_paid"))
                try db.execute(sql: "UPDATE local_repayment_cycles SET paid_amount_minor = ?, remaining_amount_minor = ?, carried_over_amount_minor = 0, status = ?, confirmed_at = ?, local_version = local_version + 1, updated_at = ? WHERE id = ?", arguments: [paid, remaining, derivedStatus, paid > 0 ? (cycle["confirmed_at"] as Date?) : nil, now, cycleID.uuidString])
            }
            return try Row.fetchOne(db, sql: "SELECT * FROM local_repayment_cycles WHERE id = ?", arguments: [cycleID.uuidString]).map { try Self.repaymentCycle(from: $0) }
        }
    }

    func createExpense(_ draft: LocalExpenseDraft, operationID: UUID) throws -> LocalExpense {
        try database.writer.write { db in
            try Self.insertExpense(draft, operationID: operationID, database: db)
        }
    }

    static func insertExpense(_ draft: LocalExpenseDraft, operationID: UUID, database db: Database) throws -> LocalExpense {
        guard draft.amountMinor > 0 else { throw LocalDataError.invalidAmount }
        let localVersion: Int64 = 1
        let entryID = UUID()
        let expense = LocalExpense(
            id: draft.id,
            profileID: draft.profileID,
            accountID: draft.accountID,
            amountMinor: draft.amountMinor,
            currency: draft.currency,
            merchantName: draft.merchantName,
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            transactionDate: draft.transactionDate,
            transactionTime: draft.transactionTime,
            note: draft.note,
            localVersion: localVersion,
            createdAt: draft.createdAt,
            updatedAt: draft.createdAt, imagePath: draft.imagePath, imageHash: draft.imageHash
        )
        let payload = try Self.outboxPayload(expense: expense)

            if let accountID = draft.accountID {
                try Self.validateActiveAccount(id: accountID, profileID: draft.profileID, database: db)
            }
            try db.execute(
                sql: """
                    INSERT INTO local_expenses (
                        id, profile_id, account_id, amount_minor, currency, merchant_name,
                        platform, category, payment_method, transaction_date, transaction_time,
                        note, local_version, created_at, updated_at, deleted_at, image_path, image_hash
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID?.uuidString,
                    draft.amountMinor,
                    draft.currency,
                    draft.merchantName,
                    draft.platform,
                    draft.category,
                    draft.paymentMethod,
                    draft.transactionDate,
                    draft.transactionTime,
                    draft.note,
                    localVersion,
                    draft.createdAt,
                    draft.createdAt, draft.imagePath, draft.imageHash
                ]
            )

            if expense.accountID != nil {
                try Self.insertExpenseEntry(id: entryID, expense: expense, occurredAt: draft.createdAt, database: db)
            }
            if expense.accountID != nil {
            try db.execute(
                sql: """
                    INSERT INTO local_outbox_operations (
                        operation_id, profile_id, aggregate_kind, aggregate_id, operation_kind,
                        aggregate_version, idempotency_key, payload_json, status, attempt_count,
                        next_attempt_at, last_error, created_at
                    ) VALUES (?, ?, 'expense', ?, 'upsert', ?, ?, ?, 'pending', 0, NULL, NULL, ?)
                    """,
                arguments: [
                    operationID.uuidString,
                    draft.profileID.uuidString,
                    draft.id.uuidString,
                    localVersion,
                    operationID.uuidString,
                    payload,
                    draft.createdAt
                ]
            )

            }
        return expense
    }

    func createIncome(_ draft: LocalIncomeDraft) throws -> LocalIncome {
        try database.writer.write { db in try Self.insertIncome(draft, database: db) }
    }

    static func insertIncome(_ draft: LocalIncomeDraft, database db: Database) throws -> LocalIncome {
        guard draft.amountMinor > 0 else { throw LocalDataError.invalidAmount }
        let income = LocalIncome(
            id: draft.id, profileID: draft.profileID, accountID: draft.accountID,
            amountMinor: draft.amountMinor, currency: draft.currency,
            sourceName: draft.sourceName, category: draft.category,
            incomeDate: draft.incomeDate, occurredAt: draft.occurredAt,
            note: draft.note, localVersion: 1, createdAt: draft.createdAt,
            updatedAt: draft.createdAt, imagePath: draft.imagePath, imageHash: draft.imageHash
        )
            if let accountID = draft.accountID {
                try Self.validateActiveIncomeAccount(id: accountID, profileID: draft.profileID, database: db)
            }
            try db.execute(sql: """
                INSERT INTO local_income_records (
                    id, profile_id, account_id, amount_minor, currency, source_name,
                    category, income_date, occurred_at, note, local_version,
                    created_at, updated_at, deleted_at, image_path, image_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL, ?, ?)
                """, arguments: [
                    income.id.uuidString, income.profileID.uuidString,
                    income.accountID?.uuidString, income.amountMinor, income.currency,
                    income.sourceName, income.category, income.incomeDate,
                    income.occurredAt, income.note, income.createdAt, income.updatedAt, income.imagePath, income.imageHash
                ])
            if let accountID = income.accountID {
                try Self.insertIncomeEntry(
                    id: UUID(), income: income, accountID: accountID, database: db
                )
            }
        return income
    }

    func updateIncome(_ update: LocalIncomeUpdate) throws -> LocalIncome {
        guard update.amountMinor > 0 else { throw LocalDataError.invalidAmount }
        return try database.writer.write { db in
            let existing = try Self.activeIncome(id: update.id, profileID: update.profileID, database: db)
            guard existing.localVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(expected: update.expectedVersion, actual: existing.localVersion)
            }
            if let accountID = update.accountID {
                if update.accountID != existing.accountID {
                    try Self.validateActiveIncomeAccount(id: accountID, profileID: existing.profileID, database: db)
                } else {
                    try Self.validateIncomeAccount(id: accountID, profileID: existing.profileID, database: db)
                }
            }
            let next = LocalIncome(
                id: existing.id, profileID: existing.profileID, accountID: update.accountID,
                amountMinor: update.amountMinor, currency: update.currency,
                sourceName: update.sourceName, category: update.category,
                incomeDate: update.incomeDate, occurredAt: update.occurredAt,
                note: update.note, localVersion: existing.localVersion + 1,
                createdAt: existing.createdAt, updatedAt: update.updatedAt, imagePath: update.removeImage ? nil : (update.imagePath ?? existing.imagePath), imageHash: update.removeImage ? nil : (update.imageHash ?? existing.imageHash)
            )
            if next.imagePath != existing.imagePath {
                try Self.enqueueFinancialImageCleanup(existing.imagePath, profileID: existing.profileID, at: update.updatedAt, database: db)
            }
            try db.execute(sql: "UPDATE local_income_records SET image_path = ?, image_hash = ? WHERE id = ?",
                           arguments: [next.imagePath, next.imageHash, update.id.uuidString])
            if existing.accountID != nil {
                try Self.voidActiveEntry(sourceID: update.id, sourceKind: "income", voidedAt: update.updatedAt, database: db)
            }
            try db.execute(sql: """
                UPDATE local_income_records SET account_id = ?, amount_minor = ?, currency = ?,
                    source_name = ?, category = ?, income_date = ?, occurred_at = ?, note = ?,
                    local_version = ?, updated_at = ?
                WHERE id = ? AND deleted_at IS NULL
                """, arguments: [
                    next.accountID?.uuidString, next.amountMinor, next.currency,
                    next.sourceName, next.category, next.incomeDate, next.occurredAt,
                    next.note, next.localVersion, next.updatedAt, next.id.uuidString
                ])
            if let accountID = next.accountID {
                try Self.insertIncomeEntry(id: UUID(), income: next, accountID: accountID, database: db)
            }
            return next
        }
    }

    func deleteIncome(id: UUID, profileID: UUID, expectedVersion: Int64, deletedAt: Date) throws -> LocalIncomeTombstone {
        try database.writer.write { db in
            let existing = try Self.activeIncome(id: id, profileID: profileID, database: db)
            guard existing.localVersion == expectedVersion else {
                throw LocalDataError.versionConflict(expected: expectedVersion, actual: existing.localVersion)
            }
            if existing.accountID != nil {
                try Self.voidActiveEntry(sourceID: id, sourceKind: "income", voidedAt: deletedAt, database: db)
            }
            try Self.enqueueFinancialImageCleanup(existing.imagePath, profileID: existing.profileID, at: deletedAt, database: db)
            let nextVersion = existing.localVersion + 1
            try db.execute(sql: "UPDATE local_income_records SET deleted_at = ?, local_version = ?, updated_at = ? WHERE id = ? AND deleted_at IS NULL",
                           arguments: [deletedAt, nextVersion, deletedAt, id.uuidString])
            return LocalIncomeTombstone(id: id, profileID: existing.profileID, localVersion: nextVersion, deletedAt: deletedAt)
        }
    }

    func income(id: UUID) throws -> LocalIncome? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM local_income_records WHERE id = ? AND deleted_at IS NULL", arguments: [id.uuidString]) else { return nil }
            return try Self.income(from: row)
        }
    }

    func incomes(profileID: UUID, monthKey: String) throws -> [LocalIncome] {
        try database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT * FROM local_income_records WHERE profile_id = ? AND income_date LIKE ? AND deleted_at IS NULL ORDER BY income_date DESC, occurred_at DESC, created_at DESC",
                             arguments: [profileID.uuidString, "\(monthKey)%"]).map(Self.income(from:))
        }
    }

    /// Imports cloud facts into the local projection. No outbox operation is
    /// created because these rows are already authoritative remotely.
    func importRemoteExpenses(_ drafts: [LocalExpenseDraft]) throws {
        guard !drafts.isEmpty else { return }
        try database.writer.write { db in
            for draft in drafts where draft.amountMinor > 0 {
                guard let accountID = draft.accountID else { throw LocalDataError.accountRequired }
                let exists = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM local_expenses WHERE id = ? AND profile_id = ?",
                    arguments: [draft.id.uuidString, draft.profileID.uuidString]
                ) != nil
                if exists { continue }
                let direction = try Self.expenseEntryDirection(
                    accountID: accountID, profileID: draft.profileID, database: db
                )
                try db.execute(sql: """
                    INSERT INTO local_expenses (
                        id, profile_id, account_id, amount_minor, currency, merchant_name,
                        platform, category, payment_method, transaction_date, transaction_time,
                        note, local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                    """, arguments: [
                        draft.id.uuidString, draft.profileID.uuidString, draft.accountID?.uuidString,
                        draft.amountMinor, draft.currency, draft.merchantName, draft.platform,
                        draft.category, draft.paymentMethod, draft.transactionDate,
                        draft.transactionTime, draft.note, draft.createdAt, draft.createdAt
                    ])
                try db.execute(sql: """
                    INSERT OR IGNORE INTO local_account_entries (
                        id, profile_id, account_id, direction, amount_minor, entry_kind,
                        source_kind, source_id, occurred_at, voided_at
                    ) VALUES (?, ?, ?, ?, ?, 'expense', 'expense', ?, ?, NULL)
                    """, arguments: [
                        UUID().uuidString, draft.profileID.uuidString, draft.accountID?.uuidString,
                        direction, draft.amountMinor, draft.id.uuidString, draft.createdAt
                    ])
            }
        }
    }

    func updateExpense(_ update: LocalExpenseUpdate, operationID: UUID) throws -> LocalExpense {
        guard update.amountMinor > 0 else { throw LocalDataError.invalidAmount }

        return try database.writer.write { db in
            let existing = try Self.activeExpense(id: update.id, database: db)
            guard existing.localVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: update.expectedVersion,
                    actual: existing.localVersion
                )
            }
            if existing.accountID != nil && update.accountID == nil {
                let authorized = try Int.fetchOne(db, sql: """
                    SELECT EXISTS(SELECT 1 FROM local_profiles p JOIN local_sync_state s ON s.profile_id=p.id
                    WHERE p.id=? AND p.cloud_user_id IS NOT NULL AND p.sync_enabled=1 AND s.sync_status!='disabled')
                    """, arguments: [existing.profileID.uuidString]) == 1
                guard !authorized else { throw LocalFinancialMutationError.synchronizedExpenseCannotUnbind }
            }
            if let accountID = update.accountID {
                try Self.validateAccount(id: accountID, profileID: existing.profileID, database: db)
                if accountID != existing.accountID {
                    try Self.validateActiveAccount(id: accountID, profileID: existing.profileID, database: db)
                }
            }

            let nextVersion = existing.localVersion + 1
            let updated = LocalExpense(
                id: existing.id,
                profileID: existing.profileID,
                accountID: update.accountID,
                amountMinor: update.amountMinor,
                currency: update.currency,
                merchantName: update.merchantName,
                platform: update.platform,
                category: update.category,
                paymentMethod: update.paymentMethod,
                transactionDate: update.transactionDate,
                transactionTime: update.transactionTime,
                note: update.note,
                localVersion: nextVersion,
                createdAt: existing.createdAt,
                updatedAt: update.updatedAt, imagePath: update.removeImage ? nil : (update.imagePath ?? existing.imagePath), imageHash: update.removeImage ? nil : (update.imageHash ?? existing.imageHash)
            )
            if updated.imagePath != existing.imagePath {
                try Self.enqueueFinancialImageCleanup(existing.imagePath, profileID: existing.profileID, at: update.updatedAt, database: db)
            }
            try db.execute(sql: "UPDATE local_expenses SET image_path = ?, image_hash = ? WHERE id = ?",
                           arguments: [updated.imagePath, updated.imageHash, update.id.uuidString])
            let replacesLedger = existing.accountID != update.accountID
                || existing.amountMinor != update.amountMinor

            if replacesLedger {
                if existing.accountID != nil {
                try Self.voidActiveEntry(
                    sourceID: update.id,
                    voidedAt: update.updatedAt,
                    database: db
                )
                }
                try Self.insertExpenseEntry(
                    id: UUID(),
                    expense: updated,
                    occurredAt: update.updatedAt,
                    database: db
                )
            }

            try db.execute(
                sql: """
                    UPDATE local_expenses
                    SET account_id = ?, amount_minor = ?, currency = ?, merchant_name = ?,
                        platform = ?, category = ?, payment_method = ?, transaction_date = ?,
                        transaction_time = ?, note = ?, local_version = ?, updated_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    updated.accountID?.uuidString,
                    updated.amountMinor,
                    updated.currency,
                    updated.merchantName,
                    updated.platform,
                    updated.category,
                    updated.paymentMethod,
                    updated.transactionDate,
                    updated.transactionTime,
                    updated.note,
                    updated.localVersion,
                    updated.updatedAt,
                    updated.id.uuidString
                ]
            )

            if updated.accountID != nil {
            try Self.insertOutbox(
                operationID: operationID,
                profileID: updated.profileID,
                aggregateKind: "expense",
                aggregateID: updated.id,
                operationKind: "upsert",
                aggregateVersion: updated.localVersion,
                payload: Self.outboxPayload(expense: updated),
                createdAt: update.updatedAt,
                database: db
            )
            } else {
                try db.execute(sql: "DELETE FROM local_outbox_operations WHERE aggregate_kind = 'expense' AND aggregate_id = ? AND status IN ('pending','failed')", arguments: [updated.id.uuidString])
            }
            return updated
        }
    }

    func deleteExpense(
        id: UUID,
        expectedVersion: Int64,
        deletedAt: Date,
        operationID: UUID
    ) throws -> LocalExpenseTombstone {
        try database.writer.write { db in
            let existing = try Self.activeExpense(id: id, database: db)
            guard existing.localVersion == expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: expectedVersion,
                    actual: existing.localVersion
                )
            }
            let tombstone = LocalExpenseTombstone(
                id: existing.id,
                profileID: existing.profileID,
                localVersion: existing.localVersion + 1,
                deletedAt: deletedAt
            )

            try Self.enqueueFinancialImageCleanup(existing.imagePath, profileID: existing.profileID, at: deletedAt, database: db)
            if existing.accountID != nil {
                try Self.voidActiveEntry(sourceID: id, voidedAt: deletedAt, database: db)
            }
            try db.execute(
                sql: """
                    UPDATE local_expenses
                    SET local_version = ?, updated_at = ?, deleted_at = ?
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    tombstone.localVersion,
                    deletedAt,
                    deletedAt,
                    id.uuidString
                ]
            )
            try Self.insertOutbox(
                operationID: operationID,
                profileID: tombstone.profileID,
                aggregateKind: "expense",
                aggregateID: tombstone.id,
                operationKind: "delete",
                aggregateVersion: tombstone.localVersion,
                payload: Self.outboxPayload(tombstone: tombstone),
                createdAt: deletedAt,
                database: db
            )
            return tombstone
        }
    }

    func expense(id: UUID) throws -> LocalExpense? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT * FROM local_expenses
                    WHERE id = ? AND deleted_at IS NULL
                    """,
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try Self.expense(from: row)
        }
    }

    func expenses(profileID: UUID, monthKey: String) throws -> [LocalExpense] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_expenses
                    WHERE profile_id = ?
                      AND transaction_date LIKE ?
                      AND deleted_at IS NULL
                    ORDER BY transaction_date DESC, transaction_time DESC, created_at DESC, id DESC
                    """,
                arguments: [profileID.uuidString, monthKey.isEmpty ? "%" : "\(monthKey)-%"]
            ).map { try Self.expense(from: $0) }
        }
    }

    func expenseCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_expenses WHERE deleted_at IS NULL"
            ) ?? 0
        }
    }

    func expenseTombstone(id: UUID) throws -> LocalExpenseTombstone? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT id, profile_id, local_version, deleted_at
                    FROM local_expenses
                    WHERE id = ? AND deleted_at IS NOT NULL
                    """,
                arguments: [id.uuidString]
            ) else {
                return nil
            }
            return try Self.tombstone(from: row)
        }
    }

    func accountEntryCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM local_account_entries WHERE voided_at IS NULL AND is_voided = 0"
            ) ?? 0
        }
    }

    func accountEntries(sourceID: UUID) throws -> [LocalAccountEntry] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, account_id, direction, amount_minor, entry_kind,
                           source_kind, source_id, occurred_at, voided_at, is_voided
                    FROM local_account_entries
                    WHERE source_id = ?
                    ORDER BY occurred_at ASC, id ASC
                    """,
                arguments: [sourceID.uuidString]
            ).map { try Self.accountEntry(from: $0) }
        }
    }

    func accountEntries(accountID: UUID) throws -> [LocalAccountEntry] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, account_id, direction, amount_minor, entry_kind,
                           source_kind, source_id, occurred_at, voided_at, is_voided
                    FROM local_account_entries
                    WHERE account_id = ?
                    ORDER BY occurred_at DESC, id DESC
                    """,
                arguments: [accountID.uuidString]
            ).map { try Self.accountEntry(from: $0) }
        }
    }

    func pendingOutboxOperations() throws -> [LocalOutboxOperation] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT sequence, operation_id, profile_id, aggregate_kind, aggregate_id,
                           operation_kind, aggregate_version, idempotency_key, status,
                           attempt_count, created_at
                    FROM local_outbox_operations
                    WHERE status = 'pending'
                    ORDER BY CASE aggregate_kind WHEN 'account' THEN 0 ELSE 1 END,
                             sequence ASC
                    """
            ).map { try Self.outboxOperation(from: $0) }
        }
    }

    @discardableResult
    func ensureAccountOutboxForPendingExpenses(profileID: UUID) throws -> Int {
        try database.writer.write { db in
            let accounts = try Row.fetchAll(
                db,
                sql: """
                    SELECT DISTINCT a.id, a.profile_id, a.name, a.kind, a.currency,
                           a.opening_balance_minor, a.created_at
                    FROM local_accounts AS a
                    JOIN local_expenses AS e ON e.account_id = a.id AND e.profile_id = a.profile_id
                    JOIN local_outbox_operations AS expense_outbox
                      ON expense_outbox.aggregate_kind = 'expense'
                     AND expense_outbox.aggregate_id = e.id
                     AND expense_outbox.profile_id = e.profile_id
                     AND expense_outbox.status IN ('pending', 'failed')
                    WHERE a.profile_id = ?
                      AND a.origin = 'local'
                      AND e.deleted_at IS NULL
                    ORDER BY a.created_at ASC, a.id ASC
                    """,
                arguments: [profileID.uuidString]
            )
            var inserted = 0
            for row in accounts {
                let accountID: String = row["id"]
                let existing = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT 1 FROM local_outbox_operations
                        WHERE profile_id = ? AND aggregate_kind = 'account' AND aggregate_id = ?
                        LIMIT 1
                        """,
                    arguments: [profileID.uuidString, accountID]
                )
                guard existing == nil,
                      let id = UUID(uuidString: accountID),
                      let storedProfileID = UUID(uuidString: row["profile_id"]) else { continue }
                let draft = LocalAccountDraft(
                    id: id,
                    profileID: storedProfileID,
                    name: row["name"],
                    kind: row["kind"],
                    currency: row["currency"],
                    openingBalanceMinor: row["opening_balance_minor"],
                    createdAt: row["created_at"]
                )
                try Self.insertOutbox(
                    operationID: UUID(),
                    profileID: draft.profileID,
                    aggregateKind: "account",
                    aggregateID: draft.id,
                    operationKind: "upsert",
                    aggregateVersion: 1,
                    payload: try Self.outboxPayload(account: draft),
                    createdAt: draft.createdAt,
                    database: db
                )
                inserted += 1
            }
            return inserted
        }
    }

    func pendingOutboxUploads(profileID: UUID) throws -> [LocalOutboxUpload] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT sequence, operation_id, profile_id, aggregate_kind, aggregate_id,
                           operation_kind, aggregate_version, idempotency_key, payload_json,
                           attempt_count, created_at
                    FROM local_outbox_operations
                    WHERE profile_id = ? AND status IN ('pending', 'failed')
                    ORDER BY CASE aggregate_kind WHEN 'account' THEN 0 ELSE 1 END,
                             sequence ASC
                    """,
                arguments: [profileID.uuidString]
            ).map { row in
                guard let operationID = UUID(uuidString: row["operation_id"]),
                      let profileID = UUID(uuidString: row["profile_id"]),
                      let aggregateID = UUID(uuidString: row["aggregate_id"]) else {
                    throw LocalDataError.invalidRecord
                }
                return LocalOutboxUpload(
                    sequence: row["sequence"],
                    operationID: operationID,
                    profileID: profileID,
                    aggregateKind: row["aggregate_kind"],
                    aggregateID: aggregateID,
                    operationKind: row["operation_kind"],
                    aggregateVersion: row["aggregate_version"],
                    idempotencyKey: row["idempotency_key"],
                    payloadJSON: row["payload_json"],
                    attemptCount: row["attempt_count"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    func markOutboxSent(operationIDs: [UUID]) throws {
        guard !operationIDs.isEmpty else { return }
        try database.writer.write { db in
            for operationID in operationIDs {
                try db.execute(
                    sql: """
                        UPDATE local_outbox_operations
                        SET status = 'sent', last_error = NULL, next_attempt_at = NULL
                        WHERE operation_id = ? AND status IN ('pending', 'failed', 'processing')
                        """,
                    arguments: [operationID.uuidString]
                )
            }
        }
    }

    /// Conflict operations are terminal in Phase A. Keep the row for
    /// diagnostics while removing it from the retry queue.
    func discardOutboxOperations(operationIDs: [UUID], reason: String) throws {
        guard !operationIDs.isEmpty else { return }
        try database.writer.write { db in
            for operationID in operationIDs {
                try db.execute(
                    sql: """
                        UPDATE local_outbox_operations
                        SET status = 'sent', last_error = ?, next_attempt_at = NULL
                        WHERE operation_id = ? AND status IN ('pending', 'failed', 'processing')
                        """,
                    arguments: [reason, operationID.uuidString]
                )
            }
        }
    }

    func markOutboxFailed(operationIDs: [UUID], error: String) throws {
        guard !operationIDs.isEmpty else { return }
        try database.writer.write { db in
            for operationID in operationIDs {
                try db.execute(
                    sql: """
                        UPDATE local_outbox_operations
                        SET status = 'failed', attempt_count = attempt_count + 1, last_error = ?
                        WHERE operation_id = ? AND status IN ('pending', 'failed', 'processing')
                        """,
                    arguments: [error, operationID.uuidString]
                )
            }
        }
    }

    func accountBalanceMinor(accountID: UUID) throws -> Int64 {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT accounts.opening_balance_minor AS opening_balance_minor,
                           COALESCE(SUM(
                               CASE entries.direction
                                   WHEN 'in' THEN entries.amount_minor
                                   WHEN 'out' THEN -entries.amount_minor
                               END
                           ), 0) AS ledger_delta_minor
                    FROM local_accounts AS accounts
                    LEFT JOIN local_account_entries AS entries
                      ON entries.account_id = accounts.id
                     AND entries.voided_at IS NULL AND entries.is_voided = 0
                     AND entries.entry_kind != 'snapshot_initialization'
                    WHERE accounts.id = ?
                    GROUP BY accounts.id
                    """,
                arguments: [accountID.uuidString]
            ) else {
                throw LocalDataError.invalidIdentifier
            }
            let openingBalance: Int64 = row["opening_balance_minor"]
            let ledgerDelta: Int64 = row["ledger_delta_minor"]
            return openingBalance + ledgerDelta
        }
    }

    func applyRemoteSnapshot(
        _ snapshot: LocalRemoteSnapshot,
        profileID: UUID,
        excludingExpenseIDs: Set<UUID> = [],
        excludingAccountIDs: Set<UUID> = []
    ) throws -> Int {
        try database.writer.write { db in
            var imported = 0
            for account in snapshot.accounts {
                if excludingAccountIDs.contains(account.id) { continue }
                if account.deletedAt != nil {
                    continue
                }
                let existing = try Row.fetchOne(db, sql: "SELECT id FROM local_accounts WHERE id = ? AND profile_id = ?", arguments: [account.id.uuidString, profileID.uuidString])
                if existing == nil {
                    try db.execute(sql: """
                        INSERT INTO local_accounts (id, profile_id, name, kind, currency, opening_balance_minor, created_at, origin)
                        VALUES (?, ?, ?, ?, ?, ?, ?, 'remote')
                        """, arguments: [account.id.uuidString, profileID.uuidString, account.name, account.kind, account.currency, account.openingBalanceMinor, Date()])
                    imported += 1
                } else {
                    try db.execute(sql: """
                        UPDATE local_accounts
                        SET name = ?, kind = ?, currency = ?,
                            origin = CASE WHEN EXISTS (
                                SELECT 1 FROM local_outbox_operations
                                WHERE aggregate_kind = 'account' AND aggregate_id = local_accounts.id
                                  AND profile_id = local_accounts.profile_id AND status IN ('pending', 'failed')
                            ) THEN origin ELSE 'remote' END
                        WHERE id = ? AND profile_id = ?
                        """, arguments: [account.name, account.kind, account.currency, account.id.uuidString, profileID.uuidString])
                }
            }
            for expense in snapshot.expenses {
                if excludingExpenseIDs.contains(expense.id) { continue }
                let row = try Row.fetchOne(db, sql: "SELECT local_version, deleted_at FROM local_expenses WHERE id = ? AND profile_id = ?", arguments: [expense.id.uuidString, profileID.uuidString])
                let localVersion: Int64 = row?["local_version"] ?? 0
                guard expense.version >= localVersion else { continue }
                let localDeletedAt: Date? = row?["deleted_at"]
                if localDeletedAt != nil, expense.deletedAt == nil, expense.version <= localVersion {
                    continue
                }
                if expense.deletedAt != nil {
                    try db.execute(sql: "UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?) WHERE source_kind = 'expense' AND source_id = ? AND voided_at IS NULL AND is_voided = 0", arguments: [expense.deletedAt, expense.id.uuidString])
                    try db.execute(sql: "UPDATE local_expenses SET local_version = ?, deleted_at = ?, updated_at = ? WHERE id = ? AND profile_id = ?", arguments: [expense.version, expense.deletedAt, Date(), expense.id.uuidString, profileID.uuidString])
                } else if row == nil {
                    try db.execute(sql: """
                        INSERT INTO local_expenses (id, profile_id, account_id, amount_minor, currency, merchant_name, platform, category, payment_method, transaction_date, transaction_time, note, local_version, created_at, updated_at, deleted_at)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                        """, arguments: [expense.id.uuidString, profileID.uuidString, expense.accountID.uuidString, expense.amountMinor, expense.currency, expense.merchantName, expense.platform, expense.category, expense.paymentMethod, expense.transactionDate, expense.transactionTime, expense.note, expense.version, Date(), Date()])
                    try db.execute(sql: """
                        INSERT INTO local_account_entries (id, profile_id, account_id, direction, amount_minor, entry_kind, source_kind, source_id, occurred_at, voided_at)
                        VALUES (?, ?, ?, 'out', ?, 'expense', 'expense', ?, ?, NULL)
                        """, arguments: [UUID().uuidString, profileID.uuidString, expense.accountID.uuidString, expense.amountMinor, expense.id.uuidString, Date()])
                    imported += 1
                } else {
                    try db.execute(sql: "UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?) WHERE source_kind = 'expense' AND source_id = ? AND voided_at IS NULL AND is_voided = 0", arguments: [Date(), expense.id.uuidString])
                    try db.execute(sql: """
                        UPDATE local_expenses SET account_id = ?, amount_minor = ?, currency = ?, merchant_name = ?, platform = ?, category = ?, payment_method = ?, transaction_date = ?, transaction_time = ?, note = ?, local_version = ?, updated_at = ?
                        WHERE id = ? AND profile_id = ?
                        """, arguments: [expense.accountID.uuidString, expense.amountMinor, expense.currency, expense.merchantName, expense.platform, expense.category, expense.paymentMethod, expense.transactionDate, expense.transactionTime, expense.note, expense.version, Date(), expense.id.uuidString, profileID.uuidString])
                    try db.execute(sql: """
                        INSERT INTO local_account_entries (id, profile_id, account_id, direction, amount_minor, entry_kind, source_kind, source_id, occurred_at, voided_at)
                        VALUES (?, ?, ?, 'out', ?, 'expense', 'expense', ?, ?, NULL)
                        """, arguments: [UUID().uuidString, profileID.uuidString, expense.accountID.uuidString, expense.amountMinor, expense.id.uuidString, Date()])
                }
            }
            return imported
        }
    }

    private static func enqueueFinancialImageCleanup(_ path: String?, profileID: UUID, at date: Date, database: Database) throws {
        guard let path else { return }
        try database.execute(sql: """
            INSERT OR IGNORE INTO local_image_cleanups
            (id, profile_id, image_path, attempt_count, last_error, created_at, updated_at)
            VALUES (?, ?, ?, 0, NULL, ?, ?)
            """, arguments: [UUID().uuidString, profileID.uuidString, path, date, date])
    }

    private static func expense(from row: Row) throws -> LocalExpense {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalExpense(
            id: id,
            profileID: profileID,
            accountID: (row["account_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"],
            currency: row["currency"],
            merchantName: row["merchant_name"],
            platform: row["platform"],
            category: row["category"],
            paymentMethod: row["payment_method"],
            transactionDate: row["transaction_date"],
            transactionTime: row["transaction_time"],
            note: row["note"],
            localVersion: row["local_version"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"], imagePath: row["image_path"], imageHash: row["image_hash"]
        )
    }

    private static func tombstone(from row: Row) throws -> LocalExpenseTombstone {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let deletedAt: Date = row["deleted_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalExpenseTombstone(
            id: id,
            profileID: profileID,
            localVersion: row["local_version"],
            deletedAt: deletedAt
        )
    }

    private static func accountEntry(from row: Row) throws -> LocalAccountEntry {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]),
              let sourceID = UUID(uuidString: row["source_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalAccountEntry(
            id: id,
            profileID: profileID,
            accountID: accountID,
            direction: row["direction"],
            amountMinor: row["amount_minor"],
            entryKind: row["entry_kind"],
            sourceKind: row["source_kind"],
            sourceID: sourceID,
            occurredAt: row["occurred_at"],
            voidedAt: row["voided_at"],
            isVoided: row.hasColumn("is_voided") ? row["is_voided"] : false
        )
    }

    private static func income(from row: Row) throws -> LocalIncome {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let accountText: String? = row["account_id"]
        return LocalIncome(
            id: id, profileID: profileID,
            accountID: accountText.flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"], currency: row["currency"],
            sourceName: row["source_name"], category: row["category"],
            incomeDate: row["income_date"], occurredAt: row["occurred_at"],
            note: row["note"], localVersion: row["local_version"],
            createdAt: createdAt, updatedAt: updatedAt, imagePath: row["image_path"], imageHash: row["image_hash"]
        )
    }

    private static func outboxOperation(from row: Row) throws -> LocalOutboxOperation {
        guard let operationID = UUID(uuidString: row["operation_id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let aggregateID = UUID(uuidString: row["aggregate_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalOutboxOperation(
            sequence: row["sequence"],
            operationID: operationID,
            profileID: profileID,
            aggregateKind: row["aggregate_kind"],
            aggregateID: aggregateID,
            operationKind: row["operation_kind"],
            aggregateVersion: row["aggregate_version"],
            idempotencyKey: row["idempotency_key"],
            status: row["status"],
            attemptCount: row["attempt_count"],
            createdAt: row["created_at"]
        )
    }

    private static func activeExpense(id: UUID, database: Database) throws -> LocalExpense {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM local_expenses WHERE id = ? AND deleted_at IS NULL",
            arguments: [id.uuidString]
        ) else {
            throw LocalDataError.recordNotFound
        }
        return try expense(from: row)
    }

    private static func activeIncome(id: UUID, profileID: UUID, database: Database) throws -> LocalIncome {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM local_income_records WHERE id = ? AND profile_id = ? AND deleted_at IS NULL",
            arguments: [id.uuidString, profileID.uuidString]
        ) else { throw LocalDataError.recordNotFound }
        return try income(from: row)
    }

    private static func validateAccount(
        id: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        guard let storedProfileID = try String.fetchOne(
            database,
            sql: "SELECT profile_id FROM local_accounts WHERE id = ?",
            arguments: [id.uuidString]
        ), storedProfileID == profileID.uuidString else {
            throw LocalDataError.invalidIdentifier
        }
    }

    private static func repaymentCycle(from row: Row) throws -> LocalRepaymentCycle {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]),
              let createdAt: Date = row["created_at"], let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalRepaymentCycle(
            id: id, profileID: profileID, accountID: accountID, cycleMonth: row["cycle_month"],
            statementStartDate: row["statement_start_date"], statementEndDate: row["statement_end_date"],
            dueDate: row["due_date"], statementAmountMinor: row["statement_amount_minor"],
            paidAmountMinor: row["paid_amount_minor"], remainingAmountMinor: row["remaining_amount_minor"],
            carriedOverAmountMinor: row["carried_over_amount_minor"],
            originalStatementAmountMinor: row["original_statement_amount_minor"],
            minPaymentAmountMinor: row["min_payment_amount_minor"],
            refundAppliedAmountMinor: row["refund_applied_amount_minor"], status: row["status"],
            autoDebitAccountID: (row["auto_debit_account_id"] as String?).flatMap(UUID.init(uuidString:)),
            autoConfirmRepayment: row["auto_confirm_repayment"], source: row["source"],
            evidenceRecordID: (row["evidence_record_id"] as String?).flatMap(UUID.init(uuidString:)),
            evidenceWalletSnapshotID: (row["evidence_wallet_snapshot_id"] as String?).flatMap(UUID.init(uuidString:)),
            confidence: row["confidence"], note: row["note"], confirmedAt: row["confirmed_at"],
            localVersion: row["local_version"], createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private static func liabilityPayment(from row: Row) throws -> LocalLiabilityPayment {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]),
              let paidAt: Date = row["paid_at"], let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else { throw LocalDataError.invalidRecord }
        return LocalLiabilityPayment(
            id: id, profileID: profileID, accountID: accountID,
            statementID: (row["statement_id"] as String?).flatMap(UUID.init(uuidString:)),
            debitAccountID: (row["debit_account_id"] as String?).flatMap(UUID.init(uuidString:)),
            amountMinor: row["amount_minor"], overpaymentAmountMinor: row["overpayment_amount_minor"],
            paidAt: paidAt, source: row["source"],
            evidenceRecordID: (row["evidence_record_id"] as String?).flatMap(UUID.init(uuidString:)),
            status: row["status"], note: row["note"], createdAt: createdAt, updatedAt: updatedAt
        )
    }

    private static func validateActiveDebitAccount(id: UUID, profileID: UUID, database: Database) throws {
        guard let row = try Row.fetchOne(database, sql: "SELECT kind, is_archived FROM local_accounts WHERE id = ? AND profile_id = ?", arguments: [id.uuidString, profileID.uuidString]) else {
            throw LocalDataError.invalidIdentifier
        }
        let kind: String = row["kind"]
        let archived: Bool = row["is_archived"]
        guard !archived, !["credit_card", "credit_line"].contains(kind) else { throw LocalDataError.invalidAccountKind }
    }

    private static func accountBalanceMinor(accountID: UUID, database: Database) throws -> Int64 {
        guard let row = try Row.fetchOne(database, sql: """
            SELECT account.opening_balance_minor AS opening_balance_minor,
                   COALESCE(SUM(CASE entry.direction WHEN 'in' THEN entry.amount_minor WHEN 'out' THEN -entry.amount_minor END), 0) AS delta
            FROM local_accounts account LEFT JOIN local_account_entries entry
              ON entry.account_id = account.id AND entry.voided_at IS NULL AND entry.is_voided = 0
             AND entry.entry_kind != 'snapshot_initialization'
            WHERE account.id = ? GROUP BY account.id
            """, arguments: [accountID.uuidString]) else { throw LocalDataError.invalidIdentifier }
        let opening: Int64 = row["opening_balance_minor"]
        let delta: Int64 = row["delta"]
        return opening + delta
    }

    private static func insertRepaymentEntry(
        id: UUID, profileID: UUID, accountID: UUID, paymentID: UUID,
        amountMinor: Int64, occurredAt: Date, database: Database
    ) throws {
        try database.execute(sql: """
            INSERT INTO local_account_entries (
                id, profile_id, account_id, direction, amount_minor, entry_kind,
                source_kind, source_id, occurred_at, voided_at
            ) VALUES (?, ?, ?, 'out', ?, 'transfer', 'liability_payment', ?, ?, NULL)
            """, arguments: [id.uuidString, profileID.uuidString, accountID.uuidString,
                              amountMinor, paymentID.uuidString, occurredAt])
    }

    private static func isMonthKey(_ value: String) -> Bool {
        value.range(of: #"^\d{4}-(0[1-9]|1[0-2])$"#, options: .regularExpression) != nil
    }

    private static func financeDate(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: value)
    }

    private static func financeDateKey(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }

    private static func shiftedFinanceDate(_ date: Date, component: Calendar.Component, value: Int) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        return calendar.date(byAdding: component, value: value, to: date)
    }

    private static func billDate(day: Int, monthStart: Date, offsetMonths: Int) -> Date? {
        guard let shifted = shiftedFinanceDate(monthStart, component: .month, value: offsetMonths) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let components = calendar.dateComponents([.year, .month], from: shifted)
        guard let year = components.year, let month = components.month,
              let lastDay = calendar.range(of: .day, in: .month, for: shifted)?.count else { return nil }
        var date = DateComponents()
        date.year = year
        date.month = month
        date.day = min(day, lastDay)
        return calendar.date(from: date)
    }

    private static func validateAccountConfiguration(
        kind: String,
        last4: String,
        billDay: Int?,
        paymentDueDay: Int?,
        autoDebitAccountID: UUID?,
        autoConfirmRepayment: Bool,
        gracePeriodDays: Int,
        isDefaultExpense: Bool,
        isDefaultIncome: Bool,
        isArchived: Bool,
        profileID: UUID,
        accountID: UUID,
        database: Database
    ) throws {
        let liabilityKinds: Set<String> = ["credit_card", "credit_line"]
        guard ["cash", "wallet_balance", "debit_card", "credit_card", "credit_line", "other"].contains(kind),
              last4.isEmpty || last4.range(of: #"^\d{4}$"#, options: .regularExpression) != nil,
              billDay.map({ (1...31).contains($0) }) ?? true,
              paymentDueDay.map({ (1...31).contains($0) }) ?? true,
              (0...60).contains(gracePeriodDays),
              !(isArchived && (isDefaultExpense || isDefaultIncome)),
              !autoConfirmRepayment || liabilityKinds.contains(kind) else {
            throw LocalDataError.invalidRecord
        }
        if let autoDebitAccountID {
            guard autoDebitAccountID != accountID,
                  let row = try Row.fetchOne(
                    database,
                    sql: "SELECT kind, is_archived FROM local_accounts WHERE id = ? AND profile_id = ?",
                    arguments: [autoDebitAccountID.uuidString, profileID.uuidString]
                  ) else { throw LocalDataError.invalidIdentifier }
            let debitKind: String = row["kind"]
            let archived: Bool = row["is_archived"]
            guard !archived, !liabilityKinds.contains(debitKind) else { throw LocalDataError.invalidAccountKind }
        }
    }

    private static func validateIncomeAccount(
        id: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        try validateAccount(id: id, profileID: profileID, database: database)
    }

    private static func validateActiveIncomeAccount(
        id: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        try validateActiveAccount(id: id, profileID: profileID, database: database)
        try validateIncomeAccount(id: id, profileID: profileID, database: database)
    }

    private static func validateActiveAccount(
        id: UUID,
        profileID: UUID,
        database: Database
    ) throws {
        try validateAccount(id: id, profileID: profileID, database: database)
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT is_archived FROM local_accounts WHERE id = ? AND profile_id = ?",
            arguments: [id.uuidString, profileID.uuidString]
        ) else { throw LocalDataError.invalidIdentifier }
        let isArchived: Bool = row["is_archived"]
        guard !isArchived else { throw LocalDataError.invalidAccountKind }
    }

    private static func expenseEntryDirection(
        accountID: UUID,
        profileID: UUID,
        database: Database
    ) throws -> String {
        try validateAccount(id: accountID, profileID: profileID, database: database)
        guard let kind = try String.fetchOne(
            database,
            sql: "SELECT kind FROM local_accounts WHERE id = ? AND profile_id = ?",
            arguments: [accountID.uuidString, profileID.uuidString]
        ) else { throw LocalDataError.invalidIdentifier }
        return kind == "credit_card" || kind == "credit_line" ? "in" : "out"
    }

    private static func voidActiveEntry(
        sourceID: UUID,
        sourceKind: String = "expense",
        voidedAt: Date,
        database: Database
    ) throws {
        guard let entryID = try String.fetchOne(
            database,
            sql: """
                SELECT id FROM local_account_entries
                WHERE source_kind = ? AND source_id = ? AND voided_at IS NULL AND is_voided = 0
                """,
            arguments: [sourceKind, sourceID.uuidString]
        ) else {
            throw LocalDataError.invalidRecord
        }
        try database.execute(
            sql: "UPDATE local_account_entries SET voided_at = ? WHERE id = ?",
            arguments: [voidedAt, entryID]
        )
    }

    private static func insertExpenseEntry(
        id: UUID,
        expense: LocalExpense,
        occurredAt: Date,
        database: Database
    ) throws {
        guard let accountID = expense.accountID else { return }
        let direction = try expenseEntryDirection(
            accountID: accountID, profileID: expense.profileID, database: database
        )
        try database.execute(
            sql: """
                INSERT INTO local_account_entries (
                    id, profile_id, account_id, direction, amount_minor, entry_kind,
                    source_kind, source_id, occurred_at, voided_at
                ) VALUES (?, ?, ?, ?, ?, 'expense', 'expense', ?, ?, NULL)
                """,
            arguments: [
                id.uuidString,
                expense.profileID.uuidString,
                accountID.uuidString,
                direction,
                expense.amountMinor,
                expense.id.uuidString,
                occurredAt
            ]
        )
    }

    private static func insertIncomeEntry(
        id: UUID,
        income: LocalIncome,
        accountID: UUID,
        database: Database
    ) throws {
        try database.execute(sql: """
            INSERT INTO local_account_entries (
                id, profile_id, account_id, direction, amount_minor, entry_kind,
                source_kind, source_id, occurred_at, voided_at
            ) VALUES (?, ?, ?, 'in', ?, 'income', 'income', ?, ?, NULL)
            """, arguments: [
                id.uuidString, income.profileID.uuidString, accountID.uuidString,
                income.amountMinor, income.id.uuidString, income.occurredAt
            ])
    }

    private static func insertOutbox(
        operationID: UUID,
        profileID: UUID,
        aggregateKind: String,
        aggregateID: UUID,
        operationKind: String,
        aggregateVersion: Int64,
        payload: String,
        createdAt: Date,
        database: Database
    ) throws {
        try database.execute(
            sql: """
                INSERT INTO local_outbox_operations (
                    operation_id, profile_id, aggregate_kind, aggregate_id, operation_kind,
                    aggregate_version, idempotency_key, payload_json, status, attempt_count,
                    next_attempt_at, last_error, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', 0, NULL, NULL, ?)
                """,
            arguments: [
                operationID.uuidString,
                profileID.uuidString,
                aggregateKind,
                aggregateID.uuidString,
                operationKind,
                aggregateVersion,
                operationID.uuidString,
                payload,
                createdAt
            ]
        )
    }

    private static func outboxPayload(account: LocalAccountDraft) throws -> String {
        try encodePayload(AccountOutboxPayload(
            id: account.id,
            profileID: account.profileID,
            name: account.name,
            kind: account.kind,
            currency: account.currency,
            openingBalanceMinor: account.openingBalanceMinor,
            localVersion: 1,
            createdAt: account.createdAt
        ))
    }

    private static func outboxPayload(expense: LocalExpense) throws -> String {
        let payload = ExpenseOutboxPayload(
            id: expense.id,
            profileID: expense.profileID,
            type: "expense",
            source: "manual",
            accountID: expense.accountID,
            amountMinor: expense.amountMinor,
            currency: expense.currency,
            merchantName: expense.merchantName,
            platform: expense.platform,
            category: expense.category,
            paymentMethod: expense.paymentMethod,
            transactionDate: expense.transactionDate,
            transactionTime: expense.transactionTime,
            note: expense.note,
            localVersion: expense.localVersion,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt
        )
        return try encodePayload(payload)
    }

    private static func outboxPayload(tombstone: LocalExpenseTombstone) throws -> String {
        try encodePayload(ExpenseDeleteOutboxPayload(
            id: tombstone.id,
            profileID: tombstone.profileID,
            localVersion: tombstone.localVersion,
            deletedAt: tombstone.deletedAt
        ))
    }

    private static func encodePayload(_ payload: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(payload), as: UTF8.self)
    }
}

private struct ExpenseOutboxPayload: Encodable {
    let id: UUID
    let profileID: UUID
    let type: String
    let source: String
    let accountID: UUID?
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
}

private struct ExpenseDeleteOutboxPayload: Encodable {
    let id: UUID
    let profileID: UUID
    let localVersion: Int64
    let deletedAt: Date
}

private struct AccountOutboxPayload: Encodable {
    let id: UUID
    let profileID: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let localVersion: Int64
    let createdAt: Date
}


enum LocalFinancialMutationError: Error, LocalizedError {
    case synchronizedExpenseCannotUnbind
    var errorDescription: String? {
        "同步已开启，当前同步协议不支持消费解绑。请保留账户绑定；关闭同步后可仅在本机解绑。"
    }
}
