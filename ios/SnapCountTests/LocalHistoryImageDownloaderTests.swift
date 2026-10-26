import XCTest
@testable import SnapCount

final class LocalHistoryImageDownloaderTests: XCTestCase {
    @MainActor
    func testLF03924TransientHTTPRetriesAreBoundedAndCanRecover() async throws {
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/legacy.jpg"
        let (inspection, reference) = try source(user: user, path: path)
        var calls = 0
        var delays: [UInt64] = []
        let bytes = Data("synthetic-original".utf8)
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!,
            pause: { delays.append($0) }) { request in
            calls += 1
            return (calls < 3 ? Data("temporary".utf8) : bytes,
                HTTPURLResponse(url: request.url!, statusCode: calls < 3 ? 503 : 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await downloader.download(reference: reference, inspection: inspection,
            cloudUserID: user, accessToken: "synthetic-token")
        XCTAssertEqual(result[path], bytes)
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(delays, [500_000_000, 1_000_000_000])
    }

    @MainActor
    func testLF03924HTTPMetadataSurvivesDiagnosticWithoutResponseSecrets() async throws {
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/legacy.jpg"
        let (inspection, reference) = try source(user: user, path: path)
        let body = Data(#"{"code":"SlowDown","message":"https://private.invalid/photo?token=synthetic-secret"}"#.utf8)
        var calls = 0
        var delays: [UInt64] = []
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!,
            pause: { delays.append($0) }) { request in
            calls += 1
            return (body, HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil,
                headerFields: ["Retry-After": "999"])!)
        }
        do {
            _ = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-token")
            XCTFail("Persistent throttling must stop after the retry budget")
        } catch {
            let http = try XCTUnwrap(error as? LocalHistoryImageHTTPError)
            XCTAssertEqual(http.statusCode, 429)
            XCTAssertEqual(http.storageCode, "SlowDown")
            XCTAssertEqual(http.attempts, 3)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("diagnostics.json")
            defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
            let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
            let context = LocalHistoryMigrationContextError(table: reference.table, field: reference.field,
                recordID: reference.recordID, underlying: http)
            let entry = store.record(context, phase: "下载历史原图", attemptID: UUID(), committed: false)
            XCTAssertEqual(entry.httpStatus, 429)
            XCTAssertEqual(entry.storageCode, "SlowDown")
            XCTAssertEqual(entry.requestAttempts, 3)
            XCTAssertEqual(entry.responseBytes, body.count)
            XCTAssertNotNil(entry.elapsedMilliseconds)
            XCTAssertTrue(entry.shareText.contains("429"))
            XCTAssertFalse(entry.shareText.contains("private.invalid"))
            XCTAssertFalse(entry.shareText.contains("synthetic-secret"))
            XCTAssertFalse(entry.shareText.contains(reference.recordID))
            let reopened = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
            XCTAssertEqual(try reopened.recent().first?.httpStatus, 429)
        }
        XCTAssertEqual(calls, 3)
        XCTAssertEqual(delays, [5_000_000_000, 5_000_000_000])
    }

    @MainActor
    func testLF03924BadRequestNeverRetriesOrExportsUnknownBodyCode() async throws {
        let user = UUID().uuidString.lowercased()
        let (inspection, reference) = try source(user: user, path: "2026-10-24/legacy.jpg")
        var calls = 0
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!,
            pause: { _ in XCTFail("Bad requests must not be retried") }) { request in
            calls += 1
            return (Data(#"{"code":"private-token-and-path","message":"private-data"}"#.utf8),
                HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-token")
            XCTFail("Bad request must remain a failure")
        } catch {
            let http = try XCTUnwrap(error as? LocalHistoryImageHTTPError)
            XCTAssertEqual(http.statusCode, 400)
            XCTAssertEqual(http.attempts, 1)
            XCTAssertNil(http.storageCode)
            XCTAssertFalse(http.localizedDescription.contains("private-"))
        }
        XCTAssertEqual(calls, 1)
    }

    @MainActor
    func testLF03924AccountChangeDuringBackoffStopsRetry() async throws {
        let user = UUID().uuidString.lowercased()
        let (inspection, reference) = try source(user: user, path: "2026-10-24/legacy.jpg")
        var current = true
        var calls = 0
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!,
            pause: { _ in current = false }) { request in
            calls += 1
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!)
        }
        do {
            _ = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-token", isCurrent: { current })
            XCTFail("Stale migration must not retry")
        } catch is CancellationError { }
        XCTAssertEqual(calls, 1)
    }

    func testLF03922CurrentAndLegacyObjectPathsUseAuthenticatedReceiptBucket() async throws {
        let user = UUID().uuidString.lowercased()
        let token = "synthetic-current-session"
        let objectPaths = [
            "\(user)/original.jpg",
            "tmp/\(user)/original.jpg",
            "\(user)/2026-10-24/new.jpg",
            "tmp/\(user)/2026-10-24/new-temp.jpg",
            "2026-10-24/legacy.jpg",
            "tmp/2026-10-24/legacy-temp.jpg"
        ]
        for objectPath in objectPaths {
            let (inspection, reference) = try source(user: user, path: objectPath)
            let bytes = Data(objectPath.utf8)
            let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
                XCTAssertEqual(request.url?.path, "/storage/v1/object/authenticated/receipt-images/\(objectPath)")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
                return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            let result = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: token)

            XCTAssertEqual(result[objectPath], bytes, "Original source key must remain the cache and mapper key")
        }
    }

    func testLF03922ExpiredLegacySignedURLUsesCurrentAuthenticatedSessionWithoutQuery() async throws {
        let user = UUID().uuidString.lowercased()
        let bytes = Data("synthetic-original".utf8)
        let objectPaths = ["2026-10-24/legacy.jpg", "\(user)/legacy-signed-url/abc123-photo.jpg"]
        for objectPath in objectPaths {
            let sourcePath = "https://fixture.invalid/storage/v1/object/sign/receipt-images/\(objectPath)?token=expired-synthetic-token"
            let (inspection, reference) = try source(user: user, path: sourcePath)
            var requests: [URLRequest] = []
            let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
                requests.append(request)
                return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            }

            let result = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-current-token")

            XCTAssertEqual(requests.count, 1, "An expired signature is never requested")
            XCTAssertEqual(requests[0].url?.path, "/storage/v1/object/authenticated/receipt-images/\(objectPath)")
            XCTAssertNil(requests[0].url?.query)
            XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-current-token")
            XCTAssertEqual(result[sourcePath], bytes)
            XCTAssertFalse(String(describing: requests[0].url).contains("expired-synthetic-token"))
        }
    }

    func testLF03922OnlyMapperSelectedImageFieldCanAuthorizeDownload() throws {
        let user = UUID().uuidString.lowercased()
        let selectedPath = "2026-10-24/selected.jpg"
        let secondaryPath = "2026-10-24/secondary.jpg"
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user, rows: [
            .records: [[
                "id": AnyCodable(UUID().uuidString.lowercased()),
                "user_id": AnyCodable(user),
                "image_url": AnyCodable(selectedPath),
                "source_image_path": AnyCodable(secondaryPath)
            ]]
        ], blockers: [])

        XCTAssertEqual(inspection.sourceImagePaths, Set([selectedPath]))
        XCTAssertNotNil(inspection.imageReference(for: selectedPath))
        XCTAssertNil(inspection.imageReference(for: secondaryPath),
            "A lower-priority path that mapper will not consume must not expand the download scope")
    }

    func testLF03922UntrustedScopeForeignOwnerExternalOriginAndTraversalNeverStartRequest() async throws {
        let user = UUID().uuidString.lowercased()
        let otherUser = UUID().uuidString.lowercased()
        let cases: [(String, LocalHistoryImageDownloadError)] = [
            ("\(otherUser)/2026-10-24/foreign.jpg", .sourceScopeMismatch),
            ("https://foreign.invalid/storage/v1/object/sign/receipt-images/2026-10-24/external.jpg?token=synthetic", .sourceScopeMismatch),
            ("https://fixture.invalid/storage/v1/object/sign/other-bucket/2026-10-24/wrong-bucket.jpg?token=synthetic", .sourceScopeMismatch),
            ("2026-10-24/../private.jpg", .unsupportedPathFormat),
            ("tmp/2026-10-24/%2e%2e/private.jpg", .unsupportedPathFormat),
            ("tmp/2026-10-24/%2fprivate.jpg", .unsupportedPathFormat),
            ("tmp/2026-10-24/%252e%252e/private.jpg", .unsupportedPathFormat),
            ("https://fixture.invalid/storage/v1/object/sign/receipt-images/tmp/2026-10-24/%2e%2e/private.jpg?token=synthetic", .unsupportedPathFormat),
            ("https://fixture.invalid/storage/v1/object/sign/receipt-images/tmp/2026-10-24/%2fprivate.jpg?token=synthetic", .unsupportedPathFormat),
            ("https://fixture.invalid/storage/v1/object/sign/receipt-images/tmp/2026-10-24/%252e%252e/private.jpg?token=synthetic", .unsupportedPathFormat),
            ("images/legacy.jpg", .unsupportedPathFormat)
        ]
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { _ in
            XCTFail("Out of scope paths must be rejected before a credentialed request")
            throw URLError(.badURL)
        }

        for (path, expected) in cases {
            let (inspection, reference) = try source(user: user, path: path)
            do {
                _ = try await downloader.download(reference: reference, inspection: inspection,
                    cloudUserID: user, accessToken: "synthetic-private-token")
                XCTFail("Accepted path outside migration scope: \(path)")
            } catch {
                XCTAssertEqual((error as? LocalHistoryImageHTTPError)?.failure ?? (error as? LocalHistoryImageDownloadError), expected)
            }
        }

        let (sourceInspection, reference) = try source(user: user, path: "2026-10-24/legacy.jpg")
        let (otherInspection, _) = try source(user: otherUser, path: "2026-10-24/legacy.jpg")
        do {
            _ = try await downloader.download(reference: reference, inspection: otherInspection,
                cloudUserID: user, accessToken: "synthetic-private-token")
            XCTFail("A source reference from a different inspection must be rejected")
        } catch {
            XCTAssertEqual(error as? LocalHistoryImageDownloadError, .sourceScopeMismatch)
        }
        XCTAssertEqual(sourceInspection.cloudUserID.lowercased(), user)
    }

    func testLF03923HTTPFailuresHaveDistinctCategoriesAndNoBearerLeak() async throws {
        let user = UUID().uuidString.lowercased()
        let cases: [(String, Int, LocalHistoryImageDownloadError)] = [
            ("2026-10-24/image.jpg", 401, .sessionExpired),
            ("2026-10-24/image.jpg", 403, .accessDenied),
            ("2026-10-24/image.jpg", 404, .missingImage),
            ("tmp/2026-10-24/image.jpg", 404, .missingTemporaryImage),
            ("tmp/\(user)/2026-10-24/image.jpg", 404, .missingTemporaryImage)
        ]
        for (path, status, expected) in cases {
            let (inspection, reference) = try source(user: user, path: path)
            let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
                (Data("Bearer synthetic-private-token".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do {
                _ = try await downloader.download(reference: reference, inspection: inspection,
                    cloudUserID: user, accessToken: "synthetic-private-token")
                XCTFail("HTTP error must not be accepted as an image")
            } catch {
                XCTAssertEqual((error as? LocalHistoryImageHTTPError)?.failure ?? (error as? LocalHistoryImageDownloadError), expected)
                XCTAssertFalse(error.localizedDescription.contains("synthetic-private-token"))
                XCTAssertFalse(error.localizedDescription.contains("Bearer"))
            }
        }
    }

    func testLF03923RedirectResponseIsRejectedWithoutASecondCredentialedRequest() async throws {
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/image.jpg"
        let (inspection, reference) = try source(user: user, path: path)
        var requestCount = 0
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            requestCount += 1
            let response = HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil,
                headerFields: ["Location": "https://foreign.invalid/image.jpg"] )!
            return (Data(), response)
        }

        do {
            _ = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-token")
            XCTFail("Redirect responses must not be followed")
        } catch {
            XCTAssertEqual((error as? LocalHistoryImageHTTPError)?.failure, .invalidResponse(302))
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testLF03923EmptyOversizedChangedAddressAndHashMismatchAreDistinct() async throws {
        enum ResponseKind { case empty, oversized, changedAddress, hashMismatch }
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/legacy.jpg"
        let bytes = Data("synthetic-image".utf8)

        for kind in [ResponseKind.empty, .oversized, .changedAddress, .hashMismatch] {
            let imageHash: String?
            switch kind {
            case .hashMismatch: imageHash = String(repeating: "0", count: 64)
            case .empty, .oversized, .changedAddress: imageHash = nil
            }
            let (inspection, reference) = try source(user: user, path: path, imageHash: imageHash)
            let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
                let responseURL: URL
                let status: Int
                let data: Data
                switch kind {
                case .empty:
                    responseURL = request.url!; status = 200; data = Data()
                case .oversized:
                    responseURL = request.url!; status = 200; data = Data(repeating: 0, count: 16 * 1024 * 1024 + 1)
                case .changedAddress:
                    responseURL = URL(string: "https://fixture.invalid/storage/v1/object/authenticated/receipt-images/other.jpg")!
                    status = 200; data = bytes
                case .hashMismatch:
                    responseURL = request.url!; status = 200; data = bytes
                }
                return (data, HTTPURLResponse(url: responseURL, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            let expected: LocalHistoryImageDownloadError
            switch kind {
            case .empty: expected = .emptyResponse
            case .oversized: expected = .imageTooLarge
            case .changedAddress: expected = .responseAddressMismatch
            case .hashMismatch: expected = .hashMismatch
            }

            do {
                _ = try await downloader.download(reference: reference, inspection: inspection,
                    cloudUserID: user, accessToken: "synthetic-token")
                XCTFail("Invalid image response must be rejected")
            } catch {
                XCTAssertEqual(error as? LocalHistoryImageDownloadError, expected)
            }
        }
    }

    func testLF03923StaleAccountAfterResponseDoesNotReturnImageBytes() async throws {
        let user = UUID().uuidString.lowercased()
        let path = "2026-10-24/legacy.jpg"
        let (inspection, reference) = try source(user: user, path: path)
        var isCurrent = true
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            isCurrent = false
            return (Data("late-response".utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }

        do {
            _ = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: user, accessToken: "synthetic-token", isCurrent: { isCurrent })
            XCTFail("A result returned after account invalidation must not escape")
        } catch is CancellationError {
            // Expected: the current migration attempt changed while the request was in flight.
        }
    }

    private func source(user: String, path: String, imageHash: String? = nil) throws -> (LocalHistoryMigrationInspection, LocalHistoryMigrationImageReference) {
        let recordID = UUID().uuidString.lowercased()
        var row: [String: AnyCodable] = [
            "id": AnyCodable(recordID),
            "user_id": AnyCodable(user),
            "source_image_path": AnyCodable(path)
        ]
        if let imageHash { row["source_image_hash"] = AnyCodable(imageHash) }
        let inspection = LocalHistoryMigrationInspection(cloudUserID: user, rows: [
            .records: [row]
        ], blockers: [])
        return (inspection, try XCTUnwrap(inspection.imageReference(for: path)))
    }
}
