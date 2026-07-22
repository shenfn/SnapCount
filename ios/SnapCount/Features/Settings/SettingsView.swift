import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showDeleteAccountConfirmation = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    profileHeader
                }

                Section("数据管理") {
                    NavigationLink {
                        DataExportView()
                    } label: {
                        settingsRow("数据导出", detail: "导出支出、收入和通用记录", systemImage: "square.and.arrow.up")
                    }
                }

                Section("AI 能力") {
                    NavigationLink {
                        VisionSettingsView()
                    } label: {
                        settingsRow(
                            "截图 / 拍照识别",
                            detail: "截图：\(providerTitle(appState.userSettings.screenshotVisionPrimary)) · 拍照：\(providerTitle(appState.userSettings.photoVisionPrimary))",
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
                            detail: appState.hasUploadToken ? "凭据已同步" : "需要重新登录同步凭据",
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
                        Text("Supabase 新加坡节点").foregroundStyle(.secondary)
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
                        Label("删除账户及全部数据", systemImage: "person.crop.circle.badge.xmark")
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
            }
            .scrollContentBackground(.hidden)
            .refreshable { await appState.loadUserSettings() }
        }
        .navigationTitle("设置")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .alert("永久删除账户？", isPresented: $showDeleteAccountConfirmation) {
            Button("删除账户及全部数据", role: .destructive) {
                Task { _ = await appState.deleteAccount() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("这会删除云端记录、账户流水、AI 识别数据和原图，且无法恢复。")
        }
        .task { await appState.loadUserSettings() }
    }

    private var profileHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(JieziTheme.brand)
            VStack(alignment: .leading, spacing: 3) {
                Text(appState.currentUserEmail.isEmpty ? "已登录用户" : appState.currentUserEmail)
                    .font(.headline)
                Text("\(appState.userSettings.planTitle) · \(appState.currentUserId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 5)
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

private struct VisionSettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
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
        .disabled(appState.isSavingSettings)
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

private struct CompanionSettingsView: View {
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
        .disabled(appState.isSavingSettings)
        .onAppear { customNote = appState.userSettings.companionCustomNote }
    }
}

private struct InsightSettingsView: View {
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
        .disabled(appState.isSavingSettings)
    }
}

private struct PrivacySettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var pendingRetention: Int?
    @State private var showRetentionConfirmation = false

    var body: some View {
        Form {
            Section("识别数据") {
                Toggle("AI 日志记录", isOn: asyncToggle(appState.userSettings.aiLogsEnabled, appState.setAILogsEnabled))
                Toggle("Prompt 优化参与", isOn: asyncToggle(appState.userSettings.promptOptimizationEnabled, appState.setPromptOptimizationEnabled))
                Text("Prompt 优化开启后会保留脱敏后的模型原始输出，默认关闭。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Section("截图原图留存") {
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
        .disabled(appState.isSavingSettings || appState.isCleaningSourceImages)
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
            guard currentRetention != value else { return }
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

private struct DataExportView: View {
    @EnvironmentObject private var appState: AppState
    @State private var request = NativeDataExportRequest()
    @State private var exportedFile: NativeExportedFile?

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
                if request.content == .universal {
                    Toggle("包含完整 payload", isOn: $request.includeFullPayload)
                }
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
        }
        .navigationTitle("数据导出")
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
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

private struct ShortcutSetupView: View {
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
                            .background(.thinMaterial, in: Circle())
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
                        .tint(JieziTheme.gold)

                        Button {
                            openShortcutTemplate(.screenshot)
                        } label: {
                            Label("安装截图记录模板", systemImage: "rectangle.on.rectangle.angled")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(JieziTheme.mint)
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
        }
        .navigationTitle("快捷指令")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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

    private enum ShortcutTemplateKind {
        case photo
        case screenshot

        var title: String {
            switch self {
            case .photo: return "拍照模板"
            case .screenshot: return "截图模板"
            }
        }

        var url: String {
            switch self {
            case .photo: return AppConfig.photoShortcutTemplateURL
            case .screenshot: return AppConfig.screenshotShortcutTemplateURL
            }
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
                .background(.thinMaterial, in: Circle())

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
