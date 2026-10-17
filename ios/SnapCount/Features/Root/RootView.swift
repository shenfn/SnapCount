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
            }
        }
        .fullScreenCover(isPresented: $appState.isOnboardingPresented) {
            OnboardingFlowView()
                .environmentObject(appState)
        }
        .preferredColorScheme(.light)
        .tint(JieziTheme.brand)
    }
}
