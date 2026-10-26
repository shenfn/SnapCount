import Foundation

struct LocalHistoryMigrationPreparedSource {
    let inspection: LocalHistoryMigrationInspection
    let images: [String: Data]
    let state: LocalHistoryMigrationState
}

struct LocalHistoryMigrationProgress {
    enum Phase: Equatable { case readingSource, downloadingImages }
    let phase: Phase
    let currentTable: LocalHistorySourceTable?
    let rowsRead: Int
    let knownRowTotal: Int?
    let pagesRead: Int
    let imagesProcessed: Int
    let imagesTotal: Int
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
                 isCurrent: () -> Bool,
                 onProgress: (@MainActor (LocalHistoryMigrationProgress) -> Void)? = nil) async throws -> LocalHistoryMigrationPreparedSource {
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        let state = try cache.begin(profileID: profileID, cloudUserID: cloudUserID)
        do {
            var rows: [LocalHistorySourceTable: [[String: AnyCodable]]] = [:]
            var completedTables = Set<LocalHistorySourceTable>()
            var rowsRead = 0
            var pagesRead = 0
            for table in LocalHistorySourceTable.allCases {
                var cursor: String?
                var seenCursors = Set<String>()
                repeat {
                    guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    guard seenCursors.insert(cursor ?? "start").inserted else { throw LocalDataError.invalidRecord }
                    await onProgress?(LocalHistoryMigrationProgress(
                        phase: .readingSource, currentTable: table, rowsRead: rowsRead, knownRowTotal: nil,
                        pagesRead: pagesRead, imagesProcessed: 0, imagesTotal: 0
                    ))
                    let page: LocalHistorySourcePage
                    if let cached = try cache.page(state: state, table: table, afterID: cursor) { page = cached }
                    else {
                        do {
                            page = try await source.page(table: table, cloudUserID: cloudUserID, afterID: cursor, accessToken: accessToken)
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch let error as LocalHistoryMigrationContextError {
                            throw error
                        } catch {
                            throw LocalHistoryMigrationContextError(table: table.rawValue, field: nil, recordID: "", underlying: error)
                        }
                        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                        try cache.savePage(state: state, table: table, afterID: cursor, page: page)
                    }
                    rows[table, default: []].append(contentsOf: page.rows)
                    rowsRead += page.rows.count
                    pagesRead += 1
                    guard rows.values.reduce(0, { $0 + $1.count }) <= 100_000 else { throw LocalCompleteBackupError.archiveTooLarge }
                    cursor = page.nextCursor
                    if cursor == nil { completedTables.insert(table) }
                    await onProgress?(LocalHistoryMigrationProgress(
                        phase: .readingSource, currentTable: cursor == nil ? nil : table, rowsRead: rowsRead,
                        knownRowTotal: completedTables.count == LocalHistorySourceTable.allCases.count ? rowsRead : nil,
                        pagesRead: pagesRead, imagesProcessed: 0, imagesTotal: 0
                    ))
                } while cursor != nil
            }
            let inspection = LocalHistoryMigrationInspection(cloudUserID: cloudUserID, rows: rows,
                blockers: LocalHistoryMigrationUseCase.blockers(rows))
            if !inspection.blockers.isEmpty {
                return LocalHistoryMigrationPreparedSource(inspection: inspection, images: [:], state: state)
            }
            var images: [String: Data] = [:]
            await onProgress?(LocalHistoryMigrationProgress(
                phase: .downloadingImages, currentTable: nil, rowsRead: rowsRead, knownRowTotal: rowsRead,
                pagesRead: pagesRead, imagesProcessed: 0, imagesTotal: inspection.sourceImagePaths.count
            ))
            var byteCount = 0
            for path in inspection.sourceImagePaths.sorted() {
                guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                let bytes: Data
                do {
                    if let cached = try cache.image(state: state, sourcePath: path) { bytes = cached }
                    else {
                        let fetched = try await downloader.download(paths: [path], cloudUserID: cloudUserID,
                            accessToken: accessToken, isCurrent: isCurrent)
                        guard let data = fetched[path], isCurrent(), !Task.isCancelled else { throw CancellationError() }
                        try cache.saveImage(state: state, sourcePath: path, data: data)
                        bytes = data
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LocalHistoryMigrationContextError {
                    throw error
                } catch {
                    let source = inspection.imageReference(for: path)
                    throw LocalHistoryMigrationContextError(
                        table: source?.table ?? "image_objects",
                        field: source?.field ?? "path",
                        recordID: source?.recordID ?? "",
                        underlying: error
                    )
                }
                byteCount += bytes.count
                guard byteCount <= 128 * 1024 * 1024 else { throw LocalCompleteBackupError.archiveTooLarge }
                images[path] = bytes
                await onProgress?(LocalHistoryMigrationProgress(
                    phase: .downloadingImages, currentTable: nil, rowsRead: rowsRead, knownRowTotal: rowsRead,
                    pagesRead: pagesRead, imagesProcessed: images.count, imagesTotal: inspection.sourceImagePaths.count
                ))
            }
            return LocalHistoryMigrationPreparedSource(inspection: inspection, images: images, state: state)
        } catch {
            try? cache.pause(state)
            throw error
        }
    }
}
