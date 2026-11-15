import SwiftUI

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var activeStep: OnboardingStep = .welcome
    @State private var completedSteps: Set<OnboardingStep> = []
    @State private var localMessage: String?
    @State private var isSavingStep = false
    @State private var showsShortcutGuide = false
    @State private var trialID: UUID?
    @State private var trialReceipt: ShortcutTrialReceipt?
    @State private var selectedTrigger = "轻点背面"

    init(initialStep: OnboardingStep = .welcome) {
        _activeStep = State(initialValue: initialStep)
    }

    var body: some View {
        ZStack {
            DomainSceneView(domain: .expense)

            VStack(spacing: 0) {
                header
                stepPage
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { stepFooter }
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
        .task {
            appState.verifyShortcutCredential()
            ShortcutTrialStore.shared.synchronize(scope: appState.onboardingScope)
            refreshTrial()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.verifyShortcutCredential()
            refreshTrial()
        }
        .onChange(of: appState.onboardingScope) { _, scope in
            cancelTrial()
            ShortcutTrialStore.shared.synchronize(scope: scope)
        }
        .onDisappear { cancelTrial() }
    }

    private var header: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(OnboardingStep.allCases) { step in
                    Capsule()
                        .fill(step.rawValue <= activeStep.rawValue ? JieziTheme.brand : JieziTheme.brand.opacity(0.15))
                        .frame(maxWidth: .infinity)
                        .frame(height: 4)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("第 \(activeStep.rawValue + 1) 步，共 5 步")
            Button(activeStep == .ready ? "完成" : "稍后设置") {
                cancelTrial()
                appState.finishOnboarding(skipped: activeStep != .ready)
            }
            .font(JieziFont.caption)
            .foregroundStyle(JieziTheme.brand)
            .fixedSize()
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(JieziScene.expense.surface.opacity(0.6), in: Capsule())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var stepPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if activeStep == .welcome || activeStep == .ready {
                    JieziCatShape(pose: activeStep == .ready ? .reading : .expense)
                        .stroke(JieziTheme.ink, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                        .frame(width: 200, height: 200)
                        .background {
                            Circle().fill(JieziTheme.gold.opacity(0.2)).frame(width: 128, height: 128)
                        }
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(activeStep == .welcome ? "留下事实，\n回看生活。" : activeStep.title)
                        .font(JieziType.prototypeOnboarding)
                        .foregroundStyle(JieziTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text(activeStep.detail)
                        .font(JieziFont.body)
                        .foregroundStyle(JieziTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    if activeStep == .welcome {
                        Text("KEEP THE FACTS · LOOK BACK")
                            .font(JieziFont.caption2).tracking(1.2).foregroundStyle(JieziTheme.muted)
                    }
                }
                stepContent(activeStep)
                if let localMessage {
                    Text(localMessage)
                        .font(JieziFont.caption)
                        .foregroundStyle(JieziTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .id(activeStep)
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: activeStep)
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

            setupCard(number: 1, title: "添加记录快捷指令", detail: "安装会打开系统快捷指令；返回不代表已经安装完成。") {
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
            }

            setupCard(number: 2, title: "选一个触发方式", detail: "这里显示设置方法，实际配置需要在系统中完成。") {
                ForEach(["轻点背面", "操作按钮", "共享菜单"], id: \.self) { trigger in
                    Button { selectedTrigger = trigger } label: {
                        HStack(spacing: 10) {
                            Image(systemName: selectedTrigger == trigger ? "largecircle.fill.circle" : "circle")
                            Text(trigger).font(JieziFont.body)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(JieziTheme.brand)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selectedTrigger == trigger ? .isSelected : [])
                }
                Text(triggerInstructions).font(JieziFont.caption).foregroundStyle(JieziTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Link("查看 Apple 设置说明", destination: triggerHelpURL)
                    .font(JieziFont.caption).frame(minHeight: 44)
            }

            setupCard(number: 3, title: "只交给芥子你选的图片", detail: "首次运行时，按系统提示确认图片传递权限。芥子不会在这里申请整个相册的访问权限。") {
                Label("权限与实际输入以系统运行时提示为准", systemImage: "hand.raised")
                    .font(JieziFont.caption).foregroundStyle(JieziTheme.muted)
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

        }
    }

    private var trialStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(spacing: 12) {
                Image(systemName: "doc.viewfinder").font(JieziType.display)
                Text("运行已安装的快捷指令\n发送一张真实图片")
                    .font(JieziFont.caption).multilineTextAlignment(.center)
            }
            .foregroundStyle(JieziTheme.muted)
            .frame(width: 200, height: 180)
            .background(JieziTheme.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 30))
            .overlay(RoundedRectangle(cornerRadius: 30).stroke(JieziTheme.brand.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5])))
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
            Label("发一张截图，看看它如何落下。", systemImage: "photo.badge.arrow.down")
                .font(JieziType.cardTitle)
                .foregroundStyle(JieziTheme.brand)
            Text("从快捷指令运行刚配置的流程，然后回到这里查看真实结果。也可以稍后再试。")
                .font(JieziFont.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                guard let url = URL(string: "shortcuts://") else { return }
                trialID = ShortcutTrialStore.shared.begin(scope: appState.onboardingScope)
                refreshTrial()
                localMessage = "正在请求打开快捷指令…"
                openURL(url) { accepted in
                    if accepted {
                        localMessage = nil
                        refreshTrial()
                    } else {
                        cancelTrial()
                        localMessage = "无法打开快捷指令；可以重试，或稍后再试。"
                    }
                }
            } label: {
                Label(trialID == nil ? "打开快捷指令试一次" : "重新试一次", systemImage: "arrow.up.forward.app")
                    .font(JieziType.button)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
            }
            .buttonStyle(.plain)
            .foregroundStyle(JieziTheme.brand)
            .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            if let trialReceipt {
                VStack(alignment: .leading, spacing: 10) {
                    if trialReceipt.processing && trialReceipt.outcome == nil { ProgressView() }
                    Text(trialStatusText(trialReceipt))
                        .font(JieziFont.body).fixedSize(horizontal: false, vertical: true)
                    Button("刷新真实结果") { refreshTrial() }
                        .font(JieziType.button).frame(minHeight: 44)
                }
                .foregroundStyle(JieziTheme.ink)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JieziScene.expense.surface, in: RoundedRectangle(cornerRadius: 22))
                .accessibilityElement(children: .contain)
            }
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
        }
    }

    private var stepFooter: some View {
        HStack(spacing: 10) {
            if activeStep != .welcome {
                Button {
                    guard !isSavingStep,
                          let previous = OnboardingStep(rawValue: activeStep.rawValue - 1) else { return }
                    if activeStep == .trial { cancelTrial() }
                    localMessage = nil
                    activeStep = previous
                } label: {
                    Image(systemName: "chevron.left")
                        .font(JieziType.button)
                        .frame(width: 52, height: 54)
                        .background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .foregroundStyle(JieziTheme.brand)
                .accessibilityLabel("上一步")
                .disabled(isSavingStep)
            }
            nextButton(footerTitle, systemImage: activeStep == .ready ? "checkmark" : "arrow.right") {
                if activeStep == .ready {
                    completedSteps.insert(.ready)
                    cancelTrial()
                    appState.finishOnboarding(skipped: false)
                } else {
                    await advance(from: activeStep)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 12)
        .background(JieziScene.expense.surface.opacity(0.9))
    }

    private var footerTitle: String {
        switch activeStep {
        case .welcome: return "开始了解"
        case .flow: return "下一步"
        case .shortcuts: return "继续"
        case .trial:
            return trialReceipt?.outcome != nil && trialReceipt?.outcome != .failed ? "查看结果后继续" : "稍后再试，继续"
        case .ready: return "完成并进入芥子"
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
        if step == .trial { cancelTrial() }
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

    private func refreshTrial() {
        trialReceipt = ShortcutTrialStore.shared.snapshot(for: appState.onboardingScope)
        if let receipt = trialReceipt {
            trialID = receipt.id
        } else if trialID != nil {
            trialID = nil
            localMessage = "本次回执已过期或失效，可以重新试一次。"
        }
    }

    private func setupCard<Content: View>(number: Int, title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)").font(JieziType.moneyInline)
                    .frame(width: 28, height: 28)
                    .background(JieziTheme.brand.opacity(0.1), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(JieziType.cardTitle)
                    Text(detail).font(JieziFont.caption).foregroundStyle(JieziTheme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content()
        }
        .foregroundStyle(JieziTheme.ink)
        .padding(14)
        .background(JieziScene.expense.surface.opacity(0.78), in: RoundedRectangle(cornerRadius: 22))
    }

    private var triggerInstructions: String {
        switch selectedTrigger {
        case "轻点背面": return "在系统设置的辅助功能（或无障碍）→触控→轻点背面中，选择已安装的记录快捷指令。"
        case "操作按钮": return "支持操作按钮的机型，可在系统设置→操作按钮中选择快捷指令。"
        default: return "在快捷指令详情启用“在共享表单中显示”，再从图片的共享菜单运行。"
        }
    }

    private var triggerHelpURL: URL {
        let path: String
        switch selectedTrigger {
        case "轻点背面": path = "https://support.apple.com/zh-cn/111772"
        case "操作按钮": path = "https://support.apple.com/zh-cn/guide/iphone/iphe89d61d66/ios"
        default: path = "https://support.apple.com/zh-cn/guide/shortcuts/apd163eb9f95/ios"
        }
        return URL(string: path)!
    }

    private func cancelTrial() {
        if let trialID { ShortcutTrialStore.shared.cancel(id: trialID) }
        trialID = nil
        trialReceipt = nil
    }

    private func trialStatusText(_ receipt: ShortcutTrialReceipt) -> String {
        switch receipt.outcome {
        case .archived: return "识别结果已自动归档到本机正式记录。"
        case .staged: return "识别结果已保存到本机待确认，确认前不计入正式统计。"
        case .remoteReturned: return "云端已返回。请在记录或待确认中核对实际结果。"
        case .failed: return "这次没有完成。请查看快捷指令返回的错误，再重试。"
        case nil: return receipt.processing ? "芥子已收到，正在处理本次试运行…" : "等待快捷指令发送图片；打开 App 不代表识别完成。"
        }
    }

    private var shortcutCredentialText: String {
        guard appState.isSignedIn else { return "登录后自动同步上传凭据；无需在快捷指令中填写 token。" }
        return appState.hasUploadToken ? "登录凭据已同步到本机。" : "登录凭据暂不可用，可稍后在设置检查。"
    }


}

enum OnboardingStep: Int, CaseIterable, Identifiable {
    case welcome
    case flow
    case shortcuts
    case trial
    case ready

    var id: Int { rawValue }



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


}
