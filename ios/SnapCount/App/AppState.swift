import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var isSignedIn = false
    @Published var currentUserEmail = ""
    @Published var lastShortcutMessage: String?
    @Published var isBootstrapping = true
    @Published var isSigningIn = false
    @Published var authMessage: String?
    @Published var authMessageIsError = false
    @Published var hasUploadToken = false
    @Published var dashboard = DashboardSnapshot()
    @Published var dashboardMessage: String?
    @Published var isLoadingDashboard = false
    @Published var shortcutCredentialMessage: String?
    @Published var notificationPermissionMessage: String?
    @Published var notificationPermissionStatusText = "检查中"
    @Published var shortcutNotificationsEnabled = ShortcutFeedbackPreferences.notificationsEnabled
    @Published var shortcutResultCardEnabled = ShortcutFeedbackPreferences.resultCardEnabled
    @Published var todayPath: [NativeDayDetailRoute] = []
    @Published var inboxPath: [String] = []
    @Published var recordsPath: [String] = []
    @Published var selectedRecordDetail: NativeRecordDetail?
    @Published var recordDetailMessage: String?
    @Published var isSavingRecordDetail = false
    @Published var isDeletingRecordDetail = false

    private let authService = SupabaseAuthService()
    private let dashboardRepository: DashboardRepositoryProtocol
    private let recordRepository: RecordRepositoryProtocol
    private let inboxRepository: InboxRepositoryProtocol
    private let domainRepository: DomainRepositoryProtocol
    private let snapshotStore: DashboardSnapshotStoreProtocol
    private let keychain = KeychainStore.shared
    private var hasAskedNotificationPermissionThisSession = false
    private var lastDashboardRefreshAt: Date?
    private var recordDetailCache: [String: NativeRecordDetail] = [:]

    init(
        dashboardRepository: DashboardRepositoryProtocol = DashboardRepository(),
        recordRepository: RecordRepositoryProtocol = RecordRepository(),
        inboxRepository: InboxRepositoryProtocol = InboxRepository(),
        domainRepository: DomainRepositoryProtocol = DomainRepository(),
        snapshotStore: DashboardSnapshotStoreProtocol = DashboardSnapshotStore()
    ) {
        self.dashboardRepository = dashboardRepository
        self.recordRepository = recordRepository
        self.inboxRepository = inboxRepository
        self.domainRepository = domainRepository
        self.snapshotStore = snapshotStore
    }

    func bootstrap() {
        Task {
            await restoreAuthentication()
            isBootstrapping = false
            await refreshNotificationPermissionStatus()
        }
    }

    private func restoreAuthentication() async {
        do {
            let session: SupabaseAuthSession
            do {
                session = try await authService.currentSession()
            } catch {
                guard let legacy = try? requireSession(),
                      let refreshToken = legacy.refreshToken, !refreshToken.isEmpty else {
                    hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
                    updateShortcutCredentialMessage()
                    return
                }
                session = try await authService.restoreSession(accessToken: legacy.accessToken, refreshToken: refreshToken)
            }
            try save(session: session)
            apply(session: session)
            restoreDashboardSnapshot(userId: session.user.id)
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
            Task {
                await refreshDashboard()
                await requestShortcutNotificationPermissionIfNeeded()
            }
        } catch {
            if isInvalidRefreshSessionError(error) {
                invalidateSession(message: "登录状态已失效，请重新登录。")
            } else {
                authMessage = error.localizedDescription
                authMessageIsError = true
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        authMessage = nil
        authMessageIsError = false

        do {
            let session = try await authService.signIn(email: email, password: password)
            let uploadToken = try await authService.fetchUploadToken(
                userId: session.user.id,
                accessToken: session.accessToken
            )
            try save(session: session, uploadToken: uploadToken)
            apply(session: session)
            hasUploadToken = true
            authMessage = "已登录，快捷指令凭据已同步。"
            updateShortcutCredentialMessage()
            await refreshDashboard()
            await requestShortcutNotificationPermissionIfNeeded()
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
        }

        isSigningIn = false
    }

    func signOut() {
        Task {
            try? await authService.signOut()
            do {
                try keychain.remove(KeychainKeys.authSession)
                try keychain.remove(KeychainKeys.uploadToken)
            } catch {
                authMessage = error.localizedDescription
                authMessageIsError = true
            }
            invalidateSession(message: "")
            authMessage = nil
            authMessageIsError = false
            hasUploadToken = false
            shortcutCredentialMessage = nil
        }
    }

    func verifyShortcutCredential() {
        do {
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
        } catch {
            shortcutCredentialMessage = error.localizedDescription
        }
    }

    func refreshDashboard() async {
        guard !isLoadingDashboard else { return }
        isLoadingDashboard = true
        dashboardMessage = nil
        lastDashboardRefreshAt = Date()

        do {
            var session = try await validSession()
            do {
                var snapshot = try await dashboardRepository.fetchDashboard(accessToken: session.accessToken)
                snapshot.domains = await resolvedDomains(accessToken: session.accessToken, snapshot: snapshot)
                dashboard = snapshot
                try? snapshotStore.save(snapshot, userId: session.user.id)
                recordDetailCache.merge(snapshot.recordDetails) { _, new in new }
                prefetchDashboardImages(snapshot)
            } catch {
                guard isExpiredJWTError(error) else { throw error }
                session = try await validSession(forceRefresh: true)
                var snapshot = try await dashboardRepository.fetchDashboard(accessToken: session.accessToken)
                snapshot.domains = await resolvedDomains(accessToken: session.accessToken, snapshot: snapshot)
                dashboard = snapshot
                try? snapshotStore.save(snapshot, userId: session.user.id)
                recordDetailCache.merge(snapshot.recordDetails) { _, new in new }
                prefetchDashboardImages(snapshot)
            }
        } catch {
            if isInvalidRefreshSessionError(error) {
                invalidateSession(message: "登录状态已失效，请重新登录。")
            } else {
                dashboardMessage = error.localizedDescription
            }
        }

        isLoadingDashboard = false
    }

    private func restoreDashboardSnapshot(userId: String) {
        guard let persisted = try? snapshotStore.load(userId: userId) else { return }
        dashboard = persisted.dashboardSnapshot
        lastDashboardRefreshAt = persisted.savedAt
    }

    private func resolvedDomains(accessToken: String, snapshot: DashboardSnapshot) async -> [NativeDomainDefinition] {
        let counts = Dictionary(grouping: snapshot.dayRecordGroups.flatMap(\.records).filter { $0.kind != .staging }) { $0.domainKey ?? $0.kind.rawValue }.mapValues(\.count)
        let definitions = (try? await domainRepository.fetchDefinitions(accessToken: accessToken)) ?? Self.fallbackDomains
        return definitions.map { domain in NativeDomainDefinition(id: domain.id, name: domain.name, description: domain.description, icon: domain.icon, isSystem: domain.isSystem, schema: domain.schema, display: domain.display, recordCount: counts[domain.id] ?? 0) }
    }

    private static let fallbackDomains = InboxArchiveDomains.all.map { NativeDomainDefinition(id: $0.id, name: $0.title, description: "", icon: "", isSystem: true, schema: [:], display: [:], recordCount: 0) }

    private func prefetchDashboardImages(_ snapshot: DashboardSnapshot) {
        let urls = snapshot.recordDetails.values.compactMap(\.imageURL)
            + snapshot.stagingRecords.compactMap(\.imageURL)
        Task {
            await RemoteImageRepository.shared.prefetch(urls)
        }
    }

    func refreshDashboardIfStale(minInterval: TimeInterval = 3, force: Bool = false) async {
        guard isSignedIn else { return }
        if !force,
           let lastDashboardRefreshAt,
           Date().timeIntervalSince(lastDashboardRefreshAt) < minInterval {
            return
        }
        await refreshDashboard()
    }

    func prefetchRecordDetails(_ references: [String]) {
        let missing = references.filter { recordDetailCache[$0] == nil }.prefix(4)
        for reference in missing {
            Task { await loadRecordDetail(reference: reference) }
        }
    }

    func openDayRecord(_ record: NativeDayRecord) {
        if record.kind == .staging {
            selectedTab = .inbox
            inboxPath = [String(record.reference.dropFirst("staging-".count))]
        } else {
            selectedTab = .records
            recordsPath = [record.reference]
        }
    }

    func openPendingExpense(_ pending: NativePendingExpense) {
        selectedTab = .records
        recordsPath = [pending.reference]
        Task { await loadRecordDetail(reference: pending.reference) }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "jiezi" else { return }

        switch url.host {
        case "inbox":
            selectedTab = .inbox
        case "records", "record":
            selectedTab = .records
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .today
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    func handleShortcutNotificationRoute(_ route: String?) {
        let parts = (route ?? "")
            .split(separator: "/")
            .map(String.init)
        let target = parts.first
        let detailPath = parts.dropFirst().joined(separator: "/")

        switch target {
        case "inbox":
            selectedTab = .inbox
            if !detailPath.isEmpty {
                inboxPath = [detailPath]
            }
        case "records":
            selectedTab = .records
            if !detailPath.isEmpty {
                recordsPath = [detailPath]
            }
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .today
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    func discardStagingRecord(_ record: NativeStagingRecord) async {
        do {
            let session = try await validSession()
            try await inboxRepository.discard(id: record.id, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func retryStagingRecord(_ record: NativeStagingRecord) async {
        do {
            let session = try await validSession()
            _ = try await inboxRepository.retry(id: record.id, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func archiveStagingRecord(_ record: NativeStagingRecord, domainKey: String) async {
        do {
            let session = try await validSession()
            let reference = try await inboxRepository.archive(record, domainKey: domainKey, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
            recordDetailCache.removeValue(forKey: reference)
            selectedRecordDetail = nil
            await loadRecordDetail(reference: reference, force: true)
            selectedTab = .records
            recordsPath = [reference]
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func resolveStagingImageURL(for record: NativeStagingRecord) async throws -> URL {
        guard let imagePath = record.imagePath, !imagePath.isEmpty else {
            throw SupabaseRemoteError.requestFailed("这条记录没有可查看的截图")
        }
        let session = try await validSession()
        return try await inboxRepository.resolveImageURL(path: imagePath, accessToken: session.accessToken)
    }

    func loadRecordDetail(reference: String, force: Bool = false) async {
        recordDetailMessage = nil
        if !force, let cached = recordDetailCache[reference] {
            selectedRecordDetail = cached
            return
        }
        if selectedRecordDetail?.id != reference {
            selectedRecordDetail = nil
        }
        do {
            let session = try await validSession()
            let detail = try await recordRepository.fetchDetail(reference: reference, accessToken: session.accessToken)
            recordDetailCache[reference] = detail
            selectedRecordDetail = detail
        } catch {
            recordDetailMessage = error.localizedDescription
        }
    }

    func saveRecordDetail(_ draft: NativeRecordEditDraft) async -> Bool {
        guard !isSavingRecordDetail else { return false }
        isSavingRecordDetail = true
        recordDetailMessage = nil
        defer { isSavingRecordDetail = false }

        do {
            let session = try await validSession()
            let reference = try await recordRepository.saveDetail(draft, accessToken: session.accessToken)
            await refreshDashboard()
            recordsPath = [reference]
            recordDetailCache.removeValue(forKey: reference)
            await loadRecordDetail(reference: reference, force: true)
            return true
        } catch {
            recordDetailMessage = error.localizedDescription
            return false
        }
    }

    func deleteRecord(reference: String) async -> Bool {
        guard !isDeletingRecordDetail else { return false }
        isDeletingRecordDetail = true
        recordDetailMessage = nil
        defer { isDeletingRecordDetail = false }

        do {
            let session = try await validSession()
            try await recordRepository.delete(reference: reference, accessToken: session.accessToken)
            recordDetailCache.removeValue(forKey: reference)
            selectedRecordDetail = nil
            recordsPath.removeAll()
            await refreshDashboard()
            return true
        } catch {
            recordDetailMessage = error.localizedDescription
            return false
        }
    }

    func requestShortcutNotificationPermission() async {
        let granted = await ShortcutNotificationService.shared.requestAuthorization()
        ShortcutFeedbackPreferences.applyNotificationAuthorization(granted: granted)
        syncShortcutFeedbackPreferences()
        await refreshNotificationPermissionStatus()
        notificationPermissionMessage = granted
            ? "已开启。快捷指令上传完成后，芥子会弹出结果通知，点击通知可回到 App。"
            : "未开启。请在系统设置里允许芥子通知，快捷指令仍会在“显示结果”里展示摘要。"
    }

    func requestShortcutNotificationPermissionIfNeeded() async {
        guard !hasAskedNotificationPermissionThisSession else { return }
        hasAskedNotificationPermissionThisSession = true

        let status = await ShortcutNotificationService.shared.authorizationStatus()
        guard status == .notDetermined else { return }
        await requestShortcutNotificationPermission()
    }

    func refreshNotificationPermissionStatus() async {
        notificationPermissionStatusText = await ShortcutNotificationService.shared.authorizationStatusText()
    }

    func sendTestShortcutNotification() async {
        await ShortcutNotificationService.shared.sendTestNotification()
        await refreshNotificationPermissionStatus()
        notificationPermissionMessage = "已发送测试通知。如果没有声音，请检查静音键、专注模式，以及系统设置里的“声音”开关。"
    }

    func setShortcutNotificationsEnabled(_ enabled: Bool) {
        ShortcutFeedbackPreferences.notificationsEnabled = enabled
        syncShortcutFeedbackPreferences()
    }

    func setShortcutResultCardEnabled(_ enabled: Bool) {
        ShortcutFeedbackPreferences.resultCardEnabled = enabled
        syncShortcutFeedbackPreferences()
    }

    func syncShortcutFeedbackPreferences() {
        shortcutNotificationsEnabled = ShortcutFeedbackPreferences.notificationsEnabled
        shortcutResultCardEnabled = ShortcutFeedbackPreferences.resultCardEnabled
    }

    private func apply(session: SupabaseAuthSession) {
        isSignedIn = true
        currentUserEmail = session.user.email ?? ""
    }

    private func updateShortcutCredentialMessage() {
        shortcutCredentialMessage = hasUploadToken
            ? "已同步。快捷指令会自动读取 Keychain，不需要手动填写 upload_token。"
            : "未同步。请先登录芥子。"
    }

    private func save(session: SupabaseAuthSession, uploadToken: String) throws {
        let data = try JSONEncoder().encode(session)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try keychain.setString(json, for: KeychainKeys.authSession)
        try keychain.setString(uploadToken, for: KeychainKeys.uploadToken)
    }

    private func save(session: SupabaseAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try keychain.setString(json, for: KeychainKeys.authSession)
    }

    private func validSession(forceRefresh: Bool = false) async throws -> SupabaseAuthSession {
        if forceRefresh {
            let refreshed = try await authService.refreshSession()
            try save(session: refreshed)
            apply(session: refreshed)
            return refreshed
        }
        let session = try await authService.currentSession()
        try save(session: session)
        apply(session: session)
        return session
    }

    private func isExpiredJWTError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("pgrst303") || message.contains("jwt expired")
    }

    private func isInvalidRefreshSessionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid refresh token")
            || message.contains("refresh token not found")
            || message.contains("refresh_token_not_found")
            || message.contains("already used")
            || message.contains("session_not_found")
    }

    private func invalidateSession(message: String) {
        try? keychain.remove(KeychainKeys.authSession)
        isSignedIn = false
        currentUserEmail = ""
        dashboard = DashboardSnapshot()
        dashboardMessage = nil
        selectedTab = .today
        authMessage = message
        authMessageIsError = true
        lastDashboardRefreshAt = nil
    }

    private func requireSession() throws -> SupabaseAuthSession {
        guard let sessionJSON = try keychain.string(for: KeychainKeys.authSession),
              let data = sessionJSON.data(using: .utf8),
              let session = try? JSONDecoder().decode(SupabaseAuthSession.self, from: data) else {
            throw SupabaseRemoteError.missingSession
        }
        return session
    }
}

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case inbox
    case records
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .inbox: return "收件箱"
        case .records: return "记录"
        case .insights: return "分析"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sparkles"
        case .inbox: return "tray.full"
        case .records: return "list.bullet.rectangle"
        case .insights: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}
