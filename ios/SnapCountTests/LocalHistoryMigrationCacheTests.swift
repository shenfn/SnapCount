import XCTest
@testable import SnapCount

final class LocalHistoryMigrationCacheTests: XCTestCase {
    @MainActor
    func testLF03925BoundedParallelDownloadsReuseCacheAndRecheckFreshBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString.lowercased()
        let timestamp = "2026-10-24T00:30:00Z"
        let rows: [[String: AnyCodable]] = (1...6).map { index in
            ["id": AnyCodable(String(format: "00000000-0000-0000-0000-%012d", index)),
             "user_id": AnyCodable(user), "domain_key": AnyCodable("food"),
             "domain_version": AnyCodable("1.0"), "created_at": AnyCodable(timestamp),
             "updated_at": AnyCodable(timestamp), "occurred_at": AnyCodable(timestamp),
             "payload_jsonb": AnyCodable(["meal_type": "午餐", "total_calorie_kcal": 500]),
             "source_image_path": AnyCodable("2026-10-24/image-\(index).jpg")]
        }
        let source = LocalHistoryMigrationSource { table, _, _ in table == "rest/v1/data_records" ? rows : [] }
        let probe = HistoryImageConcurrencyProbe()
        // A broken serial implementation is released after two seconds so the test fails instead of hanging.
        let timeout = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled { probe.release() }
        }
        defer { timeout.cancel(); probe.release() }
        var calls = 0
        var fail = false
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            calls += 1
            await probe.enter()
            defer { probe.leave() }
            return (Data("synthetic-original".utf8), HTTPURLResponse(url: request.url!, statusCode: fail ? 400 : 200,
                httpVersion: nil, headerFields: nil)!)
        }
        let cache = LocalHistoryMigrationCache(database: database,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        let coordinator = LocalHistoryMigrationCoordinator(source: source, downloader: downloader, cache: cache)
        let prepared = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
            accessToken: "synthetic-token", isCurrent: { true })
        XCTAssertEqual(probe.peak, 3, "Downloads must overlap, but never exceed three in flight")
        XCTAssertEqual(calls, 6)
        XCTAssertEqual(prepared.images.count, 6)

        let resumed = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
            accessToken: "synthetic-token", isCurrent: { true })
        XCTAssertEqual(calls, 6, "Valid preflight caches must not be downloaded again")
        XCTAssertEqual(resumed.images, prepared.images)
        let fresh = try await coordinator.loadImages(inspection: prepared.inspection, cloudUserID: user,
            accessToken: "synthetic-token", isCurrent: { true })
        XCTAssertEqual(calls, 12, "Confirmation must still recheck original bytes without using preflight cache")
        XCTAssertEqual(fresh, prepared.images)

        fail = true
        do {
            _ = try await coordinator.loadImages(inspection: prepared.inspection, cloudUserID: user,
                accessToken: "synthetic-token", isCurrent: { true })
            XCTFail("Failed confirmation downloads must not be accepted")
        } catch {
            let context = try XCTUnwrap(error as? LocalHistoryMigrationContextError)
            XCTAssertEqual((context.underlying as? LocalHistoryImageHTTPError)?.statusCode, 400)
        }
        XCTAssertEqual(calls, 15, "No additional work may be enqueued after the initial three requests fail")
        XCTAssertLessThanOrEqual(probe.peak, 3)
        XCTAssertTrue(try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-10").isEmpty)
    }

    func testLF03923TotalImageLimitUsesDistinctOverflowError() throws {
        let limit = 128 * 1024 * 1024
        XCTAssertEqual(try LocalHistoryMigrationCoordinator.checkedImageByteCount(current: limit - 1, adding: 1), limit)
        XCTAssertThrowsError(try LocalHistoryMigrationCoordinator.checkedImageByteCount(current: limit, adding: 1)) { error in
            XCTAssertEqual(error as? LocalHistoryImageDownloadError, .totalSizeExceeded)
        }
        XCTAssertThrowsError(try LocalHistoryMigrationCoordinator.checkedImageByteCount(current: Int.max, adding: 1)) { error in
            XCTAssertEqual(error as? LocalHistoryImageDownloadError, .totalSizeExceeded)
        }
    }

    func testLF03922LegacyDataRecordImageFlowsThroughCoordinatorCacheAndMapper() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString.lowercased()
        let timestamp = "2026-10-24T00:30:00Z"
        let paths = ["2026-10-24/legacy-a.jpg", "2026-10-24/legacy-b.jpg"]
        let payloads = [paths[0]: Data("synthetic-a".utf8), paths[1]: Data("synthetic-b".utf8)]
        let rows = paths.enumerated().map { index, path in
            [
                "id": AnyCodable(String(format: "00000000-0000-0000-0000-%012d", index + 1)),
                "user_id": AnyCodable(user),
                "domain_key": AnyCodable("food"),
                "domain_version": AnyCodable("1.0"),
                "title": AnyCodable("合成历史午餐"),
                "summary": AnyCodable("500 kcal"),
                "payload_jsonb": AnyCodable(["meal_type": "午餐", "total_calorie_kcal": 500]),
                "occurred_at": AnyCodable(timestamp),
                "created_at": AnyCodable(timestamp),
                "updated_at": AnyCodable(timestamp),
                "source_image_path": AnyCodable(path),
                "source_image_hash": AnyCodable(LocalImageStore.sha256(payloads[path]!))
            ]
        }
        let source = LocalHistoryMigrationSource { path, _, _ in
            path == "rest/v1/data_records" ? rows : []
        }
        var failSecondImage = true
        var calls: [String: Int] = [:]
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://synthetic.invalid")!) { request in
            let url = try XCTUnwrap(request.url)
            let fileName = url.lastPathComponent
            calls[fileName, default: 0] += 1
            if failSecondImage, fileName == "legacy-b.jpg" { throw URLError(.timedOut) }
            return (try XCTUnwrap(payloads["2026-10-24/\(fileName)"]),
                HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let imageStore = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let cache = LocalHistoryMigrationCache(database: database, imageStore: imageStore)
        let coordinator = LocalHistoryMigrationCoordinator(source: source, downloader: downloader, cache: cache)

        do {
            _ = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
                accessToken: "synthetic-session", isCurrent: { true })
            XCTFail("The second image failure must stop preparation")
        } catch {
            let context = try XCTUnwrap(error as? LocalHistoryMigrationContextError)
            XCTAssertEqual(context.table, "data_records")
            XCTAssertEqual(context.field, "source_image_path")
            XCTAssertEqual(context.recordID, "00000000-0000-0000-0000-000000000002")
            XCTAssertEqual((context.underlying as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(try LocalHistoryMigrationStore(database: database).state(profileID: profile.id)?.status, .paused)
        XCTAssertTrue(try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-10").isEmpty,
            "A failed image preparation must not create local facts")

        failSecondImage = false
        let prepared = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
            accessToken: "synthetic-session", isCurrent: { true })
        XCTAssertEqual(prepared.images[paths[0]], payloads[paths[0]])
        XCTAssertEqual(prepared.images[paths[1]], payloads[paths[1]])
        XCTAssertEqual(try cache.image(state: prepared.state, sourcePath: paths[0]), payloads[paths[0]])
        XCTAssertEqual(try cache.image(state: prepared.state, sourcePath: paths[1]), payloads[paths[1]])
        XCTAssertEqual(calls["legacy-a.jpg"], 1, "Retry must reuse the valid cached legacy image")
        XCTAssertEqual(calls["legacy-b.jpg"], 2, "Retry must fetch the image that failed previously")

        let archive = try LocalHistoryMigrationMapper(schema: database).buildArchive(
            prepared.inspection, profileID: profile.id, images: prepared.images)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let archivedImages = try XCTUnwrap(root["images"] as? [[String: Any]])
        let archivedBytes = archivedImages.compactMap { image -> Data? in
            guard let encoded = image["data"] as? String else { return nil }
            return Data(base64Encoded: encoded)
        }
        XCTAssertEqual(Set(archivedBytes), Set(payloads.values), "The mapper must receive the original cache keys and bytes")
        XCTAssertTrue(try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-10").isEmpty,
            "Preparation and archive mapping do not commit the migration")
    }

    @MainActor
    func testLF03926MissingOrEmptyImagesAreSkippedAndOtherImagesContinue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString.lowercased()
        let timestamp = "2026-10-24T00:30:00Z"
        let rows: [[String: AnyCodable]] = ["missing.jpg", "empty.jpg", "available.jpg"].enumerated().map { index, name in
            ["id": AnyCodable(String(format: "00000000-0000-0000-0000-%012d", index + 1)),
             "user_id": AnyCodable(user), "domain_key": AnyCodable("food"),
             "domain_version": AnyCodable("1.0"), "created_at": AnyCodable(timestamp),
             "updated_at": AnyCodable(timestamp), "occurred_at": AnyCodable(timestamp),
             "payload_jsonb": AnyCodable(["meal_type": "午餐", "total_calorie_kcal": 500]),
             "source_image_path": AnyCodable("2026-10-24/\(name)")]
        }
        let source = LocalHistoryMigrationSource { path, _, _ in
            path == "rest/v1/data_records" ? rows : []
        }
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://synthetic.invalid")!) { request in
            if request.url?.lastPathComponent == "missing.jpg" {
                return (Data(#"{"code":"NoSuchKey","error":"not_found"}"#.utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
            }
            if request.url?.lastPathComponent == "empty.jpg" {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }
            return (Data("available-image".utf8),
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cache = LocalHistoryMigrationCache(database: database,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        let coordinator = LocalHistoryMigrationCoordinator(source: source, downloader: downloader, cache: cache)

        let prepared = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
            accessToken: "synthetic-token", isCurrent: { true })
        XCTAssertEqual(prepared.images.count, 1)
        XCTAssertNotNil(prepared.images["2026-10-24/available.jpg"])
        XCTAssertNil(prepared.images["2026-10-24/missing.jpg"])
        XCTAssertNil(prepared.images["2026-10-24/empty.jpg"])
        let archive = try LocalHistoryMigrationMapper(schema: database).buildArchive(
            prepared.inspection, profileID: profile.id, images: prepared.images)
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: archive) as? [String: Any])
        let tables = try XCTUnwrap(root["tables"] as? [String: String])
        let records = try XCTUnwrap(JSONSerialization.jsonObject(
            with: Data(try XCTUnwrap(tables["local_records"]).utf8)) as? [[String: Any]])
        XCTAssertEqual(records.count, 3)
        XCTAssertEqual(records.filter { ($0["image_path"] as? String) == nil }.count, 2)
    }

    func testLF03923AccountSwitchAfterImageResponseDoesNotCacheOrCommitLateBytes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("local.sqlite"))
        defer { try? database.writer.close() }
        let profile = try LocalProfileStore(database: database).activeProfile()
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/legacy.jpg"
        let timestamp = "2026-10-24T00:30:00Z"
        let source = LocalHistoryMigrationSource { table, _, _ in
            guard table == "rest/v1/data_records" else { return [] }
            return [[
                "id": AnyCodable("00000000-0000-0000-0000-000000000001"),
                "user_id": AnyCodable(user),
                "domain_key": AnyCodable("food"), "domain_version": AnyCodable("1.0"),
                "payload_jsonb": AnyCodable(["meal_type": "午餐", "total_calorie_kcal": 500]),
                "occurred_at": AnyCodable(timestamp), "created_at": AnyCodable(timestamp),
                "updated_at": AnyCodable(timestamp), "source_image_path": AnyCodable(path)
            ]]
        }
        var current = true
        var imageCalls = 0
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://synthetic.invalid")!) { request in
            imageCalls += 1
            if imageCalls == 1 { current = false }
            return (Data("late-image".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let cache = LocalHistoryMigrationCache(database: database,
            imageStore: try LocalImageStore(rootDirectory: directory.appendingPathComponent("images")))
        let coordinator = LocalHistoryMigrationCoordinator(source: source, downloader: downloader, cache: cache)

        do {
            _ = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
                accessToken: "synthetic-session", isCurrent: { current })
            XCTFail("A response from an invalidated account must not escape preparation")
        } catch is CancellationError {
            // Expected: account identity changed after the request began.
        }
        XCTAssertEqual(try LocalHistoryMigrationStore(database: database).state(profileID: profile.id)?.status, .paused)
        XCTAssertTrue(try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-10").isEmpty)

        current = true
        let retry = try await coordinator.prepare(profileID: profile.id, cloudUserID: user,
            accessToken: "synthetic-session", isCurrent: { current })
        XCTAssertEqual(imageCalls, 2, "Late response bytes must not have been written to migration cache")
        XCTAssertNotNil(retry.images[path])
        XCTAssertTrue(try LocalRecordRepository(database: database).records(profileID: profile.id, monthKey: "2026-10").isEmpty)
    }

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
        catch {
            let context = try XCTUnwrap(error as? LocalHistoryMigrationContextError)
            XCTAssertEqual(context.table, "accounts")
            XCTAssertEqual((context.underlying as? URLError)?.code, .notConnectedToInternet)
        }
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
                ["id": AnyCodable(String(format: "00000000-0000-0000-0000-%012d", index + 1)), "user_id": AnyCodable(user),
                 "type": AnyCodable("expense"), "status": AnyCodable("done"),
                 "image_url": AnyCodable(user.lowercased() + "/" + name)]
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
        do {
            _ = try await coordinator.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true })
            XCTFail("download must fail")
        } catch {
            let context = try XCTUnwrap(error as? LocalHistoryMigrationContextError)
            XCTAssertEqual(context.table, "transactions")
            XCTAssertEqual(context.field, "image_url")
            XCTAssertEqual((context.underlying as? URLError)?.code, .timedOut)
        }
        XCTAssertEqual(try LocalHistoryMigrationStore(database: database).state(profileID: profile.id)?.status, .paused)
        XCTAssertEqual(try LocalExpenseRepository(database: database).expenses(profileID: profile.id, monthKey: "2026-10").count, 0)
        fail = false
        let result = try await coordinator.prepare(profileID: profile.id, cloudUserID: user, accessToken: "synthetic", isCurrent: { true })
        XCTAssertTrue(result.inspection.blockers.isEmpty)
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

@MainActor
private final class HistoryImageConcurrencyProbe {
    private var active = 0
    private var released = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var peak = 0

    func enter() async {
        active += 1
        peak = max(peak, active)
        if active >= 3 { release() }
        if !released { await withCheckedContinuation { waiters.append($0) } }
    }
    func leave() { active -= 1 }
    func release() {
        released = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}
