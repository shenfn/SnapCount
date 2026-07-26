import SwiftUI

struct ManualRecordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NativeManualRecordDraft
    @State private var localMessage: String?
    private let stagingRecord: NativeStagingRecord?
    private let preserveInboxNavigation: Bool
    private let onResolved: (() -> Void)?

    init(editing detail: NativeRecordDetail? = nil, kind: NativeManualRecordKind = .expense, domainKey: String = "sport") {
        stagingRecord = nil
        preserveInboxNavigation = false
        onResolved = nil
        _draft = State(
            initialValue: detail.map { NativeManualRecordDraft(detail: $0) }
                ?? NativeManualRecordDraft(kind: kind, domainKey: domainKey)
        )
    }

    init(
        staging record: NativeStagingRecord,
        domainKey: String,
        preserveInboxNavigation: Bool = false,
        onResolved: (() -> Void)? = nil
    ) {
        stagingRecord = record
        self.preserveInboxNavigation = preserveInboxNavigation
        self.onResolved = onResolved
        _draft = State(initialValue: NativeManualRecordDraft(stagingRecord: record, domainKey: domainKey))
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

    private var isSaving: Bool {
        appState.isCreatingManualRecord || (stagingRecord != nil && appState.inboxActionRecordId != nil)
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
            ZStack {
                JieziPageBackground()
                VStack(spacing: 0) {
                    JieziFormTopBar(
                        title: sheetTitle,
                        primaryTitle: stagingRecord == nil ? "保存" : "收下",
                        isWorking: isSaving,
                        onCancel: { dismiss() },
                        onSubmit: { Task { await save() } }
                    )

                    ScrollView {
                        VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                            recordContextSection

                            switch draft.kind {
                            case .expense:
                                expenseFields
                            case .income:
                                incomeFields
                            case .universal:
                                universalFields
                            }

                            dateFields
                            noteSection

                            if let message = localMessage ?? appState.manualRecordMessage {
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
        }
        .task {
            if appState.accounts.isEmpty { await appState.loadAccounts() }
            await appState.loadFinanceVocabulary()
            normalizeDomainSelection()
            if stagingRecord != nil {
                if draft.kind == .universal { hydrateUniversalFields() }
            } else if draft.existingRawId == nil {
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

    private var sheetTitle: String {
        if stagingRecord != nil { return "核对并收下" }
        return draft.existingRawId == nil ? "手动记录" : "编辑记录"
    }

    @ViewBuilder
    private var recordContextSection: some View {
        if let stagingRecord {
            JieziFormSection(
                title: "识别依据",
                subtitle: stagingRecord.imageURL == nil ? "原图不可用时，可根据识别文字继续核对。" : "对照原图，只调整识别不准的内容。"
            ) {
                stagingEvidence(stagingRecord)
            }

            JieziFormSection(title: "归档位置") {
                JieziFormRow(title: "准备归档到", systemImage: "tray.and.arrow.down") {
                    Text(
                        draft.kind == .universal
                            ? selectedDomain?.shortName ?? draft.domainKey
                            : draft.kind.title
                    )
                    .jieziInputSurface()
                }
            }
        } else if draft.existingRawId == nil {
            JieziFormSection(title: "记录类型", subtitle: "先选类型，下面只展示需要填写的字段。") {
                JieziFormRow(title: "类型", systemImage: "square.grid.2x2") {
                    Picker("记录类型", selection: $draft.kind) {
                        ForEach(NativeManualRecordKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        } else {
            JieziFormSection(title: "记录类型") {
                JieziFormRow(title: "当前数据域", systemImage: "square.grid.2x2") {
                    Text(selectedDomain?.shortName ?? "数据域")
                        .jieziInputSurface()
                }
            }
        }
    }

    private var expenseFields: some View {
        VStack(spacing: JieziSpacing.xl2) {
            JieziFormSection(title: "消费信息", subtitle: "金额和分类会用于后续统计，识别正确的内容无需改动。") {
                JieziFormRow(title: "金额", systemImage: "yensign", showsDivider: true) {
                    TextField("0.00", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                        .jieziInputSurface()
                }
                JieziFormRow(title: "商家", systemImage: "storefront", showsDivider: true) {
                    TextField("商家名称（可选）", text: $draft.title)
                        .jieziInputSurface()
                }
                editableOptionField(
                    "消费渠道",
                    selection: $draft.platform,
                    options: expensePlatformOptions,
                    systemImage: "shippingbox",
                    showsDivider: true
                )
                optionPicker(
                    "消费分类",
                    selection: $draft.category,
                    options: expenseCategoryOptions,
                    systemImage: "square.grid.2x2",
                    showsDivider: true
                )
                editableOptionField(
                    "支付方式",
                    selection: $draft.paymentMethod,
                    options: expensePaymentOptions,
                    systemImage: "creditcard"
                )
            }
            accountSection(title: "出资账户")
        }
    }

    private var incomeFields: some View {
        VStack(spacing: JieziSpacing.xl2) {
            JieziFormSection(title: "收入信息") {
                JieziFormRow(title: "金额", systemImage: "yensign", showsDivider: true) {
                    TextField("0.00", text: $draft.amountText)
                        .keyboardType(.decimalPad)
                        .jieziInputSurface()
                }
                JieziFormRow(title: "来源", systemImage: "arrow.down.circle", showsDivider: true) {
                    TextField("来源名称（可选）", text: $draft.title)
                        .jieziInputSurface()
                }
                optionPicker(
                    "收入类型",
                    selection: $draft.category,
                    options: NativeManualRecordDraft.incomeCategories,
                    systemImage: "tag"
                )
            }
            accountSection(title: "到账账户")
        }
    }

    private var universalFields: some View {
        VStack(spacing: JieziSpacing.xl2) {
            JieziFormSection(title: "数据域字段", subtitle: "只填写能从原图或文字事实中确认的内容。") {
                JieziFormRow(title: "数据域", systemImage: "square.grid.2x2", showsDivider: true) {
                    Menu {
                        ForEach(universalDomains) { domain in
                            Button("\(domain.icon) \(domain.shortName)") {
                                draft.domainKey = domain.id
                            }
                        }
                    } label: {
                        selectorLabel(selectedDomain?.shortName ?? draft.domainKey, placeholder: "选择数据域")
                    }
                    .buttonStyle(.plain)
                }
                JieziFormRow(title: "标题", systemImage: "textformat", showsDivider: true) {
                    TextField("标题（可选）", text: $draft.title)
                        .jieziInputSurface()
                }
                JieziFormRow(title: metadata.dimensionLabel, systemImage: "tag", showsDivider: true) {
                    TextField(metadata.dimensionLabel, text: $draft.dimension)
                        .jieziInputSurface()
                }
                JieziFormRow(title: metadata.primaryLabel, systemImage: "number") {
                    TextField(metadata.primaryLabel, text: $draft.primaryValueText)
                        .keyboardType(.decimalPad)
                        .jieziInputSurface()
                }
            }

            if draft.domainKey == "wallet" {
                JieziFormSection(title: "钱包快照") {
                    JieziFormRow(title: "记录类型", systemImage: "wallet.pass", showsDivider: true) {
                        Picker("记录类型", selection: $draft.walletRecordKind) {
                            Text("资产余额").tag("cash_snapshot")
                            Text("负债待还").tag("liability_snapshot")
                        }
                        .pickerStyle(.segmented)
                    }
                    JieziFormRow(title: "账户类型", systemImage: "creditcard", showsDivider: draft.walletRecordKind == "liability_snapshot") {
                        Picker("账户类型", selection: $draft.walletAccountType) {
                            Text("现金").tag("cash")
                            Text("微信").tag("wechat")
                            Text("支付宝").tag("alipay")
                            Text("银行卡").tag("bank_card")
                            Text("信用卡").tag("credit_card")
                            Text("消费额度").tag("credit_line")
                            Text("其他").tag("other")
                        }
                        .pickerStyle(.menu)
                        .tint(JieziTheme.brand)
                        .jieziInputSurface()
                    }
                    if draft.walletRecordKind == "liability_snapshot" {
                        JieziFormRow(title: "还款日期", systemImage: "calendar", showsDivider: true) {
                            TextField("YYYY-MM-DD（可选）", text: $draft.walletDueDate)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .jieziInputSurface()
                        }
                        JieziFormRow(title: "每月还款日", systemImage: "calendar.badge.clock") {
                            TextField("日期（可选）", text: $draft.walletBillDay)
                                .keyboardType(.numberPad)
                                .jieziInputSurface()
                        }
                    }
                }
            }
        }
    }

    private var dateFields: some View {
        JieziFormSection(title: "时间") {
            JieziFormRow(title: "日期", systemImage: "calendar", showsDivider: true) {
                DatePicker("日期", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                    .labelsHidden()
                    .jieziInputSurface()
            }
            JieziFormRow(title: "记录具体时间", systemImage: "clock", showsDivider: draft.includesTime) {
                Toggle("记录具体时间", isOn: $draft.includesTime)
                    .labelsHidden()
                    .tint(JieziTheme.brand)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if draft.includesTime {
                JieziFormRow(title: "时间", systemImage: "clock.badge") {
                    DatePicker("时间", selection: $draft.time, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .jieziInputSurface()
                }
            }
        }
    }

    private var noteSection: some View {
        JieziFormSection(title: "备注", subtitle: "选填，仅用于补充无法放进结构化字段的信息。") {
            JieziFormRow(title: "补充说明", systemImage: "note.text") {
                TextField("写下一句补充说明", text: $draft.note, axis: .vertical)
                    .lineLimit(2...5)
                    .jieziInputSurface()
            }
        }
    }

    private func optionPicker(
        _ title: String,
        selection: Binding<String>,
        options: [NativeManualRecordOption],
        systemImage: String,
        showsDivider: Bool = false
    ) -> some View {
        JieziFormRow(title: title, systemImage: systemImage, showsDivider: showsDivider) {
            Menu {
                ForEach(options) { option in
                    Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                        selection.wrappedValue = option.id
                    }
                }
            } label: {
                selectorLabel(optionTitle(selection.wrappedValue, options: options), placeholder: "请选择")
            }
            .buttonStyle(.plain)
        }
    }

    private func stagingEvidence(_ record: NativeStagingRecord) -> some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            if let imageURL = record.imageURL {
                CachedRemoteImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 300)
                        .clipShape(RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous))
                } placeholder: {
                    ProgressView("正在准备原图")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } failure: {
                    Label("原图暂不可用，请依据文字结果核对", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote)
                }
            } else {
                Label(
                    record.imagePath == nil ? "原图未保留，请依据文字结果核对" : "原图暂不可用，请依据文字结果核对",
                    systemImage: "doc.text.magnifyingglass"
                )
                .font(.footnote)
            }
            Text(record.summary)
                .font(JieziFont.footnote)
                .foregroundStyle(JieziTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(JieziSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JieziTheme.brand.opacity(0.055), in: RoundedRectangle(cornerRadius: JieziRadius.sm))
        }
        .padding(.vertical, JieziSpacing.md)
    }

    private func editableOptionField(
        _ title: String,
        selection: Binding<String>,
        options: [NativeManualRecordOption],
        systemImage: String,
        showsDivider: Bool = false
    ) -> some View {
        JieziFormRow(title: title, systemImage: systemImage, showsDivider: showsDivider) {
            HStack(spacing: 8) {
                TextField("输入或选择", text: selection)
                Menu {
                    ForEach(options) { option in
                        Button(option.isFrequent ? "\(option.title) · 常用" : option.title) {
                            selection.wrappedValue = option.id
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.brand)
                        .frame(width: 34, height: 34)
                }
                .accessibilityLabel("选择\(title)")
            }
            .jieziInputSurface()
        }
    }

    private func accountSection(title: String) -> some View {
        JieziFormSection(title: title, subtitle: "绑定后会同步生成账户流水；暂不绑定不会影响记录本身。") {
            JieziFormRow(title: "账户", systemImage: "wallet.pass") {
                Menu {
                    Button("暂不绑定") { draft.accountId = nil }
                    ForEach(accountCandidates) { account in
                        Button(account.title) { draft.accountId = account.id }
                    }
                } label: {
                    selectorLabel(selectedAccountTitle, placeholder: "暂不绑定")
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var selectedAccountTitle: String {
        guard let accountId = draft.accountId else { return "暂不绑定" }
        return accountCandidates.first(where: { $0.id == accountId })?.title ?? "暂不绑定"
    }

    private func optionTitle(_ value: String, options: [NativeManualRecordOption]) -> String {
        options.first(where: { $0.id == value })?.title ?? value
    }

    private func selectorLabel(_ value: String, placeholder: String) -> some View {
        HStack(spacing: JieziSpacing.sm) {
            Text(value.isEmpty ? placeholder : value)
                .foregroundStyle(value.isEmpty ? JieziTheme.muted : JieziTheme.ink)
                .lineLimit(1)
            Spacer(minLength: JieziSpacing.sm)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        }
        .jieziInputSurface()
    }

    private func normalizeDomainSelection() {
        guard draft.kind == .universal else { return }
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
        if let stagingRecord {
            if await appState.archiveStagingRecord(
                stagingRecord,
                draft: draft,
                domain: selectedDomain,
                preserveInboxNavigation: preserveInboxNavigation
            ) != nil {
                onResolved?()
                dismiss()
            } else {
                localMessage = appState.inboxActionMessage ?? "归档失败，请稍后重试。"
            }
        } else if await appState.createManualRecord(draft, domain: selectedDomain) {
            dismiss()
        } else {
            localMessage = appState.manualRecordMessage ?? "保存失败，请稍后重试。"
        }
    }
}
