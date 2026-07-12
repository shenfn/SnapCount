import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: NativeInboxFilter = .all

    private var allItems: [NativeInboxItem] {
        NativeInboxPresentation.items(
            pendingExpenses: appState.dashboard.pendingExpenses,
            stagingRecords: appState.dashboard.stagingRecords
        )
    }

    private var sections: [NativeInboxSection] {
        NativeInboxPresentation.sections(
            from: NativeInboxPresentation.filtered(allItems, by: filter),
            today: Self.dateKey(daysFromToday: 0),
            yesterday: Self.dateKey(daysFromToday: -1)
        )
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section { pendingSummary }

                if allItems.isEmpty {
                    ContentUnavailableView(
                        "暂无待处理记录",
                        systemImage: "checkmark.circle",
                        description: Text("待补全账单和不确定的 AI 识别结果会显示在这里。")
                    )
                } else {
                    Section { filterPicker }

                    if sections.isEmpty {
                        ContentUnavailableView(
                            "当前筛选为空",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("换一个状态查看其他待处理记录。")
                        )
                    } else {
                        ForEach(sections) { section in
                            Section(section.title) {
                                ForEach(section.items) { item in inboxRow(item) }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await appState.refreshDashboard() }
        }
        .navigationTitle("中转站")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .navigationDestination(for: String.self) { id in
            if let record = appState.dashboard.stagingRecords.first(where: { $0.id == id }) {
                StagingRecordDetailView(record: record)
            } else {
                ContentUnavailableView(
                    "记录不在中转站",
                    systemImage: "checkmark.circle",
                    description: Text("它可能已经归档、销毁，或下拉刷新后状态发生了变化。")
                )
            }
        }
    }

    @ViewBuilder
    private func inboxRow(_ item: NativeInboxItem) -> some View {
        if let pending = item.pendingExpense {
            Button { appState.openPendingExpense(pending) } label: {
                NativeInboxItemRow(item: item)
            }
            .buttonStyle(.plain)
        } else if let record = item.stagingRecord {
            NavigationLink(value: record.id) { NativeInboxItemRow(item: item) }
        }
    }

    private var pendingSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: allItems.isEmpty ? "checkmark.circle.fill" : "tray.full.fill")
                .font(.title2)
                .foregroundStyle(allItems.isEmpty ? JieziTheme.mint : JieziTheme.gold)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(allItems.isEmpty ? "中转站已清空" : "\(allItems.count) 条待处理")
                    .font(.headline)
                Text("待补全、待分类、待确认和识别失败的记录统一在这里处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $filter) {
            ForEach(NativeInboxFilter.allCases) { item in Text(item.title).tag(item) }
        }
        .pickerStyle(.menu)
    }

    private static func dateKey(daysFromToday: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return date.formatted(.iso8601.year().month().day())
    }
}

private struct NativeInboxItemRow: View {
    let item: NativeInboxItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(item.kind == .pendingExpense ? JieziTheme.gold : JieziTheme.brand)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 8)
            Text(item.statusLabel).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

private struct StagingRecordRow: View {
    let record: NativeStagingRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(statusColor)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(record.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(record.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }

                Text(record.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Text(record.recordTypeLabel)
                    Text(record.createdAtLabel)
                    if let confidence = record.confidencePercent {
                        Text("置信度 \(confidence)%")
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private var statusColor: Color {
        switch record.status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.gold
        default: return JieziTheme.mint
        }
    }
}

private struct StagingRecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    let record: NativeStagingRecord
    @State private var showDiscardConfirm = false
    @State private var selectedArchiveDomain: NativeArchiveDomain?
    @State private var showArchiveConfirm = false
    @State private var imagePreview: StagingImagePreviewRoute?
    @State private var resolvedImageURL: URL?
    @State private var isResolvingImage = false
    @State private var imageResolutionMessage: String?

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(record.statusLabel, systemImage: record.systemImage)
                            .font(.headline)
                        Text(record.title)
                            .font(.title3.weight(.semibold))
                        Text(record.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }

                if let imageURL = resolvedImageURL ?? record.imageURL {
                    Section("截图原图") {
                        Button {
                            imagePreview = StagingImagePreviewRoute(url: imageURL)
                        } label: {
                            StagingImagePreview(url: imageURL)
                        }
                        .buttonStyle(.plain)
                    }
                } else if record.imagePath != nil {
                    Section("截图原图") {
                        if isResolvingImage {
                            ProgressView("正在加载截图…")
                                .frame(maxWidth: .infinity, minHeight: 120)
                        } else {
                            Button {
                                Task { await resolveImage() }
                            } label: {
                                VStack(spacing: 8) {
                                    unavailableImageView
                                    Text(imageResolutionMessage ?? "点此重新加载")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, minHeight: 120)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Section("识别信息") {
                    LabeledContent("类型", value: record.recordTypeLabel)
                    LabeledContent("上传时间", value: record.createdAtLabel)
                    if let occurredAtLabel = record.occurredAtLabel {
                        LabeledContent("记录时间", value: occurredAtLabel)
                    }
                    if let confidence = record.confidencePercent {
                        LabeledContent("置信度", value: "\(confidence)%")
                    }
                    if record.retryCount > 0 {
                        LabeledContent("重试次数", value: "\(record.retryCount)")
                    }
                }

                if let companionMessage = record.companionMessage, !companionMessage.isEmpty {
                    Section("AI 陪伴") {
                        Text(companionMessage)
                            .font(.subheadline)
                    }
                }

                if !record.extracted.isEmpty {
                    Section("AI 提取字段") {
                        ForEach(record.extractedDisplayItems, id: \.key) { item in
                            LabeledContent(item.key, value: item.value)
                        }
                    }
                }

                if let message = record.lastErrorMessage, !message.isEmpty {
                    Section("错误信息") {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(JieziTheme.coral)
                    }
                }

                Section {
                    ForEach(InboxArchiveDomains.all) { domain in
                        Button {
                            selectedArchiveDomain = domain
                            showArchiveConfirm = true
                        } label: {
                            Label("归档到\(domain.title)", systemImage: domain.systemImage)
                        }
                    }
                    Button {
                        Task {
                            await appState.retryStagingRecord(record)
                        }
                    } label: {
                        Label("重试识别", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        showDiscardConfirm = true
                    } label: {
                        Label("销毁这条截图", systemImage: "trash")
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("待处理详情")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .confirmationDialog("确认销毁这条待处理截图？", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
            Button("销毁", role: .destructive) {
                Task {
                    await appState.discardStagingRecord(record)
                }
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog(
            "确认归档这条截图？",
            isPresented: $showArchiveConfirm,
            titleVisibility: .visible,
            presenting: selectedArchiveDomain
        ) { domain in
            Button("归档到\(domain.title)") {
                Task {
                    await appState.archiveStagingRecord(record, domainKey: domain.id)
                }
            }
            Button("取消", role: .cancel) {}
        } message: { domain in
            Text("芥子会按 PWA 的同一套规则，把这条中转站记录转入\(domain.title)域。")
        }
        .sheet(item: $imagePreview) { route in
            NavigationStack {
                ZStack {
                    Color.black.ignoresSafeArea()
                    CachedRemoteImage(url: route.url) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    } failure: {
                        Label("截图文件不可用", systemImage: "photo.badge.exclamationmark")
                            .foregroundStyle(.white)
                    }
                    .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("完成") {
                            imagePreview = nil
                        }
                    }
                }
            }
        }
        .task(id: record.id) {
            if record.imageURL == nil, record.imagePath != nil {
                await resolveImage()
            }
        }
    }

    private func resolveImage() async {
        guard !isResolvingImage else { return }
        isResolvingImage = true
        imageResolutionMessage = nil
        defer { isResolvingImage = false }
        do {
            resolvedImageURL = try await appState.resolveStagingImageURL(for: record)
        } catch {
            imageResolutionMessage = error.localizedDescription
        }
    }

    private var unavailableImageView: some View {
        Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct StagingImagePreview: View {
    let url: URL

    var body: some View {
        CachedRemoteImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Label("查看大图", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(10)
                }
        } placeholder: {
            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
        } failure: {
            Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StagingImagePreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension NativeStagingRecord {
    var extractedDisplayItems: [(key: String, value: String)] {
        extracted
            .filter { !$0.value.displayValue.isEmpty }
            .sorted { $0.key < $1.key }
            .prefix(18)
            .map { key, value in
                (key: key, value: value.displayValue)
            }
    }
}
