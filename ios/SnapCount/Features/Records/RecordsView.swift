import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @State private var selectedKind: NativeDayRecordKind = .all
    @State private var selectedMonthKey = RecordsView.currentMonthKey
    @State private var showManualRecordSheet = false

    private var query: NativeRecordQuery { NativeRecordQuery(monthKey: selectedMonthKey, kind: selectedKind) }
    private var monthGroups: [NativeDayRecordGroup] { appState.recordGroups(monthKey: selectedMonthKey) }
    private var groups: [NativeDayRecordGroup] { query.groups(from: monthGroups) }
    private var availableKinds: [NativeDayRecordKind] { query.availableKinds(from: monthGroups) }
    private var isLoadingMonth: Bool { appState.loadingRecordMonthKey == selectedMonthKey }
    private var palette: JieziGeneratedPalette { themeManager.palette }

    var body: some View {
        ZStack {
            JieziGradient.pageBackground(palette: palette).ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                    VStack(alignment: .leading, spacing: JieziSpacing.md) {
                        JieziMonthSwitcher(
                            palette: palette,
                            title: monthTitle,
                            selectionToken: selectedMonthKey,
                            canAdvance: selectedMonthKey < Self.currentMonthKey,
                            onPrevious: { shiftMonth(-1) },
                            onNext: { shiftMonth(1) }
                        )
                        ScrollView(.horizontal) {
                            HStack(spacing: JieziSpacing.sm) {
                                ForEach(availableKinds) { kind in
                                    JieziChip(
                                        palette: palette,
                                        title: kind.title,
                                        isSelected: selectedKind == kind,
                                        tint: kind == .all ? palette.brand : domainColor(for: kind.rawValue)
                                    ) {
                                        selectedKind = kind
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    .jieziCard(palette: palette, solid: true)

                    if isLoadingMonth && monthGroups.isEmpty {
                        ProgressView("正在加载本月记录…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, JieziSpacing.xl5)
                    } else if let message = appState.recordMonthMessages[selectedMonthKey],
                              selectedMonthKey != Self.currentMonthKey,
                              monthGroups.isEmpty {
                        ContentUnavailableView {
                            Label("本月记录加载失败", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                        } description: {
                            Text(message)
                        } actions: {
                            Button("重新加载") { Task { await appState.loadRecordMonth(selectedMonthKey, force: true) } }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, JieziSpacing.xl5)
                    } else if groups.isEmpty {
                        JieziEmptyState(
                            palette: palette,
                            systemImage: "doc.text.magnifyingglass",
                            title: "本月还没有记录",
                            message: "截图识别或手动记录后，会按日期出现在这里。"
                        )
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                                dayHeader(group)

                                VStack(spacing: 0) {
                                    ForEach(Array(group.records.enumerated()), id: \.element.id) { index, item in
                                        NavigationLink(value: NativeRecordRoute(reference: item.reference)) {
                                            recordRow(item, showDivider: index < group.records.count - 1)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .background(
                                    palette.paper.opacity(0.82),
                                    in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                                        .stroke(palette.brand.opacity(0.10), lineWidth: 1)
                                }
                                .jieziShadow(JieziShadows.sm(palette))
                            }
                        }
                    }
                }
                .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                .padding(.top, JieziSpacing.sm)
                .padding(.bottom, JieziSpacing.xl5)
            }
            .scrollIndicators(.hidden)
            .refreshable { await appState.loadRecordMonth(selectedMonthKey, force: true) }
        }
        .navigationTitle("记录")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showManualRecordSheet = true
                } label: {
                    Label("新增记录", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: NativeRecordRoute.self) { route in
            RecordDetailView(reference: route.reference)
        }
        .onChange(of: availableKinds) { kinds in if !kinds.contains(selectedKind) { selectedKind = .all } }
        .task(id: prefetchKey) {
            appState.prefetchRecordDetails(groups.flatMap(\.records).map(\.reference))
        }
        .task(id: selectedMonthKey) {
            await appState.loadRecordMonth(selectedMonthKey)
        }
        .sheet(isPresented: $showManualRecordSheet) {
            ManualRecordSheet()
        }
    }

    private var prefetchKey: String { "\(selectedMonthKey):\(selectedKind.rawValue):\(groups.count)" }

    private var monthTitle: String {
        NativeMonthKey.title(selectedMonthKey)
    }

    private func dayHeader(_ group: NativeDayRecordGroup) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: JieziSpacing.sm) {
                dayIdentity(group.dateKey)
                Spacer(minLength: JieziSpacing.sm)
                daySummary(group)
            }
            VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                dayIdentity(group.dateKey)
                daySummary(group)
            }
        }
        .padding(.horizontal, JieziSpacing.xs)
    }

    private func dayIdentity(_ dateKey: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: JieziSpacing.sm) {
            Text(dayTitle(dateKey))
                .font(JieziType.sectionTitle)
                .foregroundStyle(palette.ink)
            Text(weekdayTitle(dateKey))
                .font(JieziFont.footnote)
                .foregroundStyle(palette.muted)
        }
    }

    private func daySummary(_ group: NativeDayRecordGroup) -> some View {
        Text(daySummaryText(group))
            .font(JieziFont.caption)
            .foregroundStyle(palette.muted)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private func recordRow(_ item: NativeDayRecord, showDivider: Bool) -> some View {
        JieziRecordRow(
            palette: palette,
            systemImage: item.systemImage,
            iconTint: domainColor(for: item.domainKey ?? item.kind.rawValue),
            title: item.title,
            subtitle: item.subtitle,
            value: item.value,
            timeLabel: item.timeLabel ?? "全天",
            valueTint: valueColor(for: item.kind),
            showDivider: showDivider
        )
    }

    private func dayTitle(_ dateKey: String) -> String {
        guard let date = Self.dateFormatter.date(from: dateKey) else { return String(dateKey.suffix(5)) }
        return Self.dayFormatter.string(from: date)
    }

    private func weekdayTitle(_ dateKey: String) -> String {
        guard let date = Self.dateFormatter.date(from: dateKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private func daySummaryText(_ group: NativeDayRecordGroup) -> String {
        guard selectedKind == .all,
              let summary = appState.dashboard.dailySummaries.first(where: { $0.dateKey == group.dateKey }) else {
            return "\(group.records.count) 条"
        }
        var parts: [String] = []
        if summary.expense > 0 { parts.append("支出 \(money(summary.expense))") }
        if summary.income > 0 { parts.append("收入 \(money(summary.income))") }
        if parts.isEmpty { parts.append("\(group.records.count) 条") }
        return parts.joined(separator: " · ")
    }

    private func domainColor(for domain: String) -> Color {
        let supported = ["expense", "income", "sport", "sleep", "reading", "food", "wallet"]
        return supported.contains(domain) ? JieziDomainColor.color(for: domain) : palette.brand
    }

    private func valueColor(for kind: NativeDayRecordKind) -> Color {
        switch kind {
        case .expense: return palette.coral
        case .income: return palette.brand
        default: return palette.ink
        }
    }

    private func money(_ value: Double) -> String {
        String(format: "¥%.0f", value)
    }

    private func shiftMonth(_ offset: Int) {
        guard let shifted = NativeMonthKey.shifted(selectedMonthKey, by: offset) else { return }
        selectedMonthKey = shifted
        selectedKind = .all
    }

    private static var currentMonthKey: String { NativeMonthKey.current() }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM月dd日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}

struct RecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @Environment(\.dismiss) private var dismiss
    let reference: String
    @State private var imagePreview: ImagePreviewRoute?
    @State private var editDraft: NativeRecordEditDraft?
    @State private var universalEditDetail: NativeRecordDetail?
    @State private var showDeleteConfirm = false

    private var detail: NativeRecordDetail? {
        appState.recordDetail(matching: reference)
    }
    private var palette: JieziGeneratedPalette { themeManager.palette }

    var body: some View {
        ZStack {
            JieziGradient.pageBackground(palette: palette).ignoresSafeArea()
            if let detail {
                GeometryReader { scrollViewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                            recordHeader(detail)

                            if let imageURL = detail.imageURL {
                                Button {
                                    imagePreview = ImagePreviewRoute(url: imageURL)
                                } label: {
                                    RecordImagePreview(url: imageURL, palette: palette) {
                                        Task { await appState.loadRecordDetail(reference: reference, force: true) }
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("查看原始图片")
                            } else if detail.imageLoadError {
                                unavailableImageView
                            }

                            detailSection(
                                title: "基本信息",
                                rows: NativeRecordDetailPresentationAdapter.basicRows(
                                    for: detail,
                                    accountName: accountName(for: detail)
                                )
                            )

                            detailSection(
                                title: "抽取字段",
                                rows: NativeRecordDetailPresentationAdapter.extractedRows(
                                    for: detail,
                                    domain: appState.dashboard.domains.first { $0.id == detail.domainKey }
                                )
                            )

                            if let binding = NativeRecordDetailPresentationAdapter.accountBinding(
                                for: detail,
                                accounts: appState.accounts
                            ) {
                                accountBindingSection(binding, detail: detail)
                            }

                            let dishes = NativeRecordDetailPresentationAdapter.foodDishes(for: detail)
                            if !dishes.isEmpty {
                                foodDishesSection(dishes)
                            }

                            if let feedback = detail.aiFeedback {
                                NativeAIFeedbackCard(
                                    feedback: feedback,
                                    reviewable: feedback.isReviewable,
                                    reviewState: appState.recordFeedbackState,
                                    exposureState: appState.recordExpressionPlanExposureState,
                                    onRetryExposure: {
                                        appState.setRecordExpressionPlanCardVisible(
                                            true,
                                            reference: reference,
                                            feedbackIdentity: feedback.renderIdentity
                                        )
                                        Task {
                                            await appState.acknowledgeRecordExpressionPlanIfVisible(reference: reference)
                                        }
                                    }
                                ) { choice, text in
                                    Task { await appState.submitRecordFeedback(choice: choice, freeText: text) }
                                }
                                .onNativeAIFeedbackCardVisibilityChange(
                                    in: scrollViewport.frame(in: .global)
                                ) { isVisible in
                                    guard feedback.source == "expression_planner" else { return }
                                    appState.setRecordExpressionPlanCardVisible(
                                        isVisible,
                                        reference: reference,
                                        feedbackIdentity: feedback.renderIdentity
                                    )
                                    if isVisible, feedback.requiresExposureAcknowledgement {
                                        Task {
                                            await appState.acknowledgeRecordExpressionPlanIfVisible(reference: reference)
                                        }
                                    }
                                }
                                .id(feedback.renderIdentity)
                            }

                            if let companionMessage = detail.companionMessage, !companionMessage.isEmpty {
                                aiContextSection(
                                    summary: NativeRecordDetailPresentationAdapter.aiSummary(for: detail),
                                    companionMessage: companionMessage
                                )
                            } else {
                                aiContextSection(
                                    summary: NativeRecordDetailPresentationAdapter.aiSummary(for: detail),
                                    companionMessage: nil
                                )
                            }
                            actionSection(detail)
                        }
                        .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                        .padding(.top, JieziSpacing.sm)
                        .padding(.bottom, JieziSpacing.xl5)
                    }
                    .scrollIndicators(.hidden)
                }
            } else if let message = appState.recordDetailMessage {
                ContentUnavailableView(
                    "无法读取记录",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
            } else {
                ProgressView("正在读取记录")
            }
        }
        .navigationTitle("记录详情")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .task(id: reference) {
            await appState.loadRecordDetail(reference: reference)
        }
        .onDisappear {
            appState.deactivateRecordDetail(reference: reference)
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
                        Button {
                            imagePreview = nil
                            Task { await appState.loadRecordDetail(reference: reference, force: true) }
                        } label: {
                            Label("截图加载失败，点此重试", systemImage: "arrow.clockwise")
                                .foregroundStyle(.white)
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
        .sheet(item: $editDraft) { draft in
            RecordEditSheet(draft: draft) { savedDraft in
                await appState.saveRecordDetail(savedDraft)
            }
        }
        .sheet(item: $universalEditDetail) { detail in
            ManualRecordSheet(editing: detail)
        }
        .confirmationDialog("删除这条记录？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await appState.deleteRecord(reference: reference) {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后会同步处理关联账户流水，截图文件是否清理仍沿用现有服务端规则。")
        }
    }

    private var unavailableImageView: some View {
        Button {
            Task { await appState.loadRecordDetail(reference: reference, force: true) }
        } label: {
            Label("截图文件不可用，点此重新加载", systemImage: "arrow.clockwise")
                .font(JieziFont.subheadline.weight(.semibold))
                .foregroundStyle(palette.brand)
                .frame(maxWidth: .infinity, minHeight: 112)
                .jieziCard(palette: palette, solid: true)
        }
        .buttonStyle(.plain)
    }

    private func recordHeader(_ detail: NativeRecordDetail) -> some View {
        let tint = domainColor(for: detail.domainKey ?? detail.kind)
        return VStack(alignment: .leading, spacing: JieziSpacing.md) {
            HStack(spacing: JieziSpacing.sm) {
                Image(systemName: detail.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: JieziIcon.xl3, height: JieziIcon.xl3)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous))
                Text(NativeRecordDetailPresentationAdapter.domainLabel(for: detail))
                    .font(JieziType.chip)
                    .foregroundStyle(tint)
                    .padding(.horizontal, JieziSpacing.sm)
                    .padding(.vertical, JieziSpacing.xs)
                    .background(tint.opacity(0.09), in: Capsule())
                Spacer(minLength: JieziSpacing.sm)
                if detail.status == "pending" {
                    Text("待补充")
                        .font(JieziType.chip)
                        .foregroundStyle(palette.light)
                }
            }

            Text(detail.title)
                .font(JieziType.sectionTitle)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)

            if !detail.value.isEmpty {
                Text(detail.value)
                    .font(detail.kind == "expense" || detail.kind == "income" ? JieziType.moneyHero : JieziType.moneyCard)
                    .monospacedDigit()
                    .foregroundStyle(valueColor(for: detail.kind))
                    .minimumScaleFactor(0.68)
            }

            Text(detail.subtitle)
                .font(JieziFont.footnote)
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .jieziCard(palette: palette, solid: true)
    }

    private func detailSection(title: String, rows: [NativeDetailRow]) -> some View {
        JieziDetailCard(
            palette: palette,
            title: title,
            systemImage: title == "基本信息" ? "info.circle" : "text.badge.checkmark"
        ) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                JieziDetailRow(
                    palette: palette,
                    label: row.label,
                    value: row.value,
                    showDivider: index < rows.count - 1
                )
            }
        }
    }

    private func foodDishesSection(_ dishes: [NativeFoodDish]) -> some View {
        JieziDetailCard(
            palette: palette,
            title: "菜品明细",
            systemImage: "fork.knife",
            tint: JieziDomainColor.food
        ) {
            ForEach(Array(dishes.enumerated()), id: \.element.id) { index, dish in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(dish.name)
                            .font(JieziFont.subheadline.weight(.semibold))
                            .foregroundStyle(palette.ink)
                        Spacer()
                        if let calories = dish.calories {
                            Text("\(Int(calories.rounded())) kcal")
                                .font(JieziFont.caption.monospacedDigit())
                                .foregroundStyle(JieziDomainColor.food)
                        }
                    }
                    HStack(spacing: 12) {
                        if let estimatedGrams = dish.estimatedGrams { Text("约 \(estimatedGrams, specifier: "%.0f")g") }
                        if let protein = dish.protein { Text("蛋白 \(protein, specifier: "%.1f")g") }
                        if let carbs = dish.carbs { Text("碳水 \(carbs, specifier: "%.1f")g") }
                        if let fat = dish.fat { Text("脂肪 \(fat, specifier: "%.1f")g") }
                    }
                    .font(JieziFont.caption)
                    .foregroundStyle(palette.muted)
                }
                .padding(.vertical, JieziSpacing.md)
                .overlay(alignment: .bottom) {
                    if index < dishes.count - 1 {
                        let stroke = JieziStroke.divider(palette)
                        Rectangle().fill(stroke.color).frame(height: stroke.width)
                    }
                }
            }
        }
    }

    private func accountBindingSection(
        _ binding: NativeRecordAccountBindingPresentation,
        detail: NativeRecordDetail
    ) -> some View {
        let tint = accountBindingColor(binding.status)
        return JieziDetailCard(
            palette: palette,
            title: "账户影响",
            systemImage: accountBindingIcon(binding.status),
            tint: tint
        ) {
            HStack(alignment: .top, spacing: JieziSpacing.md) {
                VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                    Text(binding.title)
                        .font(JieziFont.subheadline.weight(.semibold))
                        .foregroundStyle(palette.ink)
                    Text(binding.reason)
                        .font(JieziFont.caption)
                        .foregroundStyle(palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: JieziSpacing.sm)
                if let account = binding.recommendedAccount {
                    Button {
                        Task {
                            var draft = NativeRecordEditDraft(detail: detail)
                            draft.accountId = account.id
                            _ = await appState.saveRecordDetail(draft)
                        }
                    } label: {
                        Label("绑定", systemImage: "link")
                    }
                    .buttonStyle(.bordered)
                    .tint(tint)
                    .disabled(appState.isSavingRecordDetail)
                }
            }
        }
    }

    private func accountBindingIcon(_ status: NativeRecordAccountBindingStatus) -> String {
        switch status {
        case .bound: return "checkmark.circle.fill"
        case .recommended: return "sparkles"
        case .unbound: return "link.badge.plus"
        }
    }

    private func accountBindingColor(_ status: NativeRecordAccountBindingStatus) -> Color {
        switch status {
        case .bound: return palette.brand
        case .recommended: return palette.light
        case .unbound: return palette.coral
        }
    }

    private func aiContextSection(summary: String, companionMessage: String?) -> some View {
        JieziDetailCard(
            palette: palette,
            title: "AI 记录",
            systemImage: "sparkles",
            tint: palette.light,
            solid: false
        ) {
            if let companionMessage, !companionMessage.isEmpty {
                VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                    Text("陪伴")
                        .font(JieziFont.caption.weight(.semibold))
                        .foregroundStyle(palette.muted)
                    Text(companionMessage)
                        .font(JieziFont.subheadline)
                        .foregroundStyle(palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, JieziSpacing.md)

                let stroke = JieziStroke.divider(palette)
                Rectangle().fill(stroke.color).frame(height: stroke.width)
            }

            VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                Text("识别摘要")
                    .font(JieziFont.caption.weight(.semibold))
                    .foregroundStyle(palette.muted)
                Text(summary)
                    .font(JieziFont.subheadline)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, JieziSpacing.md)
        }
    }

    @ViewBuilder
    private func actionSection(_ detail: NativeRecordDetail) -> some View {
        if detail.isEditable || detail.isDeletable {
            HStack(spacing: JieziSpacing.md) {
                if detail.isEditable {
                    JieziPrimaryButton(
                        title: detail.status == "pending" ? "补充信息" : "编辑记录",
                        systemImage: "square.and.pencil",
                        palette: palette
                    ) {
                        if detail.kind == "data" { universalEditDetail = detail }
                        else { editDraft = NativeRecordEditDraft(detail: detail) }
                    }
                    .disabled(appState.isSavingRecordDetail)
                }
                if detail.isDeletable {
                    JieziDangerButton(
                        title: "删除",
                        systemImage: "trash",
                        palette: palette
                    ) {
                        showDeleteConfirm = true
                    }
                    .disabled(appState.isDeletingRecordDetail)
                }
            }
        }
    }

    private func domainColor(for domain: String) -> Color {
        let supported = ["expense", "income", "sport", "sleep", "reading", "food", "wallet"]
        return supported.contains(domain) ? JieziDomainColor.color(for: domain) : palette.brand
    }

    private func valueColor(for kind: String) -> Color {
        switch kind {
        case "expense": return palette.coral
        case "income": return palette.brand
        default: return domainColor(for: kind)
        }
    }

    private func accountName(for detail: NativeRecordDetail) -> String? {
        guard let accountId = detail.accountId else { return nil }
        return appState.accounts.first(where: { $0.id == accountId })?.title ?? accountId
    }
}

private struct RecordImagePreview: View {
    let url: URL
    let palette: JieziGeneratedPalette
    let onRetry: () -> Void

    var body: some View {
        CachedRemoteImage(url: url) { image in
            image
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .background(palette.paper.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: JieziRadius.lg, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: JieziRadius.lg, style: .continuous)
                        .stroke(palette.brand.opacity(0.10), lineWidth: 1)
                }
        } placeholder: {
            ProgressView()
                .tint(palette.brand)
                .frame(maxWidth: .infinity, minHeight: 220)
                .background(palette.paper.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: JieziRadius.lg, style: .continuous))
        } failure: {
            Button(action: onRetry) {
                Label("截图加载失败，点此重试", systemImage: "arrow.clockwise")
                    .font(JieziFont.footnote)
                    .foregroundStyle(palette.brand)
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RecordEditSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeRecordEditDraft
    @State private var message: String?
    @State private var isSaving = false
    let onSave: (NativeRecordEditDraft) async -> Bool

    init(draft: NativeRecordEditDraft, onSave: @escaping (NativeRecordEditDraft) async -> Bool) {
        _draft = State(initialValue: draft)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            ZStack {
                JieziPageBackground()
                VStack(spacing: 0) {
                    JieziFormTopBar(
                        title: "编辑记录",
                        primaryTitle: "保存",
                        isWorking: isSaving,
                        onCancel: { dismiss() },
                        onSubmit: { Task { await save() } }
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                            primarySection
                            classificationSection
                            accountSection
                            noteSection

                            if let message {
                                JieziFormMessage(message: message)
                            }
                        }
                        .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                        .padding(.top, JieziSpacing.Semantic.card_padding)
                        .padding(.bottom, JieziSpacing.xl3)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if appState.accounts.isEmpty { await appState.loadAccounts() }
            }
        }
    }

    private var primarySection: some View {
        JieziFormSection(
            title: draft.kind == "income" ? "收入信息" : "消费信息",
            subtitle: "只修改需要纠正的字段，保存后会同步刷新详情和统计。"
        ) {
            JieziFormRow(
                title: draft.kind == "income" ? "来源" : "商户",
                systemImage: draft.kind == "income" ? "arrow.down.circle" : "storefront",
                showsDivider: true
            ) {
                TextField(draft.kind == "income" ? "收入来源" : "商户名称", text: $draft.title)
                    .jieziInputSurface()
            }
            JieziFormRow(title: "金额", systemImage: "yensign", showsDivider: true) {
                TextField("0.00", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                    .jieziInputSurface()
            }
            JieziFormRow(title: "日期", systemImage: "calendar") {
                TextField("YYYY-MM-DD", text: $draft.recordDate)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .jieziInputSurface()
            }
        }
    }

    @ViewBuilder
    private var classificationSection: some View {
        if draft.kind == "expense" {
            JieziFormSection(title: "消费字段", subtitle: "这些字段决定渠道、分类与支付统计。") {
                JieziFormRow(title: "平台", systemImage: "shippingbox", showsDivider: true) {
                    TextField("消费平台", text: $draft.platform)
                        .jieziInputSurface()
                }
                JieziFormRow(title: "分类", systemImage: "square.grid.2x2", showsDivider: true) {
                    TextField("消费分类", text: $draft.category)
                        .jieziInputSurface()
                }
                JieziFormRow(title: "支付方式", systemImage: "creditcard") {
                    TextField("支付方式", text: $draft.paymentMethod)
                        .jieziInputSurface()
                }
            }
        } else {
            JieziFormSection(title: "收入字段") {
                JieziFormRow(title: "收入类型", systemImage: "tag") {
                    TextField("收入类型", text: $draft.category)
                        .jieziInputSurface()
                }
            }
        }
    }

    private var accountSection: some View {
        JieziFormSection(
            title: "账户",
            subtitle: "保存后由服务端原子更新记录与账户流水，不会在客户端直接修改余额。"
        ) {
            JieziFormRow(title: "绑定账户", systemImage: "wallet.pass") {
                Menu {
                    Button("不绑定账户") { draft.accountId = nil }
                    ForEach(accountCandidates) { account in
                        Button(account.title) { draft.accountId = account.id }
                    }
                } label: {
                    selectorLabel(selectedAccountTitle)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noteSection: some View {
        JieziFormSection(title: "备注", subtitle: "选填，仅用于补充这条记录的背景。") {
            JieziFormRow(title: "补充说明", systemImage: "note.text") {
                TextField("写下一句补充说明", text: $draft.note, axis: .vertical)
                    .lineLimit(3...6)
                    .jieziInputSurface()
            }
        }
    }

    private var accountCandidates: [NativeAccount] {
        appState.accounts.filter { !$0.isArchived || $0.id == draft.accountId }
    }

    private var selectedAccountTitle: String {
        guard let accountId = draft.accountId else { return "不绑定账户" }
        return accountCandidates.first(where: { $0.id == accountId })?.title ?? "不绑定账户"
    }

    private func selectorLabel(_ title: String) -> some View {
        HStack(spacing: JieziSpacing.sm) {
            Text(title)
                .foregroundStyle(JieziTheme.ink)
                .lineLimit(1)
            Spacer(minLength: JieziSpacing.sm)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        }
        .jieziInputSurface()
    }

    private func save() async {
        isSaving = true
        message = nil
        let ok = await onSave(draft)
        isSaving = false
        if ok {
            dismiss()
        } else {
            message = "保存失败，请检查字段或稍后重试。"
        }
    }
}

private struct ImagePreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
