import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label(AppTab.today.title, systemImage: AppTab.today.systemImage) }
            .tag(AppTab.today)

            NavigationStack {
                InboxView()
            }
            .tabItem { Label(AppTab.inbox.title, systemImage: AppTab.inbox.systemImage) }
            .tag(AppTab.inbox)

            NavigationStack {
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
        .tint(JieziTheme.mint)
    }
}
