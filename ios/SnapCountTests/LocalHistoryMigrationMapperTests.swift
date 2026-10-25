import XCTest
@testable import SnapCount

final class LocalHistoryMigrationMapperTests: XCTestCase {
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
}
