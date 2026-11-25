import SwiftUI
import UIKit

struct ManualRecordSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var draft: NativeManualRecordDraft
    @State private var localMessage: String?
    @State private var hasCommittedRecord = false
    @State private var showLocalCameraPicker = false
    @State private var showLocalPhotoLibraryPicker = false
    @State private var showLocalPhotoOptions = false
    @State private var showLocalAccountPreparation = false
    @State private var showExtraOptions = false
    @State private var showDirectValueEditor = false
    @State private var directValueInput = ""
    @State private var isFreshAmount = false
    @State private var foodQueryInput = ""
    @State private var selectedFoodItem: JieziFoodNutritionItem?
    @State private var foodGrams: Int = 150
    @State private var foodGramsInput = "150"
    @State private var accumulatedFoodParts: [String] = []
    @State private var isInstrumentDragging = false
    @State private var lastInstrumentDragEndTime: TimeInterval = 0

    private let stagingRecord: NativeStagingRecord?
    private let preserveInboxNavigation: Bool
    private let onResolved: (() -> Void)?

    init(editing detail: NativeRecordDetail? = nil, kind: NativeManualRecordKind = .expense, domainKey: String = "sport") {
        stagingRecord = nil
        preserveInboxNavigation = false
        onResolved = nil
        var initial = detail.map { NativeManualRecordDraft(detail: $0) }
            ?? NativeManualRecordDraft(kind: kind, domainKey: domainKey)
        if detail == nil {
            Self.applyFriendlyDefaults(&initial)
        } else {
            Self.hydrateSleepOffsetsIfNeeded(&initial)
        }
        _draft = State(initialValue: initial)
    }

    init(initialImageData: Data?, onResolved: (() -> Void)? = nil) {
        stagingRecord = nil
        preserveInboxNavigation = false
        self.onResolved = onResolved
        var initial = NativeManualRecordDraft(kind: .universal, domainKey: "sport")
        initial.imageData = initialImageData
        Self.applyFriendlyDefaults(&initial)
        _draft = State(initialValue: initial)
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
        var initial = NativeManualRecordDraft(stagingRecord: record, domainKey: domainKey)
        Self.hydrateSleepOffsetsIfNeeded(&initial)
        _draft = State(initialValue: initial)
    }

    private static func applyFriendlyDefaults(_ draft: inout NativeManualRecordDraft) {
        if draft.kind == .universal {
            switch draft.domainKey {
            case "food":
                if draft.dimension.isEmpty { draft.dimension = currentMealDefault() }
                if draft.primaryValueText.isEmpty { draft.primaryValueText = "540" }
            case "sleep":
                if draft.dimension.isEmpty { draft.dimension = "良好" }
                draft.sleepUsesTimeRange = true
                draft.sleepBedOffsetMinutes = 210
                draft.sleepWakeOffsetMinutes = 675
                draft.primaryValueText = "\(675 - 210)"
            case "sport":
                if draft.dimension.isEmpty { draft.dimension = "跑步" }
                if draft.primaryValueText.isEmpty { draft.primaryValueText = "40" }
            case "reading":
                if draft.primaryValueText.isEmpty { draft.primaryValueText = "35" }
            case "wallet":
                if draft.dimension.isEmpty { draft.dimension = "微信余额" }
            default:
                break
            }
        } else if draft.kind == .income {
            if draft.category.isEmpty { draft.category = "salary" }
        } else {
            if draft.category.isEmpty { draft.category = "food" }
        }
    }

    private static func currentMealDefault() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<10: return "早餐"
        case 10..<15: return "午餐"
        case 15..<21: return "晚餐"
        default: return "加餐"
        }
    }

    private static func hydrateSleepOffsetsIfNeeded(_ draft: inout NativeManualRecordDraft) {
        guard draft.kind == .universal, draft.domainKey == "sleep" else { return }
        if let startRaw = draft.originalPayload.string("sleep_start_at"),
           let wakeRaw = draft.originalPayload.string("wake_at"),
           let startClock = NativeLocalDate.financeTimeKey(occurredAt: startRaw),
           let wakeClock = NativeLocalDate.financeTimeKey(occurredAt: wakeRaw),
           let startMin = clockStringToOffset(startClock),
           let wakeMin = clockStringToOffset(wakeClock),
           wakeMin > startMin {
            draft.sleepUsesTimeRange = true
            let clamped = JieziSleepRibbonMath.clampRange(bed: startMin, wake: wakeMin)
            draft.sleepBedOffsetMinutes = clamped.bed
            draft.sleepWakeOffsetMinutes = clamped.wake
        } else if draft.existingRawId != nil || !draft.primaryValueText.isEmpty {
            draft.sleepUsesTimeRange = false
        }
    }

    private static func clockStringToOffset(_ hhmm: String) -> Int? {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        let total = h * 60 + m
        if h >= JieziSleepRibbonMath.anchorHour {
            return total - JieziSleepRibbonMath.anchorHour * 60
        } else if h <= 12 {
            return (24 - JieziSleepRibbonMath.anchorHour) * 60 + total
        }
        return nil
    }

    // MARK: - 场景与领域映射

    private var activeAppDomain: AppDomain {
        if draft.kind == .expense || draft.kind == .income { return .expense }
        return AppDomain(rawValue: draft.domainKey) ?? .expense
    }

    private var scene: JieziSceneTokens {
        JieziScene.tokens(for: activeAppDomain.rawValue)
    }

    private var isDarkScene: Bool {
        activeAppDomain == .sleep || activeAppDomain == .reading
    }

    private var canSwitchDomainFreely: Bool {
        stagingRecord == nil && draft.existingRawId == nil && draft.domainKey != "wallet"
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

    private struct ManualAccountCandidate: Identifiable {
        let id: String
        let title: String
        let isDefaultExpense: Bool
        let isDefaultIncome: Bool
    }

    private var accountCandidates: [ManualAccountCandidate] {
        if draft.kind == .expense {
            let local = appState.localAccounts.map { account in
                ManualAccountCandidate(
                    id: account.id.uuidString,
                    title: account.name,
                    isDefaultExpense: false,
                    isDefaultIncome: false
                )
            }
            if !local.isEmpty { return local }
            return appState.accounts
                .filter { !$0.isArchived }
                .map { account in
                    ManualAccountCandidate(
                        id: account.id,
                        title: account.title,
                        isDefaultExpense: account.isDefaultExpense,
                        isDefaultIncome: account.isDefaultIncome
                    )
                }
        }
        return appState.accounts
            .filter { !$0.isArchived }
            .map { account in
                ManualAccountCandidate(
                    id: account.id,
                    title: account.title,
                    isDefaultExpense: account.isDefaultExpense,
                    isDefaultIncome: account.isDefaultIncome
                )
            }
    }

    private var isSaving: Bool {
        appState.isCreatingManualRecord || (stagingRecord != nil && appState.inboxActionRecordId != nil)
    }

    private var expensePlatformOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .platform, currentValue: draft.platform, vocabulary: appState.financeVocabulary)
    }

    private var expenseCategoryOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .category, currentValue: draft.category, vocabulary: appState.financeVocabulary)
    }

    private var expensePaymentOptions: [NativeManualRecordOption] {
        NativeFinanceOptionCatalog.options(kind: .payment, currentValue: draft.paymentMethod, vocabulary: appState.financeVocabulary)
    }

    private var recentBookTitles: [String] {
        var seen = Set<String>()
        var result: [String] = []
        let monthKey = NativeLocalDate.monthKey(from: draft.dateKey) ?? NativeMonthKey.current()
        for group in appState.recordGroups(monthKey: monthKey) {
            for record in group.records where record.domainKey == "reading" {
                let candidate = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty, candidate != "阅读记录", seen.insert(candidate).inserted {
                    result.append(candidate)
                }
                if result.count >= 5 { return result }
            }
        }
        return result
    }

    // MARK: - 主视图

    var body: some View {
        ZStack {
            DomainSceneView(domain: activeAppDomain)

            if !dynamicTypeSize.isAccessibilitySize && stagingRecord == nil && draft.domainKey != "wallet" {
                DomainCatView(domain: activeAppDomain)
                    .padding(.top, 52)
                    .padding(.trailing, 14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if let stagingRecord {
                            stagingEvidenceCard(stagingRecord)
                        }

                        if draft.domainKey == "wallet" {
                            walletSnapshotStage
                        } else {
                            asymmetricHero
                            domainInstrumentStage
                        }

                        if hasAttachedImage || showExtraOptions {
                            extraDetailsCard
                        } else if draft.kind != .expense && draft.kind != .income {
                            quietExtraTrigger
                        }

                        if let message = localMessage ?? appState.manualRecordMessage {
                            JieziFormMessage(message: message)
                        }

                        if hasCommittedRecord, appState.localProjectionRefreshMessage != nil {
                            Button("只重试列表刷新") {
                                Task {
                                    await appState.retryLocalProjectionRefresh()
                                    localMessage = appState.localProjectionRefreshMessage ?? "记录已保存，列表已刷新。"
                                }
                            }
                            .font(JieziFont.footnote.weight(.semibold))
                            .foregroundStyle(scene.accent)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .disabled(hasCommittedRecord)
                }
                .scrollIndicators(.hidden)
                .scrollDismissesKeyboard(.interactively)

                if canSwitchDomainFreely {
                    bottomDomainRail
                }
            }
            .simultaneousGesture(horizontalDomainSwipeGesture)
        }
        .preferredColorScheme(isDarkScene ? .dark : .light)
        .task {
            _ = await appState.prepareLocalWorkspace()
            if appState.accounts.isEmpty { await appState.loadAccounts() }
            await appState.loadFinanceVocabulary()
            if stagingRecord != nil {
                if draft.kind == .universal { hydrateUniversalFields() }
            } else if draft.existingRawId == nil {
                applyDefaultAccount()
            } else {
                hydrateUniversalFields()
            }
            if !draft.note.isEmpty || draft.imageData != nil || draft.existingImageData != nil {
                showExtraOptions = true
            }
            if draft.domainKey == "food", foodQueryInput.isEmpty, !draft.title.isEmpty {
                foodQueryInput = draft.title
            }
            if draft.isLocalRecord,
               draft.imageData == nil,
               let existingRawId = draft.existingRawId,
               draft.imagePath != nil {
                draft.existingImageData = try? await appState.localImageDataForRecord(id: existingRawId)
            }
        }
        .sheet(isPresented: $showLocalAccountPreparation) {
            LocalAccountPreparationView { account in
                draft.accountId = account.id.uuidString
            }
            .environmentObject(appState)
        }
        .confirmationDialog("添加本地图片", isPresented: $showLocalPhotoOptions, titleVisibility: .visible) {
            Button("拍照") { showLocalCameraPicker = true }
            Button("从相册选择") { showLocalPhotoLibraryPicker = true }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showLocalCameraPicker) {
            CameraPicker { data in
                showLocalCameraPicker = false
                draft.imageData = data
                draft.existingImageData = nil
                draft.removeImage = false
            } onCancel: { showLocalCameraPicker = false }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showLocalPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                showLocalPhotoLibraryPicker = false
                draft.imageData = data
                draft.existingImageData = nil
                draft.removeImage = false
            } onCancel: { showLocalPhotoLibraryPicker = false }
        }
        .alert("精确输入数值", isPresented: $showDirectValueEditor) {
            TextField("请输入数字", text: $directValueInput)
                .keyboardType(.decimalPad)
            Button("确定") {
                if let parsed = Double(directValueInput.replacingOccurrences(of: ",", with: ".")), parsed > 0 {
                    let clamped = min(max(parsed, 1), metadata.maximumValue)
                    draft.primaryValueText = String(Int(clamped.rounded()))
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("输入\(metadata.primaryLabel)")
        }
    }

    // MARK: - 顶栏（极简关闭 + 日期胶囊 + 收下）

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                JieziHaptics.tap()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(scene.foreground)
                    .frame(width: 38, height: 38)
                    .background(scene.surface.opacity(0.75), in: Circle())
                    .overlay(Circle().stroke(scene.foreground.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.92))
            .disabled(isSaving)
            .accessibilityLabel("取消")

            Spacer(minLength: 4)

            DatePicker("日期", selection: $draft.date, in: ...Date(), displayedComponents: .date)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(scene.accent)
                .scaleEffect(0.92)
                .padding(.horizontal, 6)
                .background(scene.surface.opacity(0.65), in: Capsule())

            Spacer(minLength: 4)

            Button {
                if hasCommittedRecord {
                    dismiss()
                } else {
                    JieziHaptics.confirm()
                    Task { await save() }
                }
            } label: {
                HStack(spacing: 5) {
                    if isSaving {
                        ProgressView()
                            .controlSize(.small)
                            .tint(isDarkScene ? JieziTheme.space : .white)
                    } else {
                        Text(hasCommittedRecord ? "完成" : (draft.existingRawId != nil ? "保存" : "收下"))
                    }
                }
                .font(JieziFont.subheadline.weight(.semibold))
                .foregroundStyle(isDarkScene ? JieziTheme.space : .white)
                .padding(.horizontal, 16)
                .frame(minHeight: 38)
                .background(scene.accent, in: Capsule())
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.95))
            .disabled(isSaving)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - 上半屏：左对齐非对称 Hero（复刻 NativeDomainPageView.dailyHero）

    private var asymmetricHero: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                switch activeAppDomain {
                case .expense:
                    financeHeroContent
                case .sleep:
                    sleepHeroContent
                case .food:
                    foodHeroContent
                case .sport:
                    sportHeroContent
                case .reading:
                    readingHeroContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if !dynamicTypeSize.isAccessibilitySize && stagingRecord == nil {
                Color.clear
                    .frame(width: 128)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 132, alignment: .topLeading)
        .padding(.horizontal, 4)
        .padding(.top, 4)
    }

    private var financeHeroContent: some View {
        Group {
            HStack(spacing: 8) {
                if canSwitchDomainFreely {
                    HStack(spacing: 2) {
                        finModePill("支出", active: draft.kind == .expense) {
                            draft.kind = .expense
                            if draft.category.isEmpty { draft.category = "food" }
                            applyDefaultAccount()
                        }
                        finModePill("收入", active: draft.kind == .income) {
                            draft.kind = .income
                            if !NativeManualRecordDraft.incomeCategories.contains(where: { $0.id == draft.category }) {
                                draft.category = "salary"
                            }
                            applyDefaultAccount()
                        }
                    }
                    .padding(2)
                    .background(scene.foreground.opacity(0.06), in: Capsule())
                } else {
                    Text(draft.kind == .income ? "收入金额" : "支出金额")
                        .font(JieziFont.caption)
                        .foregroundStyle(scene.muted)
                }
                Text("· \(selectedAccountTitle)")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(draft.kind == .income ? "+¥" : "¥")
                    .font(JieziType.prototypeBrand)
                    .foregroundStyle(draft.kind == .income ? scene.accent : scene.dataAccent)
                Text(draft.amountText.isEmpty ? "0" : draft.amountText)
                    .font(JieziType.prototypeHero.monospacedDigit())
                    .foregroundStyle(scene.foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            }

            Text(financeHeroSubtitle)
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
                .lineLimit(1)
        }
    }

    private func finModePill(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(JieziFont.caption2.weight(active ? .semibold : .regular))
                .foregroundStyle(active ? scene.foreground : scene.muted)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(active ? scene.surface.opacity(0.92) : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var financeHeroSubtitle: String {
        let options = draft.kind == .income ? NativeManualRecordDraft.incomeCategories : expenseCategoryOptions
        let catTitle = optionTitle(draft.category, options: options)
        let merchant = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return merchant.isEmpty ? "\(catTitle) · 点下方数字盘直接记一笔" : "\(catTitle) · \(merchant)"
    }

    private var sleepHeroContent: some View {
        let mins = currentSleepMinutes
        let sub: String = {
            if draft.sleepUsesTimeRange {
                let start = JieziSleepRibbonMath.clockLabel(for: draft.sleepBedOffsetMinutes)
                let wake = JieziSleepRibbonMath.clockLabel(for: draft.sleepWakeOffsetMinutes)
                let nextDay = JieziSleepRibbonMath.isNextDay(draft.sleepWakeOffsetMinutes) ? "次日 " : ""
                return "\(start) 入睡 → \(nextDay)\(wake) 醒来 · \(draft.dimension.isEmpty ? "良好" : draft.dimension)"
            }
            return "仅记总时长 · 质量\(draft.dimension.isEmpty ? "良好" : draft.dimension)"
        }()
        return Group {
            Text("主要睡眠 · Sleep")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
            durationMetricText(minutes: mins, font: JieziType.prototypeSleepHero)
                .foregroundStyle(scene.foreground)
            Text(sub)
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var foodHeroContent: some View {
        let kcal = Int((draft.primaryValue ?? 0).rounded())
        let pct = Int((Double(kcal) / 2_000.0 * 100).rounded())
        return Group {
            HStack(spacing: 6) {
                Text("餐食能量 · \(draft.dimension.isEmpty ? "餐次" : draft.dimension)")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
                Text("估算")
                    .font(JieziFont.caption2)
                    .foregroundStyle(scene.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(scene.accent.opacity(0.12), in: Capsule())
            }
            Button {
                directValueInput = draft.primaryValueText
                showDirectValueEditor = true
            } label: {
                (Text("约 ").font(JieziFont.body).foregroundStyle(scene.muted)
                 + Text("\(kcal)").font(JieziType.prototypeHero).foregroundStyle(scene.foreground)
                 + Text(" 千卡").font(JieziFont.body).foregroundStyle(scene.muted))
                .monospacedDigit()
            }
            .buttonStyle(.plain)
            .accessibilityHint("点击可直接输入热量数字")

            Text("\(draft.title.isEmpty ? "" : "\(draft.title) · ")约占 2,000 千卡通用参考 \(pct)%")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
        }
    }

    private var sportHeroContent: some View {
        let mins = Int((draft.primaryValue ?? 0).rounded())
        return Group {
            Text("本次运动 · \(draft.dimension.isEmpty ? "运动" : draft.dimension)")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
            Button {
                directValueInput = draft.primaryValueText
                showDirectValueEditor = true
            } label: {
                durationMetricText(minutes: mins, font: JieziType.prototypeHero)
                    .foregroundStyle(scene.foreground)
            }
            .buttonStyle(.plain)
            .accessibilityHint("点击可直接输入运动分钟数")

            Text(draft.note.isEmpty ? "拨动下方刻度尺调整时长" : draft.note)
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
                .lineLimit(1)
        }
    }

    private var readingHeroContent: some View {
        let mins = Int((draft.primaryValue ?? 0).rounded())
        let minLabel = mins >= 60 ? "\(mins / 60) 小时 \(mins % 60) 分钟" : "\(mins) 分钟"
        return Group {
            Text("本日书目 · Reading")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
            TextField("写下在读的书名…", text: $draft.dimension)
                .font(JieziType.prototypeBook)
                .foregroundStyle(scene.foreground)
                .tint(scene.accent)
                .submitLabel(.done)
            Text("本次阅读 \(minLabel)")
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
        }
    }

    private func durationMetricText(minutes: Int, font: Font) -> Text {
        let safe = max(0, minutes)
        if safe >= 60 {
            return (Text("\(safe / 60)").font(font)
                    + Text(" 小时 ").font(JieziFont.body).foregroundStyle(scene.muted)
                    + Text("\(safe % 60)").font(font)
                    + Text(" 分钟").font(JieziFont.body).foregroundStyle(scene.muted))
                .monospacedDigit()
        }
        return (Text("\(safe)").font(font)
                + Text(" 分钟").font(JieziFont.body).foregroundStyle(scene.muted))
            .monospacedDigit()
    }

    // MARK: - 下半屏：各域专属输入器物

    @ViewBuilder
    private var domainInstrumentStage: some View {
        switch activeAppDomain {
        case .expense:
            financeStage
        case .sleep:
            sleepStage
        case .food:
            foodStage
        case .sport:
            sportStage
        case .reading:
            readingStage
        }
    }

    // 1. 消费 / 收入：分类条 + 内联商家/账户 + 纸感数字键盘
    private var financeStage: some View {
        let options = draft.kind == .income ? NativeManualRecordDraft.incomeCategories : expenseCategoryOptions
        return VStack(spacing: 10) {
            glassCard(padding: 12) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(options) { option in
                            selectableChip(option.title, selected: draft.category == option.id) {
                                draft.category = option.id
                            }
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(
                    draft.kind == .income ? "收入来源或说明（选填）" : "商家或补充说明（选填）",
                    text: $draft.title
                )
                .font(JieziFont.subheadline)
                .foregroundStyle(scene.foreground)
                .submitLabel(.done)

                Menu {
                    Button("暂不绑定") { draft.accountId = nil }
                    ForEach(accountCandidates) { account in
                        Button(account.title) { draft.accountId = account.id }
                    }
                    if !appState.isSignedIn, draft.kind == .expense {
                        Divider()
                        Button("新建本地账户…") { showLocalAccountPreparation = true }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(selectedAccountTitle)
                            .font(JieziFont.caption.weight(.medium))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(scene.foreground)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(scene.foreground.opacity(0.06), in: Capsule())
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(scene.surface.opacity(0.75), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(scene.foreground.opacity(0.08), lineWidth: 1))

            if !appState.isSignedIn, draft.kind == .expense, appState.localAccounts.isEmpty {
                Button {
                    showLocalAccountPreparation = true
                } label: {
                    HStack {
                        Image(systemName: "wallet.pass")
                        Text("先建一个本机账户即可保存支出")
                            .font(JieziFont.caption.weight(.medium))
                        Spacer()
                        Text("去创建 ›").font(JieziFont.caption.weight(.semibold))
                    }
                    .foregroundStyle(scene.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(scene.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }

            JieziPaperKeypad(
                scene: scene,
                primaryTitle: hasCommittedRecord ? "完成" : (draft.existingRawId != nil ? "保存" : "收下"),
                isWorking: isSaving,
                showsPhotoAction: canAttachLocalImage,
                onKey: { key in
                    let next = JieziKeypadAmountEngine.apply(key, to: draft.amountText, replacingFresh: isFreshAmount)
                    draft.amountText = next.text
                    isFreshAmount = next.isFresh
                },
                onPhoto: { showLocalPhotoOptions = true },
                onSubmit: {
                    if hasCommittedRecord { dismiss() }
                    else { Task { await save() } }
                }
            )

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showExtraOptions.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: showExtraOptions ? "chevron.up" : "slider.horizontal.3")
                    Text(showExtraOptions ? "收起渠道与备注" : "渠道 · 支付方式 · 时间与备注")
                }
                .font(JieziFont.caption)
                .foregroundStyle(scene.muted)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // 2. 睡眠：夜空双端时间滑轨 / 纯时长刻度尺 + 质量选择
    private var sleepStage: some View {
        VStack(spacing: 10) {
            glassCard {
                HStack {
                    Text("入睡与醒来")
                        .font(JieziFont.subheadline.weight(.semibold))
                        .foregroundStyle(scene.foreground)
                    Spacer()
                    HStack(spacing: 2) {
                        finModePill("起止时刻", active: draft.sleepUsesTimeRange) {
                            draft.sleepUsesTimeRange = true
                            draft.primaryValueText = "\(max(30, draft.sleepWakeOffsetMinutes - draft.sleepBedOffsetMinutes))"
                        }
                        finModePill("仅记时长", active: !draft.sleepUsesTimeRange) {
                            draft.sleepUsesTimeRange = false
                            if draft.primaryValue == nil { draft.primaryValueText = "450" }
                        }
                    }
                    .padding(2)
                    .background(scene.foreground.opacity(0.08), in: Capsule())
                }

                if draft.sleepUsesTimeRange {
                    JieziSleepNightRibbon(
                        bedOffset: Binding(
                            get: { draft.sleepBedOffsetMinutes },
                            set: {
                                draft.sleepBedOffsetMinutes = $0
                                draft.primaryValueText = "\(max(30, draft.sleepWakeOffsetMinutes - $0))"
                            }
                        ),
                        wakeOffset: Binding(
                            get: { draft.sleepWakeOffsetMinutes },
                            set: {
                                draft.sleepWakeOffsetMinutes = $0
                                draft.primaryValueText = "\(max(30, $0 - draft.sleepBedOffsetMinutes))"
                            }
                        ),
                        scene: scene,
                        onScrubbingChanged: handleInstrumentScrubbing
                    )
                } else {
                    JieziInertialRuler(
                        value: primaryNumericBinding(defaultValue: 450),
                        range: 30...720,
                        step: 15,
                        majorStep: 60,
                        midStep: 30,
                        scene: scene,
                        unitLabel: "分钟",
                        onScrubbingChanged: handleInstrumentScrubbing
                    )
                    quickPresetRow([("6h", 360), ("7h", 420), ("7.5h", 450), ("8h", 480), ("9h", 540)])
                }
            }

            glassCard {
                Text("醒来感受")
                    .font(JieziFont.subheadline.weight(.semibold))
                    .foregroundStyle(scene.foreground)
                HStack(spacing: 8) {
                    ForEach(["极佳", "良好", "一般", "较差"], id: \.self) { quality in
                        selectableChip(quality, selected: draft.dimension == quality) {
                            draft.dimension = quality
                        }
                    }
                }
            }
        }
    }

    // 3. 饮食：餐次 + 惯性能量尺 + 2000 千卡参考微尺 + 食物名
    private var foodStage: some View {
        let kcal = draft.primaryValue ?? 540
        return VStack(spacing: 10) {
            glassCard {
                HStack(spacing: 8) {
                    ForEach(["早餐", "午餐", "晚餐", "加餐"], id: \.self) { meal in
                        selectableChip(meal, selected: draft.dimension == meal) {
                            draft.dimension = meal
                        }
                    }
                }

                JieziInertialRuler(
                    value: primaryNumericBinding(defaultValue: 540),
                    range: 0...2400,
                    step: 10,
                    majorStep: 200,
                    midStep: 100,
                    scene: scene,
                    unitLabel: "千卡",
                    onScrubbingChanged: handleInstrumentScrubbing
                )

                quickPresetRow([("轻食", 300), ("日常", 540), ("丰盛", 850), ("聚餐", 1200)])

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("本餐位置")
                        Spacer()
                        Text("虚线为 2,000 千卡通用日参考")
                    }
                    .font(JieziFont.caption2)
                    .foregroundStyle(scene.muted)

                    GeometryReader { geo in
                        let w = max(geo.size.width, 1)
                        ZStack(alignment: .leading) {
                            Capsule().fill(scene.foreground.opacity(0.08))
                            Capsule().fill(scene.dataAccent)
                                .frame(width: w * CGFloat(min(max(kcal / 2400, 0), 1)))
                            Rectangle()
                                .fill(scene.muted.opacity(0.65))
                                .frame(width: 1.5, height: 12)
                                .offset(x: w * CGFloat(2000.0 / 2400.0))
                        }
                    }
                    .frame(height: 6)
                }
                .padding(.top, 4)
            }

            glassCard {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("吃了什么")
                            .font(JieziFont.subheadline.weight(.semibold))
                            .foregroundStyle(scene.foreground)
                        TextField("输入食物，如 鸡胸肉 150g、米饭、拿铁", text: $foodQueryInput)
                            .font(JieziFont.subheadline)
                            .foregroundStyle(scene.foreground)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onChange(of: foodQueryInput) { _, newValue in
                                handleFoodQueryChanged(newValue)
                            }
                    }

                    let suggestions = JieziFoodCalorieEstimator.search(foodQueryInput, limit: 5)
                    if !suggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(suggestions) { item in
                                    let isPicked = selectedFoodItem?.id == item.id
                                    Button {
                                        JieziHaptics.tap()
                                        selectFoodItem(item)
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(item.name)
                                            Text("\(Int(item.kcalPer100g))kcal/100g")
                                                .font(JieziFont.caption2.monospacedDigit())
                                                .opacity(0.75)
                                        }
                                        .font(JieziFont.caption.weight(isPicked ? .semibold : .regular))
                                        .foregroundStyle(isPicked ? scene.surface : scene.foreground)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(
                                            isPicked ? scene.dataAccent : scene.foreground.opacity(0.06),
                                            in: Capsule()
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let item = selectedFoodItem {
                        let estimatedKcal = JieziFoodCalorieEstimator.estimate(item: item, grams: foodGrams)
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Text("\(item.name) · \(item.unitHint)")
                                    .font(JieziFont.caption.weight(.semibold))
                                    .foregroundStyle(scene.foreground)
                                Spacer()
                                Text("约 \(estimatedKcal) 千卡")
                                    .font(JieziFont.caption.monospacedDigit().weight(.semibold))
                                    .foregroundStyle(scene.dataAccent)
                            }

                            HStack(spacing: 8) {
                                Button {
                                    adjustFoodGrams(by: -25)
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 28, height: 28)
                                        .background(scene.foreground.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("减少 25 克")

                                HStack(spacing: 2) {
                                    TextField("150", text: $foodGramsInput)
                                        .keyboardType(.numberPad)
                                        .font(JieziFont.subheadline.monospacedDigit().weight(.semibold))
                                        .multilineTextAlignment(.center)
                                        .frame(width: 54)
                                        .onChange(of: foodGramsInput) { _, raw in
                                            let digits = raw.filter(\.isNumber)
                                            if digits != raw { foodGramsInput = digits }
                                            if let parsed = Int(digits) {
                                                let clamped = min(max(parsed, 0), JieziFoodCalorieEstimator.maxGrams)
                                                if clamped != foodGrams {
                                                    foodGrams = clamped
                                                    syncSingleFoodEstimateIfNeeded()
                                                }
                                            }
                                        }
                                    Text("克")
                                        .font(JieziFont.caption)
                                        .foregroundStyle(scene.muted)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(scene.surface.opacity(0.9), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                                Button {
                                    adjustFoodGrams(by: 25)
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 11, weight: .bold))
                                        .frame(width: 28, height: 28)
                                        .background(scene.foreground.opacity(0.08), in: Circle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("增加 25 克")

                                Spacer(minLength: 4)

                                Button {
                                    JieziHaptics.tap()
                                    applyFoodEstimate(item: item, grams: foodGrams, accumulate: false)
                                } label: {
                                    Text("设为本餐")
                                        .font(JieziFont.caption2.weight(.semibold))
                                        .foregroundStyle(scene.surface)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(scene.dataAccent, in: Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    JieziHaptics.tap()
                                    applyFoodEstimate(item: item, grams: foodGrams, accumulate: true)
                                } label: {
                                    Text("+ 累加")
                                        .font(JieziFont.caption2.weight(.semibold))
                                        .foregroundStyle(scene.dataAccent)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 6)
                                        .background(scene.dataAccent.opacity(0.14), in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 6) {
                                ForEach([50, 100, 150, 200, 300], id: \.self) { g in
                                    let isSelected = foodGrams == g
                                    Button {
                                        JieziHaptics.tap()
                                        foodGrams = g
                                        foodGramsInput = "\(g)"
                                        syncSingleFoodEstimateIfNeeded()
                                    } label: {
                                        Text("\(g)g")
                                            .font(JieziFont.caption2.monospacedDigit())
                                            .foregroundStyle(isSelected ? scene.dataAccent : scene.muted)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                isSelected ? scene.surface.opacity(0.95) : scene.foreground.opacity(0.05),
                                                in: Capsule()
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .padding(10)
                        .background(scene.foreground.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else if !draft.title.isEmpty {
                        HStack {
                            Text("已记食物：\(draft.title)")
                                .font(JieziFont.caption)
                                .foregroundStyle(scene.muted)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    // 4. 运动：项目芯片流 + 惯性时长刻度尺
    private var sportStage: some View {
        VStack(spacing: 10) {
            glassCard {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 7) {
                        ForEach(["跑步", "步行", "力量", "骑行", "游泳", "瑜伽", "球类", "其他"], id: \.self) { item in
                            selectableChip(item, selected: draft.dimension == item) {
                                draft.dimension = item
                            }
                        }
                    }
                }

                JieziInertialRuler(
                    value: primaryNumericBinding(defaultValue: 40),
                    range: 5...180,
                    step: 5,
                    majorStep: 30,
                    midStep: 15,
                    scene: scene,
                    unitLabel: "分钟",
                    onScrubbingChanged: handleInstrumentScrubbing
                )

                quickPresetRow([("15m", 15), ("30m", 30), ("45m", 45), ("60m", 60), ("90m", 90)])
            }
        }
    }

    // 5. 阅读：案头在读书目 + 书签时长滑尺
    private var readingStage: some View {
        VStack(spacing: 10) {
            if !recentBookTitles.isEmpty {
                glassCard {
                    HStack {
                        Text("案头在读")
                            .font(JieziFont.subheadline.weight(.semibold))
                            .foregroundStyle(scene.foreground)
                        Spacer()
                        Text("轻点填入上方书名")
                            .font(JieziFont.caption2)
                            .foregroundStyle(scene.muted)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(recentBookTitles, id: \.self) { book in
                                selectableChip("《\(book)》", selected: draft.dimension == book) {
                                    draft.dimension = book
                                }
                            }
                        }
                    }
                }
            }

            glassCard {
                HStack {
                    Text("阅读时长")
                        .font(JieziFont.subheadline.weight(.semibold))
                        .foregroundStyle(scene.foreground)
                    Spacer()
                    Button("手动输入") {
                        directValueInput = draft.primaryValueText
                        showDirectValueEditor = true
                    }
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.accent)
                }

                JieziInertialRuler(
                    value: primaryNumericBinding(defaultValue: 35),
                    range: 5...180,
                    step: 5,
                    majorStep: 30,
                    midStep: 15,
                    scene: scene,
                    unitLabel: "分钟",
                    onScrubbingChanged: handleInstrumentScrubbing
                )

                quickPresetRow([("15m", 15), ("30m", 30), ("45m", 45), ("60m", 60), ("90m", 90)])
            }
        }
    }

    // 钱包快照保留兼容形态（由 DomainsView 独立触发）
    private var walletSnapshotStage: some View {
        VStack(spacing: 12) {
            glassCard {
                Text("钱包快照").font(JieziType.cardTitle).foregroundStyle(scene.foreground)
                Picker("记录类型", selection: $draft.walletRecordKind) {
                    Text("资产余额").tag("cash_snapshot")
                    Text("负债待还").tag("liability_snapshot")
                }
                .pickerStyle(.segmented)

                TextField("账户 / 平台名称", text: $draft.dimension)
                    .jieziInputSurface()
                TextField("快照金额", text: $draft.primaryValueText)
                    .keyboardType(.decimalPad)
                    .jieziInputSurface()
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
                if draft.walletRecordKind == "liability_snapshot" {
                    TextField("还款日期 YYYY-MM-DD（可选）", text: $draft.walletDueDate)
                        .jieziInputSurface()
                    TextField("每月还款日 1-31（可选）", text: $draft.walletBillDay)
                        .keyboardType(.numberPad)
                        .jieziInputSurface()
                }
            }
        }
    }

    // MARK: - 选填区（备注 / 时间 / 渠道 / 支付方式 / 本地图片）

    private var quietExtraTrigger: some View {
        HStack(spacing: 18) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showExtraOptions = true }
            } label: {
                Label("备注与时间", systemImage: "note.text")
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.muted)
            }
            .buttonStyle(.plain)

            if canAttachLocalImage {
                Button {
                    showLocalPhotoOptions = true
                } label: {
                    Label("添加图片", systemImage: "photo")
                        .font(JieziFont.caption)
                        .foregroundStyle(scene.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }

    private var extraDetailsCard: some View {
        glassCard {
            if draft.kind == .expense {
                HStack {
                    Text("消费渠道").font(JieziFont.subheadline).foregroundStyle(scene.muted)
                    Spacer()
                    Menu {
                        ForEach(expensePlatformOptions) { opt in
                            Button(opt.title) { draft.platform = opt.id }
                        }
                    } label: {
                        Text(optionTitle(draft.platform, options: expensePlatformOptions))
                            .font(JieziFont.subheadline)
                            .foregroundStyle(scene.foreground)
                    }
                }
                Divider().overlay(scene.foreground.opacity(0.08))
                HStack {
                    Text("支付方式").font(JieziFont.subheadline).foregroundStyle(scene.muted)
                    Spacer()
                    Menu {
                        ForEach(expensePaymentOptions) { opt in
                            Button(opt.title) { draft.paymentMethod = opt.id }
                        }
                    } label: {
                        Text(optionTitle(draft.paymentMethod, options: expensePaymentOptions))
                            .font(JieziFont.subheadline)
                            .foregroundStyle(scene.foreground)
                    }
                }
                Divider().overlay(scene.foreground.opacity(0.08))
            }

            Toggle(isOn: $draft.includesTime) {
                Text("记录具体时间").font(JieziFont.subheadline).foregroundStyle(scene.muted)
            }
            .tint(scene.accent)

            if draft.includesTime {
                DatePicker("发生时间", selection: $draft.time, displayedComponents: .hourAndMinute)
                    .font(JieziFont.subheadline)
                    .foregroundStyle(scene.foreground)
                    .tint(scene.accent)
            }

            Divider().overlay(scene.foreground.opacity(0.08))

            TextField("写下一句补充说明（选填）", text: $draft.note, axis: .vertical)
                .font(JieziFont.subheadline)
                .foregroundStyle(scene.foreground)
                .lineLimit(1...4)

            if canAttachLocalImage {
                Divider().overlay(scene.foreground.opacity(0.08))
                localImageInlineRow
            }
        }
    }

    private var hasAttachedImage: Bool {
        draft.imageData != nil || draft.existingImageData != nil || (draft.imagePath != nil && !draft.removeImage)
    }

    private var canAttachLocalImage: Bool {
        appState.supportsLocalDomainRecords && (draft.existingRawId == nil || draft.isLocalRecord)
    }

    @ViewBuilder
    private var localImageInlineRow: some View {
        if let imageData = draft.imageData ?? draft.existingImageData,
           let image = UIImage(data: imageData) {
            VStack(alignment: .leading, spacing: 8) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                HStack(spacing: 14) {
                    Button("重新选择") { showLocalPhotoOptions = true }
                        .font(JieziFont.caption.weight(.semibold))
                        .foregroundStyle(scene.accent)
                    Button("移除图片", role: .destructive) {
                        draft.imageData = nil
                        draft.existingImageData = nil
                        draft.imagePath = nil
                        draft.imageHash = nil
                        draft.removeImage = true
                    }
                    .font(JieziFont.caption)
                }
            }
        } else {
            HStack {
                Text("本机原图").font(JieziFont.subheadline).foregroundStyle(scene.muted)
                Spacer()
                Button("拍照") { showLocalCameraPicker = true }
                    .font(JieziFont.caption.weight(.semibold))
                    .foregroundStyle(scene.accent)
                Button("相册") { showLocalPhotoLibraryPicker = true }
                    .font(JieziFont.caption.weight(.semibold))
                    .foregroundStyle(scene.accent)
                    .padding(.leading, 8)
            }
        }
    }

    // MARK: - 底部五域光点轨道（1:1 复刻 MainShellView.domainPageButtons）

    private var bottomDomainRail: some View {
        VStack(spacing: 4) {
            HStack(spacing: 0) {
                ForEach(AppDomain.allCases) { domain in
                    let isSelected = domain == activeAppDomain
                    Button {
                        switchEntryDomain(to: domain)
                    } label: {
                        Capsule()
                            .fill(isSelected ? scene.pagerAccent : scene.foreground.opacity(0.28))
                            .frame(
                                width: isSelected ? JieziPrototypeLayout.selected_page_width : JieziPrototypeLayout.page_dot_size,
                                height: JieziPrototypeLayout.page_dot_size
                            )
                            .frame(width: 40, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(domain.title)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let index = Int(floor(value.location.x / 40))
                        let clamped = min(max(index, 0), AppDomain.allCases.count - 1)
                        let target = AppDomain.allCases[clamped]
                        if target != activeAppDomain {
                            switchEntryDomain(to: target)
                        }
                    }
            )

            Text("\(activeAppDomain.title) · \(domainEnglishSubtitle)")
                .font(JieziFont.caption2)
                .foregroundStyle(scene.muted)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }

    private var domainEnglishSubtitle: String {
        switch activeAppDomain {
        case .expense: return "Spending"
        case .sleep: return "Sleep"
        case .food: return "Food"
        case .sport: return "Exercise"
        case .reading: return "Reading"
        }
    }

    private func handleInstrumentScrubbing(_ active: Bool) {
        isInstrumentDragging = active
        if !active {
            lastInstrumentDragEndTime = Date.timeIntervalSinceReferenceDate
        }
    }

    private var horizontalDomainSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 28, coordinateSpace: .local)
            .onEnded { value in
                guard canSwitchDomainFreely,
                      !isInstrumentDragging,
                      Date.timeIntervalSinceReferenceDate - lastInstrumentDragEndTime > 0.15 else {
                    return
                }
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) >= 54, abs(dx) > abs(dy) * 1.5 else { return }
                let all = AppDomain.allCases
                guard let currentIndex = all.firstIndex(of: activeAppDomain) else { return }
                let nextIndex = dx < 0 ? currentIndex + 1 : currentIndex - 1
                guard all.indices.contains(nextIndex) else { return }
                switchEntryDomain(to: all[nextIndex])
            }
    }

    private func switchEntryDomain(to domain: AppDomain) {
        guard domain != activeAppDomain else { return }
        localMessage = nil
        JieziHaptics.tap()
        withAnimation(.easeInOut(duration: 0.25)) {
            if domain == .expense {
                draft.kind = .expense
                draft.domainKey = "expense"
                if draft.category.isEmpty { draft.category = "food" }
                applyDefaultAccount()
            } else {
                draft.kind = .universal
                draft.domainKey = domain.rawValue
                draft.dimension = ""
                draft.primaryValueText = ""
                Self.applyFriendlyDefaults(&draft)
            }
        }
    }

    // MARK: - 通用样式小组件

    private func glassCard<Content: View>(padding: CGFloat = 15, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            content()
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(scene.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(scene.foreground.opacity(0.08), lineWidth: 1)
        )
    }

    private func selectableChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(JieziFont.footnote.weight(selected ? .semibold : .medium))
                .foregroundStyle(
                    selected
                        ? (isDarkScene ? JieziTheme.space : scene.surface)
                        : scene.muted
                )
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(
                    selected
                        ? (isDarkScene ? scene.accent : scene.foreground)
                        : scene.foreground.opacity(0.05),
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
    }

    private func quickPresetRow(_ items: [(String, Double)]) -> some View {
        let current = Int((draft.primaryValue ?? -1).rounded())
        return HStack(spacing: 6) {
            ForEach(items, id: \.0) { label, val in
                let isSelected = current == Int(val.rounded())
                Button {
                    JieziHaptics.tap()
                    draft.primaryValueText = "\(Int(val.rounded()))"
                } label: {
                    Text(label)
                        .font(JieziFont.caption2.monospacedDigit().weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? scene.dataAccent : scene.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            isSelected ? scene.surface.opacity(0.95) : scene.foreground.opacity(0.06),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }

    private func stagingEvidenceCard(_ record: NativeStagingRecord) -> some View {
        glassCard {
            Text("识别依据").font(JieziType.cardTitle).foregroundStyle(scene.foreground)
            if let imageURL = record.imageURL {
                CachedRemoteImage(url: imageURL) { image in
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 240)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } placeholder: {
                    ProgressView("正在准备原图").frame(maxWidth: .infinity, minHeight: 100)
                } failure: {
                    Label("原图暂不可用，请依据文字结果核对", systemImage: "photo.badge.exclamationmark")
                        .font(JieziFont.footnote)
                }
            }
            Text(record.summary)
                .font(JieziFont.footnote)
                .foregroundStyle(scene.foreground)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 数值与数据读写

    private var currentSleepMinutes: Int {
        if draft.sleepUsesTimeRange {
            return max(JieziSleepRibbonMath.minimumDurationMinutes, draft.sleepWakeOffsetMinutes - draft.sleepBedOffsetMinutes)
        }
        return Int((draft.primaryValue ?? 450).rounded())
    }

    private func primaryNumericBinding(defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { draft.primaryValue ?? defaultValue },
            set: { newValue in
                let safe = newValue.isFinite ? max(0, newValue) : defaultValue
                draft.primaryValueText = "\(Int(safe.rounded()))"
            }
        )
    }

    private func handleFoodQueryChanged(_ newValue: String) {
        let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if accumulatedFoodParts.isEmpty {
            draft.title = trimmed
        }
        guard !trimmed.isEmpty else {
            selectedFoodItem = nil
            return
        }
        if let parsedGrams = JieziFoodCalorieEstimator.parseGrams(from: trimmed) {
            foodGrams = parsedGrams
            foodGramsInput = "\(parsedGrams)"
        }
        if let top = JieziFoodCalorieEstimator.search(trimmed, limit: 1).first {
            if selectedFoodItem?.id != top.id {
                selectedFoodItem = top
                if JieziFoodCalorieEstimator.parseGrams(from: trimmed) == nil {
                    foodGrams = top.defaultGrams
                    foodGramsInput = "\(top.defaultGrams)"
                }
            }
            syncSingleFoodEstimateIfNeeded()
        } else {
            selectedFoodItem = nil
        }
    }

    private func selectFoodItem(_ item: JieziFoodNutritionItem) {
        selectedFoodItem = item
        foodQueryInput = item.name
        foodGrams = item.defaultGrams
        foodGramsInput = "\(item.defaultGrams)"
        if accumulatedFoodParts.isEmpty {
            applyFoodEstimate(item: item, grams: foodGrams, accumulate: false)
        }
    }

    private func adjustFoodGrams(by delta: Int) {
        JieziHaptics.tap()
        let next = min(max(foodGrams + delta, 10), JieziFoodCalorieEstimator.maxGrams)
        foodGrams = next
        foodGramsInput = "\(next)"
        syncSingleFoodEstimateIfNeeded()
    }

    private func syncSingleFoodEstimateIfNeeded() {
        guard accumulatedFoodParts.isEmpty, let item = selectedFoodItem else { return }
        let kcal = JieziFoodCalorieEstimator.estimate(item: item, grams: foodGrams)
        draft.primaryValueText = "\(kcal)"
        draft.title = "\(item.name) \(foodGrams)g"
    }

    private func applyFoodEstimate(item: JieziFoodNutritionItem, grams: Int, accumulate: Bool) {
        let safeGrams = min(max(grams, 1), JieziFoodCalorieEstimator.maxGrams)
        let kcal = JieziFoodCalorieEstimator.estimate(item: item, grams: safeGrams)
        let partLabel = "\(item.name) \(safeGrams)g"
        if accumulate {
            let currentKcal = Int((draft.primaryValue ?? 0).rounded())
            if accumulatedFoodParts.isEmpty, !draft.title.isEmpty, draft.title != partLabel {
                accumulatedFoodParts = [draft.title]
            }
            accumulatedFoodParts.append(partLabel)
            draft.title = accumulatedFoodParts.joined(separator: " + ")
            draft.primaryValueText = "\(min(currentKcal + kcal, 9_999))"
            foodQueryInput = ""
            selectedFoodItem = nil
        } else {
            accumulatedFoodParts = []
            draft.title = partLabel
            draft.primaryValueText = "\(kcal)"
        }
    }

    private var selectedAccountTitle: String {
        guard let accountId = draft.accountId else { return "暂不绑定" }
        return accountCandidates.first(where: { $0.id == accountId })?.title ?? "暂不绑定"
    }

    private func optionTitle(_ value: String, options: [NativeManualRecordOption]) -> String {
        options.first(where: { $0.id == value })?.title ?? value
    }

    private func hydrateUniversalFields() {
        let resolvedMetadata = NativeManualDomainMetadata.resolve(selectedDomain, fallbackDomainKey: draft.domainKey)
        draft.primaryValueText = draft.originalPayload.double(resolvedMetadata.primaryKey).map { String(Int($0.rounded())) } ?? draft.primaryValueText
        draft.dimension = draft.originalPayload.string(resolvedMetadata.dimensionKey) ?? draft.dimension
    }

    private func applyDefaultAccount() {
        switch draft.kind {
        case .expense:
            draft.accountId = accountCandidates.first(where: \.isDefaultExpense)?.id
                ?? accountCandidates.first?.id
        case .income:
            draft.accountId = accountCandidates.first(where: \.isDefaultIncome)?.id
        case .universal:
            draft.accountId = nil
        }
    }

    private func save() async {
        guard !isSaving else { return }
        localMessage = nil
        if draft.kind == .universal, draft.domainKey == "sleep", draft.sleepUsesTimeRange {
            draft.primaryValueText = "\(currentSleepMinutes)"
        }
        if let validationMessage = draft.validationMessage(domain: selectedDomain) {
            localMessage = validationMessage
            JieziHaptics.warning()
            return
        }
        if let stagingRecord {
            if await appState.archiveStagingRecord(
                stagingRecord,
                draft: draft,
                domain: selectedDomain,
                preserveInboxNavigation: preserveInboxNavigation
            ) != nil {
                JieziHaptics.absorb()
                onResolved?()
                dismiss()
            } else {
                localMessage = appState.inboxActionMessage ?? "归档失败，请稍后重试。"
                JieziHaptics.warning()
            }
        } else if await appState.createManualRecord(draft, domain: selectedDomain) {
            JieziHaptics.absorb()
            onResolved?()
            if let warning = appState.localProjectionRefreshMessage {
                hasCommittedRecord = true
                localMessage = warning
            } else {
                dismiss()
            }
        } else {
            localMessage = appState.manualRecordMessage ?? "保存失败，请稍后重试。"
            JieziHaptics.warning()
        }
    }
}
