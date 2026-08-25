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

    private static var migrator: DatabaseMigrator {
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
        return migrator
    }
}
