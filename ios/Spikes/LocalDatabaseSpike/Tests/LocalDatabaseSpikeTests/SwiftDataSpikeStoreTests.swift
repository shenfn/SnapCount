import Foundation
import XCTest
@testable import LocalDatabaseSpike

final class SwiftDataSpikeStoreTests: XCTestCase {
    func testLOCALSP001AExpenseAndOutboxCommitInOneSave() throws {
        let databaseURL = temporaryDatabaseURL(extension: "store")
        defer { removeDatabase(at: databaseURL) }
        let store = try SwiftDataSpikeStore(databaseURL: databaseURL)

        try store.insertExpenseAndOutbox(
            stableID: UUID(),
            operationID: UUID(),
            amountMinor: 2_680
        )

        XCTAssertEqual(try store.expenseCount(), 1)
        XCTAssertEqual(try store.outboxCount(), 1)
    }

    func testLOCALSP001BManualRollbackRemovesUnsavedExpense() throws {
        let databaseURL = temporaryDatabaseURL(extension: "store")
        defer { removeDatabase(at: databaseURL) }
        let store = try SwiftDataSpikeStore(databaseURL: databaseURL)

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

    func testLOCALSP001CUniqueAttributeUsesUpsertSemantics() throws {
        let databaseURL = temporaryDatabaseURL(extension: "store")
        defer { removeDatabase(at: databaseURL) }
        let store = try SwiftDataSpikeStore(databaseURL: databaseURL)
        let stableID = UUID()

        try store.insertExpenseOnly(stableID: stableID, amountMinor: 2_680)
        try store.insertExpenseOnly(stableID: stableID, amountMinor: 3_180)

        XCTAssertEqual(try store.expenseCount(), 1)
        XCTAssertEqual(try store.expense(stableID: stableID)?.amountMinor, 3_180)
    }

    func testLOCALSP001DMigratesV1FileToV2WithoutDataLoss() throws {
        let databaseURL = temporaryDatabaseURL(extension: "store")
        defer { removeDatabase(at: databaseURL) }
        let stableID = UUID()
        try SwiftDataSpikeStore.createVersion1Database(
            at: databaseURL,
            stableID: stableID,
            amountMinor: 2_680
        )

        let migratedStore = try SwiftDataSpikeStore(databaseURL: databaseURL)

        XCTAssertEqual(
            try migratedStore.expense(stableID: stableID),
            SpikeExpenseSnapshot(stableID: stableID, amountMinor: 2_680, note: nil)
        )
    }

    func testLOCALSP001EReopensPersistentFile() throws {
        let databaseURL = temporaryDatabaseURL(extension: "store")
        defer { removeDatabase(at: databaseURL) }
        let stableID = UUID()
        do {
            let store = try SwiftDataSpikeStore(databaseURL: databaseURL)
            try store.insertExpenseAndOutbox(
                stableID: stableID,
                operationID: UUID(),
                amountMinor: 2_680,
                note: "午餐"
            )
        }

        let reopenedStore = try SwiftDataSpikeStore(databaseURL: databaseURL)
        XCTAssertEqual(
            try reopenedStore.expense(stableID: stableID),
            SpikeExpenseSnapshot(stableID: stableID, amountMinor: 2_680, note: "午餐")
        )
        XCTAssertEqual(try reopenedStore.outboxCount(), 1)
    }
}
