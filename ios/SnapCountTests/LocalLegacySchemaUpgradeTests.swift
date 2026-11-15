import XCTest
import GRDB
@testable import SnapCount

final class LocalLegacySchemaUpgradeTests: XCTestCase {
    func testLF024PublishedV9WalletAndIncomeSurviveUpgradeAndTwoReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("legacy.sqlite")
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let bytes = Data("synthetic-legacy-original".utf8)
        let hash = LocalImageStore.sha256(bytes)
        _ = try images.restore(data: bytes, at: "records/original.jpg", expectedHash: hash)
        let queue = try DatabaseQueue(path: url.path)
        try LocalDatabase.migrator.migrate(queue, upTo: "local-v7-phase1-candidate-evidence")
        try queue.write { db in
            try db.execute(sql: Self.publishedDDL)
            try db.execute(sql: """
                INSERT INTO local_profiles(id,created_at) VALUES ('00000000-0000-0000-0000-000000000001', '2026-09-01 00:00:00');
                INSERT INTO local_accounts(id,profile_id,name,kind,currency,opening_balance_minor,created_at)
                VALUES ('00000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000001','synthetic','cash','CNY',10000,'2026-09-01 00:00:00');
                INSERT INTO local_incomes(id,profile_id,account_id,amount_minor,currency,income_category,source_name,income_date,income_time,local_version,created_at,updated_at)
                VALUES ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002',2000,'CNY','other',NULL,'2026-09-27',NULL,3,'2026-09-27 00:00:00','2026-09-27 01:00:00');
                INSERT INTO local_account_entries(id,profile_id,account_id,direction,amount_minor,entry_kind,source_kind,source_id,occurred_at)
                VALUES ('00000000-0000-0000-0000-000000000004','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','in',2000,'income','income','00000000-0000-0000-0000-000000000003','2026-09-27 00:00:00');
                INSERT INTO local_wallet_snapshots(id,profile_id,account_id,snapshot_kind,amount_minor,currency,account_name,account_type,snapshot_date,payload_json,image_path,image_hash,source_kind,local_version,created_at,updated_at,deleted_at)
                VALUES ('00000000-0000-0000-0000-000000000005','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000002','asset',12000,'CNY','synthetic','cash','2026-09-27','{"private":"original"}','records/original.jpg','\(hash)','manual',4,'2026-09-27 00:00:00','2026-09-27 01:00:00','2026-09-28 00:00:00');
                """)
        }
        // Reproduce the failed installation: v8-v15 have already committed before v16 fails.
        try LocalDatabase.migrator.migrate(queue, upTo: "local-v15-account-reconciliation-time")
        try queue.close()
        for _ in 0..<2 {
            let database = try LocalDatabase(databaseURL: url)
            defer { try? database.writer.close() }
            let repository = try LocalExpenseRepository(database: database)
            let account = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
            XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 12000)
            XCTAssertEqual(try repository.income(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)?.localVersion, 3)
            XCTAssertEqual(try images.data(at: "records/original.jpg"), bytes)
            let portability = LocalCompleteBackupPortability(database: database, imageStore: images)
            let backup = try portability.exportBackup()
            let preview = try portability.preview(backup)
            XCTAssertEqual(preview.tableCounts["local_wallet_snapshots"], 1)
            XCTAssertEqual(preview.tableCounts["local_income_records"], 1)
            XCTAssertEqual(preview.tableCounts["local_account_entries"], 1)
            XCTAssertEqual(preview.imageCount, 1)
            XCTAssertEqual(preview.imageBytes, bytes.count)
            try database.writer.read { db in
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_account_entries"), 1)
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT amount_minor FROM local_income_records WHERE id='00000000-0000-0000-0000-000000000003'"), 2000)
                XCTAssertEqual(try String.fetchOne(db, sql: "SELECT source_name FROM local_income_records WHERE id='00000000-0000-0000-0000-000000000003'"), "")
                XCTAssertNil(try String.fetchOne(db, sql: "SELECT occurred_at FROM local_income_records WHERE id='00000000-0000-0000-0000-000000000003'"))
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT local_version FROM local_wallet_snapshots WHERE id='00000000-0000-0000-0000-000000000005'"), 4)
                XCTAssertEqual(try String.fetchOne(db, sql: "SELECT image_path FROM local_wallet_snapshots WHERE id='00000000-0000-0000-0000-000000000005'"), "records/original.jpg")
                XCTAssertNotNil(try String.fetchOne(db, sql: "SELECT deleted_at FROM local_wallet_snapshots WHERE id='00000000-0000-0000-0000-000000000005'"))
                XCTAssertEqual(try String.fetchOne(db, sql: "SELECT json_extract(payload_json,'$.private') FROM local_wallet_snapshots WHERE id='00000000-0000-0000-0000-000000000005'"), "original")
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_incomes"), 1)
                XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            }
        }
    }
    func testLF024ModernV25DatabaseReopensAfterOnlyBridgeMarkerIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("modern.sqlite")
        let database = try LocalDatabase(databaseURL: url)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let repository = try LocalExpenseRepository(database: database)
        let account = try repository.createAccount(LocalAccountDraft(id: UUID(), profileID: profile.id,
            name: "synthetic", kind: "cash", currency: "CNY", openingBalanceMinor: 10000, createdAt: Date()))
        _ = try repository.createExpense(LocalExpenseDraft(id: UUID(), profileID: profile.id, accountID: account.id,
            amountMinor: 2000, currency: "CNY", merchantName: "synthetic", platform: "", category: "other",
            paymentMethod: "cash", transactionDate: "2026-10-25", transactionTime: nil, note: nil, createdAt: Date()), operationID: UUID())
        try database.writer.write { db in
            try db.execute(sql: """
                INSERT INTO local_wallet_snapshots(id,profile_id,title,summary,payload_json,record_date,
                    snapshot_balance_minor,currency,account_snapshot_kind,linked_account_id,linked_action,
                    local_version,created_at,updated_at)
                VALUES (?,?,'synthetic','', '{}','2026-10-25',8000,'CNY','asset',?,'link',5,?,?)
                """, arguments: [UUID().uuidString, profile.id.uuidString, account.id.uuidString, Date(), Date()])
        }
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let timestamp = Date(timeIntervalSince1970: 0)
        let before = try LocalCompleteBackupPortability(database: database, imageStore: images).exportBackup(exportedAt: timestamp)
        try database.writer.write { db in
            try db.execute(sql: "DELETE FROM grdb_migrations WHERE identifier='local-v26-legacy-financial-compatibility'")
        }
        try database.writer.close()
        for _ in 0..<2 {
            let reopened = try LocalDatabase(databaseURL: url)
            defer { try? reopened.writer.close() }
            let after = try LocalCompleteBackupPortability(database: reopened, imageStore: images).exportBackup(exportedAt: timestamp)
            XCTAssertEqual(after, before, "Modern facts, versions, relationships and history must remain identical")
            XCTAssertEqual(try LocalExpenseRepository(database: reopened).accountBalanceMinor(accountID: account.id), 8000)
            try reopened.writer.read { db in
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_account_entries WHERE voided_at IS NULL"), 1)
                XCTAssertFalse(try db.tableExists("local_wallet_snapshots_legacy_v9"))
                XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM grdb_migrations WHERE identifier='local-v26-legacy-financial-compatibility'"), 1)
            }
        }
    }

    func testLF024IncomeOnlyLegacySchemaUpgradesWithoutWallet() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("income-only.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try LocalDatabase.migrator.migrate(queue, upTo: "local-v7-phase1-candidate-evidence")
        try queue.write { db in
            try db.execute(sql: Self.publishedDDL.components(separatedBy: "CREATE TABLE local_wallet_snapshots")[0])
        }
        try queue.close()
        for _ in 0..<2 {
            let reopened = try LocalDatabase(databaseURL: url)
            try reopened.writer.close()
        }
    }

    func testLF024UnknownShapeAndStableIDConflictRollBackTransaction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("conflict.sqlite"))
        // Unknown structures are diagnostic failures, never treated as empty/new databases.
        XCTAssertThrowsError(try database.writer.write { db in
            try db.execute(sql: "ALTER TABLE local_wallet_snapshots ADD COLUMN unknown_field TEXT")
            try LocalLegacySchemaUpgrade.prepareWalletV16(db)
        })
        try database.writer.read { db in
            XCTAssertFalse(try Row.fetchAll(db, sql: "PRAGMA table_info(local_wallet_snapshots)").contains { ($0["name"] as String) == "unknown_field" })
        }
        try database.writer.write { db in
            try db.execute(sql: Self.publishedDDL.components(separatedBy: "INSERT INTO grdb_migrations")[0])
            try db.execute(sql: """
                INSERT INTO local_profiles(id,created_at) VALUES ('00000000-0000-0000-0000-000000000001','2026-09-01 00:00:00');
                INSERT INTO local_incomes(id,profile_id,amount_minor,currency,income_category,income_date,created_at,updated_at)
                VALUES ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001',2000,'CNY','other','2026-09-27','2026-09-27 00:00:00','2026-09-27 00:00:00');
                INSERT INTO local_income_records(id,profile_id,amount_minor,currency,category,source_name,income_date,created_at,updated_at)
                VALUES ('00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000001',3000,'CNY','other','','2026-09-27','2026-09-27 00:00:00','2026-09-27 00:00:00');
                """)
        }
        XCTAssertThrowsError(try database.writer.write { db in
            try db.execute(sql: "UPDATE local_incomes SET note='must roll back'")
            try LocalLegacySchemaUpgrade.copyLegacyIncome(db)
        })
        try database.writer.read { db in
            XCTAssertNil(try String.fetchOne(db, sql: "SELECT note FROM local_incomes WHERE id='00000000-0000-0000-0000-000000000003'"))
            XCTAssertEqual(try Int.fetchOne(db, sql: "SELECT amount_minor FROM local_income_records WHERE id='00000000-0000-0000-0000-000000000003'"), 3000)
        }
    }

    private static let publishedDDL = #"""

                CREATE TABLE local_incomes (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT REFERENCES local_accounts(id),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
                    currency TEXT NOT NULL,
                    income_category TEXT NOT NULL,
                    source_name TEXT,
                    income_date TEXT NOT NULL,
                    income_time TEXT,
                    note TEXT,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_incomes_profile_date_idx
                    ON local_incomes(profile_id, income_date, income_time, created_at);
                
INSERT INTO grdb_migrations(identifier) VALUES ('local-v8-phase1-income');

                CREATE TABLE local_wallet_snapshots (
                    id TEXT PRIMARY KEY NOT NULL,
                    profile_id TEXT NOT NULL REFERENCES local_profiles(id) ON DELETE CASCADE,
                    account_id TEXT REFERENCES local_accounts(id),
                    snapshot_kind TEXT NOT NULL CHECK (snapshot_kind IN ('asset', 'liability')),
                    amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
                    minimum_payment_minor INTEGER CHECK (
                        minimum_payment_minor IS NULL OR minimum_payment_minor >= 0
                    ),
                    currency TEXT NOT NULL,
                    account_name TEXT NOT NULL,
                    account_type TEXT NOT NULL,
                    snapshot_date TEXT NOT NULL,
                    snapshot_time TEXT,
                    due_date TEXT,
                    bill_day INTEGER CHECK (bill_day IS NULL OR (bill_day >= 1 AND bill_day <= 31)),
                    note TEXT,
                    payload_json TEXT NOT NULL,
                    image_path TEXT,
                    image_hash TEXT,
                    source_kind TEXT NOT NULL,
                    local_version INTEGER NOT NULL DEFAULT 1 CHECK (local_version > 0),
                    created_at DATETIME NOT NULL,
                    updated_at DATETIME NOT NULL,
                    deleted_at DATETIME
                );

                CREATE INDEX local_wallet_snapshots_profile_date_idx
                    ON local_wallet_snapshots(profile_id, snapshot_date, snapshot_time, created_at);

                CREATE INDEX local_wallet_snapshots_profile_account_idx
                    ON local_wallet_snapshots(profile_id, account_id, snapshot_date, created_at);
                
INSERT INTO grdb_migrations(identifier) VALUES ('local-v9-phase1-wallet-snapshots');
"""#
}
