import XCTest
import GRDB
@testable import SnapCount

final class LocalDatabaseConcurrencyTests: XCTestCase {
    func testWritersOnSeparateConnectionsWaitForAnActiveTransaction() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snapcount-db-lock-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("local.sqlite")
        defer { try? FileManager.default.removeItem(at: directory) }

        let first = try LocalDatabase(databaseURL: databaseURL)
        let second = try LocalDatabase(databaseURL: databaseURL)
        let transactionStarted = DispatchSemaphore(value: 0)
        let releaseTransaction = DispatchSemaphore(value: 0)
        let firstFinished = DispatchSemaphore(value: 0)
        let secondFinished = DispatchSemaphore(value: 0)
        let errorLock = NSLock()
        var firstError: Error?
        var secondError: Error?

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try first.writer.write { db in
                    try db.execute(sql: "CREATE TABLE lock_probe (id INTEGER PRIMARY KEY, value TEXT NOT NULL)")
                    transactionStarted.signal()
                    _ = releaseTransaction.wait(timeout: .now() + 5)
                    try db.execute(sql: "INSERT INTO lock_probe (value) VALUES ('first')")
                }
            } catch {
                errorLock.lock()
                firstError = error
                errorLock.unlock()
            }
            firstFinished.signal()
        }

        XCTAssertEqual(transactionStarted.wait(timeout: .now() + 2), .success)

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try second.writer.write { db in
                    try db.execute(sql: "INSERT INTO lock_probe (value) VALUES ('second')")
                }
            } catch {
                errorLock.lock()
                secondError = error
                errorLock.unlock()
            }
            secondFinished.signal()
        }

        XCTAssertEqual(
            secondFinished.wait(timeout: .now() + 0.2),
            .timedOut,
            "A second process must wait for the active writer instead of failing immediately with SQLITE_BUSY"
        )

        releaseTransaction.signal()
        XCTAssertEqual(firstFinished.wait(timeout: .now() + 3), .success)
        XCTAssertEqual(secondFinished.wait(timeout: .now() + 3), .success)

        errorLock.lock()
        let capturedFirstError = firstError
        let capturedSecondError = secondError
        errorLock.unlock()
        XCTAssertNil(capturedFirstError)
        XCTAssertNil(capturedSecondError)

        let values = try second.writer.read { db in
            try String.fetchAll(db, sql: "SELECT value FROM lock_probe ORDER BY id")
        }
        XCTAssertEqual(values, ["first", "second"])
    }
}
