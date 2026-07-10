import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    HStack {
                        Label("待处理", systemImage: "tray")
                        Spacer()
                        Text("\(appState.dashboard.pendingCount)")
                            .font(.headline.monospacedDigit())
                    }
                }

                if appState.dashboard.pendingCount == 0 {
                    ContentUnavailableView(
                        "暂无待处理记录",
                        systemImage: "checkmark.circle",
                        description: Text("上传后的不确定识别结果会先进入这里。")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationTitle("收件箱")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
