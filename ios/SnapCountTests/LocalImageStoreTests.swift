import Foundation
import XCTest
@testable import SnapCount

final class LocalImageStoreTests: XCTestCase {
    func testLF04201RejectsSymlinkThatEscapesImageRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-image-root-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-image-outside-\(UUID().uuidString).jpg")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("intake", isDirectory: true), withIntermediateDirectories: true)
        let data = Data("outside-image".utf8)
        try data.write(to: outside)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("intake/escape.jpg"),
            withDestinationURL: outside
        )
        let store = try LocalImageStore(rootDirectory: root)

        XCTAssertThrowsError(try store.data(at: "intake/escape.jpg")) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidIdentifier)
        }
        XCTAssertThrowsError(try store.remove(path: "intake/escape.jpg")) { error in
            XCTAssertEqual(error as? LocalDataError, .invalidIdentifier)
        }
        XCTAssertEqual(try Data(contentsOf: outside), data)
    }
}
