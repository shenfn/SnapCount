import SwiftUI

struct ManualRecordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeManualRecordDraft
    @State private var localMessage: String?

    init(editing detail: NativeRecordDetail? = nil, kind: NativeManualRecordKind = .expense, domainKey: String = "sport") {
        _draft = State(
            initialValue: detail.map { NativeManualRecordDraft(detail: $0) }
                ?? NativeManualRecordDraft(kind: kind, domainKey: domainKey)
        )
    }

    private var universalDomains: [NativeDomainDefinition] {
        appState.dashboard.domains.filter { !["expense", "income"].contains($0.id) }
    }

    private var selectedDomain: NativeDomainDefinition? {
        universalDomains.first { $0.id == draft.domainKey }
    }

    private var metadata: NativeManualDomainMetadata {
        NativeManualDomainMetadata.resolve(selectedDomain, fallbackDomainKey: draft.domainKey)
    }

    private var accountCandidates: [NativeAccount] {
        appState.accounts.filter { !$0.isArchived }
    }

    private var expensePlatformOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(
            kind: .platform,
            currentValue: draft.platform,
            vocabulary: appState.financeVocabulary
        )
    }

    private var expenseCategoryOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(
            kind: .category,
            currentValue: draft.category,
            vocabulary: appState.financeVocabulary
        )
    }

    private var expensePaymentOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(
            kind: .payment,
            currentValue: draft.paymentMethod,
            vocabulary: appState.financeVocabulary
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if draft.existingRawId == nil {
                    Section {
                        Picker("记录类型", selection: $draft.kind) {
                            ForEach(NativeManualRecordKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } else {
                    Section {
                        LabeledContent("记录类型", value: selectedDomain?.shortName ?? "数据域")
                    }
                }

                switch draft.kind {
                case .expense:
                    expenseFields
                case .income:
                    incomeFields
                case .universal:
                    universalFields
                }

                dateFields

                Section("备注") {
                    TextField("补充说明", text: $draft.note, axis: .vertical)
                        .lineLimit(2...5)
                }

                if let message = localMessage ?? appState.manualRecordMessage {
                    Section {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(JieziTheme.coral)
                    }
                }
            }
            .navigationTitle(draft.existingRawId == nil ? "手动记录" : "编辑记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(appState.isCreatingManualRecord)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if appState.isCreatingManualRecord {
                            ProgressView()
                        } else {
                            Text("保存")
                        }
                    }
                    .disabled(appState.isCreatingManualRecord)
                }
            }
        }
        .task {
            if appState.accounts.isEmpty { await appState.loadAccounts() }
            await appState.loadFinanceVocabulary()
            normalizeDomainSelection()
            if draft.existingRawId == nil {
                applyDefaultAccount()
            } else {
                hydrateUniversalFields()
            }
        }
        .onChange(of: draft.kind) { _ in
            localMessage = nil
            if draft.kind == .universal { normalizeDomainSelection() }
            applyDefaultAccount()
        }
        .onChange(of: draft.domainKey) { _ in
            let fallback = NativeManualDomainMetadata.resolve(
                selectedDomain,
                fallbackDomainKey: draft.domainKey
            ).defaultDimension
            if draft.dimension.isEmpty { draft.dimension = fallback }
        }
    }

    private var expenseFields: some View {
        Group {
            Section("支出") {
                TextField("金额", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                TextField("商家名称（可选）", text: $draft.title)
                editableOptionField("消费渠道", selection: $draft.platform, options: expensePlatformOptions)
                optionPicker("消费分类", selection: $draft.category, options: expenseCategoryOptions)
                editableOptionField("支付方式", selection: $draft.paymentMethod, options: expensePaymentOptions)
            }
            accountSection(title: "出资账户")
        }
    }

    private var incomeFields: some View {
        Group {
            Section("收入") {
                TextField("金额", text: $draft.amountText)
                    .keyboardType(.decimalPad)
                TextField("来源名称（可选）", text: $draft.title)
                optionPicker("收入类型", selection: $draft.category, options: NativeManualRecordDraft.incomeCategories)
            }
            accountSection(title: "到账账户")
        }
    }

    private var universalFields: some View {
        Group {
            Section("数据域") {
                Picker("数据域", selection: $draft.domainKey) {
                    ForEach(universalDomains) { domain in
                        Text("\(domain.icon) \(domain.shortName)").tag(domain.id)
                    }
                }
                TextField("标题（可选）", text: $draft.title)
                TextField(metadata.dimensionLabel, text: $draft.dimension)
                TextField(metadata.primaryLabel, text: $draft.primaryValueText)
                    .keyboardType(.decimalPad)
            }

            if draft.domainKey == "wallet" {
                Section("钱包快照") {
                    Picker("记录类型", selection: $draft.walletRecordKind) {
                        Text("资产余额").tag("cash_snapshot")
                        Text("负债待还").tag("liability_snapshot")
                    }
                    Picker("账户类型", selection: $draft.walletAccountType) {
                        Text("现金").tag("cash")
                        Text("微信").tag("wechat")
                        Text("支付宝").tag("alipay")
                        Text("银行卡").tag("bank_card")
                        Text("信用卡").tag("credit_card")
                        Text("消费额度").tag("credit_line")
                        Text("其他").tag("other")
                    }
                    if draft.walletRecordKind == "liability_snapshot" {
                        TextField("还款日期（YYYY-MM-DD，可选）", text: $draft.walletDueDate)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        TextField("每月还款日（可选）", text: $draft.walletBillDay)
                            .keyboardType(.numberPad)
                    }
                }
            }
        }
    }

    private var dateFields: some View {
        Section("时间") {
            DatePicker("日期", selection: $draft.date, in: ...Date(), displayedComponents: .date)
            Toggle("记录具体时间", isOn: $draft.includesTime)
            if draft.includesTime {
                DatePicker("时间", selection: $draft.time, displayedComponents: .hourAndMinute)
            }
        }
    }

    private func optionPicker(
        _ title: String,
        selection: Binding<String>,
        options: [NativeManualRecordOption]
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Text(option.title).tag(option.id)
            }
        }
    }

    private func editableOptionField(
        _ title: String,
        selection: Binding<String>,
        options: [NativeManualRecordOption]
    ) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                TextField("输入或选择", text: selection)
                    .multilineTextAlignment(.trailing)
                Menu {
                    ForEach(options) { option in
                        Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                            selection.wrappedValue = option.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(JieziTheme.brand)
                }
                .accessibilityLabel("选择\(title)")
            }
        }
    }

    private func accountSection(title: String) -> some View {
        Section(title) {
            Picker("账户", selection: $draft.accountId) {
                Text("暂不绑定").tag(String?.none)
                ForEach(accountCandidates) { account in
                    Text(account.title).tag(String?.some(account.id))
                }
            }
            Text("绑定账户后由现有原子 RPC 同步生成账户流水。")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func normalizeDomainSelection() {
        guard !universalDomains.isEmpty else { return }
        if !universalDomains.contains(where: { $0.id == draft.domainKey }) {
            draft.domainKey = universalDomains.first?.id ?? "sport"
        }
        if draft.dimension.isEmpty {
            draft.dimension = NativeManualDomainMetadata.resolve(
                selectedDomain,
                fallbackDomainKey: draft.domainKey
            ).defaultDimension
        }
    }

    private func hydrateUniversalFields() {
        let resolvedMetadata = NativeManualDomainMetadata.resolve(
            selectedDomain,
            fallbackDomainKey: draft.domainKey
        )
        draft.primaryValueText = draft.originalPayload.double(resolvedMetadata.primaryKey).map { String($0) } ?? draft.primaryValueText
        draft.dimension = draft.originalPayload.string(resolvedMetadata.dimensionKey) ?? draft.dimension
    }

    private func applyDefaultAccount() {
        switch draft.kind {
        case .expense:
            draft.accountId = accountCandidates.first(where: \.isDefaultExpense)?.id
        case .income:
            draft.accountId = accountCandidates.first(where: \.isDefaultIncome)?.id
        case .universal:
            draft.accountId = nil
        }
    }

    private func save() async {
        localMessage = nil
        if let validationMessage = draft.validationMessage(domain: selectedDomain) {
            localMessage = validationMessage
            return
        }
        if await appState.createManualRecord(draft, domain: selectedDomain) {
            dismiss()
        } else {
            localMessage = appState.manualRecordMessage ?? "保存失败，请稍后重试。"
        }
    }
}
