import XCTest
@testable import SnapCount

final class LocalHistoryImageDownloaderTests: XCTestCase {
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
