import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var editDraft: NativeAccountDraft?

    private var activeAccounts: [NativeAccount] { appState.accounts.filter { !$0.isArchived } }
    private var assetAccounts: [NativeAccount] { activeAccounts.filter { !$0.type.isLiability } }
    private var liabilityAccounts: [NativeAccount] { activeAccounts.filter(\.type.isLiability) }
    private var archivedAccounts: [NativeAccount] { appState.accounts.filter(\.isArchived) }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                if appState.isLoadingAccounts && appState.accounts.isEmpty {
                    ProgressView("正在加载账户…")
                        .frame(maxWidth: .infinity)
                }

                if let message = appState.accountMessage, appState.accounts.isEmpty {
                    Button("加载失败，点此重试：\(message)") {
                        Task { await appState.loadAccounts() }
                    }
                    .foregroundStyle(JieziTheme.coral)
                }

                accountSection("资产账户", accounts: assetAccounts)
                accountSection("负债与待还", accounts: liabilityAccounts)

                if !archivedAccounts.isEmpty {
                    Section("已归档") {
                        ForEach(archivedAccounts) { account in
                            NavigationLink(value: account.id) {
                                AccountRowView(account: account)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                if !appState.isLoadingAccounts,
                   appState.accounts.isEmpty,
                   appState.accountMessage == nil {
                    ContentUnavailableView(
                        "暂无账户",
                        systemImage: "wallet.pass",
                        description: Text("创建账户后，消费和收入可以绑定到账户流水。")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await appState.loadAccounts() }
        }
        .navigationTitle("账户与钱包")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink {
                    UnboundRecordsView()
                } label: {
                    Label("未绑定记录", systemImage: "link.badge.plus")
                }
                Button {
                    editDraft = NativeAccountDraft()
                } label: {
                    Label("新建账户", systemImage: "plus")
                }
            }
        }
        .navigationDestination(for: String.self) { id in
            if let account = appState.accounts.first(where: { $0.id == id }) {
                AccountDetailView(accountId: account.id)
            }
        }
        .sheet(item: $editDraft) { draft in
            AccountEditSheet(draft: draft)
        }
        .task {
            if appState.accounts.isEmpty { await appState.loadAccounts() }
        }
    }

    @ViewBuilder
    private func accountSection(_ title: String, accounts: [NativeAccount]) -> some View {
        if !accounts.isEmpty {
            Section(title) {
                ForEach(accounts) { account in
                    NavigationLink(value: account.id) {
                        AccountRowView(account: account)
                    }
                }
            }
        }
    }
}

private struct AccountRowView: View {
    let account: NativeAccount

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: account.type.systemImage)
                .foregroundStyle(account.type.isLiability ? JieziTheme.coral : JieziTheme.brand)
                .frame(width: 34, height: 34)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(account.title).font(.subheadline.weight(.semibold))
                    if account.isDefaultExpense { Image(systemName: "arrow.up.circle.fill") }
                    if account.isDefaultIncome { Image(systemName: "arrow.down.circle.fill") }
                }
                Text(account.type.title + (account.institution.isEmpty ? "" : " · \(account.institution)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(String(format: "¥%.2f", account.currentBalance))
                .font(.subheadline.monospacedDigit())
        }
    }
}

private struct AccountDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let accountId: String
    @State private var editDraft: NativeAccountDraft?
    @State private var showArchiveConfirmation = false

    private var account: NativeAccount? { appState.accounts.first { $0.id == accountId } }
    private var detail: NativeAccountDetail? {
        appState.selectedAccountDetail?.account.id == accountId ? appState.selectedAccountDetail : nil
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            if let account {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(account.type.isLiability ? "当前待还" : "当前余额")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(format: "¥%.2f", account.currentBalance))
                                .font(.largeTitle.bold().monospacedDigit())
                            Text(account.type.title + (account.institution.isEmpty ? "" : " · \(account.institution)"))
                                .foregroundStyle(.secondary)
                        }
                    }

                    if account.type.isLiability {
                        Section("还款设置") {
                            LabeledContent("账单日", value: account.billDay.map { "每月\($0)日" } ?? "未设置")
                            LabeledContent("还款日", value: account.paymentDueDay.map { "每月\($0)日" } ?? "未设置")
                            LabeledContent("自动确认", value: account.autoConfirmRepayment ? "已开启" : "需手动确认")
                        }
                    }

                    if let cycles = detail?.repaymentCycles, !cycles.isEmpty {
                        Section("还款计划") {
                            ForEach(cycles) { cycle in
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(cycle.cycleMonth).font(.subheadline.weight(.semibold))
                                        Spacer()
                                        Text(cycle.status.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text("应还 ¥\(amount(cycle.statementAmount)) · 剩余 ¥\(amount(cycle.remainingAmount))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let detail {
                        Section("账户概览") {
                            LabeledContent("初始余额", value: "¥\(amount(account.initialBalance))")
                            LabeledContent("有效流水", value: "\(detail.entries.filter { !$0.isVoided }.count) 条")
                            LabeledContent("有效净额", value: String(format: "%+.2f", activeNet(detail.entries)))
                        }
                    }

                    if let entries = detail?.entries, !entries.isEmpty {
                        Section("账户流水") {
                            ForEach(entries) { entry in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(entry.note.isEmpty ? entry.entryType : entry.note).font(.subheadline)
                                        Text(entry.occurredAt).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text((entry.direction == "in" ? "+" : "-") + "¥" + amount(entry.amount))
                                        .foregroundStyle(entry.isVoided ? .secondary : (entry.direction == "in" ? JieziTheme.mint : JieziTheme.coral))
                                        .strikethrough(entry.isVoided)
                                }
                            }
                        }
                    }

                    if let payments = detail?.payments, !payments.isEmpty {
                        Section("还款记录") {
                            ForEach(payments) { payment in
                                HStack {
                                    VStack(alignment: .leading) {
                                        Text(payment.status == "voided" ? "已撤销还款" : "已确认还款").font(.subheadline)
                                        Text(payment.paidAt + (payment.note.isEmpty ? "" : " · \(payment.note)"))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("¥\(amount(payment.amount))")
                                        .strikethrough(payment.status == "voided")
                                        .foregroundStyle(payment.status == "voided" ? .secondary : JieziTheme.brand)
                                }
                            }
                        }
                    }

                    if detail == nil {
                        ProgressView("正在加载账户详情…").frame(maxWidth: .infinity)
                    }

                    if let message = appState.accountMessage {
                        Section { Text(message).foregroundStyle(JieziTheme.coral) }
                    }
                }
                .scrollContentBackground(.hidden)
                .navigationTitle(account.title)
                .toolbar {
                    Button {
                        editDraft = NativeAccountDraft(account: account)
                    } label: {
                        Label("编辑账户", systemImage: "square.and.pencil")
                    }
                    Button(role: account.isArchived ? nil : .destructive) {
                        showArchiveConfirmation = true
                    } label: {
                        Label(account.isArchived ? "恢复账户" : "归档账户", systemImage: account.isArchived ? "arrow.uturn.backward" : "archivebox")
                    }
                }
                .sheet(item: $editDraft) { draft in AccountEditSheet(draft: draft) }
                .confirmationDialog(
                    account.isArchived ? "恢复这个账户？" : "归档这个账户？",
                    isPresented: $showArchiveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button(account.isArchived ? "恢复" : "归档", role: account.isArchived ? nil : .destructive) {
                        Task {
                            _ = await appState.setAccountArchived(account, archived: !account.isArchived)
                        }
                    }
                    Button("取消", role: .cancel) {}
                } message: {
                    Text(account.isArchived ? "恢复后可重新作为记录绑定候选。" : "归档不会删除历史流水，也不会修改当前余额。")
                }
                .task(id: account.id) { await appState.loadAccountDetail(account) }
            } else {
                ContentUnavailableView("账户不存在", systemImage: "wallet.pass", description: Text("它可能已被其他设备删除。"))
            }
        }
    }

    private func amount(_ value: Double) -> String { String(format: "%.2f", value) }
    private func activeNet(_ entries: [NativeAccountEntry]) -> Double {
        entries.filter { !$0.isVoided }.reduce(0) { $0 + ($1.direction == "in" ? $1.amount : -$1.amount) }
    }
}

private struct AccountEditSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeAccountDraft
    @State private var message: String?

    init(draft: NativeAccountDraft) {
        _draft = State(initialValue: draft)
    }

    private var debitAccounts: [NativeAccount] {
        appState.accounts.filter { !$0.isArchived && !$0.type.isLiability && $0.id != draft.accountId }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("账户名称", text: $draft.name)
                    Picker("账户类型", selection: $draft.type) {
                        ForEach(NativeAccountType.allCases, id: \.self) { type in
                            Text(type.title).tag(type)
                        }
                    }
                    TextField("机构", text: $draft.institution)
                    TextField("尾号", text: $draft.last4)
                        .keyboardType(.numberPad)
                    if draft.isCreating {
                        TextField("初始余额", text: $draft.initialBalanceText)
                            .keyboardType(.decimalPad)
                    } else {
                        LabeledContent("初始余额", value: "创建后不可直接修改")
                    }
                }

                if draft.type.isLiability {
                    Section("负债设置") {
                        TextField("账单日（1-31）", text: $draft.billDayText).keyboardType(.numberPad)
                        TextField("还款日（1-31）", text: $draft.paymentDueDayText).keyboardType(.numberPad)
                        Picker("自动扣款账户", selection: $draft.autoDebitAccountId) {
                            Text("不设置").tag(String?.none)
                            ForEach(debitAccounts) { account in
                                Text(account.title).tag(String?.some(account.id))
                            }
                        }
                        Toggle("高置信度截图自动确认", isOn: $draft.autoConfirmRepayment)
                    }
                }

                Section("默认账户") {
                    Toggle("默认支出账户", isOn: $draft.isDefaultExpense)
                    Toggle("默认收入账户", isOn: $draft.isDefaultIncome)
                    Text("保存后会自动取消其他账户的同类默认状态。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if !draft.isCreating {
                    Section("状态") {
                        Toggle("已归档", isOn: $draft.isArchived)
                    }
                }

                if let message {
                    Section { Text(message).foregroundStyle(JieziTheme.coral) }
                }
            }
            .navigationTitle(draft.isCreating ? "新建账户" : "编辑账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(appState.isSavingAccount)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if appState.isSavingAccount { ProgressView() } else { Text("保存") }
                    }
                    .disabled(appState.isSavingAccount)
                }
            }
        }
    }

    private func save() async {
        if let validationMessage = draft.validationMessage {
            message = validationMessage
            return
        }
        message = nil
        if await appState.saveAccount(draft) {
            dismiss()
        } else {
            message = appState.accountMessage
        }
    }
}
