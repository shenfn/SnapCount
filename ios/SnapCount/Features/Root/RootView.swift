import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager

    var body: some View {
        Group {
            if appState.isBootstrapping {
                ProgressView()
                    .tint(JieziTheme.brand)
            } else {
                MainShellView()
                    .safeAreaInset(edge: .top, spacing: 0) {
                        if let message = appState.localStorageInitializationMessage {
                            localStorageFailureBanner(message)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $appState.isOnboardingPresented) {
            OnboardingFlowView()
                .environmentObject(appState)
        }
        .preferredColorScheme(.light)
        .tint(JieziTheme.brand)
    }

    private func localStorageFailureBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Label("本地数据暂不可用", systemImage: "externaldrive.badge.exclamationmark")
                    .font(.subheadline.weight(.semibold))
                Text("普通记录不会改存到云端；原数据库文件已保留。可打开数据恢复选项。")
                    .font(.footnote)
                Text(message)
                    .font(.caption)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
            Button("恢复选项") {
                appState.presentedOverlay = .settings
            }
            .buttonStyle(.bordered)
            .accessibilityHint("打开设置中的数据导入与本地备份恢复")
        }
        .padding(12)
        .background(.regularMaterial)
    }
}
