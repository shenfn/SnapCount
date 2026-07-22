import SwiftUI
import UIKit

struct OnboardingFlowView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeStep: OnboardingStep = .capture
    @State private var completedSteps: Set<OnboardingStep> = []
    @State private var openedTemplates: Set<ShortcutTemplateKind> = []
    @State private var retentionDays = -1
    @State private var companionPersona = "observer"
    @State private var localMessage: String?
    @State private var isSavingStep = false
    @State private var showsCompletion = false

    var body: some View {
        ZStack {
            JieziPageBackground()

            VStack(spacing: 0) {
                header
                if showsCompletion {
                    completionView
                } else {
                    timeline
                }
            }
        }
        .interactiveDismissDisabled()
        .sensoryFeedback(.success, trigger: completedSteps.count)
        .task {
            await appState.loadUserSettings()
            retentionDays = currentRetention
            companionPersona = appState.userSettings.companionPersona
            await appState.refreshNotificationPermissionStatus()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            appState.verifyShortcutCredential()
            Task { await appState.refreshNotificationPermissionStatus() }
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
                Text(showsCompletion ? "设置完成" : "开始使用芥子")
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
                Text(showsCompletion ? "以后可在设置中重新查看" : "四步都可跳过，不影响正常记录")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            }

            Spacer(minLength: 8)

            Button(showsCompletion ? "进入首页" : "稍后") {
                appState.finishOnboarding(skipped: !showsCompletion)
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

                    Text("原图留存和 AI 语气会同步到账号；快捷指令与通知权限只作用于当前设备。")
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
                withAnimation(JieziMotion.settle) {
                    proxy.scrollTo(step.id, anchor: .center)
                }
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("让记录顺手发生")
                .font(.title2.weight(.bold))
                .foregroundStyle(JieziTheme.ink)
            Text("截图或拍照后，芥子会整理成可查记录；不确定的内容会先放进中转站，由你决定。")
                .font(.subheadline)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            ProgressView(
                value: Double(completedSteps.count),
                total: Double(OnboardingStep.allCases.count)
            )
            .tint(JieziTheme.brand)
            .padding(.top, 4)
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

                if activeStep == step {
                    Divider()
                        .overlay(JieziTheme.line)
                        .padding(.vertical, 14)
                    stepContent(step)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    if let localMessage {
                        Text(localMessage)
                            .font(.caption)
                            .foregroundStyle(localMessage.contains("失败") || localMessage.contains("不可用") ? JieziTheme.coral : JieziTheme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 10)
                    }
                }
            }
            .padding(16)
            .background(
                .white.opacity(activeStep == step ? 0.88 : 0.62),
                in: RoundedRectangle(cornerRadius: JieziRadius.card, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: JieziRadius.card, style: .continuous)
                    .stroke(activeStep == step ? JieziTheme.brand.opacity(0.2) : JieziTheme.line, lineWidth: 1)
            }
            .opacity(step.rawValue > activeStep.rawValue ? 0.58 : 1)
            .padding(.bottom, 14)
        }
        .animation(JieziMotion.settle, value: activeStep)
        .animation(JieziMotion.settle, value: completedSteps)
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
        case .capture:
            captureStep
        case .retention:
            retentionStep
        case .notification:
            notificationStep
        case .companion:
            companionStep
        }
    }

    private var captureStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(
                appState.hasUploadToken ? "登录凭据已同步到本机" : "登录凭据尚未同步",
                systemImage: appState.hasUploadToken ? "key.fill" : "key.slash"
            )
            .font(.caption.weight(.semibold))
            .foregroundStyle(appState.hasUploadToken ? JieziTheme.brand : JieziTheme.coral)

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
                        Image(systemName: openedTemplates.contains(template) ? "checkmark" : "arrow.up.forward")
                            .foregroundStyle(JieziTheme.brand)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }

            nextButton("继续", systemImage: "arrow.down") {
                await advance(from: .capture)
            }
        }
    }

    private var retentionStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("原图留存", selection: $retentionDays) {
                Text("不留").tag(0)
                Text("7 天").tag(7)
                Text("30 天").tag(30)
                Text("永久").tag(-1)
            }
            .pickerStyle(.segmented)

            Label(retentionDescription, systemImage: retentionDays == 0 ? "eye.slash" : "photo")
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            Text("这里只保存后续上传的留存策略；已有原图可在设置中单独清理。")
                .font(.caption2)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            nextButton("保存并继续", systemImage: "checkmark") {
                await advance(from: .retention)
            }
        }
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 10) {
                Image(systemName: notificationIsActive ? "bell.badge.fill" : "bell")
                    .foregroundStyle(notificationIsActive ? JieziTheme.brand : JieziTheme.muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(notificationStatusText)
                        .font(.subheadline.weight(.semibold))
                    Text("识别完成后提醒你；不开启也能正常记录。")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.muted)
                }
            }

            if notificationIsActive {
                Label("无需处理，通知已经可用", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
            } else {
                Button {
                    Task { await handleNotificationAction() }
                } label: {
                    Label(notificationActionTitle, systemImage: notificationActionIcon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(JieziTheme.brand)
                .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: JieziRadius.card))
            }

            nextButton("继续", systemImage: "arrow.down") {
                await advance(from: .notification)
            }
        }
    }

    private var companionStep: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("AI 语气", selection: $companionPersona) {
                ForEach(NativeSettingsOptions.personas) { option in
                    Text(option.title).tag(option.id)
                }
            }
            .pickerStyle(.segmented)

            Text(personaDescription)
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)

            nextButton("完成设置", systemImage: "checkmark.circle.fill") {
                await advance(from: .companion)
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 42)
            ZStack {
                Circle()
                    .fill(JieziTheme.brand.opacity(0.11))
                    .frame(width: 116, height: 116)
                Circle()
                    .stroke(JieziTheme.gold.opacity(0.55), lineWidth: 1)
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(JieziTheme.brand)
            }

            VStack(spacing: 9) {
                Text("可以开始记录了")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(JieziTheme.ink)
                Text("识别不确定时会进入中转站，统计事实由代码核算，AI 只负责表达语气。")
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 30)

            Button {
                appState.selectedTab = .today
                appState.finishOnboarding(skipped: false)
            } label: {
                Label("进入芥子", systemImage: "arrow.right.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(JieziTheme.brand, in: RoundedRectangle(cornerRadius: JieziRadius.card))
            .padding(.horizontal, 24)

            Spacer()
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
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(JieziTheme.brand, in: RoundedRectangle(cornerRadius: JieziRadius.card))
        .disabled(isSavingStep)
    }

    @MainActor
    private func advance(from step: OnboardingStep) async {
        guard activeStep == step, !isSavingStep else { return }
        isSavingStep = true
        localMessage = nil
        defer { isSavingStep = false }

        switch step {
        case .capture, .notification:
            break
        case .retention:
            await appState.setImageRetention(days: retentionDays, cleanupExisting: false)
            if let message = appState.settingsMessage, message.contains("失败") {
                localMessage = message
                return
            }
        case .companion:
            await appState.setCompanionPersona(companionPersona)
            if let message = appState.settingsMessage, message.contains("失败") {
                localMessage = message
                return
            }
        }

        completedSteps.insert(step)
        if let next = OnboardingStep(rawValue: step.rawValue + 1) {
            activeStep = next
        } else {
            withAnimation(JieziMotion.settle) {
                showsCompletion = true
            }
        }
    }

    private func openShortcutTemplate(_ template: ShortcutTemplateKind) {
        guard let url = URL(string: template.url), !template.url.isEmpty else {
            localMessage = "当前构建的\(template.title)模板链接不可用，可稍后在设置中重试。"
            return
        }
        openedTemplates.insert(template)
        localMessage = "已打开\(template.title)安装页；iOS 不提供可靠的安装完成检测。"
        openURL(url)
    }

    @MainActor
    private func handleNotificationAction() async {
        if notificationPermissionIsGranted {
            appState.setShortcutNotificationsEnabled(true)
            appState.setShortcutResultCardEnabled(false)
            return
        }
        if notificationWasDenied {
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            openURL(url)
            return
        }
        await appState.requestShortcutNotificationPermission()
    }

    private var currentRetention: Int {
        appState.userSettings.keepSourceImages ? appState.userSettings.imageRetentionDays : 0
    }

    private var retentionDescription: String {
        switch retentionDays {
        case 0: return "识别字段保留，原图按清理流程删除，隐私最轻。"
        case 7: return "保留一周复核窗口，之后自动进入清理。"
        case 30: return "适合月度对账，保留更长的核对窗口。"
        default: return "原图持续绑定记录，方便长期回看和复核。"
        }
    }

    private var personaDescription: String {
        NativeSettingsOptions.personas.first(where: { $0.id == companionPersona })?.detail
            ?? "冷静看见细节，事实为主"
    }

    private var notificationPermissionIsGranted: Bool {
        appState.notificationPermissionStatusText.hasPrefix("已开启")
            || appState.notificationPermissionStatusText.hasPrefix("临时允许")
    }

    private var notificationIsActive: Bool {
        notificationPermissionIsGranted && appState.shortcutNotificationsEnabled
    }

    private var notificationWasDenied: Bool {
        appState.notificationPermissionStatusText.hasPrefix("已关闭")
    }

    private var notificationActionTitle: String {
        if notificationPermissionIsGranted { return "启用结果通知" }
        if notificationWasDenied { return "前往系统设置" }
        return "开启结果通知"
    }

    private var notificationStatusText: String {
        if notificationPermissionIsGranted, !appState.shortcutNotificationsEnabled {
            return "系统已允许，芥子内通知已关闭"
        }
        return appState.notificationPermissionStatusText
    }

    private var notificationActionIcon: String {
        notificationWasDenied ? "gear" : "bell.badge"
    }

    private func stepColor(_ step: OnboardingStep) -> Color {
        if completedSteps.contains(step) || activeStep == step { return JieziTheme.brand }
        return JieziTheme.muted.opacity(0.7)
    }
}

private enum OnboardingStep: Int, CaseIterable, Identifiable {
    case capture
    case retention
    case notification
    case companion

    var id: Int { rawValue }

    var eyebrow: String {
        switch self {
        case .capture: return "快捷捕获"
        case .retention: return "原图选择"
        case .notification: return "结果反馈"
        case .companion: return "可选个性"
        }
    }

    var title: String {
        switch self {
        case .capture: return "不用打开 App，也能记录"
        case .retention: return "决定原图保留多久"
        case .notification: return "识别完成时告诉你"
        case .companion: return "选择 AI 说话方式"
        }
    }

    var detail: String {
        switch self {
        case .capture: return "安装拍照和截图模板，也可以稍后只用 App。"
        case .retention: return "原图帮助复核，也可以按你的选择自动删除。"
        case .notification: return "需要时再授权，不会在登录后突然弹出。"
        case .companion: return "只改变表达语气，不改变识别事实和统计口径。"
        }
    }

    var systemImage: String {
        switch self {
        case .capture: return "bolt.fill"
        case .retention: return "photo"
        case .notification: return "bell.fill"
        case .companion: return "quote.bubble.fill"
        }
    }
}
