import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeStep: OnboardingStep = .welcome
    @State private var completedSteps: Set<OnboardingStep> = []
    @State private var localMessage: String?
    @State private var isSavingStep = false
    @State private var showsShortcutGuide = false

    var body: some View {
        ZStack {
            JieziPageBackground()

            VStack(spacing: 0) {
                header
                timeline
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: completedSteps.count)
        .sheet(isPresented: $showsShortcutGuide) {
            NavigationStack {
                ShortcutSetupView()
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { showsShortcutGuide = false }
                        }
                    }
            }
            .environmentObject(appState)
            .presentationDragIndicator(.visible)
        }
        .task { appState.verifyShortcutCredential() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.verifyShortcutCredential()
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(JieziTheme.brand.opacity(0.11))
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text("芥子")
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
                Text("第 \(activeStep.rawValue + 1) 步 · 共 5 步")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            }

            Spacer(minLength: 8)

            Button("稍后") {
                appState.finishOnboarding(skipped: true)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(JieziTheme.brand)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(JieziTheme.line)
                .frame(height: 1)
        }
    }

    private var timeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    intro

                    ForEach(OnboardingStep.allCases) { step in
                        timelineNode(step)
                            .id(step.id)
                    }

                    Text("图片保留、通知和 AI 语气仍可在设置调整；本引导不会改变现有隐私策略。")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 52)
                        .padding(.top, 8)
                        .padding(.bottom, 32)
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
            .onChange(of: activeStep) { _, step in
                withAnimation(JieziEasing.spring) {
                    proxy.scrollTo(step.id, anchor: .center)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(activeStep.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(JieziTheme.ink)
            Text(activeStep.detail)
                .font(.subheadline)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(
                value: Double(completedSteps.count + (completedSteps.contains(activeStep) ? 0 : 1)),
                total: Double(OnboardingStep.allCases.count)
            )
            .tint(JieziTheme.brand)
            .padding(.top, 4)
            .accessibilityLabel("引导进度")
        }
        .padding(.top, 24)
        .padding(.bottom, 22)
    }

    private func timelineNode(_ step: OnboardingStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                timelineDot(step)
                if step.rawValue < OnboardingStep.allCases.count - 1 {
                    Rectangle()
                        .fill(completedSteps.contains(step) ? JieziTheme.brand.opacity(0.45) : JieziTheme.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 22)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    guard step.rawValue <= activeStep.rawValue || completedSteps.contains(step) else { return }
                    activeStep = step
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(step.eyebrow)
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(stepColor(step))
                            Text(step.title)
                                .font(.headline)
                                .foregroundStyle(JieziTheme.ink)
                            Text(step.detail)
                                .font(.caption)
                                .foregroundStyle(JieziTheme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        if completedSteps.contains(step) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(JieziTheme.brand)
                        } else if activeStep == step {
                            Text("当前")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(JieziTheme.brand)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(step.rawValue > activeStep.rawValue && !completedSteps.contains(step))

                if activeStep == step {
                    Divider()
                        .overlay(JieziTheme.line)
                        .padding(.vertical, 14)
                    stepContent(step)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if let localMessage {
                        Text(localMessage)
                            .font(.caption)
                            .foregroundStyle(
                                localMessage.contains("失败") || localMessage.contains("不可用")
                                    || localMessage.contains("未能打开") || localMessage.contains("无法打开")
                                    ? JieziTheme.coral : JieziTheme.muted
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(16)
            .background(
                .white.opacity(activeStep == step ? 0.88 : 0.62),
                in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                    .stroke(activeStep == step ? JieziTheme.brand.opacity(0.2) : JieziTheme.line, lineWidth: 1)
            }
            .opacity(step.rawValue > activeStep.rawValue ? 0.58 : 1)
            .padding(.bottom, 14)
        }
        .animation(JieziEasing.spring, value: activeStep)
        .animation(JieziEasing.spring, value: completedSteps)
    }

    private func timelineDot(_ step: OnboardingStep) -> some View {
        ZStack {
            Circle()
                .fill(completedSteps.contains(step) ? JieziTheme.brand : JieziTheme.paper)
            Circle()
                .stroke(stepColor(step), lineWidth: activeStep == step ? 2 : 1)
            if completedSteps.contains(step) {
                Image(systemName: "checkmark")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
            } else {
                Image(systemName: step.systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(stepColor(step))
            }
        }
        .frame(width: 22, height: 22)
    }

    @ViewBuilder
    private func stepContent(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: welcomeStep
        case .flow: recordFlowStep
        case .shortcuts: shortcutSetupStep
        case .trial: trialStep
        case .ready: readyStep
        }
    }

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("无需登录即可使用本机记录", systemImage: "iphone.gen3")
                .font(JieziType.cardTitle)
                .foregroundStyle(JieziTheme.brand)
            Text("芥子把生活记录保存在本机。你可以先开始使用，之后再决定是否登录同步。")
                .font(JieziFont.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            nextButton("开始了解", systemImage: "arrow.right") {
                await advance(from: .welcome)
            }
        }
    }

    private var recordFlowStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            onboardingFactCard(
                title: "需要确认的候选",
                detail: "候选先留在收件箱，确认前不计入正式统计。",
                systemImage: "tray.full"
            )
            onboardingFactCard(
                title: "自动归档的正式记录",
                detail: "符合现有高置信规则并完成归档的记录会正常计入统计。",
                systemImage: "checkmark.circle"
            )
            onboardingFactCard(
                title: "AI 的边界",
                detail: "AI 可整理或表达内容；金额、日期和统计仍以保存的业务事实为准。",
                systemImage: "sparkles"
            )
            nextButton("下一步", systemImage: "arrow.right") {
                await advance(from: .flow)
            }
        }
    }

    private func onboardingFactCard(title: String, detail: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .foregroundStyle(JieziTheme.brand)
                .frame(width: 24)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(JieziType.cardTitle).foregroundStyle(JieziTheme.ink)
                Text(detail).font(JieziFont.caption).foregroundStyle(JieziTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JieziScene.expense.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var shortcutSetupStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                shortcutCredentialText,
                systemImage: appState.isSignedIn && appState.hasUploadToken ? "key.fill" : "key.slash"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(appState.isSignedIn && appState.hasUploadToken ? JieziTheme.brand : JieziTheme.muted)

            ForEach(ShortcutTemplateKind.allCases) { template in
                Button {
                    openShortcutTemplate(template)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: template.systemImage)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(template == .photo ? JieziTheme.gold : JieziTheme.brand)
                            .frame(width: 34, height: 34)
                            .background((template == .photo ? JieziTheme.gold : JieziTheme.brand).opacity(0.11), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(template.title)
                                .font(.subheadline.weight(.semibold))
                            Text(template.detail)
                                .font(.caption)
                                .foregroundStyle(JieziTheme.muted)
                        }
                        Spacer(minLength: 8)
                        Image(systemName: "arrow.up.forward")
                            .foregroundStyle(JieziTheme.brand)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }

            Button {
                showsShortcutGuide = true
            } label: {
                Label("查看完整设置步骤", systemImage: "list.number")
                    .font(JieziType.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundStyle(JieziTheme.brand)
            .background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            nextButton("继续", systemImage: "arrow.down") {
                await advance(from: .shortcuts)
            }
        }
    }

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("没有识别回调时，不会生成演示记录。", systemImage: "checkmark.shield")
                .font(JieziType.cardTitle)
                .foregroundStyle(JieziTheme.brand)
            Text("可以从快捷指令运行刚配置的流程，再回到这里。识别结果以快捷指令实际返回、系统通知或正式记录为准。")
                .font(JieziFont.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let url = URL(string: "shortcuts://") else { return }
                localMessage = "正在请求打开快捷指令…"
                openURL(url) { accepted in
                    localMessage = accepted
                        ? "系统已接受打开请求。返回后请按实际结果选择是否继续。"
                        : "无法打开快捷指令；可以重试，或跳过测试后继续。"
                }
            } label: {
                Label("打开快捷指令", systemImage: "arrow.up.forward.app")
                    .font(JieziType.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundStyle(JieziTheme.brand)
            .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            nextButton("我已自行尝试，继续", systemImage: "arrow.right") {
                await advance(from: .trial)
            }
            Button("跳过测试并继续") {
                Task { await advance(from: .trial) }
            }
            .font(JieziType.button)
            .foregroundStyle(JieziTheme.brand)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .disabled(isSavingStep)
        }
    }

    private var readyStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Label("现在可以开始记录", systemImage: "checkmark.seal.fill")
                .font(JieziType.cardTitle)
                .foregroundStyle(JieziTheme.brand)
            Text("原图保留、识别完成通知和 AI 表达偏好都可稍后在设置中调整。跳过或暂未配置快捷指令，不影响本机记录。")
                .font(JieziFont.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            nextButton("完成并进入芥子", systemImage: "checkmark.circle.fill") {
                completedSteps.insert(.ready)
                appState.finishOnboarding(skipped: false)
            }
        }
    }

    private func nextButton(
        _ title: String,
        systemImage: String,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 8) {
                if isSavingStep {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(JieziTheme.brand, in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card))
        .disabled(isSavingStep)
    }

    @MainActor
    private func advance(from step: OnboardingStep) async {
        guard activeStep == step, !isSavingStep else { return }
        isSavingStep = true
        localMessage = nil
        defer { isSavingStep = false }

        completedSteps.insert(step)
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            activeStep = next
        }
    }

    private func openShortcutTemplate(_ template: ShortcutTemplateKind) {
        guard !template.url.isEmpty, let url = URL(string: template.url) else {
            localMessage = "当前构建未配置\(template.title)安装链接；可在设置查看安装步骤，或稍后继续。"
            return
        }
        localMessage = "正在请求打开\(template.title)安装页…"
        openURL(url) { accepted in
            localMessage = accepted
                ? "系统已接受模板链接；iOS 不提供可靠的安装完成检测。"
                : "未能打开模板链接；可查看设置步骤、重试或稍后继续。"
        }
    }

    private var shortcutCredentialText: String {
        guard appState.isSignedIn else { return "登录后自动同步上传凭据；无需在快捷指令中填写 token。" }
        return appState.hasUploadToken ? "登录凭据已同步到本机。" : "登录凭据暂不可用，可稍后在设置检查。"
    }

    private func stepColor(_ step: OnboardingStep) -> Color {
        if completedSteps.contains(step) || activeStep == step { return JieziTheme.brand }
        return JieziTheme.muted.opacity(0.7)
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case flow
    case shortcuts
    case trial
    case ready

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .welcome: return "欢迎"
        case .flow: return "记录如何流动"
        case .shortcuts: return "设置快捷指令"
        case .trial: return "试一次"
        case .ready: return "准备完成"
        }
    }

    var title: String {
        switch self {
        case .welcome: return "让记录顺手发生"
        case .flow: return "记录如何流动"
        case .shortcuts: return "设置快捷指令"
        case .trial: return "试一次"
        case .ready: return "准备完成"
        }
    }

    var detail: String {
        switch self {
        case .welcome: return "先从本机开始；登录同步是可选的。"
        case .flow: return "候选与正式记录分开，统计不把待确认内容算进去。"
        case .shortcuts: return "可安装拍照和截图模板，未登录时会在登录后同步凭据。"
        case .trial: return "可运行真实快捷指令，也可以跳过；没有回调不会伪造结果。"
        case .ready: return "完成后进入五域主页，图片、通知和 AI 偏好可在设置调整。"
        }
    }

    var systemImage: String {
        switch self {
        case .welcome: return "hand.wave"
        case .flow: return "arrow.triangle.branch"
        case .shortcuts: return "bolt.fill"
        case .trial: return "play.circle"
        case .ready: return "checkmark.seal"
        }
    }
}
