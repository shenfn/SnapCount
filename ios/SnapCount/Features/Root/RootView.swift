import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager

    var body: some View {
        Group {
            if appState.isBootstrapping {
                ProgressView()
                    .tint(JieziTheme.mint)
            } else {
                MainShellView()
            }
        }
        .fullScreenCover(isPresented: $appState.isOnboardingPresented) {
            OnboardingFlowView()
                .environmentObject(appState)
        }
    }
}
