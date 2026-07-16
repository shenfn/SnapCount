import SwiftUI

struct RecordsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedKind: NativeDayRecordKind = .all
    @State private var selectedMonthKey = RecordsView.currentMonthKey
    @State private var showManualRecordSheet = false

    private var query: NativeRecordQuery { NativeRecordQuery(monthKey: selectedMonthKey, kind: selectedKind) }
    private var groups: [NativeDayRecordGroup] { query.groups(from: appState.dashboard.dayRecordGroups) }
    private var availableKinds: [NativeDayRecordKind] { query.availableKinds(from: appState.dashboard.dayRecordGroups) }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    HStack {
                        Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
                        Spacer()
                        Text(monthTitle).font(.headline.monospacedDigit())
                        Spacer()
                        Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                            .disabled(selectedMonthKey >= Self.currentMonthKey)
                    }
                    Picker("数据域", selection: $selectedKind) {
                        ForEach(availableKinds) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                if groups.isEmpty {
                    ContentUnavailableView("本月还没有记录", systemImage: "doc.text.magnifyingglass", description: Text("截图识别或手动记录后，会按日期出现在这里。"))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(groups) { group in
                        Section(dayTitle(group.dateKey)) {
                            ForEach(group.records) { item in
                                NavigationLink(value: NativeRecordRoute(reference: item.reference)) {
                                    HStack(spacing: 12) {
                                        Image(systemName: item.systemImage)
                                            .foregroundStyle(JieziTheme.mint)
                                            .frame(width: 34, height: 34)
                                            .background(JieziTheme.brand.opacity(0.08), in: Circle())
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.title).font(.headline)
                                            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        }
                                        Spacer()
                                        VStack(alignment: .trailing, spacing: 3) {
                                            Text(item.value).font(.subheadline.monospacedDigit())
                                            Text(item.timeLabel ?? "全天").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await appState.refreshDashboard() }
        }
        .navigationTitle("记录")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showManualRecordSheet = true
                } label: {
                    Label("新增记录", systemImage: "plus")
                }
                NavigationLink { AccountsView() } label: { Label("账户", systemImage: "wallet.pass") }
                NavigationLink { DomainsView() } label: { Label("数据域", systemImage: "square.stack.3d.up") }
            }
        }
        .navigationDestination(for: NativeRecordRoute.self) { route in
            RecordDetailView(reference: route.reference)
        }
        .onChange(of: availableKinds) { kinds in if !kinds.contains(selectedKind) { selectedKind = .all } }
        .task(id: prefetchKey) {
            appState.prefetchRecordDetails(groups.flatMap(\.records).map(\.reference))
        }
        .sheet(isPresented: $showManualRecordSheet) {
            ManualRecordSheet()
        }
    }

    private var prefetchKey: String { "\(selectedMonthKey):\(selectedKind.rawValue):\(groups.count)" }

    private var monthTitle: String {
        let parts = selectedMonthKey.split(separator: "-")
        guard parts.count == 2 else { return selectedMonthKey }
        return "\(parts[0])年\(Int(parts[1]) ?? 0)月"
    }

    private func dayTitle(_ dateKey: String) -> String { String(dateKey.suffix(5)) }

    private func shiftMonth(_ offset: Int) {
        guard let date = Self.monthFormatter.date(from: selectedMonthKey),
              let shifted = Calendar(identifier: .gregorian).date(byAdding: .month, value: offset, to: date) else { return }
        selectedMonthKey = Self.monthFormatter.string(from: shifted)
        selectedKind = .all
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM"; return formatter
    }()
    private static var currentMonthKey: String { monthFormatter.string(from: Date()) }
}

struct RecordDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let reference: String
    @State private var imagePreview: ImagePreviewRoute?
    @State private var editDraft: NativeRecordEditDraft?
    @State private var universalEditDetail: NativeRecordDetail?
    @State private var showDeleteConfirm = false

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            if let detail = appState.selectedRecordDetail {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if let imageURL = detail.imageURL {
                            Button {
                                imagePreview = ImagePreviewRoute(url: imageURL)
                            } label: {
                                RecordImagePreview(url: imageURL)
                            }
                            .buttonStyle(.plain)
                        } else if detail.imageLoadError {
                            unavailableImageView
                        }

                        recordHeader(detail)

                        detailSection(
                            title: "基本信息",
                            rows: NativeRecordDetailPresentationAdapter.basicRows(
                                for: detail,
                                accountName: accountName(for: detail)
                            )
                        )

                        detailSection(
                            title: "抽取字段",
                            rows: NativeRecordDetailPresentationAdapter.extractedRows(for: detail)
                        )

                        let dishes = NativeRecordDetailPresentationAdapter.foodDishes(for: detail)
                        if !dishes.isEmpty {
                            foodDishesSection(dishes)
                        }

                        if let feedback = detail.aiFeedback {
                            NativeAIFeedbackCard(
                                feedback: feedback,
                                reviewable: true,
                                reviewState: appState.recordFeedbackState
                            ) { choice, text in
                                Task { await appState.submitRecordFeedback(choice: choice, freeText: text) }
                            }
                        }

                        if let companionMessage = detail.companionMessage, !companionMessage.isEmpty {
                            companionSection(companionMessage)
                        }

                        summarySection(NativeRecordDetailPresentationAdapter.aiSummary(for: detail))
                        actionSection(detail)
                    }
                    .padding(16)
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
        .toolbar {
            if let detail = appState.selectedRecordDetail {
                if detail.isEditable {
                    Button {
                        if detail.kind == "data" {
                            universalEditDetail = detail
                        } else {
                            editDraft = NativeRecordEditDraft(detail: detail)
                        }
                    } label: {
                        Label("编辑", systemImage: "square.and.pencil")
                    }
                    .disabled(appState.isSavingRecordDetail)
                }

                if detail.isDeletable {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(appState.isDeletingRecordDetail)
                }
            }
        }
        .task(id: reference) {
            await appState.loadRecordDetail(reference: reference)
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
        Label("截图文件不可用或已删除", systemImage: "photo.badge.exclamationmark")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private func recordHeader(_ detail: NativeRecordDetail) -> some View {
        HStack(spacing: 12) {
            Image(systemName: detail.systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
                .frame(width: 40, height: 40)
                .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 4) {
                Text(detail.title).font(.headline)
                Text(detail.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if !detail.value.isEmpty {
                Text(detail.value).font(.headline.monospacedDigit())
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func detailSection(title: String, rows: [NativeDetailRow]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.headline).padding(.bottom, 12)
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .top, spacing: 16) {
                    Text(row.label).font(.subheadline).foregroundStyle(.secondary).frame(width: 82, alignment: .leading)
                    Text(row.value).font(.subheadline).frame(maxWidth: .infinity, alignment: .trailing).multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
                if index < rows.count - 1 { Divider() }
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func foodDishesSection(_ dishes: [NativeFoodDish]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("菜品明细").font(.headline)
            ForEach(dishes) { dish in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(dish.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        if let calories = dish.calories { Text("\(Int(calories.rounded())) kcal").font(.caption.monospacedDigit()) }
                    }
                    HStack(spacing: 12) {
                        if let protein = dish.protein { Text("蛋白 \(protein, specifier: "%.1f")g") }
                        if let carbs = dish.carbs { Text("碳水 \(carbs, specifier: "%.1f")g") }
                        if let fat = dish.fat { Text("脂肪 \(fat, specifier: "%.1f")g") }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(JieziTheme.brand.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
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

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI 摘要").font(.headline)
            Text(summary).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func actionSection(_ detail: NativeRecordDetail) -> some View {
        HStack(spacing: 12) {
            if detail.isEditable {
                Button {
                    if detail.kind == "data" { universalEditDetail = detail }
                    else { editDraft = NativeRecordEditDraft(detail: detail) }
                } label: {
                    Label(detail.status == "pending" ? "补充信息" : "编辑", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(JieziTheme.brand)
            }
            if detail.isDeletable {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func accountName(for detail: NativeRecordDetail) -> String? {
        guard let accountId = detail.accountId else { return nil }
        return appState.accounts.first(where: { $0.id == accountId })?.title ?? accountId
    }
}

private struct RecordImagePreview: View {
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
            Form {
                Section(draft.kind == "income" ? "收入" : "消费") {
                    TextField(draft.kind == "income" ? "来源" : "商户", text: $draft.title)
                    TextField("金额", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                    TextField("日期", text: $draft.recordDate)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if draft.kind == "expense" {
                    Section("消费字段") {
                        TextField("平台", text: $draft.platform)
                        TextField("分类", text: $draft.category)
                        TextField("支付方式", text: $draft.paymentMethod)
                    }
                } else {
                    Section("收入字段") {
                        TextField("类型", text: $draft.category)
                    }
                }

                Section("账户") {
                    Picker("绑定账户", selection: $draft.accountId) {
                        Text("不绑定账户").tag(String?.none)
                        ForEach(accountCandidates) { account in
                            Text(account.title).tag(String?.some(account.id))
                        }
                    }
                    Text("保存后由服务端原子更新记录与账户流水，不会在客户端直接修改余额。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("备注") {
                    TextField("备注", text: $draft.note, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(JieziTheme.coral)
                    }
                }
            }
            .task {
                if appState.accounts.isEmpty { await appState.loadAccounts() }
            }
            .navigationTitle("编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task {
                            await save()
                        }
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(isSaving)
                }
            }
        }
    }

    private var accountCandidates: [NativeAccount] {
        appState.accounts.filter { !$0.isArchived || $0.id == draft.accountId }
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
