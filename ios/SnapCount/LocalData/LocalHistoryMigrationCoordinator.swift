import Foundation

struct LocalHistoryMigrationPreparedSource {
    let inspection: LocalHistoryMigrationInspection
    let images: [String: Data]
    let state: LocalHistoryMigrationState
}

/// Downloads source material resumably. User facts remain untouched until the caller imports the archive.
final class LocalHistoryMigrationCoordinator {
    private let source: LocalHistoryMigrationSource
    private let downloader: LocalHistoryImageDownloader
    private let cache: LocalHistoryMigrationCache

    init(source: LocalHistoryMigrationSource = LocalHistoryMigrationSource(), downloader: LocalHistoryImageDownloader,
         cache: LocalHistoryMigrationCache) {
        self.source = source; self.downloader = downloader; self.cache = cache
    }

    func prepare(profileID: UUID, cloudUserID: String, accessToken: String,
                 isCurrent: () -> Bool) async throws -> LocalHistoryMigrationPreparedSource {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        let state = try cache.begin(profileID: profileID, cloudUserID: cloudUserID)
        do {
            var rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [:]
            for table in LocalHistorySourceTable.allCases {
                var cursor: String?
                var seenCursors = Set<String>()
                repeat {
                    guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    guard seenCursors.insert(cursor ?? "start").inserted else { throw LocalDataError.invalidRecord }
                    let page: LocalHistorySourcePage
                    if let cached = try cache.page(state: state, table: table, afterID: cursor) { page = cached }
                    else {
                        page = try await source.page(table: table, cloudUserID: cloudUserID, afterID: cursor, accessToken: accessToken)
                        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                        try cache.savePage(state: state, table: table, afterID: cursor, page: page)
                    }
                    rows[table, default: []].append(contentsOf: page.rows)
                    guard rows.values.reduce(0, { $0 + $1.count }) <= 100_000 else { throw LocalCompleteBackupError.archiveTooLarge }
                    cursor = page.nextCursor
                } while cursor != nil
            }
            let inspection = LocalHistoryMigrationInspection(cloudUserID: cloudUserID, rows: rows,
                blockers: LocalHistoryMigrationUseCase.blockers(rows))
            if !inspection.blockers.isEmpty {
                return LocalHistoryMigrationPreparedSource(inspection: inspection, images: [:], state: state)
            }
            var images: [String: Data] = [:]
            var byteCount = 0
            for path in inspection.sourceImagePaths.sorted() {
                guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                let bytes: Data
                if let cached = try cache.image(state: state, sourcePath: path) { bytes = cached }
                else {
                    let fetched = try await downloader.download(paths: [path], cloudUserID: cloudUserID,
                        accessToken: accessToken, isCurrent: isCurrent)
                    guard let data = fetched[path], isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    try cache.saveImage(state: state, sourcePath: path, data: data)
                    bytes = data
                }
                byteCount += bytes.count
                guard byteCount <= 128 * 1024 * 1024 else { throw LocalCompleteBackupError.archiveTooLarge }
                images[path] = bytes
            }
            return LocalHistoryMigrationPreparedSource(inspection: inspection, images: images, state: state)
        } catch {
            try? cache.pause(state)
            throw error
        }
    }
}
