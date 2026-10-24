import Foundation
import XCTest
@testable import SnapCount

final class LocalCompleteBackupPortabilityTests: XCTestCase {
    func testLF02101CompleteBackupRestoresFinancialHistoryCandidatesAndImagesWithoutOutbox() throws {
        let source = try makeFixture()
        defer { cleanup(source) }
        let backup = try source.portability.exportBackup()
        let preview = try source.portability.preview(backup)
        XCTAssertEqual(preview.imageCount, 3)
        XCTAssertEqual(preview.tableCounts["local_accounts"], 2)
        XCTAssertEqual(preview.tableCounts["local_income_records"], 1)
        XCTAssertEqual(preview.tableCounts["local_liability_payments"], 1)
        let serialized = String(decoding: backup, as: UTF8.self)
        XCTAssertFalse(serialized.contains("cloudUser"))
        XCTAssertFalse(serialized.contains("upload_token"))
        XCTAssertFalse(serialized.contains("local_outbox_operations"))

        let target = try makeEmptyFixture()
        defer { cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let imported: LocalCompleteBackupImportResult
        do {
            imported = try target.portability.importBackup(backup, into: targetProfile.id)
        } catch {
            XCTFail("首次完整恢复失败：\(error)")
            return
        }

        XCTAssertEqual(imported.insertedRows, preview.totalRows)
        XCTAssertEqual(imported.skippedRows, 0)
        XCTAssertEqual(imported.restoredImages, 3)
        XCTAssertEqual(try LocalExpenseRepository(database: target.database).accountBalanceMinor(accountID: source.cashID), 480)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses WHERE deleted_at IS NOT NULL"), 1)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_liability_payments WHERE status = 'voided'"), 1)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_account_entries WHERE voided_at IS NOT NULL"), 3)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_staging_records WHERE status = 'pending_review'"), 1)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_image_intakes WHERE status = 'failed'"), 1)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_outbox_operations"), 0)
        XCTAssertEqual(try LocalExpenseRepository(database: target.database).accountBalanceMinor(accountID: source.liabilityID), 10_000)

        let repeated: LocalCompleteBackupImportResult
        do {
            repeated = try target.portability.importBackup(backup, into: targetProfile.id)
        } catch {
            XCTFail("重复完整恢复失败：\(error)")
            return
        }
        XCTAssertEqual(repeated.insertedRows, 0)
        XCTAssertEqual(repeated.skippedRows, preview.totalRows)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_account_entries"), 5)
    }

    func testLF02103ConflictingStableIDRejectsWholeBackupBeforeAnyInsert() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let originalBackup = try source.portability.exportBackup()
        _ = try target.portability.importBackup(originalBackup, into: targetProfile.id)
        let backup = try tamper(originalBackup) { tables in
            var expenses = try Self.tableRows("local_expenses", in: tables)
            expenses[0]["id"] = source.expenseID.uuidString
            expenses[0]["amount_minor"] = 99_999
            tables["local_expenses"] = try Self.encodeRows(expenses)
            var incomes = try Self.tableRows("local_income_records", in: tables)
            incomes.append([
                "id": UUID().uuidString,
                "profile_id": source.profileID.uuidString,
                "account_id": NSNull(),
                "amount_minor": 1,
                "currency": "CNY",
                "source_name": "冲突时不得插入",
                "category": "other",
                "income_date": "2026-10-25",
                "occurred_at": NSNull(),
                "note": NSNull(),
                "local_version": 1,
                "created_at": Date().timeIntervalSince1970,
                "updated_at": Date().timeIntervalSince1970,
                "deleted_at": NSNull()
            ])
            tables["local_income_records"] = try Self.encodeRows(incomes)
        }
        let incomeCountBefore = try count(target.database, "SELECT COUNT(*) FROM local_income_records")
        let imagesBefore = try imageFiles(in: target.imageDirectory)

        XCTAssertThrowsError(try target.portability.importBackup(backup, into: targetProfile.id)) { error in
            guard case LocalCompleteBackupError.conflictingStableID = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_income_records"), incomeCountBefore)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 2)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory), imagesBefore)
    }

    func testLF02107DatabaseFailureRollsBackRowsAndNewImageFiles() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let backup = try tamper(source.portability.exportBackup()) { tables in
            var entries = try Self.tableRows("local_account_entries", in: tables)
            entries.append([
                "id": UUID().uuidString,
                "profile_id": source.profileID.uuidString,
                "account_id": UUID().uuidString,
                "direction": "out",
                "amount_minor": 1,
                "entry_kind": "expense",
                "source_kind": "expense",
                "source_id": UUID().uuidString,
                "occurred_at": NSNull(),
                "voided_at": NSNull()
            ])
            tables["local_account_entries"] = try Self.encodeRows(entries)
        }

        XCTAssertThrowsError(try target.portability.importBackup(backup, into: targetProfile.id))
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_accounts"), 0)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory), [])
    }

    func testLF02105CompleteExportFailsWhenReferencedImageIsMissing() throws {
        let fixture = try makeFixture()
        defer { cleanup(fixture) }
        let recordImagePath = fixture.recordImage.path
        try fixture.imageStore.remove(path: recordImagePath)

        XCTAssertThrowsError(try fixture.portability.exportBackup()) { error in
            guard case LocalCompleteBackupError.missingImage = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }
    }

    func testLF02108LegacyExpenseArchivePreviewsAndImportsWithoutCreatingSyncOperations() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let legacyData = try LocalExpensePortability(database: source.database)
            .exportArchive(profileID: source.profileID)
        let preview = try target.portability.preview(legacyData)
        XCTAssertEqual(preview.formatName, "旧版消费归档")
        XCTAssertEqual(preview.schemaVersion, LocalExpenseArchive.currentSchemaVersion)
        XCTAssertEqual(preview.tableCounts["local_expenses"], 2)
        XCTAssertEqual(preview.imageCount, 0)

        let targetProfile = try target.profileStore.activeProfile()
        let imported = try target.portability.importBackup(legacyData, into: targetProfile.id)
        XCTAssertEqual(imported.insertedRows, 6) // two accounts, two expenses, two expense entries
        XCTAssertEqual(try LocalExpenseRepository(database: target.database).accountBalanceMinor(accountID: source.cashID), 480)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_outbox_operations"), 0)
        let repeated = try target.portability.importBackup(legacyData, into: targetProfile.id)
        XCTAssertEqual(repeated.insertedRows, 0)
        XCTAssertEqual(repeated.skippedRows, 6)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 2)
    }

    private func count(_ database: LocalDatabase, _ sql: String) throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: sql) ?? 0
        }
    }

    private func makeFixture() throws -> Fixture {
        let fixture = try makeEmptyFixture()
        let profile = try fixture.profileStore.activeProfile()
        let now = Date()
        let cashID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
        let liabilityID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!
        let recordID = UUID(uuidString: "00000000-0000-4000-8000-000000000003")!
        let expenseID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
        let deletedExpenseID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
        let incomeID = UUID(uuidString: "00000000-0000-4000-8000-000000000006")!
        let cycleID = UUID(uuidString: "00000000-0000-4000-8000-000000000007")!
        let paymentID = UUID(uuidString: "00000000-0000-4000-8000-000000000008")!
        let image = Data("backup-record-image".utf8)
        let stagingImage = Data("backup-staging-image".utf8)
        let intakeImage = Data("backup-intake-image".utf8)
        let recordImage = try fixture.imageStore.save(data: image, owner: recordID.uuidString)
        let stagingReference = try fixture.imageStore.save(data: stagingImage, owner: "candidate-1", bucket: "staging")
        let intakeHash = LocalImageStore.sha256(intakeImage)
        let intakeID = "\(profile.id.uuidString)-\(intakeHash)"
        let intakeReference = try fixture.imageStore.save(data: intakeImage, owner: "recognition-\(profile.id.uuidString)-\(intakeHash)", bucket: "intake")
        let deletedAt = now.addingTimeInterval(-60)

        try fixture.database.writer.write { db in
            try db.execute(
                sql: "UPDATE local_profiles SET cloud_user_id = 'synthetic-cloud-user', sync_enabled = 1 WHERE id = ?",
                arguments: [profile.id.uuidString]
            )
            try db.execute(sql: """
                INSERT INTO local_accounts (id, profile_id, name, kind, currency, opening_balance_minor, created_at,
                    institution, bill_day, payment_due_day, auto_debit_account_id, is_default_expense,
                    is_default_income, local_version, last_reconciled_at)
                VALUES (?, ?, '现金', 'cash', 'CNY', 500, ?, '', NULL, NULL, NULL, 1, 1, 2, ?)
                """, arguments: [cashID.uuidString, profile.id.uuidString, now, now])
            try db.execute(sql: """
                INSERT INTO local_accounts (id, profile_id, name, kind, currency, opening_balance_minor, created_at,
                    institution, last4, bill_day, payment_due_day, auto_debit_account_id,
                    auto_confirm_repayment, grace_period_days, local_version, last_reconciled_at)
                VALUES (?, ?, '信用卡', 'credit_card', 'CNY', 10000, ?, '银行', '1234', 31, 15, ?, 0, 3, 4, ?)
                """, arguments: [liabilityID.uuidString, profile.id.uuidString, now, cashID.uuidString, now])
            try db.execute(sql: """
                INSERT INTO local_records (id, profile_id, domain_key, title, summary, payload_json, record_date,
                    record_time, note, image_path, image_hash, local_version, created_at, updated_at,
                    deleted_at, source_kind, domain_version)
                VALUES (?, ?, 'food', '午餐', '米饭', '{\"food_name\":\"米饭\"}', '2026-10-25', NULL,
                    '本地备份', ?, ?, 2, ?, ?, NULL, 'manual', 1)
                """, arguments: [recordID.uuidString, profile.id.uuidString, recordImage.path, recordImage.hash, now, now])
            try db.execute(sql: """
                INSERT INTO local_expenses (id, profile_id, account_id, amount_minor, currency, merchant_name,
                    platform, category, payment_method, transaction_date, transaction_time, note, local_version,
                    created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, 20, 'CNY', '商户', '', '餐饮', 'card', '2026-10-25', NULL, NULL, 2, ?, ?, NULL)
                """, arguments: [expenseID.uuidString, profile.id.uuidString, cashID.uuidString, now, now])
            try db.execute(sql: """
                INSERT INTO local_expenses (id, profile_id, account_id, amount_minor, currency, merchant_name,
                    platform, category, payment_method, transaction_date, transaction_time, note, local_version,
                    created_at, updated_at, deleted_at)
                VALUES (?, ?, ?, 1000, 'CNY', '旧商户', '', '餐饮', 'card', '2026-10-24', NULL, NULL, 2, ?, ?, ?)
                """, arguments: [deletedExpenseID.uuidString, profile.id.uuidString, cashID.uuidString, now, now, deletedAt])
            try db.execute(sql: """
                INSERT INTO local_income_records (id, profile_id, account_id, amount_minor, currency, source_name,
                    category, income_date, occurred_at, note, local_version, created_at, updated_at, deleted_at)
                VALUES (?, ?, NULL, 3500, 'CNY', '工资', 'salary', '2026-10-25', NULL, '收入事实', 1, ?, ?, NULL)
                """, arguments: [incomeID.uuidString, profile.id.uuidString, now, now])
            try db.execute(sql: """
                INSERT INTO local_staging_records (id, profile_id, domain_key, status, confidence, title, summary,
                    payload_json, record_date, record_time, image_path, image_hash, created_at, updated_at,
                    source_kind, domain_version, evidence_json, missing_fields_json)
                VALUES ('candidate-1', ?, 'food', 'pending_review', 0.5, '点心', '候选', '{}', '2026-10-25', NULL,
                    ?, ?, ?, ?, 'ai_candidate', 1, '[]', '[]')
                """, arguments: [profile.id.uuidString, stagingReference.path, stagingReference.hash, now, now])
            try db.execute(sql: """
                INSERT INTO local_image_intakes (id, profile_id, capture_kind, filename, status, image_path,
                    image_hash, failure_message, attempt_count, created_at, updated_at, cleanup_message, operation_id)
                VALUES (?, ?, 'camera', 'failed.jpg', 'failed', ?, ?, 'synthetic failure', 1, ?, ?, NULL, NULL)
                """, arguments: [intakeID, profile.id.uuidString, intakeReference.path, intakeHash, now, now])
            try db.execute(sql: """
                INSERT INTO local_repayment_cycles (id, profile_id, account_id, cycle_month, statement_amount_minor,
                    paid_amount_minor, remaining_amount_minor, carried_over_amount_minor, refund_applied_amount_minor,
                    status, auto_debit_account_id, auto_confirm_repayment, source, evidence_record_id,
                    note, local_version, created_at, updated_at)
                VALUES (?, ?, ?, '2026-10', 3000, 3000, 0, 0, 0, 'paid', ?, 0, 'manual', ?, '已还', 2, ?, ?)
                """, arguments: [cycleID.uuidString, profile.id.uuidString, liabilityID.uuidString, cashID.uuidString, recordID.uuidString, now, now])
            try db.execute(sql: """
                INSERT INTO local_liability_payments (id, profile_id, account_id, statement_id, debit_account_id,
                    amount_minor, overpayment_amount_minor, paid_at, source, evidence_record_id, status, note,
                    created_at, updated_at)
                VALUES (?, ?, ?, ?, ?, 3000, 0, ?, 'manual', ?, 'voided', '撤销历史', ?, ?)
                """, arguments: [paymentID.uuidString, profile.id.uuidString, liabilityID.uuidString, cycleID.uuidString, cashID.uuidString, now, recordID.uuidString, now, now])
            try db.execute(sql: """
                INSERT INTO local_account_entries (id, profile_id, account_id, direction, amount_minor, entry_kind,
                    source_kind, source_id, occurred_at, voided_at)
                VALUES (?, ?, ?, 'out', 20, 'expense', 'expense', ?, ?, NULL),
                       (?, ?, ?, 'out', 1000, 'expense', 'expense', ?, ?, ?),
                       (?, ?, ?, 'out', 3000, 'transfer', 'liability_payment', ?, ?, ?),
                       (?, ?, ?, 'in', 3000, 'transfer', 'liability_payment', ?, ?, ?),
                       (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    UUID().uuidString, profile.id.uuidString, cashID.uuidString, expenseID.uuidString, now,
                    UUID().uuidString, profile.id.uuidString, cashID.uuidString, deletedExpenseID.uuidString, now, deletedAt,
                    UUID().uuidString, profile.id.uuidString, cashID.uuidString, paymentID.uuidString, now, deletedAt,
                    UUID().uuidString, profile.id.uuidString, liabilityID.uuidString, paymentID.uuidString, now, deletedAt,
                    UUID().uuidString, profile.id.uuidString, cashID.uuidString, "in", 500, "snapshot_initialization", "wallet_snapshot", UUID().uuidString, now, NSNull()
                ])
        }
        fixture.profileID = profile.id
        fixture.createdAt = now
        fixture.cashID = cashID
        fixture.liabilityID = liabilityID
        fixture.expenseID = expenseID
        fixture.recordImage = recordImage
        return fixture
    }

    private func makeEmptyFixture() throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-complete-backup-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("local.sqlite")
        let imageDirectory = directory.appendingPathComponent("images", isDirectory: true)
        let database = try LocalDatabase(databaseURL: databaseURL)
        let imageStore = try LocalImageStore(rootDirectory: imageDirectory)
        let profileStore = LocalProfileStore(database: database)
        let portability = LocalCompleteBackupPortability(database: database, imageStore: imageStore)
        return Fixture(
            directory: directory, database: database, imageStore: imageStore,
            profileStore: profileStore, portability: portability, cashID: UUID(),
            liabilityID: UUID(), expenseID: UUID(), recordImage: LocalImageReference(path: "", hash: "")
        )
    }

    private func cleanup(_ fixture: Fixture) { try? FileManager.default.removeItem(at: fixture.directory) }

    private func imageFiles(in directory: URL) throws -> [String] {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey])
        return try (enumerator?.allObjects as? [URL] ?? []).filter {
            try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
        }.map(\.lastPathComponent).sorted()
    }

    private func tamper(
        _ data: Data,
        change: (inout [String: String]) throws -> Void
    ) throws -> Data {
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var tables = try XCTUnwrap(archive["tables"] as? [String: String])
        try change(&tables)
        archive["tables"] = tables
        return try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])
    }

    private static func tableRows(_ table: String, in tables: [String: String]) throws -> [[String: Any]] {
        let encoded = try XCTUnwrap(tables[table])
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [[String: Any]])
    }

    private static func encodeRows(_ rows: [[String: Any]]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]), as: UTF8.self)
    }

    private final class Fixture {
        let directory: URL
        let imageDirectory: URL
        let database: LocalDatabase
        let imageStore: LocalImageStore
        let profileStore: LocalProfileStore
        let portability: LocalCompleteBackupPortability
        var profileID = UUID()
        var createdAt = Date(timeIntervalSince1970: 0)
        var cashID: UUID
        var liabilityID: UUID
        var expenseID: UUID
        var recordImage: LocalImageReference

        init(
            directory: URL, database: LocalDatabase, imageStore: LocalImageStore,
            profileStore: LocalProfileStore, portability: LocalCompleteBackupPortability,
            cashID: UUID, liabilityID: UUID, expenseID: UUID, recordImage: LocalImageReference
        ) {
            self.directory = directory
            self.imageDirectory = directory.appendingPathComponent("images", isDirectory: true)
            self.database = database
            self.imageStore = imageStore
            self.profileStore = profileStore
            self.portability = portability
            self.cashID = cashID
            self.liabilityID = liabilityID
            self.expenseID = expenseID
            self.recordImage = recordImage
        }
    }
}
