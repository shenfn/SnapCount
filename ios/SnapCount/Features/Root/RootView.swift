import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.isBootstrapping {
                ProgressView()
                    .tint(JieziTheme.mint)
            } else if appState.isSignedIn {
                tabRoot
            } else {
                LoginView()
            }
        }
        .fullScreenCover(isPresented: $appState.isOnboardingPresented) {
            OnboardingFlowView()
                .environmentObject(appState)
        }
    }

    private var tabRoot: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack(path: $appState.todayPath) {
                TodayView()
                    .navigationDestination(for: NativeDayDetailRoute.self) { route in
                        DayDetailView(route: route)
                    }
                    .navigationDestination(for: NativeRecordRoute.self) { route in
                        RecordDetailView(reference: route.reference)
                    }
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
            .tag(AppTab.today)

            NavigationStack(path: $appState.inboxPath) {
                InboxView()
            }
            .tabItem { Label(AppTab.inbox.title, systemImage: AppTab.inbox.systemImage) }
            .tag(AppTab.inbox)

            NavigationStack(path: $appState.recordsPath) {
                RecordsView()
            }
            .tabItem { Label(AppTab.records.title, systemImage: AppTab.records.systemImage) }
            .tag(AppTab.records)

            NavigationStack {
                InsightsView()
            }
            .tabItem { Label(AppTab.insights.title, systemImage: AppTab.insights.systemImage) }
            .tag(AppTab.insights)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
            .tag(AppTab.settings)
        }
        .tint(JieziTheme.brand)
        .toolbarBackground(JieziTheme.paper.opacity(0.94), for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: appState.selectedTab) { tab in
            guard [.today, .inbox, .records].contains(tab) else { return }
            Task {
                await appState.refreshDashboardIfStale()
            }
        }
    }
}
