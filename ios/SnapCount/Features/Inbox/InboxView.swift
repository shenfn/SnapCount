import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var appState: AppState
    @State private var filter: NativeInboxFilter = .all
    @State private var stageRecordId: String?

    private var allItems: [NativeInboxItem] {
        NativeInboxPresentation.items(
            pendingExpenses: appState.dashboard.pendingExpenses,
            stagingRecords: appState.dashboard.stagingRecords
        )
    }

    private var sections: [NativeInboxSection] {
        NativeInboxPresentation.sections(
            from: filteredItems,
            today: Self.dateKey(daysFromToday: 0),
            yesterday: Self.dateKey(daysFromToday: -1)
        )
    }

    private var filteredItems: [NativeInboxItem] {
        NativeInboxPresentation.filtered(allItems, by: filter)
    }

    private var stageRecords: [NativeStagingRecord] {
        filteredItems.compactMap(\.stagingRecord)
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
                LazyVStack(alignment: .leading, spacing: 0) {
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
                        filterPicker

                        if sections.isEmpty {
                            ContentUnavailableView(
                                "当前筛选为空",
                                systemImage: "line.3.horizontal.decrease.circle"
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.top, 72)
                        } else {
                            ForEach(sections) { section in
                                VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                                    Text(section.title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(JieziTheme.muted)
                                        .padding(.leading, 2)

                                    LazyVGrid(
                                        columns: [
                                            GridItem(.flexible(), spacing: JieziSpacing.md),
                                            GridItem(.flexible(), spacing: JieziSpacing.md)
                                        ],
                                        spacing: JieziSpacing.md
                                    ) {
                                        ForEach(section.items) { item in inboxCell(item) }
                                    }
                                }
                                .padding(.horizontal, JieziSpacing.Semantic.card_padding)
                                .padding(.bottom, JieziSpacing.xl2)
                            }
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
        .navigationTitle("中转站")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .navigationDestination(for: NativeInboxRoute.self) { route in
            switch route {
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

    @ViewBuilder
    private func inboxCell(_ item: NativeInboxItem) -> some View {
        if let pending = item.pendingExpense {
            NavigationLink(value: NativeInboxRoute.record(reference: pending.reference)) {
                NativeInboxFilmCard(item: item, repaymentCandidate: nil)
            }
            .buttonStyle(.plain)
        } else if let record = item.stagingRecord {
            Button {
                stageRecordId = record.id
            } label: {
                NativeInboxFilmCard(
                    item: item,
                    repaymentCandidate: appState.repaymentCandidates[record.id]
                )
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.985))
        }
    }

    private var pendingSummary: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(allItems.isEmpty ? "微尘皆已落定" : "\(allItems.count) 份证据待你裁决")
                .font(.subheadline)
                .foregroundStyle(JieziTheme.muted)
            Spacer()
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.top, JieziSpacing.sm)
        .padding(.bottom, JieziSpacing.md)
    }

    private var filterPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: JieziSpacing.sm) {
                ForEach(NativeInboxFilter.allCases) { item in
                    Button {
                        filter = item
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.title)
                            Text("\(filterCount(item))")
                                .font(.caption2.monospacedDigit())
                                .opacity(0.8)
                        }
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(filter == item ? Color.white : JieziTheme.ink)
                            .padding(.horizontal, 12)
                            .frame(height: 34)
                            .background(
                                filter == item ? JieziTheme.brand : Color.white.opacity(0.58),
                                in: Capsule()
                            )
                            .overlay(Capsule().stroke(JieziTheme.brand.opacity(filter == item ? 0 : 0.11)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, JieziSpacing.xl2)
        }
        .padding(.bottom, JieziSpacing.Semantic.card_padding)
    }

    private func filterCount(_ filter: NativeInboxFilter) -> Int {
        NativeInboxPresentation.filtered(allItems, by: filter).count
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

    private static func dateKey(daysFromToday: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return date.formatted(.iso8601.year().month().day())
    }
}

private struct NativeInboxFilmCard: View {
    let item: NativeInboxItem
    let repaymentCandidate: NativeRepaymentCandidate?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                filmContent
                InboxFilmStateBadge(label: item.statusLabel, color: statusColor)
                    .padding(8)
            }
            .aspectRatio(3 / 4, contentMode: .fit)
            .clipped()

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.ink)
                        .lineLimit(1)
                    if let record = item.stagingRecord {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("记录 \(record.occurredAtLabel ?? "未识别")")
                            Text("上传 \(record.createdAtLabel)")
                        }
                        .font(.caption2)
                        .foregroundStyle(JieziTheme.muted)
                    } else if let pending = item.pendingExpense {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("记录 \(pending.occurredAtLabel ?? pending.dateKey)")
                            Text("上传 \(pending.createdAtLabel)")
                        }
                        .font(.caption2)
                        .foregroundStyle(JieziTheme.muted)
                    }
                }
                Spacer(minLength: 4)
                if repaymentCandidate != nil {
                    Image(systemName: "creditcard.and.123")
                        .font(.caption2)
                        .foregroundStyle(JieziTheme.brand)
                } else if let confidence = item.stagingRecord?.confidencePercent {
                    Text("\(confidence)%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(JieziTheme.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
        }
        .background(Color.white.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                .stroke(JieziTheme.brand.opacity(0.12), lineWidth: 1)
        }
        .shadow(color: JieziTheme.space.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    @ViewBuilder
    private var filmContent: some View {
        if let url = item.stagingRecord?.imageURL ?? item.pendingExpense?.imageURL {
            CachedRemoteImage(url: url) { image in
                ZStack(alignment: .bottomLeading) {
                    image.resizable().scaledToFill()
                    LinearGradient(
                        colors: [.clear, JieziTheme.space.opacity(0.72)],
                        startPoint: .center,
                        endPoint: .bottom
                    )
                    Text(item.subtitle)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .padding(10)
                }
            } placeholder: {
                ProgressView().tint(JieziTheme.brand)
            } failure: {
                noteContent
            }
        } else {
            noteContent
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

private struct StagingVerdictStageView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let records: [NativeStagingRecord]
    @Binding var selection: String?
    let domains: [NativeArchiveDomain]

    @State private var showDiscardConfirmation = false
    @State private var showDetail = false

    private var currentIndex: Int {
        records.firstIndex(where: { $0.id == selection }) ?? 0
    }

    private var current: NativeStagingRecord? {
        guard !records.isEmpty else { return nil }
        return records[min(currentIndex, records.count - 1)]
    }

    private var pageSelection: Binding<String> {
        Binding(
            get: { selection ?? records.first?.id ?? "" },
            set: { selection = $0 }
        )
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
                    TabView(selection: pageSelection) {
                        ForEach(records) { record in
                            StagingStageImage(record: record)
                                .tag(record.id)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
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
            Text("这条截图将从芥子中散去，不会进入任何数据域。")
        }
        .sheet(isPresented: $showDetail) {
            if let current {
                NavigationStack { StagingRecordDetailView(record: current) }
            }
        }
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
                stageActionButton("ellipsis.circle", title: "详情") { showDetail = true }
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
        await appState.archiveStagingRecord(record, domainKey: domainId)
        finishAction(for: record.id)
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
        .padding(.horizontal, 26)
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
    @Environment(\.dismiss) private var dismiss
    let reference: String
    @State private var draft: NativePendingResolutionDraft?
    @State private var showDeleteConfirm = false

    private var detail: NativeRecordDetail? {
        guard appState.selectedRecordDetail?.id == reference else { return nil }
        return appState.selectedRecordDetail
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            if let detail, let draftBinding = Binding($draft) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(detail)
                        if let feedback = detail.aiFeedback {
                            NativeAIFeedbackCard(feedback: feedback, compact: true)
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
                            Task { _ = await appState.confirmPendingRecord(draftBinding.wrappedValue) }
                        } label: {
                            if appState.isConfirmingPendingRecord {
                                ProgressView().tint(.white).frame(maxWidth: .infinity)
                            } else {
                                Label("确认保存", systemImage: "checkmark.circle.fill").frame(maxWidth: .infinity)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(JieziTheme.brand)
                        .controlSize(.large)
                        .disabled(appState.isConfirmingPendingRecord || draftBinding.wrappedValue.validationMessage != nil)

                        Button(role: .destructive) { showDeleteConfirm = true } label: {
                            Label("删除此账单", systemImage: "trash").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(16)
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
        .confirmationDialog("删除这条待补全账单？", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                Task {
                    if await appState.deleteRecord(reference: reference) { dismiss() }
                }
            }
            Button("取消", role: .cancel) {}
        }
    }

    private func header(_ detail: NativeRecordDetail) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.title3.weight(.semibold))
                .foregroundStyle(JieziTheme.gold)
                .frame(width: 40, height: 40)
                .background(JieziTheme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.title).font(.headline)
                Text(detail.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("待补全").font(.caption.weight(.bold)).foregroundStyle(JieziTheme.gold)
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func imageSection(_ detail: NativeRecordDetail) -> some View {
        if let imageURL = detail.imageURL {
            CachedRemoteImage(url: imageURL) { image in
                image.resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 240)
            } placeholder: {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            } failure: {
                Label("截图文件不可用", systemImage: "photo.badge.exclamationmark")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
            .padding(8)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func amountSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("金额").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            HStack(spacing: 6) {
                Text(draft.wrappedValue.kind == .income ? "+¥" : "-¥")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(draft.wrappedValue.kind == .income ? JieziTheme.brand : JieziTheme.coral)
                TextField("0.00", text: draft.amountText)
                    .keyboardType(.decimalPad)
                    .font(.title2.weight(.bold).monospacedDigit())
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func typeSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("记录类型").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Picker("记录类型", selection: draft.kind) {
                ForEach(NativePendingEntryKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func fieldSection(_ draft: Binding<NativePendingResolutionDraft>) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.wrappedValue.kind == .income ? "收入字段" : "消费字段").font(.headline)
            TextField(draft.wrappedValue.kind == .income ? "来源名称（可选）" : "商家名称（可选）", text: draft.merchantOrSourceName)
                .textFieldStyle(.roundedBorder)
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
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
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
                Text(title).foregroundStyle(JieziTheme.ink)
                Spacer()
                Text(options.first(where: { $0.id == selection.wrappedValue })?.title ?? "请选择")
                    .foregroundStyle(selection.wrappedValue.isEmpty ? .secondary : JieziTheme.brand)
                Image(systemName: "chevron.up.chevron.down").font(.caption)
            }
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
                    .textFieldStyle(.roundedBorder)
                Menu {
                    ForEach(options) { option in
                        Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                            selection.wrappedValue = option.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.bordered)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
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
                    if let aiFeedback {
                        NativeAIFeedbackCard(feedback: aiFeedback, compact: true)
                    }
                    recognitionSection
                    if let companionMessage = record.companionMessage, !companionMessage.isEmpty {
                        companionSection(companionMessage)
                    }
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
                    await appState.archiveStagingRecord(record, domainKey: domain.id)
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
