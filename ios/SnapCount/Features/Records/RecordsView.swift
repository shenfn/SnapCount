import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section("概览") {
                    HStack {
                        Label("本月记录", systemImage: "calendar")
                        Spacer()
                        Text("\(appState.dashboard.monthCount)")
                            .monospacedDigit()
                    }
                    HStack {
                        Label("今日记录", systemImage: "sun.max")
                        Spacer()
                        Text("\(appState.dashboard.todayCount)")
                            .monospacedDigit()
                    }
                }

                if !appState.dashboard.recentRecords.isEmpty {
                    Section("最近") {
                        ForEach(appState.dashboard.recentRecords) { item in
                            Label {
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(item.title)
                                        Text(item.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(item.value)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: item.systemImage)
                            }
                        }
                    }
                }

                Section("数据域") {
                    Label("消费", systemImage: "creditcard")
                    Label("饮食", systemImage: "fork.knife")
                    Label("运动", systemImage: "figure.run")
                    Label("睡眠", systemImage: "moon")
                    Label("阅读", systemImage: "book")
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationTitle("记录")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
