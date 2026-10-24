import Foundation
import GRDB

protocol LocalExpenseRepositoryProtocol {
    func createProfile(id: UUID, createdAt: Date) throws -> LocalProfile
    func createAccount(_ draft: LocalAccountDraft) throws -> LocalAccount
    func updateAccount(_ update: LocalAccountUpdate) throws -> LocalAccount
    func importRemoteAccounts(_ drafts: [LocalAccountDraft]) throws
    func accounts(profileID: UUID) throws -> [LocalAccount]
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
        guard draft.openingBalanceMinor >= 0 else { throw LocalDataError.invalidAmount }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 30 else { throw LocalDataError.invalidRecord }
        try database.writer.write { db in
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
                        auto_confirm_repayment, grace_period_days, is_default_expense, is_default_income,
                        is_archived, sort_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'local', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
        }
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
                guard !(hasEntries || hasExpenses || hasIncome) else { throw LocalDataError.invalidAccountKind }
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
                        auto_confirm_repayment, grace_period_days, is_default_expense, is_default_income,
                        is_archived, sort_order
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, 'remote', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
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
                        draft.gracePeriodDays, draft.isDefaultExpense, draft.isDefaultIncome,
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
                           auto_confirm_repayment, grace_period_days, is_default_expense, is_default_income,
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
                    isDefaultExpense: row["is_default_expense"],
                    isDefaultIncome: row["is_default_income"],
                    isArchived: row["is_archived"],
                    sortOrder: row["sort_order"],
                    localVersion: row["local_version"]
                )
            }
        }
    }

    func createExpense(_ draft: LocalExpenseDraft, operationID: UUID) throws -> LocalExpense {
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
            updatedAt: draft.createdAt
        )
        let payload = try Self.outboxPayload(expense: expense)

        try database.writer.write { db in
            try Self.validateActiveAccount(id: draft.accountID, profileID: draft.profileID, database: db)
            let direction = try Self.expenseEntryDirection(
                accountID: draft.accountID, profileID: draft.profileID, database: db
            )
            try db.execute(
                sql: """
                    INSERT INTO local_expenses (
                        id, profile_id, account_id, amount_minor, currency, merchant_name,
                        platform, category, payment_method, transaction_date, transaction_time,
                        note, local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID.uuidString,
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
                    draft.createdAt
                ]
            )

            try db.execute(
                sql: """
                    INSERT INTO local_account_entries (
                        id, profile_id, account_id, direction, amount_minor, entry_kind,
                        source_kind, source_id, occurred_at, voided_at
                    ) VALUES (?, ?, ?, ?, ?, 'expense', 'expense', ?, ?, NULL)
                    """,
                arguments: [
                    entryID.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID.uuidString,
                    direction,
                    draft.amountMinor,
                    draft.id.uuidString,
                    draft.createdAt
                ]
            )

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
        guard draft.amountMinor > 0 else { throw LocalDataError.invalidAmount }
        let income = LocalIncome(
            id: draft.id, profileID: draft.profileID, accountID: draft.accountID,
            amountMinor: draft.amountMinor, currency: draft.currency,
            sourceName: draft.sourceName, category: draft.category,
            incomeDate: draft.incomeDate, occurredAt: draft.occurredAt,
            note: draft.note, localVersion: 1, createdAt: draft.createdAt,
            updatedAt: draft.createdAt
        )
        try database.writer.write { db in
            if let accountID = draft.accountID {
                try Self.validateActiveIncomeAccount(id: accountID, profileID: draft.profileID, database: db)
            }
            try db.execute(sql: """
                INSERT INTO local_income_records (
                    id, profile_id, account_id, amount_minor, currency, source_name,
                    category, income_date, occurred_at, note, local_version,
                    created_at, updated_at, deleted_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                """, arguments: [
                    income.id.uuidString, income.profileID.uuidString,
                    income.accountID?.uuidString, income.amountMinor, income.currency,
                    income.sourceName, income.category, income.incomeDate,
                    income.occurredAt, income.note, income.createdAt, income.updatedAt
                ])
            if let accountID = income.accountID {
                try Self.insertIncomeEntry(
                    id: UUID(), income: income, accountID: accountID, database: db
                )
            }
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
                createdAt: existing.createdAt, updatedAt: update.updatedAt
            )
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
                let exists = try Row.fetchOne(
                    db,
                    sql: "SELECT id FROM local_expenses WHERE id = ? AND profile_id = ?",
                    arguments: [draft.id.uuidString, draft.profileID.uuidString]
                ) != nil
                if exists { continue }
                let direction = try Self.expenseEntryDirection(
                    accountID: draft.accountID, profileID: draft.profileID, database: db
                )
                try db.execute(sql: """
                    INSERT INTO local_expenses (
                        id, profile_id, account_id, amount_minor, currency, merchant_name,
                        platform, category, payment_method, transaction_date, transaction_time,
                        note, local_version, created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                    """, arguments: [
                        draft.id.uuidString, draft.profileID.uuidString, draft.accountID.uuidString,
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
                        UUID().uuidString, draft.profileID.uuidString, draft.accountID.uuidString,
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
            try Self.validateAccount(id: update.accountID, profileID: existing.profileID, database: db)
            if update.accountID != existing.accountID {
                try Self.validateActiveAccount(id: update.accountID, profileID: existing.profileID, database: db)
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
                updatedAt: update.updatedAt
            )
            let replacesLedger = existing.accountID != update.accountID
                || existing.amountMinor != update.amountMinor

            if replacesLedger {
                try Self.voidActiveEntry(
                    sourceID: update.id,
                    voidedAt: update.updatedAt,
                    database: db
                )
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
                    updated.accountID.uuidString,
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

            try Self.voidActiveEntry(sourceID: id, voidedAt: deletedAt, database: db)
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
                arguments: [profileID.uuidString, "\(monthKey)-%"]
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
                sql: "SELECT COUNT(*) FROM local_account_entries WHERE voided_at IS NULL"
            ) ?? 0
        }
    }

    func accountEntries(sourceID: UUID) throws -> [LocalAccountEntry] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, profile_id, account_id, direction, amount_minor, entry_kind,
                           source_kind, source_id, occurred_at, voided_at
                    FROM local_account_entries
                    WHERE source_kind = 'expense' AND source_id = ?
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
                           source_kind, source_id, occurred_at, voided_at
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
                     AND entries.voided_at IS NULL
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
                let row = try Row.fetchOne(db, sql: "SELECT local_version FROM local_expenses WHERE id = ? AND profile_id = ?", arguments: [expense.id.uuidString, profileID.uuidString])
                let localVersion: Int64 = row?["local_version"] ?? 0
                guard expense.version >= localVersion else { continue }
                if expense.deletedAt != nil {
                    try db.execute(sql: "UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?) WHERE source_kind = 'expense' AND source_id = ? AND voided_at IS NULL", arguments: [expense.deletedAt, expense.id.uuidString])
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
                    try db.execute(sql: "UPDATE local_account_entries SET voided_at = COALESCE(voided_at, ?) WHERE source_kind = 'expense' AND source_id = ? AND voided_at IS NULL", arguments: [Date(), expense.id.uuidString])
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

    private static func expense(from row: Row) throws -> LocalExpense {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let accountID = UUID(uuidString: row["account_id"]) else {
            throw LocalDataError.invalidRecord
        }
        return LocalExpense(
            id: id,
            profileID: profileID,
            accountID: accountID,
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
            updatedAt: row["updated_at"]
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
            voidedAt: row["voided_at"]
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
            createdAt: createdAt, updatedAt: updatedAt
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
              gracePeriodDays >= 0,
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
                WHERE source_kind = ? AND source_id = ? AND voided_at IS NULL
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
        let direction = try expenseEntryDirection(
            accountID: expense.accountID, profileID: expense.profileID, database: database
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
                expense.accountID.uuidString,
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
    let accountID: UUID
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
