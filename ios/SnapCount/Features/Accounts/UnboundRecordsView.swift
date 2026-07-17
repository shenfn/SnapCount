import SwiftUI

struct UnboundRecordsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMonthKey = Self.currentMonthKey
    @State private var filter: UnboundRecordFilter = .all
    @State private var bindingRequest: UnboundBindingRequest?
    @State private var accountSelectionRecord: NativeUnboundRecord?
    @State private var showBatchSheet = false

    private var visibleRecords: [NativeUnboundRecord] {
        switch filter {
        case .all: return appState.unboundRecords
        case .expense: return appState.unboundRecords.filter { $0.kind == .expense }
        case .income: return appState.unboundRecords.filter { $0.kind == .income }
        }
    }

    private var batchCandidates: [NativeUnboundBindingCandidate] {
        NativeAccountRecommendationEngine.candidates(records: visibleRecords, accounts: appState.accounts)
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    monthPicker
                    Picker("记录类型", selection: $filter) {
                        ForEach(UnboundRecordFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if !batchCandidates.isEmpty {
                    Section {
                        Button {
                            showBatchSheet = true
                        } label: {
                            Label("预览并批量补绑 \(batchCandidates.count) 条推荐记录", systemImage: "checklist")
                        }
                        .disabled(appState.isBindingUnboundRecords)
                    }
                }

                if appState.isLoadingUnboundRecords && appState.unboundRecords.isEmpty {
                    ProgressView("正在加载未绑定记录…")
                        .frame(maxWidth: .infinity)
                } else if visibleRecords.isEmpty {
                    ContentUnavailableView(
                        "这个月份没有待补绑记录",
                        systemImage: "checkmark.circle",
                        description: Text("只有已完成且尚未绑定账户的消费、收入会显示在这里。")
                    )
                } else {
                    Section("待补绑") {
                        ForEach(visibleRecords) { record in
                            unboundRow(record)
                        }
                    }
                }

                if let message = appState.unboundBindingMessage {
                    Section { Text(message).font(.footnote).foregroundStyle(.secondary) }
                } else if let message = appState.unboundRecordsMessage {
                    Section {
                        Button("加载失败，点此重试：\(message)") {
                            Task { await appState.loadUnboundRecords(monthKey: selectedMonthKey) }
                        }
                        .foregroundStyle(JieziTheme.coral)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
        }
        .navigationTitle("未绑定记录")
        .task(id: selectedMonthKey) { await reload() }
        .confirmationDialog(
            "确认补绑账户？",
            isPresented: Binding(
                get: { bindingRequest != nil },
                set: { if !$0 { bindingRequest = nil } }
            ),
            titleVisibility: .visible,
            presenting: bindingRequest
        ) { request in
            Button("绑定到\(request.account.name)") {
                Task {
                    _ = await appState.bindUnboundRecord(
                        request.record,
                        accountId: request.account.id,
                        monthKey: selectedMonthKey
                    )
                }
            }
            Button("取消", role: .cancel) {}
        } message: { request in
            Text(balanceImpact(record: request.record, account: request.account))
        }
        .sheet(item: $accountSelectionRecord) { record in
            UnboundAccountPicker(record: record, monthKey: selectedMonthKey)
        }
        .sheet(isPresented: $showBatchSheet) {
            UnboundBatchBindingSheet(candidates: batchCandidates, monthKey: selectedMonthKey)
        }
    }

    private var monthPicker: some View {
        JieziMonthSwitcher(
            title: monthTitle,
            selectionToken: selectedMonthKey,
            canAdvance: selectedMonthKey < Self.currentMonthKey,
            onPrevious: { shiftMonth(-1) },
            onNext: { shiftMonth(1) }
        )
    }

    private func unboundRow(_ record: NativeUnboundRecord) -> some View {
        let recommendation = NativeAccountRecommendationEngine.recommendation(
            for: record,
            accounts: appState.accounts
        )
        return HStack(spacing: 12) {
            Button {
                appState.openUnboundRecord(record)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: record.kind.systemImage)
                        .foregroundStyle(record.kind == .income ? JieziTheme.mint : JieziTheme.coral)
                        .frame(width: 34, height: 34)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text("\(record.date) · \(record.kind.title)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        if let recommendation {
                            Text("\(recommendation.account.name) · \(recommendation.reason)")
                                .font(.caption2)
                                .foregroundStyle(JieziTheme.brand)
                                .lineLimit(2)
                        }
                    }
                }
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text((record.kind == .income ? "+" : "-") + String(format: "¥%.2f", record.amount))
                    .font(.subheadline.monospacedDigit())
                Button(recommendation == nil ? "选择账户" : "绑定") {
                    if let recommendation {
                        bindingRequest = UnboundBindingRequest(
                            record: record,
                            account: recommendation.account
                        )
                    } else {
                        accountSelectionRecord = record
                    }
                }
                .buttonStyle(.borderless)
                .disabled(appState.isBindingUnboundRecords)
            }
        }
        .padding(.vertical, 4)
    }

    private func balanceImpact(record: NativeUnboundRecord, account: NativeAccount) -> String {
        let change: String
        if record.kind == .income {
            change = account.type.isLiability ? "负债增加" : "余额增加"
        } else {
            change = account.type.isLiability ? "欠款增加" : "余额减少"
        }
        return "保存后会生成账户流水，\(account.name)\(change) ¥\(String(format: "%.2f", record.amount))。"
    }

    private func reload() async {
        if appState.accounts.isEmpty { await appState.loadAccounts() }
        await appState.loadUnboundRecords(monthKey: selectedMonthKey)
    }

    private var monthTitle: String {
        NativeMonthKey.title(selectedMonthKey)
    }

    private func shiftMonth(_ offset: Int) {
        guard let shifted = NativeMonthKey.shifted(selectedMonthKey, by: offset) else { return }
        selectedMonthKey = shifted
    }

    private static var currentMonthKey: String { NativeMonthKey.current() }
}

private enum UnboundRecordFilter: String, CaseIterable, Identifiable {
    case all, expense, income
    var id: String { rawValue }
    var title: String { switch self { case .all: return "全部"; case .expense: return "支出"; case .income: return "收入" } }
}

private struct UnboundBindingRequest: Identifiable {
    let record: NativeUnboundRecord
    let account: NativeAccount
    var id: String { "\(record.kind.rawValue)-\(record.id)-\(account.id)" }
}

private struct UnboundAccountPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let record: NativeUnboundRecord
    let monthKey: String

    private var accounts: [NativeAccount] { appState.accounts.filter { !$0.isArchived } }

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    Task {
                        if await appState.bindUnboundRecord(record, accountId: account.id, monthKey: monthKey) {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        Label(account.title, systemImage: account.type.systemImage)
                        Spacer()
                        Text(String(format: "¥%.2f", account.currentBalance))
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(appState.isBindingUnboundRecords)
            }
            .navigationTitle("选择账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
    }
}

private struct UnboundBatchBindingSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let candidates: [NativeUnboundBindingCandidate]
    let monthKey: String
    @State private var selectedIds: Set<String>

    init(candidates: [NativeUnboundBindingCandidate], monthKey: String) {
        self.candidates = candidates
        self.monthKey = monthKey
        _selectedIds = State(initialValue: Set(candidates.map(\.id)))
    }

    private var groups: [UnboundBatchGroup] {
        Dictionary(grouping: candidates, by: { $0.recommendation.account.id })
            .values
            .compactMap { items in
                items.first.map {
                    UnboundBatchGroup(account: $0.recommendation.account, candidates: items)
                }
            }
            .sorted { $0.candidates.count > $1.candidates.count }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups) { group in
                    Section(group.account.title) {
                        ForEach(group.candidates) { candidate in
                            Button {
                                if selectedIds.contains(candidate.id) {
                                    selectedIds.remove(candidate.id)
                                } else {
                                    selectedIds.insert(candidate.id)
                                }
                            } label: {
                                HStack {
                                    Image(systemName: selectedIds.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                                    VStack(alignment: .leading) {
                                        Text(candidate.record.title)
                                        Text(candidate.recommendation.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(String(format: "¥%.2f", candidate.record.amount))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("批量补绑预览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认 \(selectedIds.count) 条") {
                        Task {
                            let selected = candidates.filter { selectedIds.contains($0.id) }
                            if await appState.batchBindUnboundRecords(selected, monthKey: monthKey) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(selectedIds.isEmpty || appState.isBindingUnboundRecords)
                }
            }
        }
    }
}

private struct UnboundBatchGroup: Identifiable {
    let account: NativeAccount
    let candidates: [NativeUnboundBindingCandidate]
    var id: String { account.id }
}
