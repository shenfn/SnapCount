import Foundation

func temporaryDatabaseURL(extension pathExtension: String = "sqlite") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("local-database-spike-\(UUID().uuidString)")
        .appendingPathExtension(pathExtension)
}
func removeDatabase(at databaseURL: URL) {
    let candidates = [
        databaseURL,
        URL(fileURLWithPath: databaseURL.path + "-shm"),
        URL(fileURLWithPath: databaseURL.path + "-wal")
    ]
    for candidate in candidates {
        try? FileManager.default.removeItem(at: candidate)
    }
}
