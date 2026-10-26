import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showLogin = false
    @State private var showBindingPreview = false
    @State private var showDeleteAccountConfirmation = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    profileHeader
                }

                Section("数据与同步") {
                    LabeledContent("本机数据") {
                        Text("保存在此 iPhone")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("云端身份") {
                        Text(appState.isSignedIn ? "已登录" : "未登录")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("云同步") {
                        Text(syncStatusTitle)
                            .foregroundStyle(.secondary)
                    }
                    Text("普通同步范围：账户与消费；账户流水由本机消费投影维护。收入、四域记录、钱包快照、候选和还款不在此同步范围。‘已同步’不代表历史全量迁入或云本完全一致。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if canPreviewLocalBinding {
                        Button {
                            Task {
                                await appState.prepareLocalBindingPreview()
                                if appState.localBindingPreview != nil {
                                    showBindingPreview = true
                                }
                            }
                        } label: {
                            Label(
                                appState.isLoadingLocalBindingPreview ? "正在读取同步范围" : "查看同步预览",
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(appState.isLoadingLocalBindingPreview)
                    }
                    if canManuallySynchronizeLocalData {
                        Button {
                            Task { await appState.synchronizeLocalData() }
                        } label: {
                            Label(
                                appState.isSynchronizingLocalData ? "正在同步" : syncActionTitle,
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(appState.isSynchronizingLocalData)
                    }
                    if canDisableLocalSync {
                        Button(role: .destructive) {
                            appState.disableLocalSync()
                        } label: {
                            Label("关闭云同步", systemImage: "icloud.slash")
                        }
                    }
                    if !appState.isSignedIn {
                        Button {
                            showLogin = true
                        } label: {
                            Label("登录并管理云同步", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                }

                Section("使用帮助") {
                    Button {
                        appState.presentOnboarding()
                    } label: {
                        settingsRow(
                            "使用引导",
                            detail: appState.onboardingStatusText,
                            systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                        )
                    }
                    .buttonStyle(.plain)
                }

                Section("外观") {
                    LabeledContent("应用场景", value: "随当前领域变化")
                }

                Section("数据管理") {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        settingsRow("数据导出", detail: "导出支出、收入和通用记录", systemImage: "square.and.arrow.up")
                    }
                    NavigationLink {
                        LocalHistoryMigrationView()
                    } label: {
                        settingsRow("历史云数据迁入本机", detail: "先只读预检，再确认恢复", systemImage: "icloud.and.arrow.down")
                    }
                }

                Section("AI 能力") {
                    NavigationLink {
                        VisionSettingsView()
                    } label: {
                        settingsRow(
                            "截图 / 拍照识别",
                            detail: "图片识别：\(appState.localVisionMode.title) · 截图：\(providerTitle(appState.userSettings.screenshotVisionPrimary)) · 拍照：\(providerTitle(appState.userSettings.photoVisionPrimary))",
                            systemImage: "viewfinder"
                        )
                    }
                    NavigationLink {
                        CompanionSettingsView()
                    } label: {
                        settingsRow(
                            "AI 陪伴",
                            detail: appState.userSettings.companionEnabled ? "已开启 · \(optionTitle(NativeSettingsOptions.personas, appState.userSettings.companionPersona))" : "已关闭",
                            systemImage: "quote.bubble"
                        )
                    }
                    NavigationLink {
                        InsightSettingsView()
                    } label: {
                        settingsRow(
                            "AI 联动分析",
                            detail: optionTitle(NativeSettingsOptions.insightProviders, appState.userSettings.aiInsightProvider),
                            systemImage: "chart.line.uptrend.xyaxis"
                        )
                    }
                }

                Section("隐私与留存") {
                    NavigationLink {
                        PrivacySettingsView()
                    } label: {
                        settingsRow(
                            "识别数据与原图",
                            detail: appState.userSettings.retentionDescription,
                            systemImage: "hand.raised"
                        )
                    }
                }

                Section("快捷指令") {
                    NavigationLink {
                        ShortcutSetupView()
                    } label: {
                        settingsRow(
                            "快捷指令设置",
                            detail: appState.localVisionMode == .disabled ? "AI 已关闭，可保存到本机收件箱" : (appState.localVisionMode == .byok ? "使用本机 BYOK 凭据" : (appState.hasUploadToken ? "Hosted 凭据已同步" : "Hosted 凭据暂不可用")),
                            systemImage: "wand.and.stars"
                        )
                    }
                    Toggle(isOn: Binding(
                        get: { appState.shortcutNotificationsEnabled },
                        set: { appState.setShortcutNotificationsEnabled($0) }
                    )) {
                        Label("上传完成通知", systemImage: "bell")
                    }
                    Toggle(isOn: Binding(
                        get: { appState.shortcutResultCardEnabled },
                        set: { appState.setShortcutResultCardEnabled($0) }
                    )) {
                        Label("快捷指令结果卡片", systemImage: "rectangle.on.rectangle")
                    }
                }

                Section("关于") {
                    LabeledContent("当前版本") {
                        Text(versionLabel).foregroundStyle(.secondary)
                    }
                    LabeledContent("数据存储") {
                        Text("本机优先 · 云端可选").foregroundStyle(.secondary)
                    }
                }

                Section("账户与安全") {
                    NavigationLink {
                        LegalDocumentView(kind: .privacy)
                    } label: {
                        Label("隐私政策", systemImage: "hand.raised")
                    }
                    NavigationLink {
                        LegalDocumentView(kind: .terms)
                    } label: {
                        Label("服务协议", systemImage: "doc.text")
                    }
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        Label("删除云端账户及云端数据", systemImage: "person.crop.circle.badge.xmark")
                    }
                    .disabled(appState.isDeletingAccount)
                }

                Section {
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                if appState.isLoadingSettings || appState.isSavingSettings || appState.isDeletingAccount {
                    Section { ProgressView(appState.isLoadingSettings ? "正在同步设置" : "正在保存设置") }
                }
                if let message = appState.settingsMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message.contains("失败") ? JieziTheme.coral : .secondary)
                    }
                }
                if let message = appState.localSyncMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(message.contains("失败") || message.contains("无法") ? JieziTheme.coral : .secondary)
                    }
                }
                if appState.localSyncDiagnostic != nil || appState.localSyncFailureDiagnostic != nil {
                    Section("同步诊断") {
                        if let diagnostic = appState.localSyncDiagnostic {
                            Text(diagnostic.summary)
                                .font(.footnote)
                                .foregroundStyle(diagnostic.phase == .failed ? JieziTheme.coral : .secondary)
                                .textSelection(.enabled)
                        }
                        if let diagnostic = appState.localSyncFailureDiagnostic {
                            Text(diagnostic.userMessage)
                                .font(.footnote)
                                .foregroundStyle(diagnostic.resolution == nil ? JieziTheme.coral : .secondary)
                            if let resolution = diagnostic.resolution {
                                Text("恢复结果：\(resolution)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            diagnosticDetails(diagnostic)
                        }
                    }
                }
                if let diagnostic = appState.localStorageInitializationDiagnostic {
                    Section("本机存储诊断") {
                        Text(diagnostic.userMessage)
                            .font(.footnote)
                            .foregroundStyle(diagnostic.resolution == nil ? JieziTheme.coral : .secondary)
                        if let resolution = diagnostic.resolution {
                            Text("恢复结果：\(resolution)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        diagnosticDetails(diagnostic)
                    }
                }
                if let diagnostic = appState.localProjectionRefreshDiagnostic {
                    Section("本机列表刷新诊断") {
                        Text(diagnostic.userMessage)
                            .font(.footnote)
                            .foregroundStyle(diagnostic.resolution == nil ? JieziTheme.coral : .secondary)
                        if let resolution = diagnostic.resolution {
                            Text("恢复结果：\(resolution)")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        diagnosticDetails(diagnostic)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .tint(JieziTheme.brand)
            .refreshable {
                if appState.isSignedIn { await appState.loadUserSettings() }
            }
        }
        .navigationTitle("设置")
        .toolbarBackground(JieziScene.expense.surface, for: .navigationBar)
        .alert("永久删除账户？", isPresented: $showDeleteAccountConfirmation) {
            Button("删除云端账户及云端数据", role: .destructive) {
                Task { _ = await appState.deleteAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会永久删除云端账户及其云端记录和原图。本机数据库、原图与导出的备份仍保留。")
        }
        .sheet(isPresented: $showLogin) {
            NavigationStack { LoginView() }
                .environmentObject(appState)
        }
        .sheet(isPresented: $showBindingPreview) {
            NavigationStack {
                if let preview = appState.localBindingPreview {
                    LocalBindingPreviewView(preview: preview)
                } else {
                    ContentUnavailableView("同步预览已结束", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            .environmentObject(appState)
        }
        .task {
            appState.refreshLocalSyncState()
            appState.loadLatestLocalSyncDiagnostic()
            appState.loadLatestLocalStorageInitializationDiagnostic()
            appState.loadLatestLocalProjectionRefreshDiagnostic()
            if appState.isSignedIn { await appState.loadUserSettings() }
        }
    }

    private var profileHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(JieziTheme.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.isSignedIn
                     ? (appState.currentUserEmail.isEmpty ? "已登录用户" : appState.currentUserEmail)
                     : "本机用户")
                    .font(.headline)
                Text(appState.isSignedIn ? "云端身份可用" : "数据仅保存在此 iPhone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 5)
    }

    private var syncStatusTitle: String {
        guard let state = appState.localSyncState else { return "状态未知" }
        if state.conflictState == .unresolved { return "有待处理冲突" }
        switch state.status {
        case .disabled: return appState.isSignedIn ? "已登录，尚未开启" : "尚未开启"
        case .ready: return "已授权，等待同步"
        case .syncing: return "同步中"
        case .synced: return "账户与消费已同步"
        case .failed: return "同步失败，可重试"
        }
    }

    private var canPreviewLocalBinding: Bool {
        guard appState.isSignedIn,
              let state = appState.localSyncState else { return false }
        switch state.binding {
        case .unbound, .mismatch:
            return true
        case .bound(let userID):
            return userID == appState.currentUserId && state.status == .disabled
        }
    }

    private var canDisableLocalSync: Bool {
        guard appState.isSignedIn,
              let state = appState.localSyncState,
              state.status != .disabled else { return false }
        guard case .bound(let userID) = state.binding else { return false }
        return userID == appState.currentUserId
    }

    private var canManuallySynchronizeLocalData: Bool {
        guard appState.isSignedIn,
              let state = appState.localSyncState,
              state.conflictState == .none,
              case .bound(let userID) = state.binding,
              userID == appState.currentUserId else { return false }
        return [.ready, .failed, .synced].contains(state.status)
    }

    private var syncActionTitle: String {
        appState.localSyncState?.status == .failed ? "重试同步" : "立即同步"
    }

    private func settingsRow(_ title: String, detail: String, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(JieziTheme.brand)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }

    private func providerTitle(_ id: String) -> String {
        optionTitle(NativeSettingsOptions.visionProviders, id)
    }

    private func optionTitle(_ options: [NativeSettingsOption], _ id: String) -> String {
        options.first(where: { $0.id == id })?.title ?? id
    }

    private var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

private func diagnosticDetails(_ diagnostic: LocalHistoryMigrationDiagnostic) -> some View {
    DisclosureGroup("查看脱敏技术详情") {
        Text(diagnostic.shareText)
            .font(.caption.monospaced())
            .textSelection(.enabled)
        Button("复制脱敏诊断") {
            UIPasteboard.general.string = diagnostic.shareText
        }
        ShareLink("分享脱敏诊断", item: diagnostic.shareText)
    }
}

struct VisionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var byokAPIKeyInput = ""
    @State private var showDeleteBYOKConfirmation = false

    var body: some View {
        Form {
            Section("识别授权") {
                Picker("图片识别", selection: Binding(
                    get: { appState.localVisionMode },
                    set: { appState.setLocalVisionMode($0) }
                )) {
                    ForEach(LocalVisionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                Text(appState.localVisionMode == .disabled
                     ? "关闭后，图片只保存在本机并进入手工处理；不会发送图片或调用 OCR。"
                     : appState.localVisionMode == .hosted
                     ? "图片发送到芥子 Hosted AI；关闭云同步不会关闭这项单独授权。"
                     : "图片经 TLS 直接发送至阿里云百炼北京端点的 Qwen 3.6 Flash；费用由你的供应商账户承担。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("单模型 BYOK") {
                Text("固定模型：Qwen 3.6 Flash · 北京地域。只需 API Key，不会自动验证或发送图片。Key 使用本机 Keychain，删除本机副本不会撤销供应商账户中的 Key。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                SecureField("粘贴 API Key", text: $byokAPIKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("保存并启用 BYOK") {
                    if appState.saveBYOKAPIKey(byokAPIKeyInput) { byokAPIKeyInput = "" }
                }
                .disabled(byokAPIKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                LabeledContent("本机 Key") {
                    Text(appState.hasBYOKAPIKey ? "已保存（不显示）" : "未保存")
                        .foregroundStyle(.secondary)
                }
                if appState.hasBYOKAPIKey {
                    Button("删除本机 Key…", role: .destructive) {
                        showDeleteBYOKConfirmation = true
                    }
                }
                if let message = appState.settingsMessage {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section("当前链路") {
                LabeledContent("截图") {
                    Text(routeSummary(forPhoto: false)).foregroundStyle(.secondary)
                }
                LabeledContent("拍照") {
                    Text(routeSummary(forPhoto: true)).foregroundStyle(.secondary)
                }
            }
            providerSection(title: "截图识别", selection: appState.userSettings.screenshotVisionPrimary, forPhoto: false)
            providerSection(title: "拍照识别", selection: appState.userSettings.photoVisionPrimary, forPhoto: true)
            qwenSection(title: "截图 Qwen 参数", forPhoto: false)
            qwenSection(title: "拍照 Qwen 参数", forPhoto: true)
            Section("识别规则") {
                Text("支付、收入、余额和账单按截图链路处理；明确来自相机或判断为真实食物照片时按拍照链路处理。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("识别模型配置")
        .scrollContentBackground(.hidden)
        .background(JieziTheme.pageBackground)
        .tint(JieziTheme.brand)
        .disabled(appState.isSavingSettings)
        .confirmationDialog(
            "删除本机 BYOK Key？",
            isPresented: $showDeleteBYOKConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除 Key", role: .destructive) { _ = appState.deleteBYOKAPIKey() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("只删除此设备 Keychain 中的副本。若要彻底停用，请另到供应商控制台撤销 Key。")
        }
    }

    private func providerSection(title: String, selection: String, forPhoto: Bool) -> some View {
        Section(title) {
            ForEach(NativeSettingsOptions.visionProviders) { option in
                Button {
                    Task { await appState.setVisionProvider(option.id, forPhoto: forPhoto) }
                } label: {
                    optionRow(option, selected: selection == option.id)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func qwenSection(title: String, forPhoto: Bool) -> some View {
        Section(title) {
            ForEach(NativeSettingsOptions.qwenModels) { option in
                Button {
                    Task { await appState.setQwenModel(option.id, forPhoto: forPhoto) }
                } label: {
                    optionRow(option, selected: currentModel(forPhoto: forPhoto) == option.id)
                }
                .buttonStyle(.plain)
            }
            Toggle(
                forPhoto ? "拍照思考模式" : "截图思考模式",
                isOn: asyncToggle(currentThinking(forPhoto: forPhoto)) {
                    await appState.setQwenThinking($0, forPhoto: forPhoto)
                }
            )
            Text(forPhoto ? "开启后更重质量，速度可能变慢。" : "关闭可减少截图识别耗时。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func routeSummary(forPhoto: Bool) -> String {
        let provider = forPhoto ? appState.userSettings.photoVisionPrimary : appState.userSettings.screenshotVisionPrimary
        let title = NativeSettingsOptions.visionProviders.first(where: { $0.id == provider })?.title ?? provider
        guard provider == "qwen" else { return title }
        return "\(title) · \(currentModel(forPhoto: forPhoto))"
    }

    private func currentModel(forPhoto: Bool) -> String {
        forPhoto ? appState.userSettings.qwenPhotoModel : appState.userSettings.qwenScreenshotModel
    }

    private func currentThinking(forPhoto: Bool) -> Bool {
        forPhoto ? appState.userSettings.qwenPhotoThinking : appState.userSettings.qwenScreenshotThinking
    }

}

struct CompanionSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var customNote = ""

    var body: some View {
        Form {
            Section {
                Toggle("陪伴文案", isOn: asyncToggle(appState.userSettings.companionEnabled, appState.setCompanionEnabled))
                Toggle("长期记忆", isOn: asyncToggle(appState.userSettings.companionMemoryEnabled, appState.setCompanionMemoryEnabled))
            }
            optionSection("语气", options: NativeSettingsOptions.personas, selected: appState.userSettings.companionPersona, action: appState.setCompanionPersona)
            optionSection("记忆强度", options: NativeSettingsOptions.memoryStrengths, selected: appState.userSettings.companionMemoryStrength, action: appState.setCompanionMemoryStrength)
            optionSection("表达方式", options: NativeSettingsOptions.expressionStyles, selected: appState.userSettings.companionExpressionStyle, action: appState.setCompanionExpressionStyle)
            Section("专属指令") {
                TextField("例如：少提体重，饭点温和一点", text: $customNote, axis: .vertical)
                    .lineLimit(2...4)
                    .onChange(of: customNote) { _, value in
                        if value.count > 80 { customNote = String(value.prefix(80)) }
                    }
                Text("\(customNote.count)/80").font(.caption).foregroundStyle(.secondary)
                Button("保存专属指令") { Task { await appState.setCompanionCustomNote(customNote) } }
                    .disabled(customNote == appState.userSettings.companionCustomNote)
            }
        }
        .navigationTitle("AI 陪伴")
        .scrollContentBackground(.hidden)
        .background(JieziTheme.pageBackground)
        .tint(JieziTheme.brand)
        .disabled(appState.isSavingSettings)
        .onAppear { customNote = appState.userSettings.companionCustomNote }
    }
}

struct InsightSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("联动分析模型") {
                ForEach(NativeSettingsOptions.insightProviders) { option in
                    Button {
                        Task { await appState.setInsightProvider(option.id) }
                    } label: {
                        optionRow(option, selected: appState.userSettings.aiInsightProvider == option.id)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("AI 联动分析")
        .scrollContentBackground(.hidden)
        .background(JieziTheme.pageBackground)
        .tint(JieziTheme.brand)
        .disabled(appState.isSavingSettings)
    }
}

struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingRetention: Int?
    @State private var showRetentionConfirmation = false

    var body: some View {
        Form {
            Section("Hosted 云端识别数据") {
                Toggle("AI 日志记录", isOn: asyncToggle(appState.userSettings.aiLogsEnabled, appState.setAILogsEnabled))
                Toggle("Prompt 优化参与", isOn: asyncToggle(appState.userSettings.promptOptimizationEnabled, appState.setPromptOptimizationEnabled))
                Text("Prompt 优化开启后会保留脱敏后的模型原始输出，默认关闭。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Toggle("参与 AI 改进", isOn: asyncToggle(appState.userSettings.expressionImprovementEnabled, appState.setExpressionImprovementEnabled))
                Text("开启后保存 30 天的脱敏语义与评分，不含原图、金额、商户或通知原文；关闭会清理未关联点评的后台数据。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("云端截图原图留存") {
                Text("以下期限仅影响云端原图。本机收件箱、财务和四域原图按本机记录引用保留；删除云图不会删除本机副本。")
                    .font(.footnote).foregroundStyle(.secondary)
                retentionButton("不保留", value: 0)
                retentionButton("保留 7 天", value: 7)
                retentionButton("保留 30 天", value: 30)
                retentionButton("永久保留", value: -1)
                Text(appState.userSettings.retentionDescription).font(.footnote).foregroundStyle(.secondary)
                if appState.isCleaningSourceImages {
                    ProgressView("正在清理已有云端原图")
                }
                if let message = appState.settingsMessage {
                    Label(
                        message,
                        systemImage: message.contains("失败") ? "exclamationmark.circle" : "checkmark.circle"
                    )
                    .font(.footnote)
                    .foregroundStyle(message.contains("失败") ? JieziTheme.coral : .secondary)
                }
            }
            Section("数据存储") {
                LabeledContent("服务节点", value: "Supabase 新加坡")
                LabeledContent("访问隔离", value: "用户级 RLS")
            }
        }
        .navigationTitle("隐私与留存")
        .task { await appState.loadCloudPrivacySettings() }
        .scrollContentBackground(.hidden)
        .background(JieziTheme.pageBackground)
        .tint(JieziTheme.brand)
        .disabled(appState.isLoadingSettings || appState.isSavingSettings || appState.isCleaningSourceImages)
        .confirmationDialog(retentionDialogTitle, isPresented: $showRetentionConfirmation, titleVisibility: .visible) {
            if let pendingRetention {
                Button(retentionPrimaryActionTitle) {
                    Task { await appState.setImageRetention(days: pendingRetention) }
                }
                if currentRetention == -1, pendingRetention != -1 {
                    Button("立即清理已有原图", role: .destructive) {
                        Task { await appState.setImageRetention(days: pendingRetention, cleanupExisting: true) }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(retentionDialogMessage)
        }
    }

    private func retentionButton(_ title: String, value: Int) -> some View {
        Button {
            pendingRetention = value
            showRetentionConfirmation = true
        } label: {
            HStack {
                Text(title).foregroundStyle(JieziTheme.ink)
                Spacer()
                if currentRetention == value { Image(systemName: "checkmark").foregroundStyle(JieziTheme.brand) }
            }
        }
    }

    private var currentRetention: Int {
        appState.userSettings.keepSourceImages ? appState.userSettings.imageRetentionDays : 0
    }

    private var retentionDialogTitle: String {
        pendingRetention == -1 ? "切换为永久保留" : "修改原图留存策略"
    }

    private var retentionPrimaryActionTitle: String {
        currentRetention == -1 && pendingRetention != -1 ? "按新期限处理" : "确认修改"
    }

    private var retentionDialogMessage: String {
        guard let pendingRetention else { return "" }
        if currentRetention == -1, pendingRetention != -1 {
            return "新截图将按新策略处理。已有原图可立即清理，也可按新期限继续保留。"
        }
        if pendingRetention == -1 {
            return "新截图和已有原图将永久保留，不再自动清理。"
        }
        if pendingRetention == 0 {
            return "新截图识别后不保留原图；结构化数据和识别结果仍会保留。"
        }
        return "新截图将保留 \(pendingRetention) 天后自动清理。"
    }
}

struct LocalHistoryMigrationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showsConfirmation = false
    @State private var preparationTask: Task<Void, Never>?
    @State private var cloudInventoryTask: Task<Void, Never>?

    var body: some View {
        Form {
            Section("状态") {
                Text(statusSummary)
                    .font(.headline)
                if let message = appState.historyMigrationMessage {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(message.contains("暂停") || message.contains("失败") ? JieziTheme.coral : .secondary)
                        .textSelection(.enabled)
                }
            }

            Section("云端与本机数据盘点") {
                HStack {
                    Text("类别")
                    Spacer()
                    Text("云端")
                        .frame(minWidth: 88, alignment: .trailing)
                    Text("本机")
                        .frame(minWidth: 76, alignment: .trailing)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                ForEach(LocalHistoryInventoryCatalog.rows) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.title)
                            .font(.subheadline)
                        Spacer(minLength: 4)
                        Text(cloudValue(for: row))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 88, alignment: .trailing)
                        Text(localValue(for: row))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(minWidth: 76, alignment: .trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
                Text("类别按各自来源表或本机表独立计数，账户流水用于账务对账，不等于额外业务账单。云端与本机数量差异不代表数据丢失或待迁入数量；以稳定标识和内容核对的迁移预览为准。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let snapshot = appState.localHistoryInventory {
                    Text("本机：\(snapshot.scope) · profile #\(shortID(snapshot.profileID)) · \(snapshot.sampledAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(localImageDetail(snapshot))
                        .font(.caption)
                        .foregroundStyle(snapshot.imageVerificationComplete ? .secondary : JieziTheme.coral)
                } else if appState.isLoadingLocalHistoryInventory {
                    ProgressView("正在只读统计本机数据")
                } else if let error = appState.localHistoryInventoryError {
                    Text(error).font(.caption).foregroundStyle(JieziTheme.coral)
                }
                if appState.cloudHistoryInventory.status == .notRead {
                    Text("尚未读取云端数量。打开本页不会访问云端；点击下方按钮后才会在当前登录会话下逐表读取。")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let message = appState.cloudHistoryInventory.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if appState.isReadingCloudHistoryInventory,
                   let table = appState.cloudHistoryInventory.currentTable {
                    Text("当前表：\(tableTitle(table))，已读 \(appState.cloudHistoryInventory.currentTableRowsRead) 条；总量未知。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let sampledAt = appState.cloudHistoryInventory.sampledAt {
                    let cloudAccount = appState.currentUserEmail.isEmpty ? "账户 #\(shortID(appState.currentUserId))" : appState.currentUserEmail
                    Text("云端：\(cloudAccount) · 全日期 · \(sampledAt.formatted(date: .numeric, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if appState.isReadingCloudHistoryInventory {
                    ProgressView("已读取 \(appState.cloudHistoryInventory.totalRowsRead) 条 · \(appState.cloudHistoryInventory.pagesRead) 页")
                }
                Button {
                    cloudInventoryTask = Task { await appState.readCloudHistoryInventory() }
                } label: {
                    if appState.isReadingCloudHistoryInventory { ProgressView() }
                    else { Label("读取云端数量", systemImage: "arrow.down.doc") }
                }
                .disabled(!appState.isSignedIn || appState.isReadingCloudHistoryInventory || appState.isPreparingHistoryMigration || appState.isImportingLocalBackup)
                if appState.isReadingCloudHistoryInventory {
                    Button("停止云端读取") { cloudInventoryTask?.cancel() }
                }
                Button("刷新本机盘点") {
                    Task { await appState.loadLocalHistoryInventory() }
                }
                .disabled(appState.isLoadingLocalHistoryInventory)
            }

            Section("当前步骤") {
                if appState.isPreparingHistoryMigration {
                    ProgressView()
                    Text(appState.historyMigrationPhase.isEmpty ? "正在准备" : appState.historyMigrationPhase)
                        .font(.subheadline)
                } else {
                    Text(appState.historyMigrationPhase.isEmpty ? "尚未开始" : appState.historyMigrationPhase)
                        .font(.subheadline)
                }
                if let progress = appState.historyMigrationProgress {
                    if let table = progress.currentTable {
                        Text("当前读取表：\(tableTitle(table))；总量未知")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("源数据：已读 \(progress.rowsRead) 条，\(progress.pagesRead) 页")
                        .font(.caption).foregroundStyle(.secondary)
                    if let total = progress.knownRowTotal {
                        if total > 0 { ProgressView(value: Double(progress.rowsRead), total: Double(total)) }
                        Text(total == 0 ? "源数据读取完成：0 条" : "源数据读取完成：\(progress.rowsRead) / \(total) 条")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if progress.phase == .downloadingImages {
                        Text("原图：已处理 \(progress.imagesProcessed) / \(progress.imagesTotal) 张")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if appState.historyMigrationBlockerCount > 0 {
                Section("迁移问题与恢复") {
                    Text("共有 \(appState.historyMigrationBlockerCount) 项需要核对；本次尚未入账。先核对源表、字段和历史写入合同，不会自动跳过或补造事实。")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.coral)
                    DisclosureGroup("查看问题列表（最多展示 200 项）") {
                        ForEach(Array(appState.historyMigrationBlockers.enumerated()), id: \.offset) { _, issue in
                            Text(issue)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        if appState.historyMigrationBlockerCount > appState.historyMigrationBlockers.count {
                            Text("其余 \(appState.historyMigrationBlockerCount - appState.historyMigrationBlockers.count) 项已汇总，重新读取可查看最新清单。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("恢复：核对具体字段或来源后重新读取；若源数据仍不能等价映射，保留阻塞并导出诊断。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            if let diagnostic = appState.historyMigrationDiagnostic {
                Section("最近诊断") {
                    Text(diagnostic.userMessage)
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.coral)
                    diagnosticDetails(diagnostic)
                }
            }
            if let diagnostic = appState.localProjectionRefreshDiagnostic {
                Section("本机列表刷新诊断") {
                    Text(diagnostic.userMessage)
                        .font(.subheadline)
                        .foregroundStyle(diagnostic.resolution == nil ? JieziTheme.coral : .secondary)
                    if let resolution = diagnostic.resolution {
                        Text("恢复结果：\(resolution)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    diagnosticDetails(diagnostic)
                }
            }

            Section("迁移操作") {
                Button("预检或继续迁移") {
                    preparationTask = Task { await appState.prepareCloudHistoryMigration() }
                }
                    .disabled(!appState.isSignedIn || appState.isPreparingHistoryMigration || appState.isImportingLocalBackup)
                if !appState.isSignedIn { Text("请先登录要迁入的云账户。") }
                if appState.canPauseHistoryMigration {
                    Button("暂停，保留进度") {
                        preparationTask?.cancel()
                        appState.pauseCloudHistoryMigration()
                    }
                }
                if let preview = appState.historyMigrationPreview {
                    DisclosureGroup("查看迁移预览与对账详情") {
                        Text(preview).font(.footnote).textSelection(.enabled)
                    }
                    Button("确认恢复到本机") { showsConfirmation = true }
                        .disabled(appState.isPreparingHistoryMigration || appState.isImportingLocalBackup)
                }
                if appState.historyMigrationPhase == "已入账", appState.localProjectionRefreshMessage != nil {
                    Button("只读重试本机列表刷新") {
                        Task { await appState.retryLocalProjectionRefresh() }
                    }
                    Text("迁移数据已经入账。此操作只重新读取本机列表，不会再次导入或增加流水。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Button("丢弃预检缓存并重新读取") { appState.restartCloudHistoryMigrationPreview() }
                    .disabled(appState.isPreparingHistoryMigration || appState.isImportingLocalBackup)
                Text("丢弃只清理未入账的预检缓存，不删除已经入账的数据。")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("迁移范围与规则") {
                DisclosureGroup("查看详细说明") {
                    Text("读取当前登录云账户的账户、流水、还款、消费、收入、四域记录、候选和原图。预检会在本机缓存源数据和原图，确认前不会入账，也不会自动开启云同步。")
                    Text("遇到缺图、余额不一致、无法等价恢复的历史状态或同ID内容冲突时，整包停止并显示原因。中断或重启后再次预检，将续传缺失页和图片；确认前仍会重新核对源数据。")
                }
                .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("历史数据迁移")
        .onDisappear { cloudInventoryTask?.cancel() }
        .task {
            await appState.loadLocalHistoryInventory()
            appState.loadLatestHistoryMigrationDiagnostic()
            appState.loadLatestLocalProjectionRefreshDiagnostic()
        }
        .confirmationDialog("确认将预检中的历史恢复到本机？", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("确认恢复") { Task { _ = await appState.confirmCloudHistoryMigration() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确认前会再次读取云端源数据和原图校验，可能产生下载流量。恢复不删除云副本，不改变云同步授权。建议先导出完整本地备份。")
        }
    }

    private var statusSummary: String {
        if appState.isPreparingHistoryMigration { return "历史迁移正在 \(appState.historyMigrationPhase)，尚未确认入账。" }
        if appState.historyMigrationPhase == "已入账" { return "历史迁移已入账；请核对本机数量和恢复结果。" }
        if appState.historyMigrationPreview != nil { return "预检已通过，等待你确认；当前尚未入账。" }
        if appState.historyMigrationPhase == "预检暂停" || appState.historyMigrationPhase == "预检阻塞" || appState.historyMigrationPhase == "事务入账" { return "历史迁移暂停；请先查看问题和诊断。" }
        if appState.historyMigrationPhase == "已取消" || appState.historyMigrationPhase == "已暂停" { return "预检已暂停，未入账；已缓存进度可继续。" }
        return "预检前不会写入本机账目；云端数量需单独点击读取。"
    }

    private func localValue(for row: LocalHistoryInventoryCatalog.Row) -> String {
        guard let snapshot = appState.localHistoryInventory else {
            return appState.localHistoryInventoryError == nil ? "—" : "读取失败"
        }
        if row.key == "images.references" {
            return "\(snapshot.counts["images.references", default: 0]) / \(snapshot.counts["images.unique", default: 0])"
        }
        if row.key == "account_entries" {
            return "\(snapshot.counts["account_entries", default: 0]) / \(snapshot.counts["account_entries.effective", default: 0])"
        }
        return String(snapshot.counts[row.key, default: 0])
    }

    private func cloudValue(for row: LocalHistoryInventoryCatalog.Row) -> String {
        let inventory = appState.cloudHistoryInventory
        guard inventory.status != .notRead else { return "未读取" }
        let value = inventory.counts[row.key, default: 0]
        if inventory.status == .complete { return row.key == "images.references" ? "\(value) / \(inventory.counts["images.unique", default: 0])" : String(value) }
        guard let sourceTable = row.sourceTable else { return "部分读取" }
        if inventory.completedTables.contains(sourceTable) {
            if row.key == "account_entries" { return "\(value) / \(inventory.counts["account_entries.effective", default: 0])" }
            return String(value)
        }
        if inventory.currentTable == sourceTable { return "已读 \(value)，总量未知" }
        return "未读取"
    }

    private func localImageDetail(_ snapshot: LocalHistoryInventorySnapshot) -> String {
        let counts = snapshot.counts
        let detail = "原图：引用 \(counts["images.references", default: 0])，去重文件 \(counts["images.unique", default: 0])，已缓存 \(counts["images.cached", default: 0])，已校验 \(counts["images.verified", default: 0])，缺失 \(counts["images.missing", default: 0])，未校验 \(counts["images.unverified", default: 0])。"
        return snapshot.imageVerificationComplete ? detail : detail + "校验因本次读取上限未完成。"
    }

    private func shortID(_ value: String?) -> String {
        guard let value else { return "尚无" }
        return String(value.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
    }

    private func tableTitle(_ table: LocalHistorySourceTable) -> String {
        switch table {
        case .accounts: return "账户"
        case .accountEntries: return "账户流水"
        case .repaymentCycles: return "还款周期"
        case .payments: return "还款记录"
        case .transactions: return "交易"
        case .incomes: return "收入"
        case .records: return "四域与钱包记录"
        case .staging: return "候选"
        }
    }
}

struct DataExportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var request = NativeDataExportRequest()
    @State private var exportedFile: NativeExportedFile?
    @State private var backupForImport: Data?
    @State private var backupPreview: LocalCompleteBackupPreview?
    @State private var isShowingBackupImporter = false
    @State private var isShowingBackupConfirmation = false
    @State private var backupImportError: String?

    var body: some View {
        Form {
            Section("导出内容") {
                Picker("内容", selection: $request.content) {
                    ForEach(NativeExportContent.allCases) { Text($0.title).tag($0) }
                }
                Picker("时间范围", selection: $request.range) {
                    ForEach(NativeExportRange.allCases) { Text($0.title).tag($0) }
                }
                Picker("文件格式", selection: $request.format) {
                    ForEach(NativeExportFormat.allCases) { Text($0.title).tag($0) }
                }
                Toggle("包含完整 payload", isOn: $request.includeFullPayload)
                Toggle("包含本地图片", isOn: $request.includeImages)
            }
            Section {
                Button {
                    Task { exportedFile = await appState.exportData(request) }
                } label: {
                    if appState.isExportingData { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("生成导出文件", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity) }
                }
                .disabled(appState.isExportingData)
            }
            Section("完整本地备份") {
                Text("上方普通导出不包含账户流水、钱包快照和候选；完整恢复请使用本节备份。备份包含本机业务事实、账户流水、待处理图片和历史状态，不包含登录、同步授权或 API Key；缺失图片时会失败。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    Task { exportedFile = await appState.exportCompleteLocalBackup() }
                } label: {
                    Label("导出可恢复备份", systemImage: "externaldrive.badge.timemachine")
                }
                .disabled(appState.isExportingData)
                Button {
                    isShowingBackupImporter = true
                } label: {
                    if appState.isImportingLocalBackup { ProgressView() }
                    else { Label("恢复本地备份", systemImage: "arrow.down.doc") }
                }
                .disabled(appState.isImportingLocalBackup)
                if let message = appState.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.contains("失败") ? JieziTheme.coral : JieziTheme.mint)
                }
            }
        }
        .navigationTitle("数据导出")
        .scrollContentBackground(.hidden)
        .background(JieziTheme.pageBackground)
        .tint(JieziTheme.brand)
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .fileImporter(isPresented: $isShowingBackupImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
                let values = try url.resourceValues(forKeys: [.fileSizeKey])
                guard let size = values.fileSize, size <= 180 * 1024 * 1024 else {
                    throw LocalCompleteBackupError.archiveTooLarge
                }
                let data = try Data(contentsOf: url, options: [.mappedIfSafe])
                Task {
                    do {
                        let preview = try await appState.previewCompleteLocalBackup(data)
                        backupForImport = data
                        backupPreview = preview
                        isShowingBackupConfirmation = true
                    } catch {
                        backupImportError = error.localizedDescription
                    }
                }
            } catch {
                backupImportError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "确认恢复本地备份？",
            isPresented: $isShowingBackupConfirmation,
            titleVisibility: .visible,
            presenting: backupPreview
        ) { _ in
            Button("确认合并并恢复", role: .destructive) {
                guard let backupForImport else { return }
                Task {
                    _ = await appState.importCompleteLocalBackup(backupForImport)
                    self.backupForImport = nil
                    self.backupPreview = nil
                }
            }
            Button("取消", role: .cancel) {
                backupForImport = nil
                backupPreview = nil
            }
        } message: { preview in
            Text(preview.confirmationText)
        }
        .alert("无法读取备份", isPresented: Binding(
            get: { backupImportError != nil },
            set: { if !$0 { backupImportError = nil } }
        )) {
            Button("好", role: .cancel) { backupImportError = nil }
        } message: {
            Text(backupImportError ?? "")
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private func optionRow(_ option: NativeSettingsOption, selected: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 3) {
            Text(option.title).foregroundStyle(JieziTheme.ink)
            Text(option.detail).font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(selected ? JieziTheme.brand : JieziTheme.muted)
    }
}

private func optionSection(
    _ title: String,
    options: [NativeSettingsOption],
    selected: String,
    action: @escaping (String) async -> Void
) -> some View {
    Section(title) {
        ForEach(options) { option in
            Button { Task { await action(option.id) } } label: { optionRow(option, selected: selected == option.id) }
                .buttonStyle(.plain)
        }
    }
}

private func asyncToggle(_ value: Bool, _ action: @escaping (Bool) async -> Void) -> Binding<Bool> {
    Binding(get: { value }, set: { newValue in Task { await action(newValue) } })
}

struct ShortcutSetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var setupMessage: String?

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: appState.hasUploadToken ? "key.fill" : "key.slash")
                            .font(.title2)
                            .foregroundStyle(appState.hasUploadToken ? JieziTheme.mint : JieziTheme.coral)
                            .frame(width: 38, height: 38)
                            .background(JieziTheme.brand.opacity(0.08), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.hasUploadToken ? "凭据已同步" : "凭据未同步")
                                .font(.headline)
                            Text(appState.hasUploadToken ? "快捷指令会自动读取 Keychain，不需要填写 upload_token。" : "请先返回 App 登录一次，再配置快捷指令。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        appState.verifyShortcutCredential()
                    } label: {
                        Label("重新检查凭据", systemImage: "arrow.clockwise")
                    }
                }

                Section("系统内置动作") {
                    ShortcutActionRow(title: "上传 JPEG 到芥子", detail: "接收上一部“转换为 JPEG”的结果。点击动作里的 JPEG 图像槽，选择“转换后的图像”。", systemImage: "square.and.arrow.up")
                    ShortcutActionRow(title: "检查芥子凭据", detail: "确认登录后 Keychain 凭据可被快捷指令自动读取。", systemImage: "key.viewfinder")
                }

                Section("快捷指令模板") {
                    ShortcutStepRow(index: 1, title: "选择记录方式", detail: "拍照和截图使用不同模板。安装后都由“上传 JPEG 到芥子”完成识别，不需要手动填写凭据。")
                    VStack(spacing: 10) {
                        Button {
                            openShortcutTemplate(.photo)
                        } label: {
                            Label("安装拍照记录模板", systemImage: "camera.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JieziTheme.brand)

                        Button {
                            openShortcutTemplate(.screenshot)
                        } label: {
                            Label("安装截图记录模板", systemImage: "rectangle.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(JieziTheme.brand)
                    }
                    if let setupMessage {
                        Text(setupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ShortcutStepRow(index: 2, title: "压缩建议", detail: "如果在快捷指令里压缩，建议长边保留 1200 以上；640 容易让小字识别变差。")
                    ShortcutStepRow(index: 3, title: "结果通知", detail: "推荐开启。上传完成会弹出系统通知；点击通知会回到芥子。")
                    ShortcutStepRow(index: 4, title: "显示结果", detail: "可选兜底。如果你喜欢通知优先，可以在设置里关闭结果卡片，并在快捷指令模板里删掉“显示结果”。")
                    ShortcutStepRow(index: 5, title: "凭据处理", detail: "快捷指令里不放 token。芥子会从 Keychain 自动读取登录后同步的上传凭据。")
                }

                Section {
                    Button {
                        Task {
                            await appState.requestShortcutNotificationPermission()
                        }
                    } label: {
                        Label("开启上传结果通知", systemImage: "bell.badge")
                    }
                    Button {
                        Task {
                            await appState.sendTestShortcutNotification()
                        }
                    } label: {
                        Label("发送测试通知", systemImage: "bell.and.waves.left.and.right")
                    }
                    Button {
                        UIPasteboard.general.string = "上传 JPEG 到芥子"
                    } label: {
                        Label("复制动作名称", systemImage: "doc.on.doc")
                    }
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            openURL(url)
                        }
                    } label: {
                        Label("打开快捷指令 App", systemImage: "arrow.up.forward.app")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
            .tint(JieziTheme.brand)
        }
        .navigationTitle("快捷指令")
        .toolbarBackground(JieziScene.expense.surface, for: .navigationBar)
    }

    private func openShortcutTemplate(_ template: ShortcutTemplateKind) {
        if let url = URL(string: template.url), !template.url.isEmpty {
            openURL(url)
            return
        }

        setupMessage = "当前构建还没有配置\(template.title)链接。我会先打开快捷指令 App，你可以搜索“上传 JPEG 到芥子”继续手动配置。"
        if let url = URL(string: "shortcuts://") {
            openURL(url)
        }
    }

}

private struct ShortcutActionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
                .frame(width: 28, height: 28)
                .background(JieziTheme.brand.opacity(0.08), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutStepRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(JieziTheme.mint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
