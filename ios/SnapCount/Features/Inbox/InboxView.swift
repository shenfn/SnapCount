import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: InboxFilter = .all

    private var records: [NativeStagingRecord] {
        switch filter {
        case .all:
            return appState.dashboard.stagingRecords
        case .routing:
            return appState.dashboard.stagingRecords.filter { ["routing_failed", "unrouted", "unassigned"].contains($0.status) }
        case .review:
            return appState.dashboard.stagingRecords.filter { ["pending_review", "routed", "extracted"].contains($0.status) }
        case .failed:
            return appState.dashboard.stagingRecords.filter { ["ai_error", "failed", "extraction_failed", "schema_failed"].contains($0.status) }
        }
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    pendingSummary
                }

                if appState.dashboard.stagingRecords.isEmpty {
                    ContentUnavailableView(
                        "暂无待处理记录",
                        systemImage: "checkmark.circle",
                        description: Text("上传后的不确定识别结果会先进入这里。")
                    )
                } else {
                    Section {
                        filterPicker
                    }

                    if records.isEmpty {
                        ContentUnavailableView(
                            "当前筛选为空",
                            systemImage: "line.3.horizontal.decrease.circle",
                            description: Text("换一个状态查看其他待处理截图。")
                        )
                    } else {
                        Section("中转站") {
                            ForEach(records) { record in
                                NavigationLink {
                                    StagingRecordDetailView(record: record)
                                } label: {
                                    StagingRecordRow(record: record)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable {
                await appState.refreshDashboard()
            }
        }
        .navigationTitle("收件箱")
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

    private var pendingSummary: some View {
        HStack(spacing: 12) {
            Image(systemName: appState.dashboard.pendingCount == 0 ? "checkmark.circle.fill" : "tray.full.fill")
                .font(.title2)
                .foregroundStyle(appState.dashboard.pendingCount == 0 ? JieziTheme.mint : JieziTheme.gold)
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.dashboard.pendingCount == 0 ? "收件箱已清空" : "\(appState.dashboard.pendingCount) 条待处理")
                    .font(.headline)
                Text("待分类、待确认和识别失败的截图会显示在这里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var filterPicker: some View {
        Picker("状态", selection: $filter) {
            ForEach(InboxFilter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }
}

private enum InboxFilter: String, CaseIterable, Identifiable {
    case all
    case routing
    case review
    case failed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部"
        case .routing: return "待分类"
        case .review: return "待确认"
        case .failed: return "失败"
        }
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

                if let imageURL = record.imageURL {
                    Section("截图原图") {
                        Button {
                            imagePreview = StagingImagePreviewRoute(url: imageURL)
                        } label: {
                            StagingImagePreview(url: imageURL)
                        }
                        .buttonStyle(.plain)
                    }
                } else if record.imageLoadError {
                    Section("截图原图") {
                        unavailableImageView
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
                    ForEach(NativeDataService.archiveDomains) { domain in
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
                    AsyncImage(url: route.url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                                .tint(.white)
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                        case .failure:
                            Label("截图文件不可用", systemImage: "photo.badge.exclamationmark")
                                .foregroundStyle(.white)
                        @unknown default:
                            EmptyView()
                        }
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
        AsyncImage(url: url) { phase in
            switch phase {
            case .empty:
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 180)
            case .success(let image):
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
            case .failure:
                Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            @unknown default:
                EmptyView()
            }
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
