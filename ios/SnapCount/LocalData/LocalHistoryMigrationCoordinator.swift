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
                guard let reference = inspection.imageReference(for: path) else {
                    throw LocalHistoryMigrationContextError(table: "image_objects", field: "path", recordID: "",
                        underlying: LocalHistoryImageDownloadError.sourceScopeMismatch)
                }
                let bytes: Data
                let needsCacheWrite: Bool
                do {
                    let expectedHash = try inspection.expectedImageHash(for: path)
                    let cached = try cache.image(state: state, sourcePath: path)
                    if let cached, expectedHash.map({ LocalImageStore.sha256(cached) == $0 }) ?? true {
                        bytes = cached
                        needsCacheWrite = false
                    }
                    else {
                        let fetched = try await downloader.download(reference: reference, inspection: inspection,
                            cloudUserID: cloudUserID, accessToken: accessToken, isCurrent: isCurrent)
                        guard let data = fetched[path] else { throw LocalHistoryImageDownloadError.sourceScopeMismatch }
                        bytes = data
                        needsCacheWrite = true
                    }
                    guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
                    let nextByteCount = try Self.checkedImageByteCount(current: byteCount, adding: bytes.count)
                    if needsCacheWrite { try cache.saveImage(state: state, sourcePath: path, data: bytes) }
                    byteCount = nextByteCount
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
                images[path] = bytes
                await onProgress?(LocalHistoryMigrationProgress(
                    phase: .downloadingImages, currentTable: nil, rowsRead: rowsRead, knownRowTotal: rowsRead,
                    pagesRead: pagesRead, imagesProcessed: images.count, imagesTotal: inspection.sourceImagePaths.count
                ))
            }
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            return LocalHistoryMigrationPreparedSource(inspection: inspection, images: images, state: state)
        } catch {
            try? cache.pause(state)
            throw error
        }
    }

    static func checkedImageByteCount(current: Int, adding: Int) throws -> Int {
        guard current >= 0, adding >= 0 else { throw LocalHistoryImageDownloadError.totalSizeExceeded }
        let (total, overflow) = current.addingReportingOverflow(adding)
        guard !overflow, total <= 128 * 1024 * 1024 else {
            throw LocalHistoryImageDownloadError.totalSizeExceeded
        }
        return total
    }
}
