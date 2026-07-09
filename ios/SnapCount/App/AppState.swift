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

    private let authService = SupabaseAuthService()
    private let keychain = KeychainStore.shared

    func bootstrap() {
        defer { isBootstrapping = false }
        do {
            if let sessionJSON = try keychain.string(for: KeychainKeys.authSession),
               let data = sessionJSON.data(using: .utf8),
               let session = try? JSONDecoder().decode(SupabaseAuthSession.self, from: data) {
                apply(session: session)
            }
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
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
        selectedTab = .today
    }

    private func apply(session: SupabaseAuthSession) {
        isSignedIn = true
        currentUserEmail = session.user.email ?? ""
    }

    private func save(session: SupabaseAuthSession, uploadToken: String) throws {
        let data = try JSONEncoder().encode(session)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try keychain.setString(json, for: KeychainKeys.authSession)
        try keychain.setString(uploadToken, for: KeychainKeys.uploadToken)
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
