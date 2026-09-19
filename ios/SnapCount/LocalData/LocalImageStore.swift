import Foundation
import CryptoKit

struct LocalImageReference: Equatable {
    let path: String
    let hash: String
}

final class LocalImageStore {
    private let rootDirectory: URL
    private let fileManager: FileManager

    init(rootDirectory: URL, fileManager: FileManager = .default) throws {
        self.rootDirectory = rootDirectory.standardizedFileURL
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: self.rootDirectory,
            withIntermediateDirectories: true
        )
        try? fileManager.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: self.rootDirectory.path
        )
    }

    convenience init() throws {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("JieziLocalData/images", isDirectory: true)
        try self.init(rootDirectory: directory)
    }

    func save(data: Data, owner: String, bucket: String = "records") throws -> LocalImageReference {
        let hash = Self.sha256(data)
        let filename = Self.sha256(Data(owner.utf8)) + ".jpg"
        let relativePath = "\(bucket)/\(filename)"
        let destination = try validatedURL(for: relativePath)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: destination, options: .atomic)
        return LocalImageReference(path: relativePath, hash: hash)
    }

    func url(for relativePath: String) -> URL {
        (try? validatedURL(for: relativePath)) ?? rootDirectory.appendingPathComponent("invalid")
    }

    func remove(path: String?) throws {
        guard let path, !path.isEmpty else { return }
        let fileURL = try validatedURL(for: path)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func contains(path: String?) -> Bool {
        guard let path, !path.isEmpty else { return false }
        return fileManager.fileExists(atPath: url(for: path).path)
    }

    private func validatedURL(for relativePath: String) throws -> URL {
        guard !relativePath.isEmpty,
              !relativePath.hasPrefix("/"),
              !relativePath.contains("..") else {
            throw LocalDataError.invalidIdentifier
        }
        let candidate = rootDirectory.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path == rootDirectory.path || candidate.path.hasPrefix(rootDirectory.path + "/") else {
            throw LocalDataError.invalidIdentifier
        }
        return candidate
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
