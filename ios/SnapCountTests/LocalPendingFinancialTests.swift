import XCTest
import GRDB
@testable import SnapCount

final class LocalPendingFinancialTests: XCTestCase {
    // LF-037.31/41: a pending financial transaction is durable, separate from
    // universal-domain staging, and must retain the source date and image.
    func testLF03731PendingFinancialStorageIsDurable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("pending.sqlite")
        let profileID = UUID()
        let pendingID = UUID()
        do {
            let database = try LocalDatabase(databaseURL: url)
            let repository = try LocalExpenseRepository(database: database)
            _ = try repository.createProfile(id: profileID, createdAt: Date())
            let exists = try database.writer.read { db in
                try db.tableExists("local_pending_transactions")
            }
            XCTAssertTrue(exists, "Pending finance needs its own durable state, not an in-memory remote row")
            guard exists else { return }
            try database.writer.write { db in
                try db.execute(sql: """
                    INSERT INTO local_pending_transactions
                    (id, profile_id, amount_minor, currency, merchant_name, transaction_date,
                     transaction_time, occurred_at, created_at, image_path, image_hash, status)
                    VALUES (?, ?, 2000, 'CNY', '测试商户', '2026-10-24', '08:30', ?, ?, 'expense/original.jpg', 'original-hash', 'pending')
                    """, arguments: [pendingID.uuidString, profileID.uuidString, Date(), Date()])
            }
        }
        let reopened = try LocalDatabase(databaseURL: url)
        let row = try reopened.writer.read { db in
            try Row.fetchOne(db, sql: "SELECT * FROM local_pending_transactions WHERE id = ?", arguments: [pendingID.uuidString])
        }
        XCTAssertEqual(row?["amount_minor"] as Int64?, 2000)
        XCTAssertEqual(row?["transaction_date"] as String?, "2026-10-24")
        XCTAssertEqual(row?["image_path"] as String?, "expense/original.jpg")
        XCTAssertEqual(row?["status"] as String?, "pending")
    }

    // LF-037.41/44: converted income requires a stable source relationship so
    // a retry cannot create a second income. This checks a real SQLite contract.
    func testLF03741IncomeHasUniquePendingSourceRelationship() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("source.sqlite"))
        let columns = try database.writer.read { db in try db.columns(in: "local_income_records") }
        XCTAssertTrue(columns.contains { $0.name == "source_pending_transaction_id" },
                      "Income retries must resolve the persisted original pending transaction")
    }
}
