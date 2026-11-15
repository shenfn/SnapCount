import XCTest
@testable import SnapCount

@MainActor
final class ShortcutTrialStoreTests: XCTestCase {
    func testIOSV2POLISH008LaunchWaitsForActualClaimedResultAndCannotOverwriteIt() throws {
        try withStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let id = store.begin(scope: .device, now: now)
            XCTAssertNil(store.snapshot(for: .device, now: now)?.outcome)
            XCTAssertFalse(try XCTUnwrap(store.snapshot(for: .device, now: now)).processing)
            XCTAssertEqual(store.claim(now: now), id)
            XCTAssertNil(store.claim(now: now), "并发的第二次上传不得抢占本次试运行")
            store.complete(id: id, outcome: .staged, now: now)
            XCTAssertEqual(store.snapshot(for: .device, now: now)?.outcome, .staged)
            store.complete(id: id, outcome: .archived, now: now)
            XCTAssertEqual(store.snapshot(for: .device, now: now)?.outcome, .staged)
        }
    }

    func testIOSV2POLISH008OldNonceExpiredAndDifferentAccountCannotReceiveReceipt() throws {
        try withStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let old = store.begin(scope: .account("a"), now: now)
            _ = store.claim(now: now)
            let current = store.begin(scope: .account("a"), now: now)
            store.complete(id: old, outcome: .archived, now: now)
            XCTAssertNil(store.snapshot(for: .account("a"), now: now)?.outcome)
            XCTAssertNil(store.snapshot(for: .account("b"), now: now))
            XCTAssertEqual(store.claim(now: now), current)
            store.synchronize(scope: .account("b"))
            store.complete(id: current, outcome: .archived, now: now)
            XCTAssertNil(store.snapshot(for: .account("a"), now: now))
            let expired = store.begin(scope: .device, now: now)
            _ = store.claim(now: now)
            store.complete(id: expired, outcome: .archived, now: now.addingTimeInterval(1801))
            XCTAssertNil(store.snapshot(for: .device, now: now.addingTimeInterval(1801)))
        }
    }

    func testIOSV2POLISH008CancelledOrUnclaimedTrialDoesNotBecomeSuccess() throws {
        try withStore { store in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let id = store.begin(scope: .device, now: now)
            store.complete(id: id, outcome: .archived, now: now)
            XCTAssertNil(store.snapshot(for: .device, now: now)?.outcome)
            _ = store.claim(now: now)
            store.cancel(id: id)
            store.complete(id: id, outcome: .archived, now: now)
            XCTAssertNil(store.snapshot(for: .device, now: now))
        }
    }

    private func withStore(_ body: (ShortcutTrialStore) throws -> Void) throws {
        let name = "ShortcutTrialTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        try body(ShortcutTrialStore(defaults: defaults))
    }
}
