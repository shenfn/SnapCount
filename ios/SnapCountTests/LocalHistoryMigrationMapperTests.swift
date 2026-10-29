import XCTest
@testable import SnapCount

final class LocalHistoryMigrationMapperTests: XCTestCase {
    func testHistoryMoneyParserNormalizesEverySourceNumberType() throws {
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(8.54), 854)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(NSNumber(value: 8.54)), 854)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue("8.54"), 854)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(0.07), 7)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(99.9), 9990)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(20), 2000)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(-12.34), -1234)
        XCTAssertEqual(try LocalHistorySourceCompatibility.minorValue(Int64(9_223_372_036_854_775)),
                       922_337_203_685_477_500)
    }

    func testHistoryMoneyParserRejectsUnsafeAmounts() {
        let invalid: [Any] = [8.545, 8.546, Double.nan, Double.infinity, 1e19, true, "", NSNull()]
        for value in invalid {
            XCTAssertThrowsError(try LocalHistorySourceCompatibility.minorValue(value), "\(value)")
        }
        // 8.540000000000001 是存储层不可能出现的 11 位尾数，宁可阻塞也不放宽到分。
        XCTAssertThrowsError(try LocalHistorySourceCompatibility.minorValue(8.540000000000001))
        XCTAssertFalse(LocalHistorySourceCompatibility.validWalletBalance(-0.01))
        XCTAssertTrue(LocalHistorySourceCompatibility.validWalletBalance(8.54))
    }

    /// 线上失败值：accounts.initial_balance = 8.54，错误码 HIST-LOCAL-DATA。
    func testHistoryArchiveMapsTwoDecimalAccountBalance() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID()
        let account = UUID()
        let entry = UUID()
        let timestamp = "2026-05-28T15:57:02.937968+00:00"
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [row([
                "id": account.uuidString, "user_id": user.uuidString, "name": "微信余额",
                "type": "wallet_balance", "currency": "CNY", "initial_balance": 8.54,
                "current_balance": 8.54, "institution": "微信余额", "last4": NSNull(),
                "created_at": timestamp, "updated_at": timestamp,
                "auto_confirm_repayment": false, "grace_period_days": 0,
                "is_default_expense": false, "is_default_income": false,
                "is_archived": false, "sort_order": 0
            ])],
            .accountEntries: [row([
                "id": entry.uuidString, "user_id": user.uuidString, "account_id": account.uuidString,
                "amount": 8.54, "direction": "in", "entry_type": "snapshot_initialization",
                "is_voided": false, "occurred_at": "2026-05-28T04:00:00+00:00",
                "created_at": "2026-05-28T15:57:04.205121+00:00"
            ])]
        ], blockers: [])

        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            inspection, profileID: UUID(), images: [:])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        let accounts = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_accounts"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(accounts[0]["kind"] as? String, "wallet_balance")
        XCTAssertEqual(accounts[0]["opening_balance_minor"] as? Int, 854)
        let entries = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_account_entries"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0]["amount_minor"] as? Int, 854)
    }

    func testLF03926MissingImageDoesNotBlockMappableRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        let user = UUID()
        let record = UUID()
        let profile = try LocalProfileStore(database: schema).activeProfile().id
        let rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [
            .records: [[
                "id": AnyCodable(record.uuidString), "user_id": AnyCodable(user.uuidString),
                "domain_key": AnyCodable("food"), "domain_version": AnyCodable("1.0"),
                "title": AnyCodable("缺图历史记录"), "summary": AnyCodable("保留结构化事实"),
                "payload_jsonb": AnyCodable(["meal_type": "lunch", "total_calorie_kcal": 500]),
                "occurred_at": AnyCodable("2026-05-04T12:00:00Z"),
                "created_at": AnyCodable("2026-05-04T12:00:00Z"),
                "updated_at": AnyCodable("2026-05-04T12:00:00Z"),
                "source_image_path": AnyCodable("2026-05-04/missing.jpg")
            ]]
        ]
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: rows, blockers: [])
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            inspection, profileID: profile, images: [:])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        let records = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_records"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(records.count, 1)
        XCTAssertNil(records[0]["image_path"] as? String)
    }

    func testLF03918UnknownDateAndUnroutedCandidateArePreservedWithoutFormalFacts() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), record = UUID(), candidate = UUID()
        let profile = try LocalProfileStore(database: schema).activeProfile()
        let bytes = Data("synthetic-history-photo".utf8)
        let sourcePath = user.uuidString.lowercased() + "/history.jpg"
        let rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [
            .records: [["id": AnyCodable(record.uuidString), "user_id": AnyCodable(user.uuidString),
                "domain_key": AnyCodable("food"), "payload_jsonb": AnyCodable(["legacy_fact": "保留原文"]),
                "source_image_path": AnyCodable(sourcePath), "source_image_hash": AnyCodable(LocalImageStore.sha256(bytes)),
                "occurred_at": AnyCodable(NSNull()), "created_at": AnyCodable("2026-10-24T10:00:00Z"),
                "updated_at": AnyCodable("2026-10-24T10:00:00Z")]],
            .staging: [["id": AnyCodable(candidate.uuidString), "user_id": AnyCodable(user.uuidString),
                "status": AnyCodable("unrouted"), "raw_text": AnyCodable("合成未识别截图"),
                "created_at": AnyCodable("2026-10-24T11:00:00Z"), "updated_at": AnyCodable("2026-10-24T11:00:00Z")]]
        ]
        XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(rows).isEmpty)
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: rows, blockers: []),
            profileID: profile.id, images: [sourcePath: bytes])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        let preservedJSON = try XCTUnwrap(tables["local_history_unresolved_records"])
        let preserved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(preservedJSON.utf8)) as? [[String: Any]])
        XCTAssertEqual(preserved.count, 2)
        XCTAssertEqual(tables["local_records"], "[]")
        XCTAssertEqual(tables["local_staging_records"], "[]")
        let raw = try XCTUnwrap(preserved.first { ($0["source_table"] as? String) == "data_records" }?["source_json"] as? String)
        let source = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any])
        XCTAssertTrue(source["occurred_at"] is NSNull)
        XCTAssertTrue(raw.contains("保留原文"))
        XCTAssertNil(preserved.first?["record_date"], "原文保全不能伪造业务日期")
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let portability = LocalCompleteBackupPortability(database: schema, imageStore: images)
        XCTAssertEqual(try portability.preview(archive).imageCount, 1)
        let result = try portability.importBackup(archive, into: profile.id)
        XCTAssertEqual(result.preservedRows, 2)
        _ = try portability.importBackup(archive, into: profile.id)
        let repository = LocalHistoryUnresolvedRepository(database: schema)
        XCTAssertEqual(try repository.count(profileID: profile.id), 2)
        let restored = try XCTUnwrap(repository.records(profileID: profile.id).first { $0.sourceID == record })
        XCTAssertEqual(try images.data(at: XCTUnwrap(restored.imagePath)), bytes)
        XCTAssertTrue(try LocalFactReader(database: schema).month(profileID: profile.id, monthKey: "2026-10").facts.isEmpty)
    }

    func testLF03919PreservedRecordReferencedByLedgerRemainsHardBlocked() throws {
        let record = UUID(), user = UUID()
        let rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [
            .records: [["id": AnyCodable(record.uuidString), "user_id": AnyCodable(user.uuidString),
                "domain_key": AnyCodable("wallet"), "occurred_at": AnyCodable(NSNull()),
                "created_at": AnyCodable("2026-10-24T10:00:00Z"), "updated_at": AnyCodable("2026-10-24T10:00:00Z")]],
            .accountEntries: [["source_table": AnyCodable("data_records"), "source_id": AnyCodable(record.uuidString)]]
        ]
        XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(rows).contains { $0.contains("financial_reference") })
        var withoutSourceTime = rows
        withoutSourceTime[.records]?[0].removeValue(forKey: "updated_at")
        XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(withoutSourceTime).contains { $0.contains("updated_at") })
    }

    func testLF03917WalletUsesLegacyPayloadOnlyWhenTopLevelValueIsAbsent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), profile = try LocalProfileStore(database: schema).activeProfile().id
        let imageStore = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let portability = LocalCompleteBackupPortability(database: schema, imageStore: imageStore)
        for (top, expected) in [(NSNull() as Any, 12345), (200 as Any, 20000)] {
            let record = UUID()
            let values: [String: Any] = [
                "id": record.uuidString, "user_id": user.uuidString, "domain_key": "wallet",
                "occurred_at": "2026-10-24T10:00:00Z", "created_at": "2026-10-24T10:00:00Z",
                "title": "合成历史钱包", "summary": "", "snapshot_balance": top,
                "account_snapshot_kind": NSNull(),
                "payload_jsonb": ["snapshot_balance": 123.45, "account_snapshot_kind": "asset", "currency": "CNY"]
            ]
            let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString,
                rows: [.records: [values.mapValues(AnyCodable.init)]], blockers: [])
            XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(inspection.rows).isEmpty)
            let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(inspection, profileID: profile, images: [:])
            let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
            let tables = try XCTUnwrap(root["tables"] as? [String: String])
            let json = try XCTUnwrap(tables["local_wallet_snapshots"])
            let wallets = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
            let wallet = try XCTUnwrap(wallets.first)
            XCTAssertEqual(wallet["snapshot_balance_minor"] as? Int, expected)
            XCTAssertEqual(wallet["account_snapshot_kind"] as? String, "asset")
            XCTAssertTrue((wallet["payload_json"] as? String)?.contains("snapshot_balance") == true)
            XCTAssertEqual(try portability.preview(archive).tableCounts["local_wallet_snapshots"], 1)
            _ = try portability.importBackup(archive, into: profile)
            _ = try portability.importBackup(archive, into: profile)
            let restored = try XCTUnwrap(LocalWalletSnapshotRepository(database: schema).history(profileID: profile).first { $0.id == record })
            XCTAssertEqual(restored.balanceMinor, Int64(expected))
            XCTAssertTrue(try LocalExpenseRepository(database: schema).accounts(profileID: profile).isEmpty)
        }
        XCTAssertEqual(try LocalWalletSnapshotRepository(database: schema).history(profileID: profile).count, 2)
    }

    func testLF03919MissingOccurredAtIsPreservedWithoutInventingBusinessDate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        let user = UUID(), record = UUID()
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .records: [
                [
                    "id": AnyCodable(record.uuidString),
                    "user_id": AnyCodable(user.uuidString),
                    "domain_key": AnyCodable("food"),
                    "domain_version": AnyCodable("1.0"),
                    "payload_jsonb": AnyCodable(["meal_type": "午餐", "total_calorie_kcal": 500]),
                    "occurred_at": AnyCodable(NSNull()),
                    "created_at": AnyCodable("2026-10-24T10:00:00Z"),
                    "updated_at": AnyCodable("2026-10-24T10:00:00Z")
                ]
            ]
        ], blockers: [])

        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            inspection, profileID: UUID(), images: [:]
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        XCTAssertEqual(tables["local_records"], "[]")
        let json = try XCTUnwrap(tables["local_history_unresolved_records"])
        let preserved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(preserved.count, 1)
        XCTAssertTrue((preserved.first?["issues_json"] as? String)?.contains("occurred_at") == true)
        XCTAssertNil(preserved.first?["record_date"])
    }

    func testLF039HistoryArchiveRestoresReconciledBalanceAndOriginalImage() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        let destination = try LocalDatabase(databaseURL: directory.appendingPathComponent("destination.sqlite"))
        let imageStore = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let profile = try LocalProfileStore(database: destination).activeProfile()
        let user = UUID(), account = UUID(), expense = UUID(), entry = UUID()
        let meal = UUID(), staged = UUID()
        let timestamp = "2026-10-24T00:30:00Z"
        let imagePath = "\(user.uuidString.lowercased())/original.jpg"
        let bytes = Data("synthetic-history-original".utf8)
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [row(["id": account.uuidString, "user_id": user.uuidString, "name": "现金",
                "type": "cash", "currency": "CNY", "initial_balance": 100, "current_balance": 80,
                "created_at": timestamp, "updated_at": timestamp])],
            .transactions: [row(["id": expense.uuidString, "user_id": user.uuidString,
                "account_id": account.uuidString, "type": "expense", "status": "done", "amount": 20,
                "merchant_name": "测试商户", "platform": "微信", "category": "food",
                "payment_method": "微信支付", "transaction_date": "2026-10-24", "transaction_time": "08:30",
                "created_at": timestamp, "updated_at": timestamp, "occurred_at": timestamp,
                "image_url": imagePath, "image_hash": LocalImageStore.sha256(bytes)])],
            .records: [row(["id": meal.uuidString, "user_id": user.uuidString,
                "domain_key": "food", "domain_version": "1.0", "title": "合成午餐", "summary": "500 kcal",
                "payload_jsonb": ["meal_type": "午餐", "total_calorie_kcal": 500],
                "occurred_at": timestamp, "created_at": timestamp, "updated_at": timestamp])],
            .staging: [row(["id": staged.uuidString, "user_id": user.uuidString,
                "detected_domain_key": "sport", "resolved_domain_key": "food", "target_kind": "data",
                "status": "archived", "target_record_id": meal.uuidString, "resolved_action": "archived",
                "extracted_json": ["record_date": "2026-10-24"], "ai_summary": "已更正分类的合成候选",
                "resolved_at": timestamp, "created_at": timestamp, "updated_at": timestamp])],
            .accountEntries: [row(["id": entry.uuidString, "user_id": user.uuidString,
                "account_id": account.uuidString, "direction": "out", "amount": 20,
                "entry_type": "expense", "source_table": "transactions", "source_id": expense.uuidString,
                "occurred_at": timestamp, "created_at": timestamp, "is_voided": false]),
                row(["id": UUID().uuidString, "user_id": user.uuidString,
                    "account_id": account.uuidString, "direction": "out", "amount": 99,
                    "entry_type": "expense", "source_table": "transactions", "source_id": expense.uuidString,
                    "occurred_at": timestamp, "created_at": timestamp, "is_voided": true])]
        ], blockers: [])
        let data = try LocalHistoryMigrationMapper(schema: schema).buildArchive(inspection,
            profileID: profile.id, images: [imagePath: bytes])
        let backup = LocalCompleteBackupPortability(database: destination, imageStore: imageStore)
        _ = try backup.preview(data)
        _ = try backup.importBackup(data, into: profile.id)
        let repository = try LocalExpenseRepository(database: destination)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 8000)
        let entries = try repository.accountEntries(accountID: account)
        XCTAssertEqual(entries.count, 2, "保留作废历史，不能丢行")
        let voided = try XCTUnwrap(entries.first(where: \.isVoided))
        XCTAssertNil(voided.voidedAt, "云端没有作废时间，不能伪造日期")
        let archived = try XCTUnwrap(try LocalRecordRepository(database: destination).staging(id: staged.uuidString))
        XCTAssertEqual(archived.domainKey, "food", "归档采用最终确认分类，不沿用识别猜测")
        XCTAssertEqual(archived.status, .archived)
        XCTAssertEqual(archived.targetRecordID, meal)
        let restored = try XCTUnwrap(repository.expense(id: expense))
        XCTAssertEqual(restored.transactionDate, "2026-10-24")
        XCTAssertEqual(restored.imageHash, LocalImageStore.sha256(bytes))
        XCTAssertEqual(try imageStore.data(at: XCTUnwrap(restored.imagePath)), bytes)
        _ = try backup.importBackup(data, into: profile.id)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 8000)
    }

    /// 线上有 40 笔交易的 merchant_name 为空；本机是 NOT NULL，不能因此整包拒绝。
    func testLF03927MissingMerchantNameImportsAsUnfilledInsteadOfBlocking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), account = UUID(), expense = UUID(), entry = UUID(), pending = UUID()
        let timestamp = "2026-10-24T00:30:00Z"
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [row(["id": account.uuidString, "user_id": user.uuidString, "name": "现金",
                "type": "cash", "currency": "CNY", "initial_balance": 100, "current_balance": 80,
                "created_at": timestamp, "updated_at": timestamp])],
            .transactions: [
                row(["id": expense.uuidString, "user_id": user.uuidString, "account_id": account.uuidString,
                    "type": "expense", "status": "done", "amount": 20, "merchant_name": NSNull(),
                    "platform": "微信", "category": "food", "payment_method": "微信支付",
                    "transaction_date": "2026-10-24", "created_at": timestamp, "updated_at": timestamp,
                    "occurred_at": timestamp]),
                row(["id": pending.uuidString, "user_id": user.uuidString, "account_id": account.uuidString,
                    "type": "expense", "status": "pending", "amount": 12, "merchant_name": NSNull(),
                    "platform": NSNull(), "category": NSNull(), "payment_method": NSNull(),
                    "transaction_date": "2026-10-25", "created_at": timestamp, "updated_at": timestamp])
            ],
            .accountEntries: [row(["id": entry.uuidString, "user_id": user.uuidString,
                "account_id": account.uuidString, "direction": "out", "amount": 20, "entry_type": "expense",
                "source_table": "transactions", "source_id": expense.uuidString,
                "occurred_at": timestamp, "created_at": timestamp, "is_voided": false])]
        ], blockers: [])
        XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(inspection.rows).isEmpty)

        let profile = try LocalProfileStore(database: schema).activeProfile().id
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(inspection, profileID: profile, images: [:])
        let backup = LocalCompleteBackupPortability(database: schema,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        _ = try backup.importBackup(archive, into: profile)

        let repository = try LocalExpenseRepository(database: schema)
        let restored = try XCTUnwrap(repository.expense(id: expense))
        XCTAssertEqual(restored.merchantName, "", "空值保留为空串，不编造商户名")
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account), 8000)
        XCTAssertEqual(try LocalPendingFinancialRepository(database: schema).pending(profileID: profile).count, 1)
    }

    /// 线上有 2 条候选的 target_record_id 已被云端删除；不能留成悬空引用拖垮整包。
    func testLF03928CandidateWithDeletedTargetIsPreservedWithoutBlocking() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), candidate = UUID()
        let profile = try LocalProfileStore(database: schema).activeProfile().id
        let rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [
            .staging: [["id": AnyCodable(candidate.uuidString), "user_id": AnyCodable(user.uuidString),
                "detected_domain_key": AnyCodable("reading"), "status": AnyCodable("archived"),
                "resolved_action": AnyCodable("archived"), "target_record_id": AnyCodable(UUID().uuidString),
                "extracted_json": AnyCodable(["record_date": "2026-10-20"]),
                "ai_summary": AnyCodable("目标已删除的历史候选"),
                "created_at": AnyCodable("2026-10-20T10:00:00Z"),
                "updated_at": AnyCodable("2026-10-20T10:00:00Z")]]
        ]
        XCTAssertTrue(LocalHistoryMigrationUseCase.blockers(rows).isEmpty)
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: rows, blockers: []),
            profileID: profile, images: [:])
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        XCTAssertEqual(tables["local_staging_records"], "[]")
        let preserved = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_history_unresolved_records"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(preserved.count, 1)
        XCTAssertTrue((preserved[0]["issues_json"] as? String)?.contains("target_record_id") == true)

        let backup = LocalCompleteBackupPortability(database: schema,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        let result = try backup.importBackup(archive, into: profile)
        XCTAssertEqual(result.preservedRows, 1)
    }

    /// 逐行错误必须一次报全，而不是改一条重启一次。
    func testLF03929MapperReportsEveryRejectedRowAtOnce() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), account = UUID()
        let timestamp = "2026-10-24T00:30:00Z"
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [row(["id": account.uuidString, "user_id": user.uuidString, "name": "现金",
                "type": "cash", "currency": "CNY", "initial_balance": 0, "current_balance": 0,
                "created_at": timestamp, "updated_at": timestamp])],
            .transactions: [1, 2].map { _ in
                row(["id": UUID().uuidString, "user_id": user.uuidString, "account_id": account.uuidString,
                    "type": "expense", "status": "done", "amount": 8.545, "merchant_name": "测试",
                    "platform": "微信", "category": "food", "payment_method": "微信支付",
                    "transaction_date": "2026-10-24", "created_at": timestamp, "updated_at": timestamp])
            }
        ], blockers: [])
        XCTAssertThrowsError(try LocalHistoryMigrationMapper(schema: schema).buildArchive(
            inspection, profileID: UUID(), images: [:])) { error in
            guard case .rows(let issues)? = error as? LocalHistoryMappingError else {
                return XCTFail("应汇总行级问题，实际：\(error)")
            }
            XCTAssertEqual(issues.count, 2)
        }
    }

    /// 影子导入与真实导入必须同源同结果。
    func testLF03930ShadowImportMatchesRealImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let destination = try LocalDatabase(databaseURL: directory.appendingPathComponent("destination.sqlite"))
        defer { try? destination.writer.close() }
        let user = UUID(), account = UUID(), expense = UUID()
        let timestamp = "2026-10-24T00:30:00Z"
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [row(["id": account.uuidString, "user_id": user.uuidString, "name": "现金",
                "type": "cash", "currency": "CNY", "initial_balance": 100, "current_balance": 80,
                "created_at": timestamp, "updated_at": timestamp])],
            .transactions: [row(["id": expense.uuidString, "user_id": user.uuidString,
                "account_id": account.uuidString, "type": "expense", "status": "done", "amount": 20,
                "merchant_name": "测试商户", "platform": "微信", "category": "food",
                "payment_method": "微信支付", "transaction_date": "2026-10-24",
                "created_at": timestamp, "updated_at": timestamp, "occurred_at": timestamp])],
            .accountEntries: [row(["id": UUID().uuidString, "user_id": user.uuidString,
                "account_id": account.uuidString, "direction": "out", "amount": 20, "entry_type": "expense",
                "source_table": "transactions", "source_id": expense.uuidString,
                "occurred_at": timestamp, "created_at": timestamp, "is_voided": false])]
        ], blockers: [])
        let profile = try LocalProfileStore(database: destination).activeProfile().id
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(inspection, profileID: profile, images: [:])
        let backup = LocalCompleteBackupPortability(database: destination,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        XCTAssertNoThrow(try backup.validateImport(archive, into: profile))

        // 把流水的来源改成一个不存在的 id：真实导入拒绝，影子导入必须同样拒绝。
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        var tables = try XCTUnwrap(root["tables"] as? [String: String])
        var entries = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_account_entries"]).utf8)) as? [[String: Any]])
        entries[0]["source_id"] = UUID().uuidString
        tables["local_account_entries"] = String(decoding: try JSONSerialization.data(withJSONObject: entries), as: UTF8.self)
        root["tables"] = tables
        let broken = try JSONSerialization.data(withJSONObject: root, options: [.sortedKeys])
        XCTAssertThrowsError(try backup.importBackup(broken, into: profile))
        XCTAssertThrowsError(try backup.validateImport(broken, into: profile))
    }

    /// 同一笔还款的资产侧与负债侧是两条流水（线上 4 组），本地唯一索引含 account_id，必须都能入账。
    func testLF03931RepaymentDualEntriesAcrossAccountsBothImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = try LocalDatabase(databaseURL: directory.appendingPathComponent("schema.sqlite"))
        defer { try? schema.writer.close() }
        let user = UUID(), asset = UUID(), liability = UUID()
        let cycle = UUID(), payment = UUID()
        let timestamp = "2026-10-24T00:30:00Z"
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user.uuidString, rows: [
            .accounts: [
                row(["id": asset.uuidString, "user_id": user.uuidString, "name": "储蓄卡",
                    "type": "debit_card", "currency": "CNY", "initial_balance": 100, "current_balance": 80,
                    "created_at": timestamp, "updated_at": timestamp]),
                row(["id": liability.uuidString, "user_id": user.uuidString, "name": "信用卡",
                    "type": "credit_line", "currency": "CNY", "initial_balance": 1000, "current_balance": 980,
                    "created_at": timestamp, "updated_at": timestamp])
            ],
            .repaymentCycles: [row(["id": cycle.uuidString, "user_id": user.uuidString,
                "account_id": liability.uuidString, "cycle_month": "2026-10", "status": "paid",
                "source": "manual", "statement_amount": 1000, "paid_amount": 20, "remaining_amount": 980,
                "carried_over_amount": 0, "created_at": timestamp, "updated_at": timestamp])],
            .payments: [row(["id": payment.uuidString, "user_id": user.uuidString,
                "account_id": liability.uuidString, "statement_id": cycle.uuidString,
                "debit_account_id": asset.uuidString, "amount": 20, "overpayment_amount": 0,
                "paid_at": timestamp, "source": "manual", "status": "confirmed",
                "created_at": timestamp, "updated_at": timestamp])],
            .accountEntries: [
                row(["id": UUID().uuidString, "user_id": user.uuidString, "account_id": liability.uuidString,
                    "direction": "out", "amount": 20, "entry_type": "transfer",
                    "source_table": "liability_payments", "source_id": payment.uuidString,
                    "occurred_at": timestamp, "created_at": timestamp, "is_voided": false]),
                row(["id": UUID().uuidString, "user_id": user.uuidString, "account_id": asset.uuidString,
                    "direction": "out", "amount": 20, "entry_type": "transfer",
                    "source_table": "liability_payments", "source_id": payment.uuidString,
                    "occurred_at": timestamp, "created_at": timestamp, "is_voided": false])
            ]
        ], blockers: [])
        let profile = try LocalProfileStore(database: schema).activeProfile().id
        let archive = try LocalHistoryMigrationMapper(schema: schema).buildArchive(inspection, profileID: profile, images: [:])
        let backup = LocalCompleteBackupPortability(database: schema,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        _ = try backup.importBackup(archive, into: profile)
        let repository = try LocalExpenseRepository(database: schema)
        XCTAssertEqual(try repository.accountEntries(accountID: asset).count, 1)
        XCTAssertEqual(try repository.accountEntries(accountID: liability).count, 1)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: asset), 8000)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: liability), 98000)
    }
}
