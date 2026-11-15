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
    /// 在下载原图之前跑一遍结构预检：先把「能不能入账」问清楚，再花时间下载。
    private let validateStructure: ((LocalHistoryMigrationInspection, UUID) throws -> Void)?

    init(source: LocalHistoryMigrationSource = LocalHistoryMigrationSource(), downloader: LocalHistoryImageDownloader,
         cache: LocalHistoryMigrationCache,
         validateStructure: ((LocalHistoryMigrationInspection, UUID) throws -> Void)? = nil) {
        self.source = source; self.downloader = downloader; self.cache = cache
        self.validateStructure = validateStructure
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
            try validateStructure?(inspection, profileID)
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
            var abortingError: Error?
            // 图片总量到达上限后不再发起新请求，已拿到的照常入账，剩余图片留空。
            var budgetExhausted = false
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
                        // 容量到顶就停止后续下载（丢的是图片，不是记录）；其它写入失败只丢这一张。
                        if (error as? LocalHistoryImageDownloadError) == .totalSizeExceeded {
                            budgetExhausted = true
                        }
                    }
                case .failure(let error):
                    if error is CancellationError { group.cancelAll(); throw error }
                    if Self.isFatalImageFailure(error), abortingError == nil { abortingError = error }
                }
                // Drain already-started successes into cache after a fatal error, but do not start another request.
                if abortingError == nil, !budgetExhausted, next < pending.count {
                    let reference = pending[next]; next += 1
                    group.addTask { @MainActor in
                        await self.downloadResult(reference, inspection: inspection, cloudUserID: cloudUserID,
                            accessToken: accessToken, isCurrent: isCurrent)
                    }
                }
            }
            if let abortingError { throw abortingError }
        }
        guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
        return images
    }

    /// 图片是记录的补充材料，读不到不该拖住整包。只有「继续下去也没有意义」的情况才中断：
    /// - 取消：用户主动停止。
    /// - 会话失效（HTTP 401）：剩余图片会全部失败，应让用户重新登录，而不是把上千张图逐张跳过。
    /// - 身份/范围类错误：本机与云账户归属不一致，继续写库是错的。
    /// 其余（404/NoSuchKey、403 与 400 的 AccessDenied、空响应、单图超限、哈希不符、
    /// 路径不被接受）都只是「这一张图拿不到」：跳过该图，对应记录照常入账，图片字段留空。
    private static func isFatalImageFailure(_ error: Error) -> Bool {
        guard let context = error as? LocalHistoryMigrationContextError else { return true }
        if context.underlying is LocalHistoryMigrationError { return true }
        if let http = context.underlying as? LocalHistoryImageHTTPError {
            return http.failure == .sessionExpired
        }
        if let image = context.underlying as? LocalHistoryImageDownloadError {
            return image == .sessionExpired
        }
        return false
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
