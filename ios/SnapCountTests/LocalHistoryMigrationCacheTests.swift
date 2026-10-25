import XCTest
@testable import SnapCount

final class LocalHistoryMigrationCacheTests: XCTestCase {
    func testLF03903NetworkFailureResumesMissingPageWithoutFetchingCommittedPageAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("local.sqlite")
        let database = try LocalDatabase(databaseURL: url)
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString
        let id = "00000000-0000-0000-0000-000000000001"
        let store = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        var firstPageCalls = 0, secondPageCalls = 0
        var fail = true
        let source = LocalHistoryMigrationSource(pageSize: 1) { path, query, _ in
            guard path == "rest/v1/accounts" else { return [] }
            if query.contains(where: { $0.name == "id" }) {
                secondPageCalls += 1
                if fail { throw URLError(.notConnectedToInternet) }
                return []
            }
            firstPageCalls += 1
            return [["id": AnyCodable(id), "user_id": AnyCodable(user)]]
        }
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://synthetic.invalid")!)
        let first = LocalHistoryMigrationCoordinator(source: source, downloader: downloader,
            cache: LocalHistoryMigrationCache(database: database, imageStore: store))
        do { _ = try await first.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true }); XCTFail("network must fail") }
        catch { XCTAssertEqual((error as? URLError)?.code, .notConnectedToInternet) }
        fail = false
        try database.writer.close()
        let reopened = try LocalDatabase(databaseURL: url)
        defer { try? reopened.writer.close() }
        let resumed = LocalHistoryMigrationCoordinator(source: source, downloader: downloader,
            cache: LocalHistoryMigrationCache(database: reopened, imageStore: store))
        let result = try await resumed.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true })
        XCTAssertEqual(firstPageCalls, 1)
        XCTAssertEqual(secondPageCalls, 2)
        XCTAssertEqual(result.inspection.counts["accounts"], 1)
        XCTAssertEqual(try LocalHistoryMigrationStore(database: reopened).state(profileID: profile.id)?.status, .running)
        XCTAssertEqual(try LocalExpenseRepository(database: reopened).accounts(profileID: profile.id).count, 0, "source cache is not a business fact")
    }

    func testLF03903ImageFailureResumesWithoutDownloadingFirstImageAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString
        let source = LocalHistoryMigrationSource { path, _, _ in
            guard path == "rest/v1/transactions" else { return [] }
            return ["a.jpg", "b.jpg"].enumerated().map { index, name in
                ["id": AnyCodable(String(format: "00000000-0000-0000-0000-%012d", index + 1)), "user_id": AnyCodable(user), "image_url": AnyCodable(user.lowercased() + "/" + name)]
            }
        }
        var calls: [String: Int] = [:]
        var fail = true
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://synthetic.invalid")!) { request in
            let url = try XCTUnwrap(request.url)
            calls[url.lastPathComponent, default: 0] += 1
            if fail, url.lastPathComponent == "b.jpg" { throw URLError(.timedOut) }
            return (Data(url.lastPathComponent.utf8), HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cache = LocalHistoryMigrationCache(database: database, imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        let coordinator = LocalHistoryMigrationCoordinator(source: source, downloader: downloader, cache: cache)
        do { _ = try await coordinator.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true }); XCTFail("download must fail") } catch { }
        fail = false
        let result = try await coordinator.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true })
        XCTAssertEqual(calls["a.jpg"], 1)
        XCTAssertEqual(calls["b.jpg"], 2)
        XCTAssertEqual(result.images.count, 2)
    }
    func testLF03903ReopenResumesAfterCommittedPageAndKeepsImageBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("local.sqlite")
        let database = try LocalDatabase(databaseURL: url)
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let cache = LocalHistoryMigrationCache(database: database, imageStore: images)
        let first = try cache.begin(profileID: profile.id, cloudUserID: user)
        let id = UUID().uuidString.lowercased()
        let rows = [["id": AnyCodable(id), "user_id": AnyCodable(user)]]
        try cache.savePage(state: first, table: .accounts, afterID: nil,
                           page: LocalHistorySourcePage(rows: rows, nextCursor: id))
        let bytes = Data("cached-original".utf8)
        try cache.saveImage(state: first, sourcePath: "original", data: bytes)
        let businessImage = try images.save(data: Data("business-original".utf8), owner: "business-record", bucket: "records")
        let interrupted = try images.save(data: Data("interrupted-cache-write".utf8), owner: "interrupted", bucket: "history-cache")
        try database.writer.close()
        let reopenedDatabase = try LocalDatabase(databaseURL: url)
        defer { try? reopenedDatabase.writer.close() }
        let reopened = LocalHistoryMigrationCache(database: reopenedDatabase, imageStore: images)
        let resumed = try reopened.begin(profileID: profile.id, cloudUserID: user)
        XCTAssertFalse(images.contains(path: interrupted.path), "uncommitted cache files are recovered after restart")
        XCTAssertGreaterThan(resumed.generation, first.generation)
        let page = try XCTUnwrap(reopened.page(state: resumed, table: .accounts, afterID: nil))
        XCTAssertEqual(page.nextCursor, id)
        XCTAssertEqual(page.rows.first?["id"]?.value as? String, id)
        XCTAssertEqual(try reopened.image(state: resumed, sourcePath: "original"), bytes)
        XCTAssertThrowsError(try reopened.savePage(state: first, table: .accounts, afterID: id,
            page: LocalHistorySourcePage(rows: [], nextCursor: nil)))
        XCTAssertThrowsError(try reopened.saveImage(state: first, sourcePath: "late", data: bytes))
        XCTAssertThrowsError(try reopened.begin(profileID: profile.id, cloudUserID: UUID().uuidString))
        XCTAssertEqual(try LocalHistoryMigrationStore(database: reopenedDatabase).state(profileID: profile.id)?.status, .running)
        let account = try LocalExpenseRepository(database: reopenedDatabase).createAccount(LocalAccountDraft(
            id: UUID(), profileID: profile.id, name: "原有现金", kind: "cash", currency: "CNY", openingBalanceMinor: 10000, createdAt: Date()))
        XCTAssertThrowsError(try reopened.completeAfterImport(resumed), "partial source must not be completed")
        try reopened.restartSource(resumed)
        XCTAssertThrowsError(try reopened.assertCurrent(resumed))
        let restarted = try reopened.begin(profileID: profile.id, cloudUserID: user)
        XCTAssertNil(try reopened.page(state: restarted, table: .accounts, afterID: nil))
        XCTAssertNil(try reopened.image(state: restarted, sourcePath: "original"))
        let cacheDirectory = images.url(for: "history-cache/probe").deletingLastPathComponent()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).count, 0)
        XCTAssertTrue(images.contains(path: businessImage.path))
        XCTAssertEqual(try LocalExpenseRepository(database: reopenedDatabase).accountBalanceMinor(accountID: account.id), 10000)
        XCTAssertThrowsError(try reopened.restartSource(resumed), "old attempts cannot reset newer caches")
        for table in LocalHistorySourceTable.allCases {
            try reopened.savePage(state: restarted, table: table, afterID: nil, page: LocalHistorySourcePage(rows: [], nextCursor: nil))
        }
        try reopened.saveImage(state: restarted, sourcePath: "completed-image", data: bytes)
        try reopened.completeAfterImport(restarted)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: cacheDirectory.path).count, 0)
        XCTAssertTrue(images.contains(path: businessImage.path))
        XCTAssertThrowsError(try reopened.restartSource(restarted)) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .alreadyCompleted)
        }
        XCTAssertThrowsError(try reopened.begin(profileID: profile.id, cloudUserID: user)) { error in
            XCTAssertEqual(error as? LocalHistoryMigrationError, .alreadyCompleted)
        }
    }
}
