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
    @Published var inboxPath: [String] = []
    @Published var recordsPath: [String] = []
    @Published var selectedRecordDetail: NativeRecordDetail?
    @Published var recordDetailMessage: String?
    @Published var isSavingRecordDetail = false
    @Published var isDeletingRecordDetail = false

    private let authService = SupabaseAuthService()
    private let dataService = NativeDataService()
    private let keychain = KeychainStore.shared
    private var hasAskedNotificationPermissionThisSession = false
    private var lastDashboardRefreshAt: Date?

    func bootstrap() {
        defer { isBootstrapping = false }
        do {
            if let sessionJSON = try keychain.string(for: KeychainKeys.authSession),
               let data = sessionJSON.data(using: .utf8),
               let session = try? JSONDecoder().decode(SupabaseAuthSession.self, from: data) {
                apply(session: session)
                Task {
                    await refreshDashboard()
                    await requestShortcutNotificationPermissionIfNeeded()
                }
            }
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
            Task {
                await refreshNotificationPermissionStatus()
            }
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
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
        do {
            try keychain.remove(KeychainKeys.authSession)
            try keychain.remove(KeychainKeys.uploadToken)
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
        }
        isSignedIn = false
        currentUserEmail = ""
        hasUploadToken = false
        dashboard = DashboardSnapshot()
        dashboardMessage = nil
        shortcutCredentialMessage = nil
        selectedTab = .today
        lastDashboardRefreshAt = nil
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
            let session = try await validSession()
            dashboard = try await dataService.fetchDashboard(accessToken: session.accessToken)
        } catch {
            dashboardMessage = error.localizedDescription
        }

        isLoadingDashboard = false
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
            try await dataService.discardStagingRecord(id: record.id, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func retryStagingRecord(_ record: NativeStagingRecord) async {
        do {
            let session = try await validSession()
            _ = try await dataService.retryStagingRecord(id: record.id, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func archiveStagingRecord(_ record: NativeStagingRecord, domainKey: String) async {
        do {
            let session = try await validSession()
            let reference = try await dataService.archiveStagingRecord(record, domainKey: domainKey, accessToken: session.accessToken)
            inboxPath.removeAll()
            await refreshDashboard()
            selectedTab = .records
            recordsPath = [reference]
        } catch {
            dashboardMessage = error.localizedDescription
        }
    }

    func loadRecordDetail(reference: String) async {
        recordDetailMessage = nil
        selectedRecordDetail = nil
        do {
            let session = try await validSession()
            selectedRecordDetail = try await dataService.fetchRecordDetail(reference: reference, accessToken: session.accessToken)
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
            let reference = try await dataService.saveRecordDetail(draft, accessToken: session.accessToken)
            await refreshDashboard()
            recordsPath = [reference]
            await loadRecordDetail(reference: reference)
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
            try await dataService.deleteRecord(reference: reference, accessToken: session.accessToken)
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

    private func validSession() async throws -> SupabaseAuthSession {
        let session = try requireSession()
        guard let refreshToken = session.refreshToken, !refreshToken.isEmpty else {
            return session
        }

        do {
            let refreshed = try await authService.refreshSession(refreshToken: refreshToken)
            try save(session: refreshed)
            apply(session: refreshed)
            return refreshed
        } catch {
            return session
        }
    }

    private func requireSession() throws -> SupabaseAuthSession {
        guard let sessionJSON = try keychain.string(for: KeychainKeys.authSession),
              let data = sessionJSON.data(using: .utf8),
              let session = try? JSONDecoder().decode(SupabaseAuthSession.self, from: data) else {
            throw NativeDataServiceError.missingSession
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
