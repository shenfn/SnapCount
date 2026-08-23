import Foundation
import XCTest
@testable import LocalDatabaseSpike

final class GRDBSpikeStoreTests: XCTestCase {
    func testLOCALSP001AExpenseAndOutboxCommitTogether() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try GRDBSpikeStore(databaseURL: databaseURL)

        try store.insertExpenseAndOutbox(
            stableID: UUID(),
            operationID: UUID(),
            amountMinor: 2_680
        )

        XCTAssertEqual(try store.expenseCount(), 1)
        XCTAssertEqual(try store.outboxCount(), 1)
    }

    func testLOCALSP001BRollbackRemovesPartialExpense() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try GRDBSpikeStore(databaseURL: databaseURL)

        XCTAssertThrowsError(
            try store.insertExpenseAndOutbox(
                stableID: UUID(),
                operationID: UUID(),
                amountMinor: 2_680,
                injectFailureAfterExpense: true
            )
        )

        XCTAssertEqual(try store.expenseCount(), 0)
        XCTAssertEqual(try store.outboxCount(), 0)
    }

    func testLOCALSP001CStableUUIDIsRejectedWhenDuplicated() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let store = try GRDBSpikeStore(databaseURL: databaseURL)
        let stableID = UUID()

        try store.insertExpenseAndOutbox(
            stableID: stableID,
            operationID: UUID(),
            amountMinor: 2_680
        )

        XCTAssertThrowsError(
            try store.insertExpenseAndOutbox(
                stableID: stableID,
                operationID: UUID(),
                amountMinor: 3_180
            )
        )
        XCTAssertEqual(try store.expenseCount(), 1)
        XCTAssertEqual(try store.outboxCount(), 1)
    }

    func testLOCALSP001DMigratesV1FileToV2WithoutDataLoss() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let stableID = UUID()
        try GRDBSpikeStore.createVersion1Database(
            at: databaseURL,
            stableID: stableID,
            amountMinor: 2_680
        )

        let migratedStore = try GRDBSpikeStore(databaseURL: databaseURL)

        XCTAssertEqual(
            try migratedStore.expense(stableID: stableID),
            SpikeExpenseSnapshot(stableID: stableID, amountMinor: 2_680, note: nil)
        )
    }

    func testLOCALSP001EReopensPersistentFile() throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }
        let stableID = UUID()
        do {
            let store = try GRDBSpikeStore(databaseURL: databaseURL)
            try store.insertExpenseAndOutbox(
                stableID: stableID,
                operationID: UUID(),
                amountMinor: 2_680,
                note: "午餐"
            )
        }

        let reopenedStore = try GRDBSpikeStore(databaseURL: databaseURL)
        XCTAssertEqual(
            try reopenedStore.expense(stableID: stableID),
            SpikeExpenseSnapshot(stableID: stableID, amountMinor: 2_680, note: "午餐")
        )
        XCTAssertEqual(try reopenedStore.outboxCount(), 1)
    }
}
