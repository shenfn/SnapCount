import SwiftUI

struct HistoryMigrationView: View {
    @EnvironmentObject private var appState: AppState
    @State private var exportedFile: NativeExportedFile?
    @State private var detailItem: HistoryMigrationDiagnosticItem?
    @State private var isRefreshing = false
    @State private var feedbackMessage: String?

    private var package: HistoryMigrationDiagnosticPackage {
        HistoryMigrationExportBuilder.package(from: appState.dashboard)
    }

    private var groupedItems: [(HistoryMigrationIssueCategory, [HistoryMigrationDiagnosticItem])] {
        Dictionary(grouping: package.items, by: \.category)
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { ($0.key, $0.value) }
    }

    var body: some View {
        ZStack {
            JieziPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                    header
                    summaryCard
                    actionCard
                    exportCard
                    reviewGroups
                    if let feedbackMessage {
                        Text(feedbackMessage)
                            .font(JieziFont.footnote)
                            .foregroundStyle(JieziTheme.muted)
                            .padding(.horizontal, JieziSpacing.xs)
                    }
                }
                .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                .padding(.top, JieziSpacing.lg)
                .padding(.bottom, JieziSpacing.xl4)
            }
        }
        .navigationTitle("历史数据迁移")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await refresh()
        }
        .sheet(item: $exportedFile) { file in
            ActivityView(activityItems: [file.url])
        }
        .sheet(item: $detailItem) { item in
            NavigationStack {
                HistoryMigrationDetailView(item: item)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.sm) {
            Text("先把问题导出来")
                .font(JieziType.display)
                .foregroundStyle(JieziTheme.ink)
            Text("查看当前已读取的历史记录和待核对材料，导出一份文档交给 AI 做整体分析。")
                .font(JieziFont.body)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryCard: some View {
        JieziCard {
            VStack(alignment: .leading, spacing: JieziSpacing.lg) {
                JieziSectionHeader(
                    title: "当前读取摘要",
                    subtitle: "仅展示现有数据链路已经读取到的范围"
                )
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: JieziSpacing.xl2
                ) {
                    JieziMetric(label: "当前已读取正式记录", value: "\(package.summary.readableRecords)")
                    JieziMetric(label: "待补全账单", value: "\(package.summary.pendingExpenses)", valueTint: JieziTheme.coral)
                    JieziMetric(label: "当前已读取待核对", value: "\(package.summary.pendingReview)", valueTint: JieziTheme.gold)
                    JieziMetric(label: "已缓存图片", value: "\(package.summary.cachedImages)", valueTint: JieziTheme.mint)
                    JieziMetric(label: "缺失图片", value: "\(package.summary.missingImages)", valueTint: JieziTheme.coral)
                    JieziMetric(label: "读取警告", value: "\(package.summary.loadWarnings)", valueTint: package.summary.loadWarnings == 0 ? JieziTheme.mint : JieziTheme.coral)
                }
            }
        }
    }

    private var actionCard: some View {
        JieziDetailCard(title: "读取与处理", systemImage: "arrow.triangle.2.circlepath", tint: JieziTheme.brand) {
            JieziDetailRow(
                label: "预检",
                value: "重新读取当前数据并更新摘要，不修改本机数据。",
                showDivider: true
            )
            HStack(spacing: JieziSpacing.md) {
                Button {
                    Task { await refresh() }
                } label: {
                    Label(isRefreshing ? "正在读取" : "预检并刷新", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(JieziTheme.brand)
                .disabled(isRefreshing)

                Button {
                    appState.selectedTab = .inbox
                } label: {
                    Label("去待处理", systemImage: "tray")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, JieziSpacing.sm)
        }
    }

    private var exportCard: some View {
        JieziDetailCard(title: "导出给 AI 的诊断包", systemImage: "square.and.arrow.up", tint: JieziTheme.mint) {
            JieziDetailRow(
                label: "推荐格式",
                value: "Markdown 适合直接阅读；JSON 适合结构化分析。默认不包含图片二进制。",
                showDivider: true
            )
            HStack(spacing: JieziSpacing.md) {
                Button {
                    export(.markdown)
                } label: {
                    Label("导出 Markdown", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(JieziTheme.mint)

                Button {
                    export(.json)
                } label: {
                    Label("导出 JSON", systemImage: "curlybraces")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, JieziSpacing.sm)
        }
    }

    private var reviewGroups: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            JieziSectionHeader(title: "待核对材料", subtitle: "点击记录查看原始字段")
            if groupedItems.isEmpty {
                JieziCard(solid: true) {
                    Label("当前没有已读取的待核对材料", systemImage: "checkmark.circle")
                        .font(JieziFont.subheadline.weight(.semibold))
                        .foregroundStyle(JieziTheme.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(JieziSpacing.lg)
                }
            } else {
                ForEach(groupedItems, id: \.0) { category, items in
                    VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                        HStack {
                            Text(category.rawValue)
                                .font(JieziType.cardTitle)
                                .foregroundStyle(JieziTheme.ink)
                            Spacer()
                            Text("\(items.count) 条")
                                .font(JieziFont.caption.monospacedDigit())
                                .foregroundStyle(JieziTheme.muted)
                        }

                        JieziCard(solid: true) {
                            VStack(spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                    JieziListRow(
                                        systemImage: icon(for: category),
                                        iconTint: tint(for: category),
                                        title: item.title,
                                        subtitle: "\(item.businessDate) · \(item.imageStatus) · \(item.status)",
                                        trailingText: item.uploadDate,
                                        trailingSubtitle: "上传/创建",
                                        showsChevron: true,
                                        showDivider: index < items.count - 1
                                    ) {
                                        detailItem = item
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await appState.refreshDashboard()
        feedbackMessage = "预检完成：当前本机数据未修改。"
    }

    private func export(_ format: HistoryMigrationExportFormat) {
        do {
            exportedFile = try HistoryMigrationExportBuilder.write(format: format, snapshot: appState.dashboard)
            feedbackMessage = "文件已生成，可以直接分享给 AI。"
        } catch {
            feedbackMessage = "导出失败：\(error.localizedDescription)"
        }
    }

    private func icon(for category: HistoryMigrationIssueCategory) -> String {
        switch category {
        case .missingDate: return "calendar.badge.exclamationmark"
        case .uncertainType: return "questionmark.folder"
        case .unknownStatus: return "questionmark.circle"
        case .missingRelation: return "link.badge.plus"
        case .compatibility: return "arrow.triangle.2.circlepath"
        case .pendingCompletion: return "creditcard"
        case .recognitionFailed: return "exclamationmark.triangle"
        }
    }

    private func tint(for category: HistoryMigrationIssueCategory) -> Color {
        switch category {
        case .missingDate, .unknownStatus, .recognitionFailed: return JieziTheme.coral
        case .compatibility, .missingRelation: return JieziTheme.gold
        case .uncertainType, .pendingCompletion: return JieziTheme.brand
        }
    }
}

private struct HistoryMigrationDetailView: View {
    let item: HistoryMigrationDiagnosticItem
    @State private var showRaw = false

    private var rawText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(item.raw),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                    JieziDetailCard(title: item.title, systemImage: "doc.text.magnifyingglass") {
                        JieziDetailRow(label: "问题类别", value: item.category.rawValue, valueTint: JieziTheme.coral, showDivider: true)
                        JieziDetailRow(label: "记录摘要", value: item.summary, showDivider: true)
                        JieziDetailRow(label: "上传/创建时间", value: item.uploadDate, showDivider: true)
                        JieziDetailRow(label: "有效业务日期", value: item.businessDate, showDivider: true)
                        JieziDetailRow(label: "图片状态", value: item.imageStatus, valueTint: item.imageStatus == "已缓存" ? JieziTheme.mint : JieziTheme.coral, showDivider: true)
                        JieziDetailRow(label: "当前状态", value: item.status)
                    }

                    JieziCard(solid: true) {
                        Button {
                            withAnimation(JieziEasing.standard) { showRaw.toggle() }
                        } label: {
                            HStack {
                                Label("查看原始数据", systemImage: showRaw ? "chevron.down" : "chevron.right")
                                Spacer()
                                Text("只读")
                                    .font(JieziFont.caption)
                                    .foregroundStyle(JieziTheme.muted)
                            }
                            .font(JieziFont.subheadline.weight(.semibold))
                            .foregroundStyle(JieziTheme.ink)
                            .padding(JieziSpacing.lg)
                        }
                        .buttonStyle(.plain)

                        if showRaw {
                            ScrollView(.horizontal, showsIndicators: false) {
                                Text(rawText)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(JieziTheme.ink)
                                    .textSelection(.enabled)
                                    .padding(.horizontal, JieziSpacing.lg)
                                    .padding(.bottom, JieziSpacing.lg)
                            }
                        }
                    }
                }
                .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                .padding(.top, JieziSpacing.lg)
                .padding(.bottom, JieziSpacing.xl4)
            }
        }
        .navigationTitle("待核对详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}
