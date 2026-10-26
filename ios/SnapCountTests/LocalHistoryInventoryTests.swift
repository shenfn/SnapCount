import XCTest
import GRDB
@testable import SnapCount

final class LocalHistoryInventoryTests: XCTestCase {
    func testLF03901CloudInventoryKeepsTransactionsCandidatesAndLedgerSeparate() {
        func row(_ values: [String: Any]) -> [String: AnyCodable] { values.mapValues(AnyCodable.init) }
        let counts = LocalHistoryInventoryCatalog.cloudCounts([
            .transactions: [
                row(["type": "expense", "status": "done"]),
                row(["type": "expense", "status": "pending"]),
                row(["type": "income", "status": "done"]),
                row(["type": "expense", "status": "done", "deleted_at": "2026-10-24T00:00:00Z", "image_url": "deleted.jpg"]),
                row(["type": "expense", "status": "deleted", "image_url": "deleted-pending.jpg"]),
                row(["type": "expense", "status": "done", "image_url": "active.jpg"])
            ],
            .incomes: [row(["id": UUID().uuidString])],
            .staging: [row(["status": "unassigned"]), row(["status": "pending_review"])],
            .records: [row(["domain_key": "food"]), row(["domain_key": "wallet",
                "source_image_path": "https://fixture.invalid/storage/v1/object/sign/receipt-images/active.jpg?token=synthetic"])],
            .accountEntries: [row(["is_voided": false]), row(["is_voided": true])]
        ])

        XCTAssertEqual(counts["expenses"], 2)
        XCTAssertEqual(counts["pending_expenses"], 1)
        XCTAssertEqual(counts["transactions.other"], 1, "legacy income carriers remain visible without being counted as income_records")
        XCTAssertEqual(counts["transactions.deleted"], 2)
        XCTAssertEqual(counts["incomes"], 1)
        XCTAssertEqual(counts["staging.pending_review"], 2, "unassigned candidates are pending review, but are not pending expenses")
        XCTAssertEqual(counts["records.food"], 1)
        XCTAssertEqual(counts["records.wallet"], 1)
        XCTAssertEqual(counts["account_entries"], 2)
        XCTAssertEqual(counts["account_entries.effective"], 1)
        XCTAssertEqual(counts["images.references"], 2, "deleted transaction references are not active image references")
        XCTAssertEqual(counts["images.unique"], 1)
    }

    func testLF03916AssignedAndConfirmedCandidatesAreVisibleAsArchived() {
        func row(_ status: String) -> [String: AnyCodable] { ["status": AnyCodable(status)] }
        let counts = LocalHistoryInventoryCatalog.cloudCounts([
            .staging: [row("assigned"), row("confirmed"), row("future_status")]
        ])

        XCTAssertEqual(counts["staging.archived"], 2)
        XCTAssertEqual(counts["staging.other"], 1)
        XCTAssertTrue(LocalHistoryInventoryCatalog.rows.contains { $0.key == "staging.other" })
        XCTAssertTrue(LocalHistoryInventoryCatalog.rows.contains { $0.key == "staging.archived" })
    }

    func testLF03901LocalInventoryIsReadOnlyAndDoesNotCreateProfile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let reader = LocalHistoryInventoryReader(database: database, imageStore: images)

        let snapshot = try reader.readLocal()
        let profileCount = try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM local_profiles") ?? 0
        }

        XCTAssertNil(snapshot.profileID)
        XCTAssertEqual(snapshot.counts["expenses"], 0)
        XCTAssertEqual(profileCount, 0)
    }

    func testLF03901LocalInventoryCountsOnlyActiveRowsInCurrentProfileAndVerifiesImages() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let firstProfile = UUID(), secondProfile = UUID()
        let firstAccount = UUID(), secondAccount = UUID()
        let activeExpense = UUID(), deletedExpense = UUID(), otherProfileExpense = UUID()
        let bytes = Data("synthetic-local-image".utf8)
        let image = try images.save(data: bytes, owner: "fixture", bucket: "records")
        try database.writer.write { db in
            try db.execute(sql: "INSERT INTO local_profiles(id,created_at,cloud_user_id,sync_enabled) VALUES(?,?,NULL,0)", arguments: [firstProfile.uuidString, Date(timeIntervalSince1970: 1)])
            try db.execute(sql: "INSERT INTO local_profiles(id,created_at,cloud_user_id,sync_enabled) VALUES(?,?,NULL,0)", arguments: [secondProfile.uuidString, Date(timeIntervalSince1970: 2)])
            for (id, profile) in [(firstAccount, firstProfile), (secondAccount, secondProfile)] {
                try db.execute(sql: "INSERT INTO local_accounts(id,profile_id,name,kind,currency,opening_balance_minor,created_at) VALUES(?,?,?,'cash','CNY',0,?)",
                    arguments: [id.uuidString, profile.uuidString, "合成账户", Date()])
            }
            try db.execute(sql: """
                INSERT INTO local_expenses(id,profile_id,account_id,amount_minor,currency,merchant_name,platform,category,payment_method,transaction_date,created_at,updated_at,image_path,image_hash)
                VALUES(?,?,?,100,'CNY','合成商户','','food','cash','2026-10-24',?,?,?,?)
                """, arguments: [activeExpense.uuidString, firstProfile.uuidString, firstAccount.uuidString, Date(), Date(), image.path, image.hash])
            try db.execute(sql: """
                INSERT INTO local_expenses(id,profile_id,account_id,amount_minor,currency,merchant_name,platform,category,payment_method,transaction_date,created_at,updated_at,deleted_at)
                VALUES(?,?,?,200,'CNY','已删除','','food','cash','2026-10-24',?,?,?)
                """, arguments: [deletedExpense.uuidString, firstProfile.uuidString, firstAccount.uuidString, Date(), Date(), Date()])
            try db.execute(sql: """
                INSERT INTO local_expenses(id,profile_id,account_id,amount_minor,currency,merchant_name,platform,category,payment_method,transaction_date,created_at,updated_at)
                VALUES(?,?,?,300,'CNY','其他 profile','','food','cash','2026-10-24',?,?)
                """, arguments: [otherProfileExpense.uuidString, secondProfile.uuidString, secondAccount.uuidString, Date(), Date()])
            for (id, status) in [(UUID(), "pending"), (UUID(), "deleted"), (UUID(), "converted")] {
                try db.execute(sql: """
                    INSERT INTO local_pending_transactions(id,profile_id,amount_minor,currency,merchant_name,transaction_date,created_at,image_path,image_hash,status)
                    VALUES(?,?,100,'CNY','合成待处理','2026-10-24',?,?,?,?)
                    """, arguments: [id.uuidString, firstProfile.uuidString, Date(), status == "pending" ? image.path : nil,
                        status == "pending" ? image.hash : nil, status])
            }
        }

        let snapshot = try LocalHistoryInventoryReader(database: database, imageStore: images).readLocal()

        XCTAssertEqual(snapshot.profileID, firstProfile.uuidString)
        XCTAssertEqual(snapshot.counts["accounts"], 1)
        XCTAssertEqual(snapshot.counts["expenses"], 1)
        XCTAssertEqual(snapshot.counts["pending_expenses"], 1)
        XCTAssertEqual(snapshot.counts["transactions.deleted"], 2, "deleted expense and deleted pending row remain visible separately from active data")
        XCTAssertEqual(snapshot.counts["transactions.other"], 1, "converted pending row is not a pending expense")
        XCTAssertEqual(snapshot.counts["images.references"], 2)
        XCTAssertEqual(snapshot.counts["images.unique"], 1)
        XCTAssertEqual(snapshot.counts["images.cached"], 1)
        XCTAssertEqual(snapshot.counts["images.verified"], 1)
        XCTAssertEqual(snapshot.counts["images.missing"], 0)
    }
}
