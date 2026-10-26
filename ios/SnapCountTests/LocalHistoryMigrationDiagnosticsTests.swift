import XCTest
@testable import SnapCount

final class LocalHistoryMigrationDiagnosticsTests: XCTestCase {
    func testLF03923ImageFailureCategoriesStayDistinctAndRedacted() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let privateID = UUID().uuidString
        let expected: [(LocalHistoryImageDownloadError, String)] = [
            (.unsupportedPathFormat, "HIST-IMAGE-PATH-UNSUPPORTED"),
            (.sourceScopeMismatch, "HIST-IMAGE-SCOPE-MISMATCH"),
            (.sessionExpired, "HIST-IMAGE-401"),
            (.accessDenied, "HIST-IMAGE-403"),
            (.missingImage, "HIST-IMAGE-404"),
            (.missingTemporaryImage, "HIST-TEMP-IMAGE-404"),
            (.invalidResponse(503), "HIST-IMAGE-HTTP"),
            (.emptyResponse, "HIST-IMAGE-EMPTY"),
            (.imageTooLarge, "HIST-IMAGE-SINGLE-TOO-LARGE"),
            (.totalSizeExceeded, "HIST-IMAGE-TOTAL-TOO-LARGE"),
            (.responseAddressMismatch, "HIST-IMAGE-RESPONSE-ADDRESS"),
            (.hashMismatch, "HIST-IMAGE-HASH")
        ]

        for (error, code) in expected {
            let context = LocalHistoryMigrationContextError(
                table: "data_records", field: "source_image_path", recordID: privateID, underlying: error)
            let entry = store.record(context, phase: "读取原图", sourceTable: "data_records",
                sourceField: "source_image_path", recordID: privateID,
                progressSummary: "2221行，28页，原图0/1368",
                attemptID: UUID(), committed: false)

            XCTAssertEqual(entry.code, code)
            XCTAssertEqual(entry.sourceTable, "data_records")
            XCTAssertEqual(entry.sourceField, "source_image_path")
            XCTAssertEqual(entry.recordHint, String(LocalImageStore.sha256(Data(privateID.lowercased().utf8)).prefix(10)))
            XCTAssertEqual(entry.progressSummary, "2221行28页原图0/1368")
            XCTAssertFalse(entry.committed)
            XCTAssertTrue(entry.userMessage.contains("本次尚未入账"))
            XCTAssertFalse(entry.shareText.contains(privateID))
            XCTAssertFalse(entry.shareText.contains("https://"))
            XCTAssertFalse(entry.shareText.contains("token="))
            XCTAssertFalse(entry.shareText.contains("source_image_path/2026-10-24"))
            XCTAssertFalse(entry.safeReason?.isEmpty ?? true)
            XCTAssertFalse(entry.recoveryAction.isEmpty)
        }
    }

    func testLF039UnknownFailurePersistsOnlyRedactedBoundedDiagnostic() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let privateID = "f6e7c494-1a2b-4c3d-8e9f-0123456789ab"
        let error = NSError(domain: "fixture.network", code: 503, userInfo: [
            NSLocalizedDescriptionKey: "https://fixture.invalid/image?token=synthetic-secret Bearer synthetic-secret"
        ])
        let attempt = UUID()

        let entry = store.record(error, phase: "读取图片", sourceTable: "data_records", sourceField: "source_image_path",
            recordID: privateID, attemptID: attempt, committed: false)
        let entries = try store.recent()
        let file = try String(contentsOf: url, encoding: .utf8)

        XCTAssertEqual(entries, [entry])
        XCTAssertEqual(entry.code, "HIST-UNKNOWN")
        XCTAssertEqual(entry.underlyingCause, "domain-#\(LocalHistoryMigrationDiagnosticStore.identityHint("fixture.network"))#503")
        XCTAssertFalse(entry.shareText.contains(privateID))
        XCTAssertFalse(file.contains(privateID))
        XCTAssertFalse(file.contains("synthetic-secret"))
        XCTAssertFalse(file.contains("fixture.network"))
        XCTAssertFalse(entry.shareText.contains("fixture.invalid"))
    }

    func testLF03914AccountBalanceMismatchHasStableSafeReasonAndSourceContext() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let privateID = UUID().uuidString
        let failure = LocalHistoryMigrationContextError(
            table: "accounts", field: "current_balance", recordID: privateID,
            underlying: LocalHistoryMigrationValidationError.accountBalanceMismatch
        )

        let entry = store.record(failure, phase: "核对历史字段与转换", attemptID: UUID(), committed: false)

        XCTAssertEqual(entry.code, "HIST-ACCOUNT-BALANCE-MISMATCH")
        XCTAssertEqual(entry.phase, "核对历史字段与转换")
        XCTAssertTrue(entry.safeReason?.contains("当前余额与有效账户流水合计不一致") == true)
        XCTAssertTrue(entry.userMessage.contains("原因：账户当前余额与有效账户流水合计不一致"))
        XCTAssertTrue(entry.shareText.contains("原因类别：HIST-ACCOUNT-BALANCE-MISMATCH"))
        XCTAssertFalse(entry.shareText.contains(privateID))
        XCTAssertFalse(entry.shareText.contains("opening balance"))
    }

    @MainActor
    func testLF03914FailureRecordingKeepsStageBeforePreparePause() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let state = AppState(localStorageInitializationMessage: "合成测试", historyMigrationDiagnosticStore: store)

        _ = state.recordHistoryMigrationFailure(LocalDataError.invalidRecord, committed: false,
            phase: "核对历史字段与转换")

        XCTAssertEqual(try store.recent().last?.phase, "核对历史字段与转换")
    }

    @MainActor
    func testLF03915AccountResetClearsPreviousMigrationDiagnosisAndPhase() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let state = AppState(localStorageInitializationMessage: "合成测试", historyMigrationDiagnosticStore: store)
        state.currentUserId = UUID().uuidString
        state.historyMigrationDiagnostic = store.record(LocalDataError.invalidRecord, phase: "已入账",
            accountID: state.currentUserId, attemptID: UUID(), committed: true)
        state.historyMigrationPhase = "已入账"

        state.resetUserScopedState()

        XCTAssertNil(state.historyMigrationDiagnostic)
        XCTAssertEqual(state.historyMigrationPhase, "")
        state.currentUserId = UUID().uuidString
        state.loadLatestHistoryMigrationDiagnostic()
        XCTAssertNil(state.historyMigrationDiagnostic)
    }

    func testLF039DiagnosticStoreRetainsOnlyRecentFiftyEntries() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let now = Date()

        for index in 0..<60 {
            _ = store.record(LocalDataError.invalidRecord, phase: "映射", attemptID: UUID(), committed: false,
                at: now.addingTimeInterval(TimeInterval(index - 60)))
        }

        let entries = try store.recent()
        XCTAssertEqual(entries.count, LocalHistoryMigrationDiagnosticStore.maximumEntries)
        XCTAssertEqual(entries.first?.occurredAt, now.addingTimeInterval(-50))
        XCTAssertEqual(entries.last?.occurredAt, now.addingTimeInterval(-1))
        let size = try (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue
        XCTAssertLessThanOrEqual(size ?? Int.max, LocalHistoryMigrationDiagnosticStore.maximumFileBytes)
    }

    func testLF039ExpiredDiagnosticsAreRemovedFromDisk() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        _ = store.record(LocalDataError.invalidRecord, phase: "旧诊断", attemptID: UUID(), committed: false,
            at: Date().addingTimeInterval(-LocalHistoryMigrationDiagnosticStore.maximumAge - 1))

        XCTAssertTrue(try store.recent().isEmpty)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "[]")
    }

    func testLF04005DiagnosticRecoveryCannotResolveAnotherAccountsFailure() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let accountA = UUID().uuidString
        let accountB = UUID().uuidString
        let entry = store.record(LocalDataError.invalidRecord, phase: "预检暂停", accountID: accountA,
            attemptID: UUID(), committed: false)

        try store.resolve(entry.id, outcome: "不应跨账号更新", expectedAccountID: accountB)
        XCTAssertNil(try store.recent().last?.resolution)

        try store.resolve(entry.id, outcome: "本次账号已恢复", expectedAccountID: accountA)
        XCTAssertEqual(try store.recent().last?.resolution, "本次账号已恢复")
    }

    func testLF04009SyncAndPostCommitFailuresHaveScopedSafeDiagnostics() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("history-migration-diagnostics.json")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = try LocalHistoryMigrationDiagnosticStore(fileURL: url)
        let accountID = UUID().uuidString
        let imageHashFailure = store.record(
            LocalCompleteBackupError.invalidImage("synthetic-private-image-path"),
            phase: "图片校验",
            attemptID: UUID(),
            committed: false
        )
        let syncFailure = store.record(
            LocalSyncError.syncNotAuthorized,
            phase: "同步请求",
            accountID: accountID,
            operation: "local-sync",
            codeOverride: "SYNC-NOT-AUTHORIZED",
            attemptID: UUID(),
            committed: false
        )
        let refreshFailure = store.record(
            LocalWriteRefreshError(),
            phase: "本机列表刷新",
            operation: "local-write-refresh",
            codeOverride: "LOCAL-POST-COMMIT-REFRESH",
            attemptID: UUID(),
            committed: true
        )

        XCTAssertTrue(syncFailure.userMessage.contains("云同步失败。本机事实仍保留；云端同步结果可能未完整确认。"))
        XCTAssertTrue(syncFailure.shareText.contains("操作结果：未确认全部完成"))
        XCTAssertEqual(imageHashFailure.code, "HIST-IMAGE-HASH")
        XCTAssertFalse(imageHashFailure.shareText.contains("synthetic-private-image-path"))
        XCTAssertTrue(syncFailure.userMessage.contains("诊断编号：\(syncFailure.id)"))
        XCTAssertEqual(refreshFailure.code, "LOCAL-POST-COMMIT-REFRESH")
        XCTAssertTrue(refreshFailure.committed)
        XCTAssertNil(try store.resolveLatest(operation: "local-sync", outcome: "跨账号恢复", expectedAccountID: UUID().uuidString))
        let resolved = try store.resolveLatest(operation: "local-sync", outcome: "同步已完成", expectedAccountID: accountID)
        XCTAssertEqual(resolved?.resolution, "同步已完成")
        XCTAssertEqual(try store.recent().last?.id, refreshFailure.id)
    }
}
