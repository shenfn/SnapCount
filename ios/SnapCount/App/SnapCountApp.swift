import SwiftUI

@main
struct SnapCountApp: App {
    @UIApplicationDelegateAdaptor(AppNotificationDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task {
                    appState.bootstrap()
                    if let route = AppNotificationDelegate.consumePendingRoute() {
                        appState.handleShortcutNotificationRoute(route)
                    }
                }
                .onOpenURL { url in
                    appState.handleDeepLink(url)
                }
                .onReceive(NotificationCenter.default.publisher(for: .snapCountShortcutNotificationRoute)) { notification in
                    appState.handleShortcutNotificationRoute(notification.userInfo?["route"] as? String)
                }
                .onChange(of: scenePhase) { phase in
                    guard phase == .active else { return }
                    Task {
                        await appState.refreshDashboardIfStale(minInterval: 1, force: true)
                    }
                }
        }
    }
}
