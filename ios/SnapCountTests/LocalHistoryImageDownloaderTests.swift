import XCTest
@testable import SnapCount

final class LocalHistoryImageDownloaderTests: XCTestCase {
    func testLF03905HTTPFailuresAreDistinctAndNeverExposeBearer() async throws {
        let user = UUID().uuidString.lowercased()
        let cases: [(Int, LocalHistoryImageDownloadError)] = [(401, .sessionExpired), (403, .accessDenied), (404, .missingImage)]
        for (status, expected) in cases {
            let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
                (Data("Bearer synthetic-private-token".utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
            do {
                _ = try await downloader.download(paths: ["\(user)/image.jpg"], cloudUserID: user, accessToken: "synthetic-private-token")
                XCTFail("HTTP error must not become a successful image")
            } catch {
                XCTAssertEqual(error as? LocalHistoryImageDownloadError, expected)
                XCTAssertFalse(error.localizedDescription.contains("synthetic-private-token"))
                XCTAssertFalse(error.localizedDescription.contains("Bearer"))
            }
        }
    }

    func testLF03905ExpiredSignedURLRetriesOnlySameOwnersAuthenticatedObject() async throws {
        let user = UUID().uuidString.lowercased()
        let bytes = Data("original".utf8)
        let path = "https://fixture.invalid/storage/v1/object/sign/receipt-images/\(user)/image.jpg?token=expired-synthetic"
        var requests: [URLRequest] = []
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            requests.append(request)
            let signed = request.url!.path.contains("/sign/")
            return (signed ? Data() : bytes, HTTPURLResponse(url: request.url!, statusCode: signed ? 400 : 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await downloader.download(paths: [path], cloudUserID: user, accessToken: "synthetic-private-token")
        XCTAssertEqual(result[path], bytes)
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].url?.path, "/storage/v1/object/authenticated/receipt-images/\(user)/image.jpg")
        XCTAssertNil(requests[1].url?.query)
        XCTAssertEqual(requests[1].url?.host, "fixture.invalid")
    }
    func testLF039ImageDownloadsStayInCurrentOwnersStorageAndCheckHash() async throws {
        let user = UUID().uuidString.lowercased()
        let path = "\(user)/original.jpg"
        let bytes = Data("synthetic-original".utf8)
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            XCTAssertEqual(request.url?.host, "fixture.invalid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-token")
            return (bytes, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await downloader.download(paths: [path], cloudUserID: user,
            accessToken: "synthetic-test-token", expectedHashes: [path: LocalImageStore.sha256(bytes)])
        XCTAssertEqual(result[path], bytes)
    }

    func testLF043ForeignHostOwnerAndTraversalNeverStartDownload() async throws {
        let user = UUID().uuidString.lowercased()
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { _ in
            XCTFail("Rejected path must not send credentials or start network I/O")
            throw LocalDataError.invalidRecord
        }
        for path in ["https://foreign.invalid/photo.jpg", "other-user/photo.jpg", "\(user)/../photo.jpg", "\(user)/%2e%2e/photo.jpg"] {
            do {
                _ = try await downloader.download(paths: [path], cloudUserID: user, accessToken: "synthetic-test-token")
                XCTFail("Invalid image source accepted: \(path)")
            } catch { }
        }
    }

    func testLF039ImageRedirectAndChangedIdentityCannotCommitBytes() async throws {
        let user = UUID().uuidString.lowercased()
        let downloader = LocalHistoryImageDownloader(baseURL: URL(string: "https://fixture.invalid")!) { request in
            (Data("wrong".utf8), HTTPURLResponse(url: request.url!, statusCode: 302, httpVersion: nil, headerFields: ["Location": "https://foreign.invalid"])!)
        }
        do {
            _ = try await downloader.download(paths: ["\(user)/photo.jpg"], cloudUserID: user, accessToken: "synthetic-test-token")
            XCTFail("Redirect must not be accepted as original image bytes")
        } catch { }
    }
}
