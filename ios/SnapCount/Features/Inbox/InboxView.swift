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

                if let message = appState.inboxFinanceMessage {
                    Section { Text(message).foregroundStyle(JieziTheme.brand) }
                }

                if let message = appState.inboxActionMessage {
                    Section {
                        Label(
                            message,
                            systemImage: appState.inboxActionRecordId == nil
                                ? (appState.inboxActionMessageIsError ? "exclamationmark.circle" : "checkmark.circle")
                                : "hourglass"
                        )
                        .foregroundStyle(appState.inboxActionMessageIsError ? JieziTheme.coral : JieziTheme.brand)
                    }
                }

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
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadInboxRepaymentCandidates()
            }
        }
        .navigationTitle("中转站")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
        .task { await appState.loadInboxRepaymentCandidates() }
    }

    @ViewBuilder
    private func inboxRow(_ item: NativeInboxItem) -> some View {
        if let pending = item.pendingExpense {
            NavigationLink(value: NativeInboxRoute.record(reference: pending.reference)) {
                NativeInboxItemRow(item: item, repaymentCandidate: nil)
            }
        } else if let record = item.stagingRecord {
            NavigationLink(value: NativeInboxRoute.staging(recordId: record.id)) {
                NativeInboxItemRow(
                    item: item,
                    repaymentCandidate: appState.repaymentCandidates[record.id]
                )
            }
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
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
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
                            .frame(height: 32)
                            .background(filter == item ? JieziTheme.brand : JieziTheme.line.opacity(0.45), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func filterCount(_ filter: NativeInboxFilter) -> Int {
        NativeInboxPresentation.filtered(allItems, by: filter).count
    }

    private static func dateKey(daysFromToday: Int) -> String {
        let date = Calendar.current.date(byAdding: .day, value: daysFromToday, to: Date()) ?? Date()
        return date.formatted(.iso8601.year().month().day())
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
                optionMenu("消费渠道", selection: draft.platform, options: NativeManualRecordDraft.expensePlatforms)
                optionMenu("消费分类", selection: draft.category, options: NativeManualRecordDraft.expenseCategories)
                optionMenu("支付方式", selection: draft.paymentMethod, options: NativeManualRecordDraft.expensePayments)
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
                Button(option.title) { selection.wrappedValue = option.id }
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
