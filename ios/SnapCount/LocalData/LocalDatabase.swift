import Foundation
import GRDB

final class LocalDatabase {
    let writer: DatabaseQueue

    init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        writer = try DatabaseQueue(path: databaseURL.path)
        try Self.migrator.migrate(writer)
    }

    /// 接管一个已打开的连接（校验副本用），并确保结构在当前版本。
    init(queue: DatabaseQueue) throws {
        writer = queue
        try Self.migrator.migrate(writer)
    }

    convenience init() throws {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("JieziLocalData", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: directory.path
        )
        let databaseURL = directory.appendingPathComponent("jiezi.sqlite")
        try self.init(databaseURL: databaseURL)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: databaseURL.path
        )
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("local-v1") { database in
            try database.execute(sql: """
                CREATE TABLE local_profiles (
                    id TEXT PRIMARY KEY NOT NULL,
                    created_at DATETIME NOT NULL,
                    cloud_user_id TEXT,
                    sync_enabled BOOLEAN NOT NULL DEFAULT 0
                );

                CREATE TABLE local_accounts (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    name TEXT NOT NULL,
                    kind TEXT NOT NULL,
                    currency TEXT NOT NULL,
                    opening_balance_minor INTEGER NOT NULL,
                    created_at DATETIME NOT NULL
                );

                CREATE INDEX local_accounts_profile_idx
                    ON local_accounts(profile_id, created_at);

                CREATE TABLE local_expenses (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT NOT NULL REFERENCES local_accounts(id),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    currency TEXT NOT NULL,
                    merchant_name TEXT NOT NULL,
                    platform TEXT NOT NULL,
                    category TEXT NOT NULL,
                    payment_method TEXT NOT NULL,
                    transaction_date TEXT NOT NULL,
                    transaction_time TEXT,
                    note TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_expenses_profile_date_idx
                    ON local_expenses(profile_id, transaction_date, created_at);

                CREATE TABLE local_account_entries (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT NOT NULL REFERENCES local_accounts(id),
                    direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    entry_kind TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    occurred_at DATETIME NOT NULL,
                    voided_at DATETIME
                );

                CREATE UNIQUE INDEX local_account_entries_active_source_idx
                    ON local_account_entries(source_kind, source_id)
                    WHERE voided_at IS NULL;

                CREATE INDEX local_account_entries_account_idx
                    ON local_account_entries(account_id, occurred_at);

                CREATE TABLE local_outbox_operations (
                    sequence INTEGER PRIMARY KEY AUTOINCREMENT,
                    operation_id TEXT NOT NULL UNIQUE,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    aggregate_kind TEXT NOT NULL,
                    aggregate_id TEXT NOT NULL,
                    operation_kind TEXT NOT NULL,
                    aggregate_version INTEGER NOT NULL CHECK (aggregate_version > 0),
                    idempotency_key TEXT NOT NULL UNIQUE,
                    payload_json TEXT NOT NULL,
                    status TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'processing', 'failed', 'sent')),
                    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
                    next_attempt_at DATETIME,
                    last_error TEXT,
                    created_at DATETIME NOT NULL
                );

                CREATE INDEX local_outbox_pending_idx
                    ON local_outbox_operations(status, sequence);
                """)
        }
        migrator.registerMigration("local-v2-sync-state") { database in
            try database.execute(sql: """
                CREATE TABLE local_sync_state (
                    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    sync_generation INTEGER NOT NULL DEFAULT 0 CHECK (sync_generation >= 0),
                    pull_cursor TEXT,
                    last_successful_sync_at DATETIME,
                    active_attempt_id TEXT,
                    sync_status TEXT NOT NULL DEFAULT 'disabled'
                        CHECK (sync_status IN ('disabled', 'ready', 'syncing', 'synced', 'failed')),
                    conflict_status TEXT NOT NULL DEFAULT 'none'
                        CHECK (conflict_status IN ('none', 'unresolved'))
                );

                INSERT OR IGNORE INTO local_sync_state (profile_id)
                    SELECT id FROM local_profiles;
                """)
        }
        migrator.registerMigration("local-v3-phase-a-origin") { database in
            try database.execute(sql: """
                ALTER TABLE local_accounts
                ADD COLUMN origin TEXT NOT NULL DEFAULT 'local'
                    CHECK (origin IN ('local', 'remote'));
                """)
        }
        migrator.registerMigration("local-v4-phase1-domain-records") { database in
            try database.execute(sql: """
                CREATE TABLE local_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    domain_key TEXT NOT NULL CHECK (domain_key IN ('expense', 'food', 'sleep', 'sport', 'reading')),
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    record_date TEXT NOT NULL,
                    record_time TEXT,
                    note TEXT,
                    image_path TEXT,
                    image_hash TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_records_profile_date_idx
                    ON local_records(profile_id, record_date, record_time, created_at);

                CREATE TABLE local_staging_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    domain_key TEXT NOT NULL CHECK (domain_key IN ('expense', 'food', 'sleep', 'sport', 'reading')),
                    status TEXT NOT NULL CHECK (status IN ('pending_review', 'archived', 'discarded', 'failed')),
                    confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    record_date TEXT NOT NULL,
                    record_time TEXT,
                    image_path TEXT,
                    image_hash TEXT,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                );

                CREATE INDEX local_staging_profile_status_idx
                    ON local_staging_records(profile_id, status, record_date, created_at);
                """)
        }
        migrator.registerMigration("local-v5-phase1-staging-resolution") { database in
            try database.execute(sql: """
                ALTER TABLE local_staging_records
                ADD COLUMN target_record_id TEXT;

                ALTER TABLE local_staging_records
                ADD COLUMN resolved_action TEXT;

                ALTER TABLE local_staging_records
                ADD COLUMN resolved_at DATETIME;

                CREATE INDEX local_staging_target_record_idx
                    ON local_staging_records(target_record_id);
                """)
        }
        migrator.registerMigration("local-v6-phase1-fact-provenance") { database in
            try database.execute(sql: """
                ALTER TABLE local_records
                ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'manual'
                    CHECK (source_kind IN ('manual', 'ai_auto_archive', 'ai_candidate', 'ai_confirmed', 'imported'));

                ALTER TABLE local_records
                ADD COLUMN domain_version INTEGER NOT NULL DEFAULT 1
                    CHECK (domain_version > 0);

                ALTER TABLE local_staging_records
                ADD COLUMN source_kind TEXT NOT NULL DEFAULT 'ai_candidate'
                    CHECK (source_kind IN ('manual', 'ai_auto_archive', 'ai_candidate', 'ai_confirmed', 'imported'));

                ALTER TABLE local_staging_records
                ADD COLUMN domain_version INTEGER NOT NULL DEFAULT 1
                    CHECK (domain_version > 0);
                """)
        }
        migrator.registerMigration("local-v7-phase1-candidate-evidence") { database in
            try database.execute(sql: """
                ALTER TABLE local_staging_records
                ADD COLUMN evidence_json TEXT NOT NULL DEFAULT '[]';

                ALTER TABLE local_staging_records
                ADD COLUMN missing_fields_json TEXT NOT NULL DEFAULT '[]';
                """)
        }
        migrator.registerMigration("local-v8-image-intake") { database in
            try database.execute(sql: """
                CREATE TABLE local_image_intakes (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    capture_kind TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (status IN ('receiving', 'failed', 'completed')),
                    image_path TEXT NOT NULL,
                    image_hash TEXT NOT NULL,
                    failure_message TEXT,
                    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                );

                CREATE INDEX local_image_intakes_profile_status_idx
                    ON local_image_intakes(profile_id, status, updated_at DESC);
                """)
        }
        migrator.registerMigration("local-v9-image-intake-cleanup") { database in
            try database.execute(sql: """
                ALTER TABLE local_image_intakes
                ADD COLUMN cleanup_message TEXT;
                """)
        }
        migrator.registerMigration("local-v10-image-cleanup-queue") { database in
            try database.execute(sql: """
                CREATE TABLE local_image_cleanups (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    image_path TEXT NOT NULL UNIQUE,
                    attempt_count INTEGER NOT NULL DEFAULT 0 CHECK (attempt_count >= 0),
                    last_error TEXT,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                );

                CREATE INDEX local_image_cleanups_profile_idx
                    ON local_image_cleanups(profile_id, updated_at);
                """)
        }
        migrator.registerMigration("local-v11-image-intake-operation-claim") { database in
            try database.execute(sql: """
                ALTER TABLE local_image_intakes ADD COLUMN operation_id TEXT;
                """)
        }
        migrator.registerMigration("local-v12-income-facts-and-optional-entry-time") { database in
            try database.execute(sql: """
                CREATE TABLE local_income_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT REFERENCES local_accounts(id),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    currency TEXT NOT NULL,
                    source_name TEXT NOT NULL,
                    category TEXT NOT NULL,
                    income_date TEXT NOT NULL,
                    occurred_at DATETIME,
                    note TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_income_profile_date_idx
                    ON local_income_records(profile_id, income_date, created_at);

                CREATE TABLE local_account_entries_v12 (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT NOT NULL REFERENCES local_accounts(id),
                    direction TEXT NOT NULL CHECK (direction IN ('in', 'out')),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    entry_kind TEXT NOT NULL,
                    source_kind TEXT NOT NULL,
                    source_id TEXT NOT NULL,
                    occurred_at DATETIME,
                    voided_at DATETIME
                );

                INSERT INTO local_account_entries_v12
                    (id, profile_id, account_id, direction, amount_minor, entry_kind,
                     source_kind, source_id, occurred_at, voided_at)
                SELECT id, profile_id, account_id, direction, amount_minor, entry_kind,
                       source_kind, source_id, occurred_at, voided_at
                FROM local_account_entries;

                DROP INDEX local_account_entries_active_source_idx;
                DROP INDEX local_account_entries_account_idx;
                DROP TABLE local_account_entries;
                ALTER TABLE local_account_entries_v12 RENAME TO local_account_entries;

                CREATE UNIQUE INDEX local_account_entries_active_source_idx
                    ON local_account_entries(source_kind, source_id)
                    WHERE voided_at IS NULL;

                CREATE INDEX local_account_entries_account_idx
                    ON local_account_entries(account_id, occurred_at);
                """)
        }
        migrator.registerMigration("local-v13-managed-account-configuration") { database in
            try database.execute(sql: """
                ALTER TABLE local_accounts ADD COLUMN institution TEXT NOT NULL DEFAULT '';
                ALTER TABLE local_accounts ADD COLUMN last4 TEXT NOT NULL DEFAULT ''
                    CHECK (last4 = '' OR (length(last4) = 4 AND last4 NOT GLOB '*[^0-9]*'));
                ALTER TABLE local_accounts ADD COLUMN bill_day INTEGER
                    CHECK (bill_day IS NULL OR bill_day BETWEEN 1 AND 31);
                ALTER TABLE local_accounts ADD COLUMN payment_due_day INTEGER
                    CHECK (payment_due_day IS NULL OR payment_due_day BETWEEN 1 AND 31);
                ALTER TABLE local_accounts ADD COLUMN auto_debit_account_id TEXT REFERENCES local_accounts(id);
                ALTER TABLE local_accounts ADD COLUMN auto_confirm_repayment BOOLEAN NOT NULL DEFAULT 0
                    CHECK (auto_confirm_repayment IN (0, 1));
                ALTER TABLE local_accounts ADD COLUMN grace_period_days INTEGER NOT NULL DEFAULT 0
                    CHECK (grace_period_days >= 0);
                ALTER TABLE local_accounts ADD COLUMN is_default_expense BOOLEAN NOT NULL DEFAULT 0
                    CHECK (is_default_expense IN (0, 1));
                ALTER TABLE local_accounts ADD COLUMN is_default_income BOOLEAN NOT NULL DEFAULT 0
                    CHECK (is_default_income IN (0, 1));
                ALTER TABLE local_accounts ADD COLUMN is_archived BOOLEAN NOT NULL DEFAULT 0
                    CHECK (is_archived IN (0, 1));
                ALTER TABLE local_accounts ADD COLUMN sort_order INTEGER NOT NULL DEFAULT 0;
                ALTER TABLE local_accounts ADD COLUMN local_version INTEGER NOT NULL DEFAULT 1
                    CHECK (local_version > 0);

                CREATE UNIQUE INDEX local_accounts_default_expense_idx
                    ON local_accounts(profile_id) WHERE is_default_expense = 1 AND is_archived = 0;
                CREATE UNIQUE INDEX local_accounts_default_income_idx
                    ON local_accounts(profile_id) WHERE is_default_income = 1 AND is_archived = 0;
                """)
        }
        migrator.registerMigration("local-v14-repayment-cycles-and-payments") { database in
            try database.execute(sql: """
                DROP INDEX local_account_entries_active_source_idx;
                CREATE UNIQUE INDEX local_account_entries_active_source_idx
                    ON local_account_entries(source_kind, source_id, account_id)
                    WHERE voided_at IS NULL;

                CREATE TABLE local_repayment_cycles (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT NOT NULL REFERENCES local_accounts(id),
                    cycle_month TEXT NOT NULL CHECK (cycle_month GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]'),
                    statement_start_date TEXT,
                    statement_end_date TEXT,
                    due_date TEXT,
                    statement_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (statement_amount_minor >= 0),
                    paid_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (paid_amount_minor >= 0),
                    remaining_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (remaining_amount_minor >= 0),
                    carried_over_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (carried_over_amount_minor >= 0),
                    original_statement_amount_minor INTEGER CHECK (original_statement_amount_minor IS NULL OR original_statement_amount_minor >= 0),
                    min_payment_amount_minor INTEGER CHECK (min_payment_amount_minor IS NULL OR min_payment_amount_minor >= 0),
                    refund_applied_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (refund_applied_amount_minor >= 0),
                    status TEXT NOT NULL,
                    auto_debit_account_id TEXT REFERENCES local_accounts(id),
                    auto_confirm_repayment BOOLEAN NOT NULL DEFAULT 0 CHECK (auto_confirm_repayment IN (0, 1)),
                    source TEXT NOT NULL,
                    evidence_record_id TEXT REFERENCES local_records(id) ON DELETE SET NULL,
                    confidence REAL,
                    note TEXT NOT NULL DEFAULT '',
                    confirmed_at DATETIME,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    UNIQUE(account_id, cycle_month)
                );
                CREATE INDEX local_repayment_cycles_profile_month_idx
                    ON local_repayment_cycles(profile_id, cycle_month DESC);

                CREATE TABLE local_liability_payments (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT NOT NULL REFERENCES local_accounts(id),
                    statement_id TEXT REFERENCES local_repayment_cycles(id) ON DELETE SET NULL,
                    debit_account_id TEXT REFERENCES local_accounts(id) ON DELETE SET NULL,
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    overpayment_amount_minor INTEGER NOT NULL DEFAULT 0 CHECK (overpayment_amount_minor >= 0),
                    paid_at DATETIME NOT NULL,
                    source TEXT NOT NULL CHECK (source IN ('screenshot', 'manual', 'auto_debit_assumed', 'system_match')),
                    evidence_record_id TEXT REFERENCES local_records(id) ON DELETE SET NULL,
                    status TEXT NOT NULL CHECK (status IN ('pending_review', 'confirmed', 'voided')),
                    note TEXT,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL
                );
                CREATE INDEX local_liability_payments_profile_time_idx
                    ON local_liability_payments(profile_id, paid_at DESC);
                CREATE INDEX local_liability_payments_cycle_status_idx
                    ON local_liability_payments(statement_id, status);
                """)
        }
        migrator.registerMigration("local-v15-account-reconciliation-time") { database in
            try database.execute(sql: """
                ALTER TABLE local_accounts ADD COLUMN last_reconciled_at DATETIME;
                CREATE TRIGGER local_accounts_grace_days_insert_check
                BEFORE INSERT ON local_accounts
                WHEN NEW.grace_period_days NOT BETWEEN 0 AND 60
                BEGIN SELECT RAISE(ABORT, 'grace period must be between 0 and 60 days'); END;
                CREATE TRIGGER local_accounts_grace_days_update_check
                BEFORE UPDATE OF grace_period_days ON local_accounts
                WHEN NEW.grace_period_days NOT BETWEEN 0 AND 60
                BEGIN SELECT RAISE(ABORT, 'grace period must be between 0 and 60 days'); END;
                """)
        }
        // Released v8/v9 used a different financial schema. Run the bridge before
        // v16 even when a previous launch already committed the newer v8-v15.
        migrator.registerMigration("local-v26-legacy-financial-compatibility") { database in
            try LocalLegacySchemaUpgrade.prepareWalletV16(database)
            try LocalLegacySchemaUpgrade.copyLegacyIncome(database)
        }
        migrator.registerMigration("local-v16-wallet-snapshot-facts") { database in
            try database.execute(sql: """
                CREATE TABLE local_wallet_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    record_date TEXT NOT NULL,
                    record_time TEXT,
                    occurred_at TEXT,
                    snapshot_balance_minor INTEGER NOT NULL CHECK (snapshot_balance_minor >= 0),
                    currency TEXT NOT NULL,
                    account_snapshot_kind TEXT NOT NULL CHECK (account_snapshot_kind IN ('asset', 'liability')),
                    linked_account_id TEXT REFERENCES local_accounts(id) ON DELETE SET NULL,
                    image_path TEXT,
                    image_hash TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_wallet_snapshots_profile_date_idx
                    ON local_wallet_snapshots(profile_id, record_date DESC, occurred_at DESC, created_at DESC);
                """)
            try LocalLegacySchemaUpgrade.finishWalletV16(database)
        }
        migrator.registerMigration("local-v17-wallet-snapshot-link-action") { database in
            try database.execute(sql: """
                ALTER TABLE local_wallet_snapshots
                ADD COLUMN linked_action TEXT CHECK (linked_action IN ('create', 'link'));
                """)
            if try database.tableExists("local_wallet_snapshots_legacy_v9") {
                try database.execute(sql: """
                    UPDATE local_wallet_snapshots SET linked_action = 'link'
                    WHERE linked_account_id IS NOT NULL
                      AND id IN (SELECT id FROM local_wallet_snapshots_legacy_v9);
                    """)
            }
        }
        migrator.registerMigration("local-v18-wallet-snapshot-cycle-evidence") { database in
            try database.execute(sql: """
                ALTER TABLE local_repayment_cycles
                ADD COLUMN evidence_wallet_snapshot_id TEXT
                    REFERENCES local_wallet_snapshots(id) ON DELETE SET NULL;
                """)
        }
        migrator.registerMigration("local-v19-wallet-repayment-staging") { database in
            try database.execute(sql: """
                CREATE TABLE local_staging_records_v19 (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    domain_key TEXT NOT NULL CHECK (domain_key IN ('expense', 'wallet', 'food', 'sleep', 'sport', 'reading')),
                    status TEXT NOT NULL CHECK (status IN ('pending_review', 'archived', 'discarded', 'failed')),
                    confidence REAL CHECK (confidence IS NULL OR (confidence >= 0 AND confidence <= 1)),
                    title TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    record_date TEXT NOT NULL,
                    record_time TEXT,
                    image_path TEXT,
                    image_hash TEXT,
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    target_record_id TEXT,
                    resolved_action TEXT,
                    resolved_at DATETIME,
                    source_kind TEXT NOT NULL DEFAULT 'ai_candidate'
                        CHECK (source_kind IN ('manual', 'ai_auto_archive', 'ai_candidate', 'ai_confirmed', 'imported')),
                    domain_version INTEGER NOT NULL DEFAULT 1 CHECK (domain_version > 0),
                    evidence_json TEXT NOT NULL DEFAULT '[]',
                    missing_fields_json TEXT NOT NULL DEFAULT '[]'
                );
                INSERT INTO local_staging_records_v19 (
                    id, profile_id, domain_key, status, confidence, title, summary, payload_json,
                    record_date, record_time, image_path, image_hash, created_at, updated_at,
                    target_record_id, resolved_action, resolved_at, source_kind, domain_version,
                    evidence_json, missing_fields_json
                ) SELECT
                    id, profile_id, domain_key, status, confidence, title, summary, payload_json,
                    record_date, record_time, image_path, image_hash, created_at, updated_at,
                    target_record_id, resolved_action, resolved_at, source_kind, domain_version,
                    evidence_json, missing_fields_json
                FROM local_staging_records;
                DROP TABLE local_staging_records;
                ALTER TABLE local_staging_records_v19 RENAME TO local_staging_records;
                CREATE INDEX local_staging_profile_status_idx
                    ON local_staging_records(profile_id, status, record_date, created_at);
                CREATE INDEX local_staging_target_record_idx
                    ON local_staging_records(target_record_id);
                """)
        }
        migrator.registerMigration("local-v20-screenshot-payment-evidence") { database in
            try database.execute(sql: """
                ALTER TABLE local_liability_payments
                ADD COLUMN evidence_staging_id TEXT REFERENCES local_staging_records(id) ON DELETE SET NULL;
                CREATE UNIQUE INDEX local_liability_payments_evidence_staging_idx
                    ON local_liability_payments(evidence_staging_id)
                    WHERE evidence_staging_id IS NOT NULL;
                """)
        }
        migrator.registerMigration("local-v21-history-migration-checkpoint") { database in
            try database.execute(sql: """
                CREATE TABLE local_history_migrations (
                    profile_id TEXT PRIMARY KEY NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    cloud_user_id TEXT NOT NULL,
                    generation INTEGER NOT NULL CHECK (generation > 0),
                    status TEXT NOT NULL CHECK (status IN ('running', 'paused', 'completed')),
                    expected_scopes_json TEXT NOT NULL,
                    source_cursors_json TEXT NOT NULL DEFAULT '{"nextByScope":{},"completedScopes":[]}',
                    imported_row_count INTEGER NOT NULL DEFAULT 0 CHECK (imported_row_count >= 0),
                    started_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    completed_at DATETIME
                );
                """)
        }
        migrator.registerMigration("local-v22-financial-images-and-pending") { database in
            try database.execute(sql: """
                ALTER TABLE local_expenses ADD COLUMN image_path TEXT;
                ALTER TABLE local_expenses ADD COLUMN image_hash TEXT;
                ALTER TABLE local_income_records ADD COLUMN image_path TEXT;
                ALTER TABLE local_income_records ADD COLUMN image_hash TEXT;
                ALTER TABLE local_income_records ADD COLUMN source_pending_transaction_id TEXT;
                CREATE UNIQUE INDEX local_income_pending_source_idx ON local_income_records(source_pending_transaction_id);
                CREATE TABLE local_pending_transactions (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id),
                    amount_minor INTEGER NOT NULL CHECK(amount_minor >= 0),
                    currency TEXT NOT NULL, merchant_name TEXT NOT NULL,
                    transaction_date TEXT NOT NULL, transaction_time TEXT, occurred_at DATETIME,
                    created_at DATETIME NOT NULL, image_path TEXT, image_hash TEXT,
                    status TEXT NOT NULL CHECK(status IN ('pending','done','converted','deleted')),
                    target_kind TEXT, target_id TEXT,
                    preferred_kind TEXT NOT NULL DEFAULT 'expense' CHECK(preferred_kind IN ('expense','income'))
                );
                """)
        }
        migrator.registerMigration("local-v23-unbound-expense") { database in
            try database.execute(sql: """
                CREATE TABLE local_expenses_unbound (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT REFERENCES local_accounts(id),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    currency TEXT NOT NULL, merchant_name TEXT NOT NULL,
                    platform TEXT NOT NULL, category TEXT NOT NULL, payment_method TEXT NOT NULL,
                    transaction_date TEXT NOT NULL, transaction_time TEXT, note TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL, deleted_at DATETIME,
                    image_path TEXT, image_hash TEXT
                );
                INSERT INTO local_expenses_unbound SELECT * FROM local_expenses;
                DROP TABLE local_expenses;
                ALTER TABLE local_expenses_unbound RENAME TO local_expenses;
                CREATE INDEX local_expenses_profile_date_idx ON local_expenses(profile_id, transaction_date, created_at);
                """)
        }
        migrator.registerMigration("local-v24-history-ledger-evidence") { database in
            try database.execute(sql: """
                ALTER TABLE local_account_entries ADD COLUMN is_voided INTEGER NOT NULL DEFAULT 0 CHECK(is_voided IN (0,1));
                ALTER TABLE local_account_entries ADD COLUMN source_metadata_json TEXT;
                ALTER TABLE local_liability_payments ADD COLUMN evidence_wallet_snapshot_id TEXT REFERENCES local_wallet_snapshots(id);
                DROP INDEX local_account_entries_active_source_idx;
                CREATE UNIQUE INDEX local_account_entries_active_source_idx
                    ON local_account_entries(source_kind, source_id, account_id)
                    WHERE voided_at IS NULL AND is_voided = 0;
                """)
        }
        migrator.registerMigration("local-v25-history-migration-cache") { database in
            try database.execute(sql: """
                CREATE TABLE local_history_migration_cache (
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    cloud_user_id TEXT NOT NULL,
                    cache_kind TEXT NOT NULL CHECK(cache_kind IN ('page','image')),
                    cache_key TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    updated_at DATETIME NOT NULL,
                    PRIMARY KEY(profile_id, cache_kind, cache_key)
                );
                """)
        }
        migrator.registerMigration("local-v27-history-unresolved-originals") { database in
            try database.execute(sql: """
                CREATE TABLE local_history_unresolved_records (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    source_table TEXT NOT NULL CHECK(source_table IN ('data_records','staging_records')),
                    source_id TEXT NOT NULL,
                    source_json TEXT NOT NULL CHECK(json_valid(source_json) AND json_type(source_json) = 'object'),
                    issues_json TEXT NOT NULL CHECK(json_valid(issues_json) AND json_type(issues_json) = 'array' AND json_array_length(issues_json) > 0),
                    image_path TEXT, image_hash TEXT,
                    created_at DATETIME NOT NULL, updated_at DATETIME NOT NULL,
                    CHECK ((image_path IS NULL AND image_hash IS NULL) OR (image_path IS NOT NULL AND image_hash IS NOT NULL)),
                    UNIQUE(profile_id, source_table, source_id)
                );
                CREATE INDEX local_history_unresolved_profile_idx ON local_history_unresolved_records(profile_id, created_at, id);
                """)
        }
        return migrator
    }
}
