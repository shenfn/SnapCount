import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @State private var scope: NativeInboxScope = .today
    @State private var filter: NativeInboxFilter = .all
    @State private var columnCount = 2
    @State private var stageItemId: String?

    private var allItems: [NativeInboxItem] {
        NativeInboxPresentation.items(
            pendingExpenses: appState.dashboard.pendingExpenses,
            stagingRecords: appState.dashboard.stagingRecords
        )
    }

    private var visibleItems: [NativeInboxItem] {
        NativeInboxPresentation.filtered(
            allItems,
            scope: scope,
            filter: filter,
            today: Self.dateKey(daysFromToday: 0)
        )
    }

    private var filterCounts: [NativeInboxFilter: Int] {
        NativeInboxPresentation.counts(
            allItems,
            scope: scope,
            today: Self.dateKey(daysFromToday: 0)
        )
    }

    private var visibleFilters: [NativeInboxFilter] {
        NativeInboxFilter.allCases.filter { option in
            option == .all || option == filter || (filterCounts[option] ?? 0) > 0
        }
    }

    private var sections: [NativeInboxSection] {
        NativeInboxPresentation.sections(
            from: visibleItems,
            today: Self.dateKey(daysFromToday: 0),
            yesterday: Self.dateKey(daysFromToday: -1)
        )
    }

    private var archiveDomains: [NativeArchiveDomain] {
        let domains = appState.dashboard.domains.map {
            NativeArchiveDomain(id: $0.id, title: $0.shortName, systemImage: $0.systemImage)
        }
        return domains.isEmpty ? InboxArchiveDomains.all : domains
    }

    private var stagePresented: Binding<Bool> {
        Binding(
            get: { stageItemId != nil },
            set: { if !$0 { stageItemId = nil } }
        )
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    pendingSummary

                    if let message = appState.inboxFinanceMessage {
                        messageBanner(message, isError: false, isWorking: false)
                    }

                    if let message = appState.inboxActionMessage {
                        messageBanner(
                            message,
                            isError: appState.inboxActionMessageIsError,
                            isWorking: appState.inboxActionRecordId != nil
                        )
                    }

                    if allItems.isEmpty {
                        InboxSettledEmptyView()
                    } else {
                        scopeControl
                        workspaceHeading
                        filterBar
                        if visibleItems.isEmpty {
                            filteredEmptyState
                        } else {
                            workspaceSections
                        }
                    }
                }
                .padding(.bottom, 84)
            }
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadInboxRepaymentCandidates()
            }
        }
        .navigationTitle("收件箱")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: NativeInboxRoute.self) { route in
            switch route {
            case .category(let filter):
                InboxCategoryView(filter: filter)
            case .staging(let recordId):
                if let record = appState.dashboard.stagingRecords.first(where: { $0.id == recordId }) {
                    StagingRecordDetailView(record: record)
                } else {
                    ContentUnavailableView(
                        "记录不在中转站",
                        systemImage: "checkmark.circle",
                        description: Text("它可能已经归档、销毁，或下拉刷新后状态发生了变化。")
                    )
                }
            case .record(let reference):
                PendingExpenseResolutionView(reference: reference)
            }
        }
        .toolbar {
            if !visibleItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(JieziEasing.standard) {
                            columnCount = columnCount == 2 ? 1 : 2
                        }
                    } label: {
                        Image(systemName: columnCount == 2 ? "rectangle.grid.2x2" : "rectangle")
                    }
                    .accessibilityLabel(columnCount == 2 ? "切换为单列" : "切换为双列")
                }
            }
        }
        .fullScreenCover(isPresented: stagePresented) {
            InboxVerdictStageView(
                items: visibleItems,
                selection: $stageItemId,
                domains: archiveDomains
            )
            .environmentObject(appState)
        }
        .onChange(of: scope) { _, _ in
            if (filterCounts[filter] ?? 0) == 0 { filter = .all }
        }
        .task { await appState.loadInboxRepaymentCandidates() }
    }

    private var pendingSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(allItems.isEmpty ? "微尘皆已落定" : "先整理，再连续翻阅")
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
                if !allItems.isEmpty {
                    Text("\(allItems.count) 条待处理记录")
                        .font(.subheadline)
                        .foregroundStyle(JieziTheme.muted)
                }
            }
            Spacer()
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.top, JieziSpacing.sm)
        .padding(.bottom, JieziSpacing.md)
    }

    private var scopeControl: some View {
        Picker("记录范围", selection: $scope) {
            ForEach(NativeInboxScope.allCases) { option in
                Text(option.title).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.bottom, JieziSpacing.lg)
    }

    private var workspaceHeading: some View {
        HStack(alignment: .bottom, spacing: JieziSpacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(scope == .today ? "今天发生的记录" : "全部待处理记录")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
                Text("待处理底片")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
            }
            Spacer()
            Text("\(filterCounts[.all] ?? 0) 条")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(JieziTheme.muted)
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.bottom, JieziSpacing.sm)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JieziSpacing.sm) {
                ForEach(visibleFilters) { option in
                    Button {
                        withAnimation(JieziEasing.standard) { filter = option }
                    } label: {
                        HStack(spacing: 5) {
                            Text(option.title)
                            Text("\(filterCounts[option] ?? 0)")
                                .monospacedDigit()
                                .opacity(0.72)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == option ? .white : JieziTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(
                            filter == option ? InboxVisualStyle.color(for: option) : Color.white.opacity(0.56),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(InboxVisualStyle.color(for: option).opacity(filter == option ? 0 : 0.16))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, JieziSpacing.xl2)
            .padding(.bottom, JieziSpacing.lg)
        }
    }

    private var workspaceSections: some View {
        ForEach(sections) { section in
            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                Text(section.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JieziTheme.muted)
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(minimum: 0), spacing: JieziSpacing.lg, alignment: .top),
                        count: columnCount
                    ),
                    spacing: JieziSpacing.xl2
                ) {
                    ForEach(section.items) { item in
                        Button {
                            stageItemId = item.id
                        } label: {
                            NativeInboxFilmCard(
                                item: item,
                                repaymentCandidate: item.stagingRecord.flatMap { appState.repaymentCandidates[$0.id] },
                                isSingleColumn: columnCount == 1
                            )
                        }
                        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.985))
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, JieziSpacing.Semantic.card_padding)
            .padding(.bottom, JieziSpacing.xl2)
        }
    }

    private var filteredEmptyState: some View {
        ContentUnavailableView(
            scope == .today ? "今天没有这类记录" : "这类记录已经处理完了",
            systemImage: "checkmark.circle",
            description: Text(scope == .today ? "切换到“全部”可以查看更早的待处理记录。" : "换一个状态看看。")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 56)
    }

    private static func dateKey(daysFromToday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let date = calendar.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return NativeLocalDate.dateKey(date)
    }

    private func messageBanner(_ message: String, isError: Bool, isWorking: Bool) -> some View {
        Label(
            message,
            systemImage: isWorking ? "hourglass" : (isError ? "exclamationmark.circle" : "checkmark.circle")
        )
        .font(.footnote.weight(.medium))
        .foregroundStyle(isError ? JieziTheme.coral : JieziTheme.brand)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isError ? JieziTheme.coral : JieziTheme.brand).opacity(0.08),
            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
        )
        .padding(.horizontal, JieziSpacing.Semantic.card_padding)
        .padding(.bottom, JieziSpacing.md)
    }

}

private struct NativeInboxCategoryCard: View {
    let category: NativeInboxCategory

    private var tint: Color {
        InboxVisualStyle.color(for: category.filter)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InboxAlbumPreview(
                items: Array(category.items.prefix(3)),
                tint: tint
            )
            .frame(height: 148)

            HStack(alignment: .top, spacing: JieziSpacing.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: category.systemImage)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                        Text(category.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JieziTheme.ink)
                            .lineLimit(1)
                    }
                    Text("\(category.count) 条 · \(category.subtitle)")
                        .font(.caption2)
                        .foregroundStyle(JieziTheme.muted)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JieziTheme.muted)
                    .padding(.top, 3)
            }
            .padding(12)
        }
        .frame(width: 232, alignment: .leading)
        .background(Color.white.opacity(0.76), in: RoundedRectangle(cornerRadius: JieziRadius.lg, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.lg, style: .continuous)
                .stroke(tint.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: JieziTheme.space.opacity(0.08), radius: 12, x: 0, y: 6)
    }
}

private struct InboxAlbumPreview: View {
    let items: [NativeInboxItem]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            if items.count <= 1, let item = items.first {
                InboxThumbnail(item: item, tint: tint)
            } else {
                HStack(spacing: 2) {
                    if let first = items.first {
                        InboxThumbnail(item: first, tint: tint)
                            .frame(width: proxy.size.width * 0.58)
                    }

                    VStack(spacing: 2) {
                        if items.count > 1 {
                            InboxThumbnail(item: items[1], tint: tint)
                        }
                        if items.count > 2 {
                            InboxThumbnail(item: items[2], tint: tint)
                        } else {
                            Rectangle()
                                .fill(tint.opacity(0.08))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .clipped()
        .background(tint.opacity(0.08))
    }
}

private struct InboxThumbnail: View {
    let item: NativeInboxItem
    let tint: Color

    private var imageURL: URL? {
        item.stagingRecord?.imageURL ?? item.pendingExpense?.imageURL
    }

    var body: some View {
        Group {
            if let imageURL {
                CachedRemoteImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    InboxThumbnailFallback(item: item, tint: tint, isLoading: true)
                } failure: {
                    InboxThumbnailFallback(item: item, tint: tint, isLoading: false)
                }
            } else {
                InboxThumbnailFallback(item: item, tint: tint, isLoading: false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }
}

private struct InboxThumbnailFallback: View {
    let item: NativeInboxItem
    let tint: Color
    let isLoading: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [tint.opacity(0.18), JieziTheme.paper.opacity(0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            if isLoading {
                ProgressView().tint(tint)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: item.systemImage)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(tint)
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.ink)
                        .lineLimit(2)
                    Text(item.subtitle)
                        .font(.caption2)
                        .foregroundStyle(JieziTheme.muted)
                        .lineLimit(2)
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }
}

private struct InboxCategoryView: View {
    @EnvironmentObject private var appState: AppState

    let filter: NativeInboxFilter

    @State private var columnCount = 2
    @State private var stageRecordId: String?

    private var allItems: [NativeInboxItem] {
        NativeInboxPresentation.items(
            pendingExpenses: appState.dashboard.pendingExpenses,
            stagingRecords: appState.dashboard.stagingRecords
        )
    }

    private var items: [NativeInboxItem] {
        NativeInboxPresentation.filtered(allItems, by: filter)
    }

    private var sections: [NativeInboxSection] {
        NativeInboxPresentation.sections(
            from: items,
            today: Self.dateKey(daysFromToday: 0),
            yesterday: Self.dateKey(daysFromToday: -1)
        )
    }

    private var stageRecords: [NativeStagingRecord] {
        items.compactMap(\.stagingRecord)
    }

    private var archiveDomains: [NativeArchiveDomain] {
        let domains = appState.dashboard.domains.map {
            NativeArchiveDomain(id: $0.id, title: $0.shortName, systemImage: $0.systemImage)
        }
        return domains.isEmpty ? InboxArchiveDomains.all : domains
    }

    private var stagePresented: Binding<Bool> {
        Binding(
            get: { stageRecordId != nil },
            set: { if !$0 { stageRecordId = nil } }
        )
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    categoryHeader

                    if sections.isEmpty {
                        ContentUnavailableView(
                            "这里已经处理完了",
                            systemImage: "checkmark.circle",
                            description: Text("返回中转站，看看其他分类。")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 72)
                    } else {
                        ForEach(sections) { section in
                            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(JieziTheme.muted)

                                inboxGrid(section.items)
                            }
                            .padding(.horizontal, JieziSpacing.Semantic.card_padding)
                            .padding(.bottom, JieziSpacing.xl2)
                        }
                    }
                }
                .padding(.bottom, 84)
            }
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadInboxRepaymentCandidates()
            }
        }
        .navigationTitle(filter.galleryTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(JieziEasing.standard) {
                        columnCount = columnCount == 2 ? 1 : 2
                    }
                } label: {
                    Image(systemName: columnCount == 2 ? "rectangle.grid.2x2" : "rectangle")
                }
                .accessibilityLabel(columnCount == 2 ? "切换为单列" : "切换为双列")
            }
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onEnded { scale in
                    guard abs(scale - 1) > 0.08 else { return }
                    withAnimation(JieziEasing.standard) {
                        if scale > 1.08 {
                            columnCount = 1
                        } else if scale < 0.92 {
                            columnCount = 2
                        }
                    }
                }
        )
        .fullScreenCover(isPresented: stagePresented) {
            StagingVerdictStageView(
                records: stageRecords,
                selection: $stageRecordId,
                domains: archiveDomains
            )
            .environmentObject(appState)
        }
        .task { await appState.loadInboxRepaymentCandidates() }
    }

    private var categoryHeader: some View {
        HStack(alignment: .top, spacing: JieziSpacing.md) {
            VStack(alignment: .leading, spacing: 5) {
                Text(filter.galleryTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
                Text(filter.gallerySubtitle)
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text("\(items.count)")
                    .font(JieziType.moneyCard.monospacedDigit())
                    .foregroundStyle(InboxVisualStyle.color(for: filter))
                Text("条")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            }
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.top, JieziSpacing.md)
        .padding(.bottom, JieziSpacing.lg)
    }

    private func inboxGrid(_ sectionItems: [NativeInboxItem]) -> some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(minimum: 0), spacing: JieziSpacing.lg, alignment: .top),
                count: columnCount
            ),
            spacing: JieziSpacing.xl2
        ) {
            ForEach(sectionItems) { item in
                inboxCell(item)
            }
        }
    }

    @ViewBuilder
    private func inboxCell(_ item: NativeInboxItem) -> some View {
        if let pending = item.pendingExpense {
            NavigationLink(value: NativeInboxRoute.record(reference: pending.reference)) {
                NativeInboxFilmCard(
                    item: item,
                    repaymentCandidate: nil,
                    isSingleColumn: columnCount == 1
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        } else if let record = item.stagingRecord {
            Button {
                stageRecordId = record.id
            } label: {
                NativeInboxFilmCard(
                    item: item,
                    repaymentCandidate: appState.repaymentCandidates[record.id],
                    isSingleColumn: columnCount == 1
                )
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.985))
            .frame(maxWidth: .infinity)
        }
    }

    private static func dateKey(daysFromToday: Int) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        let date = calendar.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return NativeLocalDate.dateKey(date)
    }
}

private enum InboxVisualStyle {
    static func color(for filter: NativeInboxFilter) -> Color {
        switch filter {
        case .pendingExpense: return Color(hex: "A66A18")
        case .routing: return JieziTheme.brand
        case .review: return Color(hex: "5A6D9A")
        case .failed: return JieziTheme.coral
        case .repair: return Color(hex: "8B5A2B")
        case .all: return JieziTheme.ink
        }
    }
}

private struct NativeInboxFilmCard: View {
    let item: NativeInboxItem
    let repaymentCandidate: NativeRepaymentCandidate?
    var isSingleColumn = false

    private var imageURL: URL? {
        item.stagingRecord?.imageURL ?? item.pendingExpense?.imageURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.sm) {
            mediaSurface
            caption
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var mediaSurface: some View {
        if isSingleColumn, imageURL != nil {
            singleColumnMediaSurface
        } else {
            fixedAspectMediaSurface
        }
    }

    private var singleColumnMediaSurface: some View {
        ZStack(alignment: .topLeading) {
            filmContent
                .frame(maxWidth: .infinity)
                .clipped()
            InboxFilmStateBadge(label: item.statusLabel, color: statusColor)
                .padding(JieziSpacing.sm)
        }
        .frame(maxWidth: .infinity)
        .background(JieziTheme.paper.opacity(0.74))
        .clipShape(mediaShape)
        .overlay {
            mediaShape.stroke(statusColor.opacity(0.14), lineWidth: 1)
        }
        .shadow(color: JieziTheme.space.opacity(0.07), radius: 10, x: 0, y: 6)
    }

    private var fixedAspectMediaSurface: some View {
        // The shape owns the grid-cell size; overlay content cannot widen the column.
        mediaShape
            .fill(JieziTheme.paper.opacity(0.74))
            .aspectRatio(isSingleColumn ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                filmContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .overlay(alignment: .topLeading) {
                InboxFilmStateBadge(label: item.statusLabel, color: statusColor)
                    .padding(JieziSpacing.sm)
            }
            .clipShape(mediaShape)
            .overlay {
                mediaShape.stroke(statusColor.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: JieziTheme.space.opacity(0.07), radius: 10, x: 0, y: 6)
    }

    private var mediaShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous)
    }

    @ViewBuilder
    private var filmContent: some View {
        if let imageURL {
            CachedRemoteImage(url: imageURL) { image in
                if isSingleColumn || item.pendingExpense != nil {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                } else {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } placeholder: {
                ProgressView()
                    .tint(JieziTheme.brand)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(isSingleColumn ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
            } failure: {
                noteContent
                    .aspectRatio(isSingleColumn ? 4.0 / 3.0 : 3.0 / 4.0, contentMode: .fit)
            }
        } else {
            noteContent
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: JieziSpacing.sm) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                captionAccessory
            }

            if item.stagingRecord != nil, !item.subtitle.isEmpty {
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(isSingleColumn ? 3 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            timeStack
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var captionAccessory: some View {
        if repaymentCandidate != nil {
            Image(systemName: "creditcard.and.123")
                .font(.caption)
                .foregroundStyle(JieziTheme.brand)
                .accessibilityLabel("可能是还款记录")
        } else if let pending = item.pendingExpense {
            Text(String(format: "-¥%.2f", pending.amount))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(JieziTheme.coral)
                .lineLimit(1)
        } else if let confidence = item.stagingRecord?.confidencePercent {
            Text("\(confidence)%")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(JieziTheme.muted)
        }
    }

    @ViewBuilder
    private var timeStack: some View {
        if let record = item.stagingRecord {
            inboxTimes(
                occurredAt: record.occurredAtLabel ?? "未识别",
                createdAt: record.createdAtLabel
            )
        } else if let pending = item.pendingExpense {
            inboxTimes(
                occurredAt: pending.occurredAtLabel ?? pending.dateKey,
                createdAt: pending.createdAtLabel
            )
        }
    }

    private func inboxTimes(occurredAt: String, createdAt: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            inboxTimeRow(label: "记录", value: occurredAt)
            inboxTimeRow(label: "上传", value: createdAt)
        }
        .font(.caption2)
        .foregroundStyle(JieziTheme.muted)
    }

    private func inboxTimeRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label)
                .foregroundStyle(JieziTheme.muted.opacity(0.72))
            Text(value)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
    }

    private var noteContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "F8F4E9"), Color(hex: "F0EAD8")],
                startPoint: .top,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 9) {
                Text(item.stagingRecord == nil ? "账单事实" : "文字事实")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(JieziTheme.gold)

                HStack(spacing: 8) {
                    Image(systemName: item.systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .frame(width: 30, height: 30)
                        .overlay(Circle().stroke(statusColor.opacity(0.22)))
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.ink)
                        .lineLimit(2)
                }

                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(4)

                if let record = item.stagingRecord {
                    let fields = Array(NativeStagingDetailPresentation.fields(for: record).prefix(3))
                    if !fields.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(fields) { field in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(field.label)
                                        .foregroundStyle(JieziTheme.muted)
                                    Spacer(minLength: 4)
                                    Text(field.value)
                                        .foregroundStyle(JieziTheme.ink)
                                        .lineLimit(1)
                                }
                                .font(.caption2)
                            }
                        }
                        .padding(.top, 5)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(JieziTheme.brand.opacity(0.12))
                                .frame(height: 1)
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusColor: Color {
        guard let record = item.stagingRecord else { return JieziTheme.gold }
        switch record.status {
        case "ai_error", "failed", "extraction_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.brand
        case "schema_failed": return JieziTheme.ink
        default: return Color(hex: "8A6D2F")
        }
    }
}

private struct InboxFilmStateBadge: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).lineLimit(1)
        }
        .font(.system(size: 10, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(JieziTheme.paper.opacity(0.88), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct InboxSettledEmptyView: View {
    var body: some View {
        VStack(spacing: JieziSpacing.Semantic.card_padding) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                let ringRadius: CGFloat = 48
                context.stroke(
                    Path(ellipseIn: CGRect(
                        x: center.x - ringRadius,
                        y: center.y - ringRadius,
                        width: ringRadius * 2,
                        height: ringRadius * 2
                    )),
                    with: .color(JieziTheme.brand.opacity(0.1)),
                    lineWidth: 1
                )
                context.fill(
                    Path(ellipseIn: CGRect(x: center.x - 4, y: center.y + 18, width: 8, height: 8)),
                    with: .color(JieziTheme.gold)
                )
            }
            .frame(width: 150, height: 150)

            VStack(spacing: JieziSpacing.sm) {
                Text("微尘皆已落定")
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
                Text("新的截图会在这里稍作停留")
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }
}

private struct InboxVerdictStageView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let items: [NativeInboxItem]
    @Binding var selection: String?
    let domains: [NativeArchiveDomain]

    @State private var showDiscardConfirmation = false
    @State private var editorContext: StagingEditorContext?
    @State private var pendingEditorContext: PendingEditorContext?

    private var currentIndex: Int {
        items.firstIndex(where: { $0.id == selection }) ?? 0
    }

    private var current: NativeInboxItem? {
        guard !items.isEmpty else { return nil }
        return items[min(currentIndex, items.count - 1)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "EFEADA"), Color(hex: "EAE4D2")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if items.isEmpty {
                VStack(spacing: JieziSpacing.Semantic.card_padding) {
                    Text("微尘皆已落定").font(.headline)
                    Text("当前序列已经处理完毕").font(.subheadline).foregroundStyle(JieziTheme.muted)
                    Button("回到中转站") { closeStage() }
                        .buttonStyle(.borderedProminent)
                        .tint(JieziTheme.brand)
                }
            } else if let current {
                VStack(spacing: 0) {
                    stageTopBar(current)
                    InboxStageRecordPager(
                        canMovePrevious: currentIndex > 0,
                        canMoveNext: currentIndex < items.count - 1,
                        move: movePage
                    ) {
                        stageVisual(current)
                            .id(current.id)
                    }
                    .frame(maxHeight: .infinity)

                    stageInfo(current)
                    stageActions(current)
                    if let record = current.stagingRecord {
                        domainStrip(record)
                    } else {
                        Spacer().frame(height: 24)
                    }
                }
            }
        }
        .onAppear {
            if selection == nil || !items.contains(where: { $0.id == selection }) {
                selection = items.first?.id
            }
        }
        .onChange(of: items.map(\.id)) { oldIds, newIds in
            guard let selected = selection else {
                selection = newIds.first
                return
            }
            guard !newIds.contains(selected) else { return }
            guard !newIds.isEmpty else {
                closeStage()
                return
            }
            let previousIndex = oldIds.firstIndex(of: selected) ?? 0
            selection = newIds[min(previousIndex, newIds.count - 1)]
        }
        .confirmationDialog(
            "销毁后无法恢复",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认销毁", role: .destructive) {
                guard let item = current, let record = item.stagingRecord else { return }
                Task {
                    if await appState.discardStagingRecord(record, preserveInboxNavigation: true) {
                        finishAction(for: item.id)
                    }
                }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("这条截图不会进入任何数据域，原图会在后台安全清理。")
        }
        .sheet(item: $editorContext) { context in
            ManualRecordSheet(
                staging: context.record,
                domainKey: context.domainId,
                preserveInboxNavigation: true,
                onResolved: { finishAction(for: "staging-\(context.record.id)") }
            )
            .environmentObject(appState)
        }
        .sheet(item: $pendingEditorContext) { context in
            NavigationStack {
                PendingExpenseResolutionView(
                    reference: context.reference,
                    preserveInboxNavigation: true,
                    onResolved: { finishAction(for: context.itemId) }
                )
                .environmentObject(appState)
            }
        }
    }

    @ViewBuilder
    private func stageVisual(_ item: NativeInboxItem) -> some View {
        if let record = item.stagingRecord {
            StagingStageImage(record: record)
        } else if let pending = item.pendingExpense {
            PendingStageImage(pending: pending)
        }
    }

    private func movePage(_ offset: Int) {
        guard let next = NativeInboxPresentation.adjacentSelection(
            to: selection,
            offset: offset,
            in: items.map(\.id)
        ) else { return }
        selection = next
        JieziHaptics.tap()
    }

    private func stageTopBar(_ item: NativeInboxItem) -> some View {
        HStack(spacing: JieziSpacing.md) {
            Button { closeStage() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(JieziTheme.brand)
                    .background(JieziTheme.brand.opacity(0.08), in: Circle())
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor(for: item)).frame(width: 6, height: 6)
                Text("\(item.statusLabel) · \(contextLabel(for: item))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor(for: item))
                    .lineLimit(1)
            }
            Spacer()
            Text("\(currentIndex + 1) / \(items.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(JieziTheme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func stageInfo(_ item: NativeInboxItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(item.stagingRecord?.summary ?? item.title)
                .font(.headline)
                .foregroundStyle(JieziTheme.ink)
                .lineLimit(3)
            if let record = item.stagingRecord {
                HStack(spacing: JieziSpacing.md) {
                    if let confidence = record.confidencePercent {
                        HStack(spacing: 5) {
                            ForEach(0..<3, id: \.self) { index in
                                Circle()
                                    .fill(index < assuranceDots(confidence) ? JieziTheme.ink.opacity(0.55) : .clear)
                                    .overlay(Circle().stroke(JieziTheme.ink.opacity(0.3), lineWidth: 1))
                                    .frame(width: 5, height: 5)
                            }
                            Text(assuranceLabel(confidence))
                        }
                    }
                    if record.retryCount > 0 { Text("已重试 \(record.retryCount) 次") }
                }
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
            } else if let pending = item.pendingExpense {
                Text(String(format: "待补全金额 ¥%.2f", pending.amount))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(JieziTheme.coral)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("记录时间：\(occurredAtLabel(for: item) ?? "未识别")")
                Text("上传时间：\(createdAtLabel(for: item))")
            }
            .font(.caption2)
            .foregroundStyle(JieziTheme.muted)
            if let error = item.stagingRecord?.lastErrorMessage, !error.isEmpty {
                Text(NativeStagingDetailPresentation.errorSummary(error))
                    .font(.caption)
                    .foregroundStyle(JieziTheme.coral)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func stageActions(_ item: NativeInboxItem) -> some View {
        if let pending = item.pendingExpense {
            Button {
                pendingEditorContext = PendingEditorContext(itemId: item.id, reference: pending.reference)
            } label: {
                Label("补全这笔账单", systemImage: "rectangle.and.pencil.and.ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(JieziTheme.brandWash, in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
            .padding(.horizontal, 26)
            .padding(.top, JieziSpacing.md)
        } else if let record = item.stagingRecord {
            VStack(spacing: JieziSpacing.sm) {
                if let suggested = domains.first(where: { $0.id == record.domainKey }) {
                    Button {
                        Task { await archive(item, record: record, to: suggested.id) }
                    } label: {
                        Label("收下 · \(suggested.title)", systemImage: "arrow.down.to.line")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .background(JieziTheme.brandWash, in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
                }

                HStack(spacing: JieziSpacing.sm) {
                    stageActionButton("slider.horizontal.3", title: "调整") {
                        let domainId = record.domainKey ?? domains.first?.id ?? "expense"
                        editorContext = StagingEditorContext(record: record, domainId: domainId)
                    }
                    stageActionButton("arrow.clockwise", title: "重试") {
                        Task {
                            if await appState.retryStagingRecord(record, preserveInboxNavigation: true) {
                                finishAction(for: item.id, keepIfPresent: true)
                            }
                        }
                    }
                    stageActionButton("trash", title: "销毁", destructive: true) {
                        showDiscardConfirmation = true
                    }
                }
            }
            .disabled(appState.inboxActionRecordId != nil)
            .padding(.horizontal, 26)
            .padding(.top, JieziSpacing.md)
        }
    }

    private func stageActionButton(
        _ systemImage: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? JieziTheme.coral : JieziTheme.brand)
        .background(
            (destructive ? JieziTheme.coral : JieziTheme.brand).opacity(0.08),
            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
        )
    }

    private func domainStrip(_ record: NativeStagingRecord) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JieziSpacing.sm) {
                Text("改判到")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                ForEach(domains) { domain in
                    Button(domain.title) {
                        guard let item = current else { return }
                        Task { await archive(item, record: record, to: domain.id) }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(domain.id == record.domainKey ? JieziTheme.brand : JieziTheme.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(
                        domain.id == record.domainKey ? JieziTheme.brand.opacity(0.1) : Color.white.opacity(0.48),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(JieziTheme.brand.opacity(domain.id == record.domainKey ? 0.28 : 0.1)))
                    .disabled(appState.inboxActionRecordId != nil)
                }
            }
            .padding(.horizontal, 26)
        }
        .padding(.top, JieziSpacing.sm)
        .padding(.bottom, 24)
    }

    private func archive(_ item: NativeInboxItem, record: NativeStagingRecord, to domainId: String) async {
        if await appState.archiveStagingRecord(
            record,
            domainKey: domainId,
            preserveInboxNavigation: true
        ) != nil {
            finishAction(for: item.id)
        }
    }

    private func finishAction(for itemId: String, keepIfPresent: Bool = false) {
        if keepIfPresent {
            let liveItems = NativeInboxPresentation.items(
                pendingExpenses: appState.dashboard.pendingExpenses,
                stagingRecords: appState.dashboard.stagingRecords
            )
            if liveItems.contains(where: { $0.id == itemId }) {
                selection = itemId
                return
            }
        }
        if let next = NativeInboxPresentation.nextSelection(
            afterRemoving: itemId,
            from: items.map(\.id)
        ) {
            selection = next
        } else {
            closeStage()
        }
    }

    private func closeStage() {
        selection = nil
        dismiss()
    }

    private func contextLabel(for item: NativeInboxItem) -> String {
        item.stagingRecord?.domainName
            ?? item.stagingRecord?.recordTypeLabel
            ?? "支出"
    }

    private func occurredAtLabel(for item: NativeInboxItem) -> String? {
        item.stagingRecord?.occurredAtLabel ?? item.pendingExpense?.occurredAtLabel
    }

    private func createdAtLabel(for item: NativeInboxItem) -> String {
        item.stagingRecord?.createdAtLabel ?? item.pendingExpense?.createdAtLabel ?? "最近上传"
    }

    private func statusColor(for item: NativeInboxItem) -> Color {
        guard let record = item.stagingRecord else { return JieziTheme.gold }
        switch record.status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.brand
        default: return Color(hex: "8A6D2F")
        }
    }

    private func assuranceDots(_ confidence: Int) -> Int {
        if confidence >= 85 { return 3 }
        if confidence >= 60 { return 2 }
        return 1
    }

    private func assuranceLabel(_ confidence: Int) -> String {
        switch assuranceDots(confidence) {
        case 3: return "较有把握"
        case 2: return "不太确定"
        default: return "需要你看看"
        }
    }
}

private struct PendingEditorContext: Identifiable {
    let itemId: String
    let reference: String
    var id: String { itemId }
}

private struct PendingStageImage: View {
    let pending: NativePendingExpense

    var body: some View {
        Group {
            if let url = pending.imageURL {
                CachedRemoteImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ProgressView().tint(JieziTheme.brand)
                } failure: {
                    factSheet("原图加载失败，以账单事实为准")
                }
            } else {
                factSheet(pending.imagePath == nil ? "原图未保留，以账单事实为准" : "原图暂不可用，以账单事实为准")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func factSheet(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账单事实")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.gold)
            HStack(spacing: 10) {
                Image(systemName: "creditcard")
                    .foregroundStyle(JieziTheme.brand)
                    .frame(width: 36, height: 36)
                    .overlay(Circle().stroke(JieziTheme.brand.opacity(0.18)))
                Text(pending.title)
                    .font(.headline)
                    .foregroundStyle(JieziTheme.ink)
            }
            Text(String(format: "¥%.2f", pending.amount))
                .font(.title2.weight(.semibold).monospacedDigit())
                .foregroundStyle(JieziTheme.coral)
            Text(message)
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color(hex: "F8F4E9"), in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                .stroke(JieziTheme.brand.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct StagingVerdictStageView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let records: [NativeStagingRecord]
    @Binding var selection: String?
    let domains: [NativeArchiveDomain]

    @State private var showDiscardConfirmation = false
    @State private var editorContext: StagingEditorContext?

    private var currentIndex: Int {
        records.firstIndex(where: { $0.id == selection }) ?? 0
    }

    private var current: NativeStagingRecord? {
        guard !records.isEmpty else { return nil }
        return records[min(currentIndex, records.count - 1)]
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "EFEADA"), Color(hex: "EAE4D2")],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if records.isEmpty {
                VStack(spacing: JieziSpacing.Semantic.card_padding) {
                    Text("微尘皆已落定").font(.headline)
                    Text("全部处理完毕").font(.subheadline).foregroundStyle(JieziTheme.muted)
                    Button("回到中转站") { closeStage() }
                        .buttonStyle(.borderedProminent)
                        .tint(JieziTheme.brand)
                }
            } else if let current {
                VStack(spacing: 0) {
                    stageTopBar(current)
                    InboxStageRecordPager(
                        canMovePrevious: currentIndex > 0,
                        canMoveNext: currentIndex < records.count - 1,
                        move: movePage
                    ) {
                        StagingStageImage(record: current)
                            .id(current.id)
                    }
                    .frame(maxHeight: .infinity)

                    stageInfo(current)
                    stageActions(current)
                    domainStrip(current)
                }
            }
        }
        .onAppear {
            if selection == nil { selection = records.first?.id }
        }
        .onChange(of: records.map(\.id)) { _, ids in
            guard let selection else {
                self.selection = ids.first
                return
            }
            if !ids.contains(selection) { self.selection = ids.first }
        }
        .confirmationDialog(
            "销毁后无法恢复",
            isPresented: $showDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("确认销毁", role: .destructive) {
                guard let current else { return }
                Task {
                    await appState.discardStagingRecord(current)
                    finishAction(for: current.id)
                }
            }
            Button("再想想", role: .cancel) {}
        } message: {
            Text("这条截图不会进入任何数据域，原图会在后台安全清理。")
        }
        .sheet(item: $editorContext) { context in
            ManualRecordSheet(staging: context.record, domainKey: context.domainId)
                .environmentObject(appState)
        }
    }

    private func movePage(_ offset: Int) {
        guard let next = NativeInboxPresentation.adjacentSelection(
            to: selection,
            offset: offset,
            in: records.map(\.id)
        ) else { return }
        selection = next
        JieziHaptics.tap()
    }

    private func stageTopBar(_ record: NativeStagingRecord) -> some View {
        HStack(spacing: JieziSpacing.md) {
            Button { closeStage() } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 34, height: 34)
                    .foregroundStyle(JieziTheme.brand)
                    .background(JieziTheme.brand.opacity(0.08), in: Circle())
            }
            HStack(spacing: 6) {
                Circle().fill(statusColor(for: record)).frame(width: 6, height: 6)
                Text("\(record.statusLabel) · \(record.domainName ?? record.recordTypeLabel)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor(for: record))
                    .lineLimit(1)
            }
            Spacer()
            Text("\(currentIndex + 1) / \(records.count)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(JieziTheme.muted)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 6)
    }

    private func stageInfo(_ record: NativeStagingRecord) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.summary)
                .font(.headline)
                .foregroundStyle(JieziTheme.ink)
                .lineLimit(3)
            HStack(spacing: JieziSpacing.md) {
                if let confidence = record.confidencePercent {
                    HStack(spacing: 5) {
                        ForEach(0..<3, id: \.self) { index in
                            Circle()
                                .fill(index < assuranceDots(confidence) ? JieziTheme.ink.opacity(0.55) : .clear)
                                .overlay(Circle().stroke(JieziTheme.ink.opacity(0.3), lineWidth: 1))
                                .frame(width: 5, height: 5)
                        }
                        Text(assuranceLabel(confidence))
                    }
                }
                if record.retryCount > 0 { Text("已重试 \(record.retryCount) 次") }
            }
            .font(.caption)
            .foregroundStyle(JieziTheme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text("记录时间：\(record.occurredAtLabel ?? "未识别")")
                Text("上传时间：\(record.createdAtLabel)")
            }
            .font(.caption2)
            .foregroundStyle(JieziTheme.muted)
            if let error = record.lastErrorMessage, !error.isEmpty {
                Text(NativeStagingDetailPresentation.errorSummary(error))
                    .font(.caption)
                    .foregroundStyle(JieziTheme.coral)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func stageActions(_ record: NativeStagingRecord) -> some View {
        VStack(spacing: JieziSpacing.sm) {
            if let suggested = domains.first(where: { $0.id == record.domainKey }) {
                Button {
                    Task { await archive(record, to: suggested.id) }
                } label: {
                    Label("收下 · \(suggested.title)", systemImage: "arrow.down.to.line")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(JieziTheme.brandWash, in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
                .disabled(appState.inboxActionRecordId != nil)
            }

            HStack(spacing: JieziSpacing.sm) {
                stageActionButton("slider.horizontal.3", title: "调整") {
                    let domainId = record.domainKey ?? domains.first?.id ?? "expense"
                    editorContext = StagingEditorContext(record: record, domainId: domainId)
                }
                stageActionButton("arrow.clockwise", title: "重试") {
                    Task {
                        await appState.retryStagingRecord(record)
                        finishAction(for: record.id)
                    }
                }
                stageActionButton("trash", title: "销毁", destructive: true) {
                    showDiscardConfirmation = true
                }
            }
            .disabled(appState.inboxActionRecordId != nil)
        }
        .padding(.horizontal, 26)
        .padding(.top, JieziSpacing.md)
    }

    private func stageActionButton(
        _ systemImage: String,
        title: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                Text(title).font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .foregroundStyle(destructive ? JieziTheme.coral : JieziTheme.brand)
        .background(
            (destructive ? JieziTheme.coral : JieziTheme.brand).opacity(0.08),
            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
        )
    }

    private func domainStrip(_ record: NativeStagingRecord) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JieziSpacing.sm) {
                Text("改判到")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                ForEach(domains) { domain in
                    Button(domain.title) {
                        Task { await archive(record, to: domain.id) }
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(domain.id == record.domainKey ? JieziTheme.brand : JieziTheme.ink)
                    .padding(.horizontal, 11)
                    .frame(height: 32)
                    .background(
                        domain.id == record.domainKey ? JieziTheme.brand.opacity(0.1) : Color.white.opacity(0.48),
                        in: Capsule()
                    )
                    .overlay(Capsule().stroke(JieziTheme.brand.opacity(domain.id == record.domainKey ? 0.28 : 0.1)))
                    .disabled(appState.inboxActionRecordId != nil)
                }
            }
            .padding(.horizontal, 26)
        }
        .padding(.top, JieziSpacing.sm)
        .padding(.bottom, 24)
    }

    private func archive(_ record: NativeStagingRecord, to domainId: String) async {
        if await appState.archiveStagingRecord(record, domainKey: domainId) != nil {
            finishAction(for: record.id)
        }
    }

    private func finishAction(for recordId: String) {
        if appState.dashboard.stagingRecords.contains(where: { $0.id == recordId }) {
            selection = recordId
            return
        }
        let remainingIds = Set(appState.dashboard.stagingRecords.map(\.id))
        if let next = records.first(where: { $0.id != recordId && remainingIds.contains($0.id) }) {
            selection = next.id
        } else {
            closeStage()
        }
    }

    private func closeStage() {
        selection = nil
        dismiss()
    }

    private func statusColor(for record: NativeStagingRecord) -> Color {
        switch record.status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.brand
        default: return Color(hex: "8A6D2F")
        }
    }

    private func assuranceDots(_ confidence: Int) -> Int {
        if confidence >= 85 { return 3 }
        if confidence >= 60 { return 2 }
        return 1
    }

    private func assuranceLabel(_ confidence: Int) -> String {
        switch assuranceDots(confidence) {
        case 3: return "较有把握"
        case 2: return "不太确定"
        default: return "需要你看看"
        }
    }
}

private struct StagingEditorContext: Identifiable {
    let record: NativeStagingRecord
    let domainId: String

    var id: String { "\(record.id):\(domainId)" }
}

private struct StagingStageImage: View {
    @EnvironmentObject private var appState: AppState
    let record: NativeStagingRecord
    @State private var resolvedURL: URL?
    @State private var isResolving = false
    @State private var errorMessage: String?

    private var imageURL: URL? { resolvedURL ?? record.imageURL }

    var body: some View {
        Group {
            if let imageURL {
                CachedRemoteImage(url: imageURL) { image in
                    InboxZoomableImage {
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                } placeholder: {
                    ProgressView().tint(JieziTheme.brand)
                } failure: {
                    stageFallback("原图加载失败，以文字事实为准")
                }
            } else if isResolving {
                ProgressView("正在加载截图…")
            } else {
                stageFallback(errorMessage ?? "原图未保留，以文字事实为准")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: record.id) {
            guard record.imageURL == nil, record.imagePath != nil, resolvedURL == nil else { return }
            isResolving = true
            defer { isResolving = false }
            do {
                resolvedURL = try await appState.resolveStagingImageURL(for: record)
            } catch {
                errorMessage = NativeStagingDetailPresentation.errorSummary(error.localizedDescription)
            }
        }
    }

    private func stageFallback(_ message: String) -> some View {
        StagingFactSheet(record: record, message: message)
    }
}

private struct InboxStageRecordPager<Content: View>: View {
    let canMovePrevious: Bool
    let canMoveNext: Bool
    let move: (Int) -> Void
    private let content: Content

    @GestureState private var resistedDragOffset: CGFloat = 0

    init(
        canMovePrevious: Bool,
        canMoveNext: Bool,
        move: @escaping (Int) -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.canMovePrevious = canMovePrevious
        self.canMoveNext = canMoveNext
        self.move = move
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 6) {
            pageButton(
                systemImage: "chevron.left",
                accessibilityLabel: "上一条记录",
                enabled: canMovePrevious,
                action: { move(-1) }
            )

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    Color.white.opacity(0.76),
                    in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                )
                .clipShape(RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                        .stroke(JieziTheme.brand.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: JieziTheme.space.opacity(0.1), radius: 12, x: 0, y: 7)
                .contentShape(Rectangle())
                .offset(x: resistedDragOffset)
                .simultaneousGesture(horizontalSwipeGesture)

            pageButton(
                systemImage: "chevron.right",
                accessibilityLabel: "下一条记录",
                enabled: canMoveNext,
                action: { move(1) }
            )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 10)
    }

    private var horizontalSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .local)
            .updating($resistedDragOffset) { value, state, transaction in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                transaction.animation = nil
                state = min(12, max(-12, value.translation.width * 0.08))
            }
            .onEnded { value in
                guard let offset = NativeInboxPresentation.swipePageOffset(
                    translationX: Double(value.translation.width),
                    translationY: Double(value.translation.height),
                    predictedEndTranslationX: Double(value.predictedEndTranslation.width)
                ) else { return }
                guard (offset < 0 && canMovePrevious) || (offset > 0 && canMoveNext) else { return }
                move(offset)
            }
    }

    private func pageButton(
        systemImage: String,
        accessibilityLabel: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 28, height: 44)
                .foregroundStyle(JieziTheme.brand)
                .background(
                    JieziTheme.brand.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.22)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct StagingFactSheet: View {
    let record: NativeStagingRecord
    let message: String

    private var fields: [NativeStagingDisplayField] {
        Array(NativeStagingDetailPresentation.fields(for: record).prefix(5))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("文字事实")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JieziTheme.gold)
                HStack(spacing: 9) {
                    Image(systemName: record.systemImage)
                        .foregroundStyle(JieziTheme.brand)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().stroke(JieziTheme.brand.opacity(0.18)))
                    Text(record.domainName ?? record.recordTypeLabel)
                        .font(.headline)
                        .foregroundStyle(JieziTheme.ink)
                }
                Text(record.summary)
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
                    .lineSpacing(4)

                if !fields.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(fields) { field in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(field.label)
                                    .font(.caption)
                                    .foregroundStyle(JieziTheme.muted)
                                Spacer(minLength: 8)
                                Text(field.value)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(JieziTheme.ink)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding(.top, 8)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(JieziTheme.brand.opacity(0.12))
                            .frame(height: 1)
                    }
                }

                Text(message)
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
                    .lineSpacing(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(
            LinearGradient(
                colors: [Color(hex: "F8F4E9"), Color(hex: "F0EAD8")],
                startPoint: .top,
                endPoint: .bottom
            ),
            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                .stroke(JieziTheme.brand.opacity(0.12), lineWidth: 1)
        }
    }
}

private struct InboxZoomableImage<Content: View>: View {
    let content: Content
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var liveScale: CGFloat = 1
    @GestureState private var liveOffset: CGSize = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(scale * liveScale)
            .offset(x: offset.width + liveOffset.width, y: offset.height + liveOffset.height)
            .gesture(
                MagnifyGesture()
                    .updating($liveScale) { value, state, _ in state = value.magnification }
                    .onEnded { value in
                        scale = min(max(scale * value.magnification, 1), 3)
                        if scale == 1 { offset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($liveOffset) { value, state, _ in
                        guard scale > 1 else { return }
                        state = value.translation
                    }
                    .onEnded { value in
                        guard scale > 1 else { return }
                        offset.width += value.translation.width
                        offset.height += value.translation.height
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    if scale > 1 {
                        scale = 1
                        offset = .zero
                    } else {
                        scale = 1.9
                    }
                }
            }
            .clipped()
    }
}

private struct PendingExpenseResolutionView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @Environment(\.dismiss) private var dismiss
    let reference: String
    let preserveInboxNavigation: Bool
    let onResolved: (() -> Void)?
    @State private var draft: NativePendingResolutionDraft?
    @State private var showDeleteConfirm = false

    init(
        reference: String,
        preserveInboxNavigation: Bool = false,
        onResolved: (() -> Void)? = nil
    ) {
        self.reference = reference
        self.preserveInboxNavigation = preserveInboxNavigation
        self.onResolved = onResolved
    }

    private var detail: NativeRecordDetail? {
        guard appState.selectedRecordDetail?.id == reference else { return nil }
        return appState.selectedRecordDetail
    }
    private var palette: JieziGeneratedPalette { themeManager.palette }

    var body: some View {
        ZStack {
            JieziGradient.pageBackground(palette: palette).ignoresSafeArea()
            if let detail, let draftBinding = Binding($draft) {
                GeometryReader { scrollViewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            header(detail)
                            if let companionMessage = detail.companionMessage, !companionMessage.isEmpty {
                                companionSection(
                                    companionMessage,
                                    feedback: NativeRecordExpressionFeedbackPolicy.companionFeedbackToReview(
                                        companionMessage: companionMessage,
                                        feedback: detail.aiFeedback
                                    ),
                                    viewportFrame: scrollViewport.frame(in: .global)
                                )
                            }
                            if let feedback = NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                                companionMessage: detail.companionMessage,
                                feedback: detail.aiFeedback
                            ) {
                                NativeAIFeedbackCard(
                                    feedback: feedback,
                                    compact: true,
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
                            imageSection(detail)
                            amountSection(draftBinding)
                            typeSection(draftBinding)
                            fieldSection(draftBinding)
                            accountSection(draftBinding)
                            if let message = appState.pendingResolutionMessage {
                                Label(message, systemImage: message.hasPrefix("保存失败") ? "exclamationmark.circle" : "info.circle")
                                    .font(.footnote)
                                    .foregroundStyle(message.hasPrefix("保存失败") ? JieziTheme.coral : JieziTheme.brand)
                            }
                            Button {
                                Task {
                                    if await appState.confirmPendingRecord(
                                        draftBinding.wrappedValue,
                                        preserveInboxNavigation: preserveInboxNavigation
                                    ) {
                                        onResolved?()
                                        dismiss()
                                    }
                                }
                            } label: {
                                if appState.isConfirmingPendingRecord {
                                    ProgressView().tint(.white).frame(maxWidth: .infinity)
                                } else {
                                    Label("确认保存", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.brand)
                            .controlSize(.large)
                            .disabled(appState.isConfirmingPendingRecord || draftBinding.wrappedValue.validationMessage != nil)

                            Button(role: .destructive) { showDeleteConfirm = true } label: {
                                Label("删除此账单", systemImage: "trash").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(16)
                    }
                }
            } else if let message = appState.recordDetailMessage {
                ContentUnavailableView("无法读取待补全账单", systemImage: "exclamationmark.triangle", description: Text(message))
            } else {
                ProgressView("正在读取识别结果")
            }
        }
        .navigationTitle("补充账单信息")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: reference) {
            appState.pendingResolutionMessage = nil
            await appState.loadRecordDetail(reference: reference)
            if let detail = appState.selectedRecordDetail, detail.id == reference {
                draft = NativePendingResolutionDraft(detail: detail)
            }
            await appState.loadFinanceVocabulary()
        }
        .onDisappear {
            appState.deactivateRecordDetail(reference: reference)
        }
        .confirmationDialog("删除这条待补全账单？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await appState.deleteRecord(reference: reference) {
                        onResolved?()
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func header(_ detail: NativeRecordDetail) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.light)
                .frame(width: 40, height: 40)
                .background(palette.light.opacity(0.12), in: RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.title).font(.headline)
                Text(detail.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("待补全").font(.caption.weight(.bold)).foregroundStyle(palette.light)
        }
        .jieziCard(palette: palette, solid: true)
    }

    private func companionSection(
        _ message: String,
        feedback: NativeAIFeedback?,
        viewportFrame: CGRect
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill")
                .foregroundStyle(JieziTheme.brand)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("AI 陪伴")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        if let feedback, !feedback.badge.isEmpty {
                            Text(feedback.badge)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(JieziTheme.brand)
                        }
                    }
                    Text(message)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let feedback {
                    NativeAIFeedbackSupportingContent(
                        feedback: feedback,
                        primaryMessage: message,
                        compact: true
                    )
                    NativeAIFeedbackCard(
                        feedback: feedback,
                        compact: true,
                        reviewOnly: true,
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
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JieziTheme.brand.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
        .onNativeAIFeedbackCardVisibilityChange(in: viewportFrame) { isVisible in
            guard let feedback, feedback.source == "expression_planner" else { return }
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
        .id(feedback.map { "companion-\($0.renderIdentity)" } ?? "companion-message")
    }

    @ViewBuilder
    private func imageSection(_ detail: NativeRecordDetail) -> some View {
        if let imageURL = detail.imageURL {
            CachedRemoteImage(url: imageURL) { image in
                image.resizable().scaledToFit().frame(maxWidth: .infinity)
            } placeholder: {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } failure: {
                Label("截图文件不可用", systemImage: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .jieziCard(palette: palette, solid: true)
        }
    }

    private func amountSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("金额").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(draft.wrappedValue.kind == .income ? "+¥" : "-¥")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(draft.wrappedValue.kind == .income ? palette.brand : palette.coral)
                TextField("0.00", text: draft.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.bold).monospacedDigit())
            }
            .jieziInputSurface(palette: palette)
        }
        .jieziCard(palette: palette, solid: true)
    }

    private func typeSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("记录类型").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Picker("记录类型", selection: draft.kind) {
                ForEach(NativePendingEntryKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
        }
        .jieziCard(palette: palette, solid: true)
    }

    private func fieldSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.wrappedValue.kind == .income ? "收入字段" : "消费字段").font(.headline)
            TextField(draft.wrappedValue.kind == .income ? "来源名称（可选）" : "商家名称（可选）", text: draft.merchantOrSourceName)
                .jieziInputSurface(palette: palette)
            if draft.wrappedValue.kind == .expense {
                editableOptionField(
                    "消费渠道",
                    selection: draft.platform,
                    options: financeOptions(kind: .platform, currentValue: draft.wrappedValue.platform)
                )
                optionMenu(
                    "消费分类",
                    selection: draft.category,
                    options: financeOptions(kind: .category, currentValue: draft.wrappedValue.category)
                )
                editableOptionField(
                    "支付方式",
                    selection: draft.paymentMethod,
                    options: financeOptions(kind: .payment, currentValue: draft.wrappedValue.paymentMethod)
                )
            } else {
                optionMenu("收入类型", selection: draft.incomeCategory, options: NativeManualRecordDraft.incomeCategories)
            }
        }
        .jieziCard(palette: palette, solid: true)
    }

    private func optionMenu(_ title: String, selection: Binding<String>, options: [NativeManualRecordOption]) -> some View {
        Menu {
            ForEach(options) { option in
                Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                    selection.wrappedValue = option.id
                }
            }
        } label: {
            HStack {
                Text(title).foregroundStyle(palette.ink)
                Spacer()
                Text(options.first(where: { $0.id == selection.wrappedValue })?.title ?? "请选择")
                    .foregroundStyle(selection.wrappedValue.isEmpty ? palette.muted : palette.brand)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
            .jieziInputSurface(palette: palette)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func editableOptionField(
        _ title: String,
        selection: Binding<String>,
        options: [NativeManualRecordOption]
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                TextField("输入或选择", text: selection)
                    .jieziInputSurface(palette: palette)
                Menu {
                    ForEach(options) { option in
                        Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                            selection.wrappedValue = option.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .foregroundStyle(palette.brand)
                        .frame(width: 46, height: 46)
                        .background(
                            palette.brand.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("选择\(title)")
            }
        }
    }

    private func financeOptions(
        kind: NativeFinanceVocabularyKind,
        currentValue: String
    ) -> [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(
            kind: kind,
            currentValue: currentValue,
            vocabulary: appState.financeVocabulary
        )
    }

    private func accountSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.wrappedValue.kind == .income ? "到账账户" : "出资账户").font(.headline)
            Menu {
                Button("暂不绑定") { draft.accountId.wrappedValue = nil }
                ForEach(appState.accounts.filter { !$0.isArchived }) { account in
                    Button(account.title) { draft.accountId.wrappedValue = account.id }
                }
            } label: {
                HStack {
                    Text(draft.wrappedValue.accountId.flatMap { id in appState.accounts.first(where: { $0.id == id })?.title } ?? "暂不绑定")
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .jieziInputSurface(palette: palette)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .jieziCard(palette: palette, solid: true)
    }
}

private struct NativeInboxItemRow: View {
    let item: NativeInboxItem
    let repaymentCandidate: NativeRepaymentCandidate?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(item.statusLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.12), in: Capsule())
                }
                Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                if let record = item.stagingRecord {
                    HStack(spacing: 8) {
                        Text(record.recordTypeLabel)
                        Text(record.occurredAtLabel ?? record.createdAtLabel)
                        if let confidence = record.confidencePercent {
                            Text("\(confidence)%").monospacedDigit()
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    if let confidence = record.confidencePercent {
                        ProgressView(value: Double(confidence), total: 100)
                            .tint(confidenceColor(confidence))
                    }
                    if let error = record.lastErrorMessage, !error.isEmpty {
                        Text(NativeStagingDetailPresentation.errorSummary(error))
                            .font(.caption2)
                            .foregroundStyle(JieziTheme.coral)
                            .lineLimit(2)
                    }
                }
                if let repaymentCandidate {
                    Text("可能是 \(repaymentCandidate.account.name) \(repaymentCandidate.cycle.cycleMonth) 还款")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(JieziTheme.brand)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = item.stagingRecord?.imageURL {
            CachedRemoteImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            } failure: {
                fallbackThumbnail
            }
            .frame(width: 48, height: 48)
            .background(JieziTheme.line.opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            fallbackThumbnail
        }
    }

    private var fallbackThumbnail: some View {
        Image(systemName: item.systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(statusColor)
            .frame(width: 48, height: 48)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var statusColor: Color {
        guard let record = item.stagingRecord else { return JieziTheme.gold }
        switch record.status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.gold
        default: return JieziTheme.brand
        }
    }

    private func confidenceColor(_ value: Int) -> Color {
        if value >= 70 { return JieziTheme.mint }
        if value >= 40 { return JieziTheme.gold }
        return JieziTheme.coral
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
    @Environment(\.dismiss) private var dismiss
    let record: NativeStagingRecord
    @State private var showDiscardConfirm = false
    @State private var selectedArchiveDomain: NativeArchiveDomain?
    @State private var showRepaymentConfirm = false

    private var archiveDomains: [NativeArchiveDomain] {
        let domains = appState.dashboard.domains.map { NativeArchiveDomain(id: $0.id, title: $0.shortName, systemImage: $0.systemImage) }
        return domains.isEmpty ? InboxArchiveDomains.all : domains
    }
    private var repaymentCandidate: NativeRepaymentCandidate? {
        appState.repaymentCandidates[record.id]
    }
    private var aiFeedback: NativeAIFeedback? {
        NativeAIFeedback(payload: record.extracted.dictionary("ai_feedback"))
            ?? NativeAIFeedback(payload: record.extracted.dictionary("payload_jsonb")?.dictionary("ai_feedback"))
    }
    @State private var showArchiveConfirm = false
    @State private var imagePreview: StagingImagePreviewRoute?
    @State private var resolvedImageURL: URL?
    @State private var isResolvingImage = false
    @State private var imageResolutionMessage: String?

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    stagingHeader
                    stagingImageSection
                    if let companionMessage = record.companionMessage, !companionMessage.isEmpty {
                        companionSection(companionMessage)
                    }
                    if let feedback = NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                        companionMessage: record.companionMessage,
                        feedback: aiFeedback
                    ) {
                        NativeAIFeedbackCard(feedback: feedback, compact: true)
                    }
                    recognitionSection
                    if !NativeStagingDetailPresentation.fields(for: record).isEmpty {
                        extractedSection
                    }
                    if let message = record.lastErrorMessage, !message.isEmpty {
                        errorSection(message)
                    }
                    if let candidate = repaymentCandidate {
                        repaymentSection(candidate)
                    }
                    if let message = appState.inboxFinanceMessage {
                        statusMessage(message, isError: false)
                    }
                    if let message = appState.inboxActionMessage {
                        statusMessage(message, isError: appState.inboxActionMessageIsError)
                    }
                    stagingActions
                }
                .padding(16)
            }
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
                    if await appState.archiveStagingRecord(record, domainKey: domain.id) != nil {
                        dismiss()
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: { domain in
            Text("芥子会按 PWA 的同一套规则，把这条中转站记录转入\(domain.title)域。")
        }
        .confirmationDialog(
            "确认把这张截图作为还款证据？",
            isPresented: $showRepaymentConfirm,
            titleVisibility: .visible,
            presenting: repaymentCandidate
        ) { _ in
            Button("确认还款") {
                Task { _ = await appState.confirmStagingRepayment(record) }
            }
            Button("取消", role: .cancel) {}
        } message: { candidate in
            Text("账单：\(candidate.account.name) \(candidate.cycle.cycleMonth)；金额：¥\(String(format: "%.2f", candidate.amount))。确认后会更新欠款、扣款账户和账户流水。")
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
                            Task { await resolveImage() }
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
        .task(id: record.id) {
            if record.imageURL == nil, record.imagePath != nil {
                await resolveImage()
            }
        }
    }

    private var stagingHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(record.statusLabel, systemImage: record.systemImage)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(statusColor)
                Spacer()
                if let confidence = record.confidencePercent {
                    Text("置信度 \(confidence)%").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            Text(record.title).font(.title3.weight(.bold))
            Text(record.summary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var stagingImageSection: some View {
        if let imageURL = resolvedImageURL ?? record.imageURL {
            Button { imagePreview = StagingImagePreviewRoute(url: imageURL) } label: {
                StagingImagePreview(url: imageURL) { Task { await resolveImage() } }
                    .padding(8)
                    .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        } else if record.imagePath != nil {
            Button { Task { await resolveImage() } } label: {
                VStack(spacing: 8) {
                    if isResolvingImage { ProgressView("正在加载截图…") }
                    else {
                        unavailableImageView
                        Text(imageResolutionMessage ?? "点此重新加载").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding(8)
                .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
    }

    private var recognitionSection: some View {
        detailCard("识别信息", rows: [
            ("类型", record.recordTypeLabel),
            ("上传时间", record.createdAtLabel),
            ("记录时间", record.occurredAtLabel ?? ""),
            ("置信度", record.confidencePercent.map { "\($0)%" } ?? ""),
            ("重试次数", record.retryCount > 0 ? "\(record.retryCount)" : "")
        ].filter { !$0.1.isEmpty })
    }

    private var extractedSection: some View {
        detailCard(
            "识别出的业务信息",
            rows: NativeStagingDetailPresentation.fields(for: record).map { ($0.label, $0.value) }
        )
    }

    private func companionSection(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "quote.bubble.fill").foregroundStyle(JieziTheme.brand)
            VStack(alignment: .leading, spacing: 5) {
                Text("AI 陪伴").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                Text(message).font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JieziTheme.brand.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }

    private func errorSection(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("识别未完成", systemImage: "exclamationmark.triangle.fill").font(.headline).foregroundStyle(JieziTheme.coral)
            Text(NativeStagingDetailPresentation.errorSummary(message))
                .font(.subheadline)
                .foregroundStyle(JieziTheme.coral)
                .fixedSize(horizontal: false, vertical: true)
            DisclosureGroup("技术详情") {
                Text(message)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.top, 6)
            }
            .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JieziTheme.coral.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private func repaymentSection(_ candidate: NativeRepaymentCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("可能是还款截图").font(.headline)
            detailRow("匹配账户", candidate.account.title)
            detailRow("账单月份", candidate.cycle.cycleMonth)
            detailRow("确认金额", String(format: "¥%.2f", candidate.amount))
            Text(candidate.reason).font(.footnote).foregroundStyle(.secondary)
            Button { showRepaymentConfirm = true } label: {
                if appState.stagingRepaymentId == record.id { ProgressView().frame(maxWidth: .infinity) }
                else { Label("确认还款", systemImage: "checkmark.circle").frame(maxWidth: .infinity) }
            }
            .buttonStyle(.borderedProminent)
            .tint(JieziTheme.brand)
            .disabled(appState.stagingRepaymentId != nil)
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func statusMessage(_ message: String, isError: Bool) -> some View {
        Label(message, systemImage: isError ? "exclamationmark.circle" : "checkmark.circle")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(isError ? JieziTheme.coral : JieziTheme.brand)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isError ? JieziTheme.coral : JieziTheme.brand).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }

    private var stagingActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("归档到数据域").font(.headline)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(archiveDomains) { domain in
                    Button {
                        selectedArchiveDomain = domain
                        showArchiveConfirm = true
                    } label: {
                        Label(domain.title, systemImage: domain.systemImage)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .tint(domain.id == record.domainKey ? JieziTheme.brand : JieziTheme.ink)
                }
            }

            HStack(spacing: 10) {
                Button { Task { await appState.retryStagingRecord(record) } } label: {
                    if appState.inboxActionRecordId == record.id { ProgressView().frame(maxWidth: .infinity) }
                    else { Label("重新识别", systemImage: "arrow.clockwise").frame(maxWidth: .infinity) }
                }
                .buttonStyle(.borderedProminent)
                .tint(JieziTheme.brand)

                Button(role: .destructive) { showDiscardConfirm = true } label: {
                    Label("销毁", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        .disabled(appState.inboxActionRecordId != nil)
    }

    private func detailCard(_ title: String, rows: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 10)
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                detailRow(row.0, row.1).padding(.vertical, 8)
                if index < rows.count - 1 { Divider() }
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).multilineTextAlignment(.trailing)
        }
    }

    private var statusColor: Color {
        switch record.status {
        case "ai_error", "failed", "extraction_failed", "schema_failed": return JieziTheme.coral
        case "routing_failed", "unrouted", "unassigned": return JieziTheme.gold
        default: return JieziTheme.brand
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
    let onRetry: () -> Void

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
            Button(action: onRetry) {
                Label("截图加载失败，点此重新签名", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.brand)
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct StagingImagePreviewRoute: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
