import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @State private var activeStep: OnboardingStep
    private let onClose: (() -> Void)?

    init(initialStep: OnboardingStep = .welcome, onClose: (() -> Void)? = nil) {
        _activeStep = State(initialValue: initialStep)
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            switch activeStep {
            case .welcome:
                welcome
                    .toolbar {
                        if let onClose {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("关闭", action: onClose)
                            }
                        }
                    }
            case .shortcuts:
                ShortcutSetupView(showsPrivacy: true)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("返回") { activeStep = .welcome }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button(onClose == nil ? "开始使用" : "完成") { finish(skipped: false) }
                        }
                    }
            }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        ZStack {
            DomainSceneView(domain: .expense)
            ScrollView {
                VStack(alignment: .leading, spacing: JieziSpacing.lg) {
                    JieziCatShape(pose: .expense)
                        .stroke(JieziTheme.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 150, height: 150)
                        .background { Circle().fill(JieziTheme.gold.opacity(0.2)).frame(width: 102) }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    Text("生活小事，随手记")
                        .font(JieziType.prototypeOnboarding)
                        .accessibilityAddTraits(.isHeader)
                    Text("拍张照或截个图，把生活里的小事记下来。")
                        .font(JieziFont.body)
                    Label("记录优先保存在这台设备上，手动记录无需登录。", systemImage: "lock")
                        .font(JieziFont.caption)
                        .foregroundStyle(JieziTheme.muted)
                    NavigationLink {
                        GuidePrivacyView()
                    } label: {
                        Label("隐私设置", systemImage: "hand.raised")
                            .frame(minHeight: 44)
                    }
                    .foregroundStyle(JieziTheme.brand)
                }
                .foregroundStyle(JieziTheme.ink)
                .frame(maxWidth: 420, alignment: .leading)
                .padding(JieziSpacing.xl2)
                .padding(.top, JieziSpacing.xl2)
                .frame(maxWidth: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: JieziSpacing.sm) {
                Button { activeStep = .shortcuts } label: {
                    Text("设置快捷指令").frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                Button(onClose == nil ? "直接开始记录" : "返回设置") { finish(skipped: true) }
                    .frame(minHeight: 44)
            }
            .tint(JieziTheme.brand)
            .frame(maxWidth: 420)
            .padding(JieziSpacing.lg)
            .frame(maxWidth: .infinity)
            .background(JieziScene.expense.surface)
        }
    }

    private func finish(skipped: Bool) {
        if let onClose {
            onClose()
        } else {
            appState.finishOnboarding(skipped: skipped)
        }
    }
}

enum OnboardingStep: CaseIterable {
    case welcome
    case shortcuts
}
