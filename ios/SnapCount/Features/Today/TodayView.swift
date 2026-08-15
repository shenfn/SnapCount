import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showUploadOptions = false
    @State private var showCameraPicker = false
    @State private var showPhotoLibraryPicker = false
    @State private var showManualRecordSheet = false
    @State private var isUploading = false
    @State private var uploadMessage: String?
    @State private var uploadMessageIsError = false
    @State private var showUploadResult = false
    @State private var showWidgetManager = false
    @State private var showDatePicker = false
    @State private var selectedDate = Date()
    @State private var widgetConfiguration = NativeHomeWidgetPreferences.load()
    @State private var financeCardConfiguration = NativeHomeInsightPreferences.loadFinance()
    @State private var domainCardConfiguration = NativeHomeInsightPreferences.loadDomains()
    @State private var selectedFinanceCard: NativeHomeFinanceCardKey = .cashSafety
    @State private var selectedDomainCard: NativeHomeDomainCardKey = .sleepRecovery
    @AppStorage(NativeUserDisplayPreferences.nicknameKey) private var nickname = ""

    private var enabledWidgets: [NativeHomeWidgetConfiguration] {
        widgetConfiguration.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    private var enabledFinanceCards: [NativeHomeFinanceCardConfiguration] {
        financeCardConfiguration.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    private var enabledDomainCards: [NativeHomeDomainCardConfiguration] {
        domainCardConfiguration.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    private var financeSummary: NativeHomeFinanceSummary {
        let daySummary = NativeHomeInsightAnalytics.dailySummary(
            on: selectedDateKey,
            from: selectedInsightSnapshot
        )
        return NativeHomeFinanceSummary.make(
            accounts: appState.accounts,
            dayExpense: daySummary.expense,
            dayIncome: daySummary.income
        )
    }

    private var pendingSummary: NativeHomePendingSummary {
        NativeHomePendingSummary.make(dashboard: appState.dashboard)
    }

    private var selectedInsightSnapshot: DashboardSnapshot {
        appState.reportSnapshot(monthKey: selectedMonthKey)
    }

    private var recentFinanceMonthKeys: [String] {
        NativeHomeInsightAnalytics.monthKeysForRecentWindow(endingAt: selectedDateKey)
    }

    private var recentFinanceSnapshot: DashboardSnapshot {
        NativeHomeInsightAnalytics.combining(
            recentFinanceMonthKeys.map { appState.reportSnapshot(monthKey: $0) }
        )
    }

    private var requiredMonthKeys: [String] {
        ([selectedMonthKey] + recentFinanceMonthKeys).reduce(into: [String]()) { result, monthKey in
            if !result.contains(monthKey) { result.append(monthKey) }
        }
    }

    private var insightLoadKey: String {
        requiredMonthKeys.joined(separator: "|")
    }

    private var selectedDateKey: String {
        Self.dateKeyFormatter.string(from: selectedDate)
    }

    private var selectedMonthKey: String {
        String(selectedDateKey.prefix(7))
    }

    private var selectedDaySummary: NativeDailySummary {
        NativeHomeInsightAnalytics.dailySummary(on: selectedDateKey, from: selectedInsightSnapshot)
    }

    private var selectedMonthSummaries: [NativeDailySummary] {
        let summaries = NativeHomeInsightAnalytics.dailySummaries(from: selectedInsightSnapshot)
        return summaries.isEmpty ? [selectedDaySummary] : summaries
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    masthead
                    dashboardStatus
                    if isFreshCanvas {
                        freshCanvasCard
                    } else if enabledWidgets.isEmpty {
                        emptyWidgetState
                    } else {
                        ForEach(enabledWidgets) { widget in
                            widgetView(widget.key)
                        }
                    }
                }
                .animation(JieziEasing.standard, value: isFreshCanvas)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadAccounts()
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    captureFab
                }
                .padding(.trailing, 16)
            }
        }
        .navigationBarHidden(true)
        .confirmationDialog("留下此刻", isPresented: $showUploadOptions, titleVisibility: .visible) {
            Button("手动记录") { showManualRecordSheet = true }
            Button("从相册选择") { showPhotoLibraryPicker = true }
            Button("拍摄照片") { showCameraPicker = true }
            Button("取消", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showCameraPicker) {
            CameraPicker { data in
                showCameraPicker = false
                Task { await uploadImageData(data, captureKind: "camera", filename: "camera-capture.jpg") }
            } onCancel: { showCameraPicker = false }
                .ignoresSafeArea()
        }
        .sheet(isPresented: $showPhotoLibraryPicker) {
            PhotoLibraryPicker { data in
                showPhotoLibraryPicker = false
                Task { await uploadImageData(data, captureKind: "screenshot", filename: "photo-library-upload.jpg") }
            } onCancel: { showPhotoLibraryPicker = false }
        }
        .sheet(isPresented: $showManualRecordSheet) {
            ManualRecordSheet()
        }
        .sheet(isPresented: $showWidgetManager) {
            HomeWidgetManagerSheet(
                configuration: $widgetConfiguration,
                financeConfiguration: $financeCardConfiguration,
                domainConfiguration: $domainCardConfiguration
            )
        }
        .sheet(isPresented: $showDatePicker) {
            NavigationStack {
                DatePicker(
                    "选择日期",
                    selection: $selectedDate,
                    in: ...Date(),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("选择日期")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showDatePicker = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .alert(uploadMessageIsError ? "上传失败" : "上传完成", isPresented: $showUploadResult) {
            Button("好", role: .cancel) {}
        } message: { Text(uploadMessage ?? "") }
        .task {
            if appState.accounts.isEmpty { await appState.loadAccounts() }
        }
        .task(id: insightLoadKey) {
            for monthKey in requiredMonthKeys {
                await appState.loadRecordMonth(monthKey)
            }
        }
        .onAppear {
            normalizeInsightSelections()
        }
        .onChange(of: financeCardConfiguration) { _ in
            normalizeInsightSelections()
        }
        .onChange(of: domainCardConfiguration) { _ in
            normalizeInsightSelections()
        }
    }

    @ViewBuilder
    private var dashboardStatus: some View {
        if appState.isLoadingDashboard && appState.dashboard.monthCount == 0 {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在同步 PWA 数据")
            }
            .font(.subheadline)
            .foregroundStyle(JieziTheme.muted)
        } else if appState.isShowingCachedDashboard {
            Text(appState.dashboardMessage ?? "正在展示本地数据，芥子会在后台同步最新内容。")
                .font(.footnote)
                .foregroundStyle(JieziTheme.gold)
        } else if let message = appState.dashboardMessage {
            Button { Task { await appState.refreshDashboard() } } label: {
                Label("数据加载失败，点此重试：\(message)", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(JieziTheme.coral)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        } else if !appState.dashboard.loadWarnings.isEmpty {
            Text("部分数据域暂未同步，已显示可用数据")
                .font(.footnote)
                .foregroundStyle(JieziTheme.gold)
        }
    }

    private var masthead: some View {
        HomeMastheadView(
            dateText: Self.fullDateFormatter.string(from: selectedDate),
            syncText: syncStatusText,
            greetingText: NativeDayGreeting.line(nickname: nickname.isEmpty ? nil : nickname),
            briefText: briefLine,
            whisper: currentWhisper,
            onCalendar: { showDatePicker = true },
            onManageWidgets: { showWidgetManager = true },
            onWhisperTap: { appState.selectedTab = .insights }
        )
    }

    private var isViewingToday: Bool {
        selectedDateKey == Self.todayKey
    }

    private var syncStatusText: String {
        if appState.isLoadingDashboard { return "同步中" }
        if let syncedAt = appState.lastDashboardSyncedAt {
            return "\(Self.timeFormatter.string(from: syncedAt)) 已同步"
        }
        return "待同步"
    }

    private var briefLine: String {
        let day = selectedDaySummary
        let prefix = isViewingToday ? "今日" : Self.monthDayFormatter.string(from: selectedDate)
        var parts: [String] = []
        parts.append(day.recordCount > 0 ? "已记 \(day.recordCount) 条" : "还没落笔")
        if day.expense > 0 { parts.append("支出 ¥\(Int(day.expense.rounded()))") }
        if day.income > 0 { parts.append("收入 ¥\(Int(day.income.rounded()))") }
        if pendingSummary.total > 0 { parts.append("\(pendingSummary.total) 条待处理") }
        return "\(prefix) " + parts.joined(separator: " · ")
    }

    private var currentWhisper: NativeHomeWhisper {
        NativeHomeWhisper.make(
            isToday: isViewingToday,
            dayRecordCount: selectedDaySummary.recordCount,
            pendingCount: pendingSummary.total
        )
    }

    private var emptyWidgetState: some View {
        ContentUnavailableView {
            Label("首页组件已全部隐藏", systemImage: "rectangle.stack.badge.minus")
        } description: {
            Text("重新选择组件后，首页会恢复你的常用信息。")
        } actions: {
            Button("管理组件") { showWidgetManager = true }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
    }

    /// 新账号 / 全无数据时，首页不显示 ¥0 与空指标砖，改为一张衬线大字的「尚未落笔」引导卡。
    private var isFreshCanvas: Bool {
        guard !appState.isLoadingDashboard else { return false }
        let dashboard = appState.dashboard
        return dashboard.monthCount == 0
            && dashboard.todayCount == 0
            && dashboard.pendingCount == 0
            && dashboard.dailySummaries.isEmpty
    }

    private var freshCanvasCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(JieziTheme.gold)
                    .frame(width: 22, height: 1)
                Text("SNAPCOUNT · DAY 0")
                    .font(JieziFont.caption2)
                    .foregroundStyle(JieziTheme.muted)
                    .tracking(1.4)
            }
            Text("尚未落笔")
                .font(JieziType.displayLarge)
                .foregroundStyle(JieziTheme.space)
            Text("按下右下角，记下第一条。芥子会顺着你的笔迹，一点点把这一页填成你的样子。")
                .font(.system(size: 14, design: .serif))
                .foregroundStyle(JieziTheme.ink.opacity(0.72))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Divider()
                .overlay(JieziTheme.brand.opacity(0.12))
                .padding(.vertical, 2)
            HStack(spacing: 18) {
                freshCanvasStat(label: "今日支出", placeholder: "—")
                freshCanvasStat(label: "本月记录", placeholder: "—")
                freshCanvasStat(label: "待处理", placeholder: "—")
            }
            HStack(spacing: 10) {
                Button {
                    showUploadOptions = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus.circle.fill")
                        Text("留下第一条")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(JieziTheme.brand, in: Capsule())
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
                Button {
                    showManualRecordSheet = true
                } label: {
                    Text("手动记录")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(JieziTheme.brand)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .overlay(Capsule().stroke(JieziTheme.brand.opacity(0.35)))
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
                Spacer()
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .jieziCard(palette: JieziTheme.palette, solid: true)
    }

    private func freshCanvasStat(label: String, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(JieziFont.caption2)
                .foregroundStyle(JieziTheme.muted)
                .tracking(0.6)
            Text(placeholder)
                .font(.system(size: 20, weight: .semibold, design: .serif).monospacedDigit())
                .foregroundStyle(JieziTheme.ink.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func widgetView(_ key: NativeHomeWidgetKey) -> some View {
        switch key {
        case .finance:
            financeSection
        case .today:
            todaySection
        case .pending:
            pendingSection
        case .domains:
            domainsSection
        case .daily:
            dailySection
        }
    }

    private var financeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "财务状态", subtitle: financeScopeLabel) {
                NavigationLink {
                    AccountsView()
                } label: {
                    Label("账户", systemImage: "chevron.right")
                }
            }
            if enabledFinanceCards.isEmpty {
                insightEmptyState(title: "财务卡片已隐藏", message: "在首页组件管理中选择你最关心的财务信息。")
            } else {
                TabView(selection: $selectedFinanceCard) {
                    ForEach(enabledFinanceCards) { configuration in
                        NavigationLink {
                            financeDestination(for: configuration.key)
                        } label: {
                            HomeFinanceInsightCardView(
                                key: configuration.key,
                                summary: financeSummary,
                                snapshot: selectedInsightSnapshot,
                                recentSnapshot: recentFinanceSnapshot,
                                accounts: appState.accounts,
                                selectedDateKey: selectedDateKey
                            )
                        }
                        .buttonStyle(JieziPressableButtonStyle())
                        .accessibilityHint("打开\(configuration.key.title)详情")
                        .tag(configuration.key)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 270)
            }
        }
    }

    private var todaySection: some View {
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: selectedDateKey == Self.todayKey ? "今日记录" : "当天记录", subtitle: "按数据域查看所选日期")
            dailyCard(selectedDaySummary)
        }
    }

    private var financeScopeLabel: String {
        selectedDateKey == Self.todayKey
            ? "账户状态实时 · 今日收支"
            : "账户状态实时 · \(Self.monthDayFormatter.string(from: selectedDate))收支"
    }

    private var pendingSection: some View {
        Button {
            appState.openInbox(filter: .all)
        } label: {
            HStack(spacing: 12) {
                Text("\(pendingSummary.total)")
                    .font(.system(size: 22, weight: .bold, design: .serif).monospacedDigit())
                    .foregroundStyle(pendingSummary.total > 0 ? JieziTheme.gold : JieziTheme.muted)
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 2) {
                    Text(pendingSummary.total > 0 ? "条记录待安顿" : "待处理都已安顿")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(JieziTheme.ink)
                    if pendingSummary.total > 0 {
                        Text(pendingBreakdown)
                            .font(JieziFont.caption2)
                            .foregroundStyle(JieziTheme.muted)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(JieziTheme.muted)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous))
            .jieziCard(palette: JieziTheme.palette, solid: true)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .animation(JieziEasing.standard, value: pendingSummary.total)
        .accessibilityLabel(pendingSummary.total > 0 ? "\(pendingSummary.total) 条待处理：\(pendingBreakdown)" : "没有待处理")
        .accessibilityHint("打开待处理收件箱")
    }

    private var pendingBreakdown: String {
        var parts: [String] = []
        if pendingSummary.pendingExpenses > 0 { parts.append("补全 \(pendingSummary.pendingExpenses)") }
        if pendingSummary.routing > 0 { parts.append("分类 \(pendingSummary.routing)") }
        if pendingSummary.review > 0 { parts.append("确认 \(pendingSummary.review)") }
        if pendingSummary.failed > 0 { parts.append("重试 \(pendingSummary.failed)") }
        if pendingSummary.repair > 0 { parts.append("修补 \(pendingSummary.repair)") }
        return parts.joined(separator: " · ")
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "数据域", subtitle: "所选月记录分布") {
                NavigationLink {
                    DomainsView()
                } label: {
                    Label("全部", systemImage: "chevron.right")
                }
            }
            if enabledDomainCards.isEmpty {
                insightEmptyState(title: "数据域卡片已隐藏", message: "在首页组件管理中选择你想长期观察的生活信息。")
            } else {
                TabView(selection: $selectedDomainCard) {
                    ForEach(enabledDomainCards) { configuration in
                        NavigationLink {
                            domainDestination(for: configuration.key)
                        } label: {
                            HomeDomainInsightCardView(
                                key: configuration.key,
                                snapshot: selectedInsightSnapshot,
                                selectedDaySummary: NativeHomeInsightAnalytics.dailySummary(
                                    on: selectedDateKey,
                                    from: selectedInsightSnapshot
                                ),
                                selectedDateKey: selectedDateKey
                            )
                        }
                        .buttonStyle(JieziPressableButtonStyle())
                        .accessibilityHint("打开\(configuration.key.title)详情")
                        .tag(configuration.key)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
                .frame(height: 246)
            }
        }
    }

    private func insightEmptyState(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jieziCard(palette: JieziTheme.palette, solid: true)
    }

    private func normalizeInsightSelections() {
        if let first = enabledFinanceCards.first?.key,
           !enabledFinanceCards.contains(where: { $0.key == selectedFinanceCard }) {
            selectedFinanceCard = first
        }
        if let first = enabledDomainCards.first?.key,
           !enabledDomainCards.contains(where: { $0.key == selectedDomainCard }) {
            selectedDomainCard = first
        }
    }

    @ViewBuilder
    private func financeDestination(for key: NativeHomeFinanceCardKey) -> some View {
        switch key.destination {
        case .accounts:
            AccountsView()
        case .records:
            RecordsView(initialMonthKey: selectedMonthKey)
        case .expenseDomain:
            domainDetailOrList(domainKey: "expense")
        case .nearestLiability:
            if let account = financeSummary.nearestLiability {
                AccountDetailView(accountId: account.id)
            } else {
                AccountsView()
            }
        }
    }

    @ViewBuilder
    private func domainDestination(for key: NativeHomeDomainCardKey) -> some View {
        switch key.destination {
        case .domain(let domainKey):
            domainDetailOrList(domainKey: domainKey)
        case .allDomains:
            DomainsView()
        case .selectedDay:
            DayDetailView(route: NativeDayDetailRoute(dateKey: selectedDateKey, kind: .all))
        }
    }

    @ViewBuilder
    private func domainDetailOrList(domainKey: String) -> some View {
        if let domain = appState.dashboard.domains.first(where: { $0.id == domainKey }) {
            DomainDetailView(domain: domain)
        } else {
            DomainsView()
        }
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) -> some View {
        JieziSectionHeader(title: title, subtitle: subtitle) {
            accessory()
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        sectionHeader(title: title, subtitle: subtitle) { EmptyView() }
    }

    private var captureFab: some View {
        Button {
            JieziHaptics.tap()
            showUploadOptions = true
        } label: {
            Image(systemName: isUploading ? "hourglass" : "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(JieziTheme.brand, in: Circle())
                .shadow(color: JieziTheme.brand.opacity(0.35), radius: 12, x: 0, y: 6)
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.92))
        .disabled(isUploading)
        .accessibilityLabel("留下此刻：手动记录、相册或拍照")
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "因缘流转", subtitle: "按日期汇总\(NativeMonthKey.title(selectedMonthKey))") {
                Button {
                    showDatePicker = true
                } label: {
                    Label("选日期", systemImage: "calendar")
                }
            }

            JieziMonthSwitcher(
                title: NativeMonthKey.title(selectedMonthKey),
                selectionToken: selectedMonthKey,
                canAdvance: selectedMonthKey < Self.currentMonthKey,
                onPrevious: { shiftSelectedMonth(-1) },
                onNext: { shiftSelectedMonth(1) }
            )

            ForEach(selectedMonthSummaries) { dailyCard($0) }
        }
    }

    private func dailyCard(_ day: NativeDailySummary) -> some View {
        let group = appState.recordGroups(monthKey: String(day.dateKey.prefix(7))).first { $0.dateKey == day.dateKey }
        return NavigationLink(value: NativeDayDetailRoute(dateKey: day.dateKey, kind: .all)) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(String(day.dateKey.suffix(5)))
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .monospacedDigit()
                    Spacer()
                    Text(weekday(day.dateKey))
                        .font(.headline)
                        .foregroundStyle(JieziTheme.muted)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(JieziTheme.muted)
                }
                Divider().overlay(JieziTheme.muted.opacity(0.2))
                if day.expense > 0 {
                    daySummaryRow(color: JieziTheme.coral, title: "支出", value: money(day.expense))
                }
                if day.income > 0 {
                    daySummaryRow(color: JieziTheme.brand, title: "收入", value: money(day.income, signed: true))
                }
                ForEach(group?.availableKinds.filter { ![.all, .expense, .income, .staging].contains($0) } ?? []) { kind in
                    daySummaryRow(color: JieziTheme.mint, title: kind.title, value: "\(group?.records(for: kind).count ?? 0)条")
                }
                if day.pendingCount > 0 {
                    daySummaryRow(color: JieziTheme.gold, title: "待处理", value: "\(day.pendingCount)条")
                }
                if day.recordCount == 0 && day.pendingCount == 0 {
                    summaryRow(color: JieziTheme.muted, title: "记录", value: "0条")
                }
            }
            .foregroundStyle(JieziTheme.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous))
            .jieziCard(palette: JieziTheme.palette, solid: true)
        }
        .buttonStyle(JieziPressableButtonStyle())
        .accessibilityHint("打开当天全部记录")
    }

    private func daySummaryRow(color: Color, title: String, value: String) -> some View {
        HStack {
            summaryRow(color: color, title: title, value: value)
            Image(systemName: "chevron.right")
                .font(.caption2.bold())
                .foregroundStyle(JieziTheme.muted)
        }
    }

    private func summaryRow(color: Color, title: String, value: String) -> some View {
        HStack {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(title).foregroundStyle(JieziTheme.muted)
            Spacer()
            Text(value).font(.headline.monospacedDigit())
        }
    }

    private func shiftSelectedMonth(_ offset: Int) {
        guard let shiftedMonth = NativeMonthKey.shifted(selectedMonthKey, by: offset),
              let shiftedDate = Self.dateKeyFormatter.date(from: "\(shiftedMonth)-01") else { return }
        selectedDate = shiftedDate
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
    }

    private func weekday(_ dateKey: String) -> String {
        guard let date = Self.dateKeyFormatter.date(from: dateKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private func uploadImageData(_ data: Data, captureKind: String, filename: String) async {
        isUploading = true
        defer { isUploading = false }
        do {
            guard let uploadToken = try KeychainStore.shared.string(for: KeychainKeys.uploadToken), !uploadToken.isEmpty else { throw SnapCountUploadServiceError.requestFailed("登录凭据未同步，请重新登录") }
            let result = try await SnapCountUploadService().uploadNativeImageResult(
                data: data,
                uploadToken: uploadToken,
                captureKind: captureKind,
                filename: filename
            )
            uploadMessage = result.notificationText
            uploadMessageIsError = false
            await appState.refreshDashboard()
        } catch {
            uploadMessage = "上传失败：\(error.localizedDescription)"
            uploadMessageIsError = true
        }
        showUploadResult = true
    }

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"; return formatter
    }()
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "EEE"; return formatter
    }()
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日"; return formatter
    }()
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "HH:mm"; return formatter
    }()
    private static var todayKey: String { dateKeyFormatter.string(from: Date()) }
    private static var currentMonthKey: String { NativeMonthKey.current() }
}

private struct HomeWidgetManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration: [NativeHomeWidgetConfiguration]
    @Binding var financeConfiguration: [NativeHomeFinanceCardConfiguration]
    @Binding var domainConfiguration: [NativeHomeDomainCardConfiguration]

    var body: some View {
        NavigationStack {
            List {
                Section("首页组件") {
                    ForEach(configuration.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Image(systemName: configuration[index].key.systemImage)
                                .foregroundStyle(JieziTheme.mint)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(configuration[index].key.title)
                                    .font(.headline)
                                Text(configuration[index].key.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $configuration[index].isEnabled)
                                .labelsHidden()
                            Button {
                                move(index, offset: -1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == 0)
                            .accessibilityLabel("上移\(configuration[index].key.title)")
                            Button {
                                move(index, offset: 1)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(index == configuration.count - 1)
                            .accessibilityLabel("下移\(configuration[index].key.title)")
                        }
                        .padding(.vertical, 5)
                    }
                }

                Section {
                    Text("财务状态和数据域各最多显示 3 张卡片，首页可左右滑动查看。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("财务状态卡片") {
                    ForEach(financeConfiguration.indices, id: \.self) { index in
                        insightConfigurationRow(
                            title: financeConfiguration[index].key.title,
                            detail: financeConfiguration[index].key.detail,
                            systemImage: financeConfiguration[index].key.systemImage,
                            isEnabled: financeConfiguration[index].isEnabled,
                            enabledCount: financeConfiguration.filter(\.isEnabled).count,
                            onToggle: { isEnabled in
                                financeConfiguration = NativeHomeInsightPreferences.updatingFinance(
                                    financeConfiguration,
                                    key: financeConfiguration[index].key,
                                    isEnabled: isEnabled
                                )
                            },
                            moveUp: { moveFinance(index, offset: -1) },
                            moveDown: { moveFinance(index, offset: 1) },
                            isFirst: index == 0,
                            isLast: index == financeConfiguration.count - 1
                        )
                    }
                }

                Section("数据域卡片") {
                    ForEach(domainConfiguration.indices, id: \.self) { index in
                        insightConfigurationRow(
                            title: domainConfiguration[index].key.title,
                            detail: domainConfiguration[index].key.detail,
                            systemImage: domainConfiguration[index].key.systemImage,
                            isEnabled: domainConfiguration[index].isEnabled,
                            enabledCount: domainConfiguration.filter(\.isEnabled).count,
                            onToggle: { isEnabled in
                                domainConfiguration = NativeHomeInsightPreferences.updatingDomain(
                                    domainConfiguration,
                                    key: domainConfiguration[index].key,
                                    isEnabled: isEnabled
                                )
                            },
                            moveUp: { moveDomain(index, offset: -1) },
                            moveDown: { moveDomain(index, offset: 1) },
                            isFirst: index == 0,
                            isLast: index == domainConfiguration.count - 1
                        )
                    }
                }

                Section {
                    Button("恢复默认") {
                        configuration = NativeHomeWidgetPreferences.defaults
                        financeConfiguration = NativeHomeInsightPreferences.financeDefaults
                        domainConfiguration = NativeHomeInsightPreferences.domainDefaults
                    }
                }
            }
            .navigationTitle("管理首页")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .onChange(of: configuration) { value in
            NativeHomeWidgetPreferences.save(value)
        }
        .onChange(of: financeConfiguration) { value in
            NativeHomeInsightPreferences.saveFinance(value)
        }
        .onChange(of: domainConfiguration) { value in
            NativeHomeInsightPreferences.saveDomains(value)
        }
    }

    private func insightConfigurationRow(
        title: String,
        detail: String,
        systemImage: String,
        isEnabled: Bool,
        enabledCount: Int,
        onToggle: @escaping (Bool) -> Void,
        moveUp: @escaping () -> Void,
        moveDown: @escaping () -> Void,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(JieziTheme.mint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Toggle("", isOn: Binding(get: { isEnabled }, set: onToggle))
                .labelsHidden()
                .disabled(!isEnabled && enabledCount >= NativeHomeInsightPreferences.maximumEnabledCards)
            Button(action: moveUp) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .disabled(isFirst)
            .accessibilityLabel("上移\(title)")
            Button(action: moveDown) {
                Image(systemName: "arrow.down")
            }
            .buttonStyle(.borderless)
            .disabled(isLast)
            .accessibilityLabel("下移\(title)")
        }
        .padding(.vertical, 5)
    }

    private func move(_ index: Int, offset: Int) {
        let destination = index + offset
        guard configuration.indices.contains(index), configuration.indices.contains(destination) else { return }
        configuration.swapAt(index, destination)
        configuration = configuration.enumerated().map { order, item in
            NativeHomeWidgetConfiguration(key: item.key, isEnabled: item.isEnabled, order: order)
        }
    }

    private func moveFinance(_ index: Int, offset: Int) {
        let destination = index + offset
        guard financeConfiguration.indices.contains(index), financeConfiguration.indices.contains(destination) else { return }
        financeConfiguration.swapAt(index, destination)
        financeConfiguration = financeConfiguration.enumerated().map { order, item in
            NativeHomeFinanceCardConfiguration(key: item.key, isEnabled: item.isEnabled, order: order)
        }
    }

    private func moveDomain(_ index: Int, offset: Int) {
        let destination = index + offset
        guard domainConfiguration.indices.contains(index), domainConfiguration.indices.contains(destination) else { return }
        domainConfiguration.swapAt(index, destination)
        domainConfiguration = domainConfiguration.enumerated().map { order, item in
            NativeHomeDomainCardConfiguration(key: item.key, isEnabled: item.isEnabled, order: order)
        }
    }
}
