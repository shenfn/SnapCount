import Foundation
import GRDB
import XCTest
@testable import SnapCount

final class LocalCompleteBackupPortabilityTests: XCTestCase {
    func testLF024MigrationPreservesOldExpenseBeforeAllowingUnboundRecords() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("old.sqlite")
        let queue = try DatabaseQueue(path: url.path)
        try LocalDatabase.migrator.migrate(queue, upTo: "local-v21-history-migration-checkpoint")
        let profile = UUID(), account = UUID(), expense = UUID()
        try queue.write { db in
            try db.execute(sql: "INSERT INTO local_profiles(id, created_at) VALUES (?, ?)", arguments: [profile.uuidString, Date()])
            try db.execute(sql: "INSERT INTO local_accounts(id, profile_id, name, kind, currency, opening_balance_minor, created_at) VALUES (?, ?, 'synthetic', 'cash', 'CNY', 10000, ?)", arguments: [account.uuidString, profile.uuidString, Date()])
            try db.execute(sql: "INSERT INTO local_expenses(id, profile_id, account_id, amount_minor, currency, merchant_name, platform, category, payment_method, transaction_date, created_at, updated_at) VALUES (?, ?, ?, 2000, 'CNY', 'synthetic', '', 'other', 'cash', '2026-10-25', ?, ?)", arguments: [expense.uuidString, profile.uuidString, account.uuidString, Date(), Date()])
        }
        for _ in 0..<2 {
            let database = try LocalDatabase(databaseURL: url)
            let preserved = try XCTUnwrap(try LocalExpenseRepository(database: database).expense(id: expense))
            XCTAssertEqual(preserved.amountMinor, 2000)
            XCTAssertEqual(preserved.accountID, account)
            XCTAssertNil(preserved.imagePath)
            try database.writer.read { db in
                XCTAssertTrue(try Row.fetchAll(db, sql: "PRAGMA foreign_key_check").isEmpty)
            }
        }
    }

    func testLF036FinancialOriginalSurvivesCreateEditAndReopen() async throws {
        let fixture = try makeEmptyFixture()
        defer { cleanup(fixture) }
        let repository = try LocalExpenseRepository(database: fixture.database)
        let useCase = LocalExpenseUseCase(profileStore: fixture.profileStore, repository: repository, imageStore: fixture.imageStore)
        let bytes = Data("synthetic-income-original".utf8)
        let income = try await useCase.createIncome(LocalIncomeCommand(id: UUID(), accountID: nil,
            amountText: "20", currency: "CNY", sourceName: "合成收入", category: "其他",
            incomeDate: "2026-10-25", occurredAt: nil, note: nil, createdAt: Date(), imageData: bytes))
        let path = try XCTUnwrap(income.imagePath)
        XCTAssertEqual(try fixture.imageStore.data(at: path), bytes)
        let reopened = try LocalExpenseRepository(database: LocalDatabase(databaseURL: fixture.directory.appendingPathComponent("local.sqlite")))
        XCTAssertEqual(try reopened.income(id: income.id)?.imageHash, LocalImageStore.sha256(bytes))
        let edited = try await useCase.updateIncome(LocalIncomeUpdate(id: income.id, profileID: income.profileID,
            expectedVersion: income.localVersion, accountID: nil, amountMinor: 3000, currency: "CNY",
            sourceName: "合成收入", category: "其他", incomeDate: "2026-10-25", occurredAt: nil,
            note: "edited", updatedAt: Date()))
        XCTAssertEqual(edited.imagePath, path)
        let cleared = try await useCase.updateIncome(LocalIncomeUpdate(id: income.id, profileID: income.profileID,
            expectedVersion: edited.localVersion, accountID: nil, amountMinor: 3000, currency: "CNY",
            sourceName: "合成收入", category: "其他", incomeDate: "2026-10-25", occurredAt: nil,
            note: nil, updatedAt: Date(), removeImage: true))
        XCTAssertNil(cleared.imagePath)
        let cleanupRows = try LocalRecordRepository(database: fixture.database).pendingImageCleanups(profileID: income.profileID)
        XCTAssertTrue(cleanupRows.contains { $0.imagePath == path })
    }

    func testLF02104DanglingLedgerSourceCannotBeRestored() throws {
        let source = try makeFixture()
        defer { cleanup(source) }
        let backup = try tamper(source.portability.exportBackup()) { tables in
            var entries = try Self.tableRows("local_account_entries", in: tables)
            entries[0]["source_id"] = UUID().uuidString
            tables["local_account_entries"] = try Self.encodeRows(entries)
        }
        XCTAssertThrowsError(try source.portability.preview(backup))
    }

    func testLF03601FinancialImageReferencesSurviveCompleteBackup() throws {
        let source = try makeFixture()
        defer { cleanup(source) }
        let bytes = Data("synthetic-financial-original".utf8)
        let image = try source.imageStore.save(data: bytes, owner: UUID().uuidString)
        try source.database.writer.write { db in
            try db.execute(sql: "UPDATE local_income_records SET image_path = ?, image_hash = ?", arguments: [image.path, image.hash])
        }
        let backup = try source.portability.exportBackup()
        XCTAssertEqual(try source.portability.preview(backup).imageCount, 4)
        let target = try makeEmptyFixture()
        defer { cleanup(target) }
        _ = try target.portability.importBackup(backup, into: target.profileStore.activeProfile().id)
        XCTAssertEqual(try target.imageStore.data(at: image.path), bytes)
    }

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

    func testLF021CompleteBackupPreservesWalletSnapshotRepaymentEvidence() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let profile = try source.profileStore.activeProfile()
        let snapshotID = UUID()
        let snapshot = try LocalWalletSnapshotRepository(database: source.database).create(LocalWalletSnapshotDraft(
            id: snapshotID,
            profileID: profile.id,
            title: "账单证据",
            summary: "备份关联验证",
            payloadJSON: try LocalRecordCodec.encode(["cycle_month": AnyCodable("2026-10")]),
            recordDate: "2026-10-25",
            recordTime: nil,
            occurredAt: nil,
            balanceMinor: 10_000,
            currency: "CNY",
            kind: .liability,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date()
        ))
        let cycle = try XCTUnwrap(LocalExpenseRepository(database: source.database).repaymentCycles(accountID: source.liabilityID).first)
        try source.database.writer.write { db in
            try db.execute(sql: """
                UPDATE local_repayment_cycles
                SET evidence_record_id = NULL, evidence_wallet_snapshot_id = ?
                WHERE id = ?
                """, arguments: [snapshot.id.uuidString, cycle.id.uuidString])
        }

        let backup = try source.portability.exportBackup()
        let targetProfile = try target.profileStore.activeProfile()
        _ = try target.portability.importBackup(backup, into: targetProfile.id)
        let restored = try XCTUnwrap(
            LocalExpenseRepository(database: target.database).repaymentCycles(accountID: source.liabilityID).first
        )

        XCTAssertEqual(restored.evidenceWalletSnapshotID, snapshotID)
        XCTAssertNil(restored.evidenceRecordID)
        XCTAssertTrue(try LocalWalletSnapshotRepository(database: target.database).history(profileID: targetProfile.id).map(\.id).contains(snapshotID))
    }

    func testLF021BackupPreservesConfirmedScreenshotPaymentAndOriginalImage() async throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let profile = try XCTUnwrap(source.profileID)
        let cycle = try XCTUnwrap(
            LocalExpenseRepository(database: source.database).repaymentCycles(accountID: source.liabilityID).first
        )
        try await source.database.writer.write { db in
            try db.execute(sql: """
                UPDATE local_repayment_cycles
                SET paid_amount_minor = 0, remaining_amount_minor = statement_amount_minor,
                    status = 'pending', source = 'manual'
                WHERE id = ?
                """, arguments: [cycle.id.uuidString])
        }
        let imageData = Data("synthetic-confirmed-repayment-evidence".utf8)
        let recordUseCase = LocalRecordUseCase(
            profileStore: source.profileStore,
            repository: try LocalRecordRepository(database: source.database),
            imageStore: source.imageStore
        )
        let candidate = try await recordUseCase.stage(LocalRecordCandidate(
            id: "backup-screenshot-\(UUID().uuidString)", domainKey: "wallet",
            title: "合成已还款截图", summary: "备份证据关联",
            payload: [
                "record_kind": AnyCodable("liability_snapshot"),
                "status": AnyCodable("paid"),
                "amount": AnyCodable(20.0)
            ],
            confidence: 0.9, recordDate: "2026-10-25", recordTime: nil,
            imageData: imageData, createdAt: Date()
        ))
        _ = try await LocalExpenseUseCase(
            profileStore: source.profileStore,
            repository: LocalExpenseRepository(database: source.database)
        ).confirmScreenshotRepayment(
            stagingID: candidate.record.id, cycleID: cycle.id, paidAmountMinor: 2_000,
            debitAccountID: source.cashID, note: "备份截图还款", paidAt: Date()
        )

        let backup = try source.portability.exportBackup()
        let preview = try source.portability.preview(backup)
        XCTAssertEqual(preview.schemaVersion, LocalCompleteBackupPortability.currentSchemaVersion)
        XCTAssertEqual(preview.imageCount, 4)
        let targetProfile = try target.profileStore.activeProfile()
        _ = try target.portability.importBackup(backup, into: targetProfile.id)

        let payment = try XCTUnwrap(LocalExpenseRepository(database: target.database)
            .liabilityPayments(accountID: source.liabilityID)
            .first(where: { $0.source == "screenshot" }))
        let evidenceStagingIDValue = try await target.database.writer.read { db in
            try String.fetchOne(
                db,
                sql: "SELECT evidence_staging_id FROM local_liability_payments WHERE id = ?",
                arguments: [payment.id.uuidString]
            )
        }
        let evidenceStagingID = try XCTUnwrap(evidenceStagingIDValue)
        XCTAssertEqual(evidenceStagingID, candidate.record.id)
        let targetRecordUseCase = LocalRecordUseCase(
            profileStore: target.profileStore,
            repository: try LocalRecordRepository(database: target.database),
            imageStore: target.imageStore
        )
        let restoredCandidateMaybe = try await targetRecordUseCase.staging(id: evidenceStagingID)
        let restoredCandidate = try XCTUnwrap(restoredCandidateMaybe)
        XCTAssertEqual(restoredCandidate.status, .archived)
        XCTAssertEqual(try target.imageStore.data(at: try XCTUnwrap(restoredCandidate.imagePath)), imageData)
    }

    func testLF02109And11RestoreKeepsWakeDateDeletionAndLedgerProjection() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let sourceProfile = try XCTUnwrap(source.profileID)
        let sleepID = UUID()
        let sleepPayload = [
            "sleep_minutes": AnyCodable(420),
            "wake_at": AnyCodable("2026-09-30T16:30:00Z")
        ]
        _ = try LocalRecordRepository(database: source.database).createRecord(LocalRecordDraft(
            id: sleepID,
            profileID: sourceProfile,
            domainKey: "sleep",
            title: "跨月睡眠",
            summary: "按醒来日统计",
            payloadJSON: try LocalRecordCodec.encode(sleepPayload),
            recordDate: "2026-11-10",
            recordTime: nil,
            note: nil,
            imagePath: nil,
            imageHash: nil,
            createdAt: Date()
        ))

        let backup = try source.portability.exportBackup()
        let targetProfile = try target.profileStore.activeProfile()
        _ = try target.portability.importBackup(backup, into: targetProfile.id)

        let reader = try LocalFactReader(database: target.database)
        let octoberFacts = try reader.range(
            profileID: targetProfile.id,
            from: "2026-10-01",
            to: "2026-10-31"
        ).facts
        let restoredSleep = try XCTUnwrap(octoberFacts.first { $0.id == sleepID })
        XCTAssertEqual(restoredSleep.businessDate, "2026-10-01")
        XCTAssertTrue(try reader.range(
            profileID: targetProfile.id,
            from: "2026-11-01",
            to: "2026-11-30"
        ).facts.allSatisfy { $0.id != sleepID })

        let rows = LocalInsightAggregator.rows(from: octoberFacts)
        let daily = try XCTUnwrap(rows.first { $0.date == "2026-10-25" })
        XCTAssertEqual(daily.expenseTotal, 0.20, accuracy: 0.0001)
        XCTAssertEqual(daily.expenseCount, 1)
        XCTAssertEqual(daily.incomeTotal, 35, accuracy: 0.0001)
        XCTAssertEqual(daily.incomeCount, 1)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.expenseTotal }, 0.20, accuracy: 0.0001)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.incomeTotal }, 35, accuracy: 0.0001)
        let deletedExpenseID = UUID(uuidString: "00000000-0000-4000-8000-000000000005")!
        XCTAssertFalse(octoberFacts.contains { $0.id == deletedExpenseID })
        XCTAssertEqual(try LocalExpenseRepository(database: target.database).accountBalanceMinor(accountID: source.cashID), 480)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_outbox_operations"), 0)
    }

    func testLF021SupportsVersion17DeletedWalletTombstoneWithoutArchivedImage() async throws {
        let source = try makeEmptyFixture()
        defer { cleanup(source) }
        let walletRepository = LocalWalletSnapshotRepository(database: source.database)
        let useCase = LocalWalletSnapshotUseCase(
            profileStore: source.profileStore,
            repository: walletRepository,
            imageStore: source.imageStore
        )
        let snapshot = try await useCase.create(LocalWalletSnapshotCommand(
            id: UUID(), title: "旧备份删除快照", summary: "v17行为兼容",
            payload: ["account_type": AnyCodable("cash")],
            recordDate: "2026-10-24", recordTime: nil, occurredAt: nil,
            balanceMinor: 500, currency: "CNY", kind: .asset,
            imageData: Data("synthetic legacy tombstone image".utf8), createdAt: Date()
        ))
        _ = try await useCase.delete(snapshot)
        let currentBackup = try source.portability.exportBackup()
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: currentBackup) as? [String: Any])
        archive["schemaVersion"] = 17
        archive["images"] = [[String: Any]]()
        let version17Backup = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])

        let target = try makeEmptyFixture()
        defer { cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let preview = try target.portability.preview(version17Backup)
        XCTAssertEqual(preview.imageCount, 0)
        let imported = try target.portability.importBackup(version17Backup, into: targetProfile.id)
        XCTAssertEqual(imported.insertedRows, preview.totalRows)
        let restored = try XCTUnwrap(
            LocalWalletSnapshotRepository(database: target.database).history(profileID: targetProfile.id).first
        )
        XCTAssertNotNil(restored.deletedAt)
        XCTAssertEqual(restored.id, snapshot.id)
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

    func testLF02110ResumeAfterImagesWereWrittenBeforeDatabaseCommit() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let backup = try source.portability.exportBackup()
        let archive = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        let images = try XCTUnwrap(archive["images"] as? [[String: Any]])

        // A terminated import can leave atomically written, content-addressed files while the DB transaction rolls back.
        for image in images {
            let path = try XCTUnwrap(image["path"] as? String)
            let hash = try XCTUnwrap(image["hash"] as? String)
            let encoded = try XCTUnwrap(image["data"] as? String)
            let data = try XCTUnwrap(Data(base64Encoded: encoded))
            XCTAssertTrue(try target.imageStore.restore(data: data, at: path, expectedHash: hash))
        }
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_records"), 0)

        let preview = try target.portability.preview(backup)
        let imported = try target.portability.importBackup(backup, into: targetProfile.id)
        XCTAssertEqual(imported.insertedRows, preview.totalRows)
        XCTAssertEqual(imported.skippedRows, 0)
        XCTAssertEqual(imported.restoredImages, 0)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory).count, images.count)

        let repeated = try target.portability.importBackup(backup, into: targetProfile.id)
        XCTAssertEqual(repeated.insertedRows, 0)
        XCTAssertEqual(repeated.skippedRows, preview.totalRows)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 2)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory).count, images.count)
    }

    func testLF02110ImageWriteFailureRemovesEarlierFilesAndLeavesDatabaseUnchanged() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let targetProfile = try target.profileStore.activeProfile()
        let backup = try source.portability.exportBackup()
        let earlierPath = LocalImageStore.relativePath(owner: "recognition-\(source.profileID.uuidString)-\(LocalImageStore.sha256(Data("backup-intake-image".utf8)))", bucket: "intake")
        let laterPath = LocalImageStore.relativePath(owner: "candidate-1", bucket: "staging")
        let blocker = Data("existing file that conflicts with archive image".utf8)
        let blockerURL = target.imageStore.url(for: laterPath)
        try FileManager.default.createDirectory(
            at: blockerURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try blocker.write(to: blockerURL)

        XCTAssertThrowsError(try target.portability.importBackup(backup, into: targetProfile.id))

        XCTAssertFalse(target.imageStore.contains(path: earlierPath))
        XCTAssertTrue(target.imageStore.contains(path: laterPath))
        XCTAssertEqual(try target.imageStore.data(at: laterPath), blocker)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_accounts"), 0)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_records"), 0)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 0)
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
        XCTAssertEqual(try count(fixture.database, "SELECT COUNT(*) FROM local_records WHERE image_path = '\(recordImagePath)'"), 1)
        XCTAssertFalse(fixture.imageStore.contains(path: recordImagePath))
    }

    func testLF02104MalformedAndDuplicateBackupsAreRejectedWithoutPartialWrites() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let backup = try source.portability.exportBackup()
        let targetProfile = try target.profileStore.activeProfile()

        XCTAssertThrowsError(try target.portability.preview(Data("{".utf8))) { error in
            XCTAssertEqual(error as? LocalCompleteBackupError, .invalidFormat)
        }

        let duplicate = try tamper(backup) { tables in
            var expenses = try Self.tableRows("local_expenses", in: tables)
            expenses.append(try XCTUnwrap(expenses.first))
            tables["local_expenses"] = try Self.encodeRows(expenses)
        }
        XCTAssertThrowsError(try target.portability.importBackup(duplicate, into: targetProfile.id)) { error in
            guard case LocalCompleteBackupError.duplicateID = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        var badImageArchive = try XCTUnwrap(JSONSerialization.jsonObject(with: backup) as? [String: Any])
        var images = try XCTUnwrap(badImageArchive["images"] as? [[String: Any]])
        images[0]["hash"] = String(repeating: "0", count: 64)
        badImageArchive["images"] = images
        let badImageHash = try JSONSerialization.data(withJSONObject: badImageArchive, options: [.sortedKeys])
        XCTAssertThrowsError(try target.portability.importBackup(badImageHash, into: targetProfile.id)) { error in
            guard case LocalCompleteBackupError.invalidImage = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        images[0]["path"] = "../outside.jpg"
        badImageArchive["images"] = images
        let unsafeImagePath = try JSONSerialization.data(withJSONObject: badImageArchive, options: [.sortedKeys])
        XCTAssertThrowsError(try target.portability.importBackup(unsafeImagePath, into: targetProfile.id)) { error in
            guard case LocalCompleteBackupError.invalidImage = error else {
                return XCTFail("unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_accounts"), 0)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 0)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_account_entries"), 0)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory), [])
    }

    func testLF02104InvalidExpenseAmountAndDanglingAccountFailPreflight() throws {
        let source = try makeFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let backup = try source.portability.exportBackup()
        let targetProfile = try target.profileStore.activeProfile()

        let invalidAmount = try tamper(backup) { tables in
            var expenses = try Self.tableRows("local_expenses", in: tables)
            expenses[0]["amount_minor"] = -1
            tables["local_expenses"] = try Self.encodeRows(expenses)
        }
        XCTAssertThrowsError(try target.portability.importBackup(invalidAmount, into: targetProfile.id)) { error in
            XCTAssertEqual(error as? LocalCompleteBackupError, .invalidRows("local_expenses"))
        }

        let nonNumericAmount = try tamper(backup) { tables in
            var expenses = try Self.tableRows("local_expenses", in: tables)
            expenses[0]["amount_minor"] = true
            tables["local_expenses"] = try Self.encodeRows(expenses)
        }
        XCTAssertThrowsError(try target.portability.importBackup(nonNumericAmount, into: targetProfile.id)) { error in
            XCTAssertEqual(error as? LocalCompleteBackupError, .invalidRows("local_expenses"))
        }

        let danglingAccount = try tamper(backup) { tables in
            var expenses = try Self.tableRows("local_expenses", in: tables)
            expenses[0]["account_id"] = UUID().uuidString
            tables["local_expenses"] = try Self.encodeRows(expenses)
        }
        XCTAssertThrowsError(try target.portability.importBackup(danglingAccount, into: targetProfile.id)) { error in
            XCTAssertEqual(error as? LocalCompleteBackupError, .invalidRows("local_expenses"))
        }

        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_accounts"), 0)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_expenses"), 0)
        XCTAssertEqual(try imageFiles(in: target.imageDirectory), [])
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

    func testLF02111Version15CompleteBackupRemainsImportableAfterWalletTableWasAdded() throws {
        let source = try makeEmptyFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let currentData = try source.portability.exportBackup()
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: currentData) as? [String: Any])
        var tables = try XCTUnwrap(archive["tables"] as? [String: String])
        XCTAssertNotNil(tables.removeValue(forKey: "local_wallet_snapshots"))
        archive["tables"] = tables
        archive["schemaVersion"] = 15
        let version15 = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])

        let preview = try target.portability.preview(version15)
        XCTAssertEqual(preview.schemaVersion, 15)
        XCTAssertEqual(preview.tableCounts["local_wallet_snapshots"], 0)
        let targetProfile = try target.profileStore.activeProfile()
        let imported = try target.portability.importBackup(version15, into: targetProfile.id)
        XCTAssertEqual(imported.insertedRows, preview.totalRows)
        XCTAssertEqual(try count(target.database, "SELECT COUNT(*) FROM local_wallet_snapshots"), 0)
    }

    func testLF02111Version16BackupImportsWalletRowsWithoutLinkedActionColumn() async throws {
        let source = try makeEmptyFixture()
        let target = try makeEmptyFixture()
        defer { cleanup(source); cleanup(target) }
        let sourceProfile = try source.profileStore.activeProfile()
        let wallets = LocalWalletSnapshotRepository(database: source.database)
        _ = try await LocalWalletSnapshotUseCase(
            profileStore: source.profileStore,
            repository: wallets
        ).create(LocalWalletSnapshotCommand(
            id: UUID(), title: "微信零钱", summary: "余额快照",
            payload: ["account_type": AnyCodable("wechat"), "snapshot_balance": AnyCodable(12.34)],
            recordDate: "2026-10-25", recordTime: nil, occurredAt: nil,
            balanceMinor: 1_234, currency: "CNY", kind: .asset,
            imageData: nil, createdAt: Date()
        ))
        var archive = try XCTUnwrap(JSONSerialization.jsonObject(with: source.portability.exportBackup()) as? [String: Any])
        var tables = try XCTUnwrap(archive["tables"] as? [String: String])
        var walletRows = try Self.tableRows("local_wallet_snapshots", in: tables)
        XCTAssertEqual(walletRows.count, 1)
        walletRows[0].removeValue(forKey: "linked_action")
        tables["local_wallet_snapshots"] = try Self.encodeRows(walletRows)
        archive["tables"] = tables
        archive["schemaVersion"] = 16
        let version16 = try JSONSerialization.data(withJSONObject: archive, options: [.sortedKeys])

        let preview = try target.portability.preview(version16)
        XCTAssertEqual(preview.schemaVersion, 16)
        XCTAssertEqual(preview.tableCounts["local_wallet_snapshots"], 1)
        let targetProfile = try target.profileStore.activeProfile()
        let imported = try target.portability.importBackup(version16, into: targetProfile.id)

        XCTAssertEqual(imported.insertedRows, preview.totalRows)
        let restored = try XCTUnwrap(LocalWalletSnapshotRepository(database: target.database)
            .unlinked(profileID: targetProfile.id).first)
        XCTAssertNil(restored.linkedAction)
        XCTAssertEqual(restored.balanceMinor, 1_234)
        XCTAssertNotEqual(targetProfile.id, sourceProfile.id)
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
        let openingSnapshotID = UUID(uuidString: "00000000-0000-4000-8000-000000000009")!
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
                    UUID().uuidString, profile.id.uuidString, cashID.uuidString, "in", 500, "snapshot_initialization", "wallet_snapshot", openingSnapshotID.uuidString, now, NSNull()
                ])
            try db.execute(sql: """
                INSERT INTO local_wallet_snapshots(id,profile_id,title,summary,payload_json,record_date,
                    snapshot_balance_minor,currency,account_snapshot_kind,linked_account_id,linked_action,created_at,updated_at)
                VALUES (?,?,'期初快照','合成来源','{}','2026-10-25',500,'CNY','asset',?,'create',?,?)
                """, arguments: [openingSnapshotID.uuidString, profile.id.uuidString, cashID.uuidString, now, now])
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
