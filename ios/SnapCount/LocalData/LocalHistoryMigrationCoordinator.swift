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

    @MainActor
    func prepare(profileID: UUID, cloudUserID: String, accessToken: String,
                 isCurrent: @escaping () -> Bool,
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
            let imageTotal = inspection.sourceImagePaths.count
            let images = try await loadImages(inspection: inspection, cloudUserID: cloudUserID,
                accessToken: accessToken, state: state, isCurrent: isCurrent) { processed in
                onProgress?(LocalHistoryMigrationProgress(
                    phase: .downloadingImages, currentTable: nil, rowsRead: rowsRead, knownRowTotal: rowsRead,
                    pagesRead: pagesRead, imagesProcessed: processed, imagesTotal: imageTotal
                ))
            }
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            return LocalHistoryMigrationPreparedSource(inspection: inspection, images: images, state: state)
        } catch {
            try? cache.pause(state)
            throw error
        }
    }

    private struct ImageResult {
        let reference: LocalHistoryMigrationImageReference
        let result: Result<Data, Error>
    }

    /// Shared by preflight and confirmation. Passing no state forces a fresh integrity recheck.
    @MainActor
    func loadImages(inspection: LocalHistoryMigrationInspection, cloudUserID: String, accessToken: String,
                    state: LocalHistoryMigrationState? = nil, isCurrent: @escaping () -> Bool,
                    onProgress: (@MainActor (Int) -> Void)? = nil) async throws -> [String: Data] {
        guard inspection.blockers.isEmpty,
              let owner = UUID(uuidString: cloudUserID), owner == UUID(uuidString: inspection.cloudUserID),
              state.map({ UUID(uuidString: $0.cloudUserID) == owner }) ?? true else {
            throw LocalHistoryImageDownloadError.sourceScopeMismatch
        }
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        var images: [String: Data] = [:]
        var byteCount = 0
        var pending: [LocalHistoryMigrationImageReference] = []
        onProgress?(0)
        for path in inspection.sourceImagePaths.sorted() {
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            guard let reference = inspection.imageReference(for: path) else {
                throw LocalHistoryImageDownloadError.sourceScopeMismatch
            }
            do {
                let expectedHash = try inspection.expectedImageHash(for: path)
                let cached = try state.flatMap { try cache.image(state: $0, sourcePath: path) }
                if let cached, expectedHash.map({ LocalImageStore.sha256(cached) == $0 }) ?? true {
                    byteCount = try Self.checkedImageByteCount(current: byteCount, adding: cached.count)
                    images[path] = cached
                    onProgress?(images.count)
                } else { pending.append(reference) }
            } catch {
                throw LocalHistoryMigrationContextError(table: reference.table, field: reference.field,
                    recordID: reference.recordID, underlying: error)
            }
        }

        try await withThrowingTaskGroup(of: ImageResult.self) { group in
            var next = 0
            var firstError: Error?
            // ponytail: At most three requests in flight; keep this bound until device measurements justify changing it.
            for _ in 0..<min(3, pending.count) {
                let reference = pending[next]; next += 1
                group.addTask { @MainActor in
                    await self.downloadResult(reference, inspection: inspection, cloudUserID: cloudUserID,
                        accessToken: accessToken, isCurrent: isCurrent)
                }
            }
            while let outcome = try await group.next() {
                guard isCurrent(), !Task.isCancelled else { group.cancelAll(); throw CancellationError() }
                let reference = outcome.reference
                switch outcome.result {
                case .success(let bytes):
                    do {
                        let total = try Self.checkedImageByteCount(current: byteCount, adding: bytes.count)
                        if let state { try cache.saveImage(state: state, sourcePath: reference.path, data: bytes) }
                        byteCount = total
                        images[reference.path] = bytes
                        onProgress?(images.count)
                    } catch {
                        if firstError == nil {
                            firstError = LocalHistoryMigrationContextError(table: reference.table, field: reference.field,
                                recordID: reference.recordID, underlying: error)
                        }
                    }
                case .failure(let error):
                    if error is CancellationError { group.cancelAll(); throw error }
                    if firstError == nil { firstError = error }
                }
                // Drain already-started successes into cache after a failure, but do not start another request.
                if firstError == nil, next < pending.count {
                    let reference = pending[next]; next += 1
                    group.addTask { @MainActor in
                        await self.downloadResult(reference, inspection: inspection, cloudUserID: cloudUserID,
                            accessToken: accessToken, isCurrent: isCurrent)
                    }
                }
            }
            if let firstError { throw firstError }
        }
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        return images
    }

    @MainActor
    private func downloadResult(_ reference: LocalHistoryMigrationImageReference,
                                inspection: LocalHistoryMigrationInspection, cloudUserID: String,
                                accessToken: String, isCurrent: () -> Bool) async -> ImageResult {
        do {
            let fetched = try await downloader.download(reference: reference, inspection: inspection,
                cloudUserID: cloudUserID, accessToken: accessToken, isCurrent: isCurrent)
            guard let data = fetched[reference.path] else { throw LocalHistoryImageDownloadError.sourceScopeMismatch }
            return ImageResult(reference: reference, result: .success(data))
        } catch is CancellationError {
            return ImageResult(reference: reference, result: .failure(CancellationError()))
        } catch {
            return ImageResult(reference: reference, result: .failure(LocalHistoryMigrationContextError(
                table: reference.table, field: reference.field, recordID: reference.recordID, underlying: error)))
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
