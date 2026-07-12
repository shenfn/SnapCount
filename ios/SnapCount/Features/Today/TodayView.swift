import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("jiezi.home.widgets.v1") private var widgetConfiguration = HomeWidget.defaultConfiguration
    @State private var showUploadOptions = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var showWidgetManager = false
    @State private var isUploading = false
    @State private var uploadMessage: String?
    @State private var uploadMessageIsError = false
    @State private var showUploadResult = false

    private var enabledWidgets: [HomeWidget] {
        HomeWidget.decode(widgetConfiguration).filter(.isEnabled)
    }

    var body: some View {
        ZStack {
            JieziPageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    greetingHeader
                    widgetToolbar
                    ForEach(enabledWidgets) { widget in
                        widgetView(widget)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 36)
            }
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(JieziTheme.paper.opacity(0.9), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("留下此刻", isPresented: $showUploadOptions, titleVisibility: .visible) {
            Button("从相册选择") { showPhotoLibraryPicker = true }
            Button("拍摄照片") { showCameraPicker = true }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { data in
                showCameraPicker = false
                Task { await uploadImageData(data, captureKind: "camera", filename: "camera-capture.jpg") }
            } onCancel: {
                showCameraPicker = false
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                showPhotoLibraryPicker = false
                Task { await uploadImageData(data, captureKind: "screenshot", filename: "photo-library-upload.jpg") }
            } onCancel: {
                showPhotoLibraryPicker = false
            }
        }
        .sheet(isPresented: $showWidgetManager) {
            HomeWidgetManager(configuration: $widgetConfiguration)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(uploadMessageIsError ? "上传失败" : "上传完成", isPresented: $showUploadResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(uploadMessage ?? "")
        }
    }

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Self.dateFormatter.string(from: Date()))
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                Spacer()
                Text("芥")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                    .foregroundStyle(JieziTheme.brand)
                    .frame(width: 44, height: 44)
                    .background(JieziTheme.paper.opacity(0.72), in: Circle())
                    .overlay(Circle().stroke(JieziTheme.brand.opacity(0.13)))
            }

            Text(Self.greeting)
                .font(.system(size: 38, weight: .regular, design: .serif))
                .foregroundStyle(JieziTheme.ink)
                .tracking(-1.2)
            Text("生活无需被刻意整理，留下痕迹就好。")
                .font(.body)
                .foregroundStyle(JieziTheme.muted)
        }
        .padding(.top, 6)
    }

    private var widgetToolbar: some View {
        HStack {
            Text("今日首页")
                .font(.headline)
            Spacer()
            Button("管理组件") {
                showWidgetManager = true
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(JieziTheme.brand)
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func widgetView(_ widget: HomeWidget) -> some View {
        switch widget.kind {
        case .overview:
            overviewCard
        case .pending:
            pendingCard
        case .domains:
            domainCard
        case .capture:
            captureCard
        case .flow:
            flowCard
        }
    }

    private var overviewCard: some View {
        HomeSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("今日概览")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(appState.dashboard.todayCount == 0 ? "今天还没有新的微尘。" : "今天已有 (appState.dashboard.todayCount) 粒微尘沉淀。")
                            .font(.system(size: 21, weight: .medium, design: .serif))
                    }
                    Spacer()
                    if appState.isLoadingDashboard { ProgressView().tint(JieziTheme.brand) }
                }

                HStack(spacing: 8) {
                    OverviewMetric(value: appState.dashboard.todayCount, label: "今日记录")
                    OverviewMetric(value: appState.dashboard.pendingCount, label: "待处理")
                    OverviewMetric(value: appState.dashboard.monthCount, label: "本月沉淀")
                }

                if let message = appState.dashboardMessage {
                    Label(message, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.coral)
                }
            }
        }
    }

    private var captureCard: some View {
        Button {
            showUploadOptions = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: isUploading ? "hourglass" : "camera.viewfinder")
                    .font(.title3.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(isUploading ? "正在接住这粒微尘" : "留下此刻")
                        .font(.headline)
                    Text(isUploading ? "图片正在进入 AI 识别链路" : "拍照或从相册选择图片")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.66))
                }
                Spacer()
                Image(systemName: "plus")
                    .font(.title3.weight(.medium))
            }
            .padding(16)
            .foregroundStyle(.white)
            .background(JieziTheme.brandWash, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(.white.opacity(0.14)))
            .shadow(color: JieziTheme.brand.opacity(0.18), radius: 20, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
    }

    private var pendingCard: some View {
        Button {
            appState.selectedTab = .inbox
        } label: {
            HomeSurface {
                HStack(spacing: 14) {
                    Image(systemName: "tray.full")
                        .font(.headline)
                        .foregroundStyle(JieziTheme.brand)
                        .frame(width: 46, height: 46)
                        .background(JieziTheme.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("待处理提醒")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(appState.dashboard.pendingCount == 0 ? "微尘都已找到归处" : "(appState.dashboard.pendingCount) 粒微尘仍在寻找归处")
                            .font(.headline)
                            .foregroundStyle(JieziTheme.ink)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JieziTheme.muted)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var domainCard: some View {
        HomeSurface {
            VStack(alignment: .leading, spacing: 12) {
                Text("数据域快捷入口")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                Text("沿着生活的脉络查看")
                    .font(.system(size: 20, weight: .medium, design: .serif))
                HStack(spacing: 8) {
                    DomainShortcut(title: "消费", symbol: "yensign.circle") { openRecords() }
                    DomainShortcut(title: "运动", symbol: "figure.run") { openRecords() }
                    DomainShortcut(title: "饮食", symbol: "fork.knife") { openRecords() }
                    DomainShortcut(title: "睡眠", symbol: "moon") { openRecords() }
                }
            }
        }
    }

    private var flowCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("因缘流转")
                    .font(.headline)
                Spacer()
                Text("最近沉淀")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            }

            if appState.dashboard.recentRecords.isEmpty {
                HomeSurface {
                    Text("留下第一张截图或照片后，记录会在这里按时间自然流转。")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(appState.dashboard.recentRecords.prefix(6)) { item in
                        Button {
                            openRecord(item.id)
                        } label: {
                            HomeSurface {
                                NativeFlowRow(item: item)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func openRecords() {
        appState.selectedTab = .records
        appState.recordsPath.removeAll()
    }

    private func openRecord(_ reference: String) {
        if reference.hasPrefix("staging-") {
            appState.selectedTab = .inbox
            appState.inboxPath = [String(reference.dropFirst("staging-".count))]
            return
        }
        appState.selectedTab = .records
        appState.recordsPath = [reference]
    }

    private func uploadImageData(_ data: Data, captureKind: String, filename: String) async {
        isUploading = true
        uploadMessage = "正在上传并等待 AI 识别结果。"
        uploadMessageIsError = false

        do {
            guard let uploadToken = try KeychainStore.shared.string(for: KeychainKeys.uploadToken), !uploadToken.isEmpty else {
                throw NativeUploadError.missingUploadToken
            }
            uploadMessage = try await SnapCountUploadService().uploadNativeImage(
                data: data,
                uploadToken: uploadToken,
                captureKind: captureKind,
                filename: filename
            )
            uploadMessageIsError = false
            await appState.refreshDashboard()
            showUploadResult = true
        } catch {
            uploadMessage = "上传失败：(error.localizedDescription)"
            uploadMessageIsError = true
            showUploadResult = true
        }
        isUploading = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M 月 d 日 · EEEE"
        return formatter
    }()

    private static var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<11: return "早上好，
今天也由芥子接住。"
        case 11..<18: return "下午好，
让生活自然沉淀。"
        default: return "晚上好，
今天的痕迹都在这里。"
        }
    }
}

private struct HomeSurface<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(JieziTheme.paper.opacity(0.7), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(JieziTheme.brand.opacity(0.1)))
            .shadow(color: JieziTheme.space.opacity(0.055), radius: 16, x: 0, y: 9)
    }
}

private struct OverviewMetric: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("(value)")
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(JieziTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(JieziTheme.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct DomainShortcut: View {
    let title: String
    let symbol: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.body.weight(.medium))
                    .foregroundStyle(JieziTheme.brand)
                    .frame(width: 34, height: 34)
                    .background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(JieziTheme.muted)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

private struct NativeFlowRow: View {
    let item: NativeRecordSummary

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.medium))
                .foregroundStyle(JieziTheme.brand)
                .frame(width: 42, height: 42)
                .background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(1)
            }
            Spacer()
            if !item.value.isEmpty {
                Text(item.value)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
                    .monospacedDigit()
            }
        }
    }
}

private struct HomeWidgetManager: View {
    @Environment(.dismiss) private var dismiss
    @Binding var configuration: String
    @State private var widgets: [HomeWidget]

    init(configuration: Binding<String>) {
        _configuration = configuration
        _widgets = State(initialValue: HomeWidget.decode(configuration.wrappedValue))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($widgets) { $widget in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(widget.title).font(.headline)
                                Text(widget.description).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $widget.isEnabled).labelsHidden().tint(JieziTheme.brand)
                        }
                    }
                    .onMove { source, destination in
                        widgets.move(fromOffsets: source, toOffset: destination)
                    }
                } footer: {
                    Text("拖动可调整顺序。财务状态会在账户与欠款聚合接入后加入。")
                }
            }
            .navigationTitle("首页组件")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        configuration = HomeWidget.encode(widgets)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct HomeWidget: Identifiable, Codable {
    enum Kind: String, Codable {
        case overview, pending, domains, capture, flow
    }

    let kind: Kind
    var isEnabled: Bool
    var id: String { kind.rawValue }

    var title: String {
        switch kind {
        case .overview: return "今日概览"
        case .pending: return "待处理提醒"
        case .domains: return "数据域快捷入口"
        case .capture: return "留下此刻"
        case .flow: return "因缘流转"
        }
    }

    var description: String {
        switch kind {
        case .overview: return "当天记录、待处理与本月沉淀"
        case .pending: return "进入中转站处理异常记录"
        case .domains: return "快速查看已沉淀的数据"
        case .capture: return "拍照或从相册选择图片"
        case .flow: return "查看最近沉淀记录"
        }
    }

    static let defaults = Kind.allCases.map { HomeWidget(kind: $0, isEnabled: true) }
    static let defaultConfiguration = encode(defaults)

    static func decode(_ value: String) -> [HomeWidget] {
        guard let data = value.data(using: .utf8), let decoded = try? JSONDecoder().decode([HomeWidget].self, from: data) else {
            return defaults
        }
        var result = decoded.filter { widget in defaults.contains(where: { $0.kind == widget.kind }) }
        for item in defaults where !result.contains(where: { $0.kind == item.kind }) { result.append(item) }
        return result
    }

    static func encode(_ widgets: [HomeWidget]) -> String {
        guard let data = try? JSONEncoder().encode(widgets), let string = String(data: data, encoding: .utf8) else { return "[]" }
        return string
    }
}

extension HomeWidget.Kind: CaseIterable {}

private enum NativeUploadError: LocalizedError {
    case missingUploadToken

    var errorDescription: String? {
        switch self {
        case .missingUploadToken: return "缺少上传凭据，请重新登录。"
        }
    }
}
