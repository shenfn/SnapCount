import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var appState: AppState
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

    private var recentHomeMonthKeys: [String] {
        NativeHomeInsightAnalytics.monthKeysForRecentWindow(endingAt: selectedDateKey, dayCount: 14)
    }

    private var recentHomeSnapshot: DashboardSnapshot {
        NativeHomeInsightAnalytics.combining(
            recentHomeMonthKeys.map { appState.reportSnapshot(monthKey: $0) }
        )
    }

    private var requiredMonthKeys: [String] {
        ([selectedMonthKey] + recentHomeMonthKeys).reduce(into: [String]()) { result, monthKey in
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

    private var timelineRecords: [NativeDayRecord] {
        NativeHomeInsightAnalytics.timelineRecords(on: selectedDateKey, from: selectedInsightSnapshot)
    }

    private var activityDays: [NativeHomeActivityDay] {
        NativeHomeInsightAnalytics.activityDays(from: recentHomeSnapshot, endingAt: selectedDateKey)
    }

    private var earlierSummaries: [NativeDailySummary] {
        NativeHomeInsightAnalytics.earlierDailySummaries(
            before: selectedDateKey,
            from: recentHomeSnapshot
        )
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JieziSpacing.xl3) {
                    HomeMastheadView(
                        selectedDate: selectedDate,
                        isToday: selectedDateKey == Self.todayKey,
                        summary: selectedDaySummary,
                        stableRecordCount: timelineRecords.count,
                        isLoading: appState.isLoadingDashboard,
                        isShowingCachedData: appState.isShowingCachedDashboard,
                        onSelectDate: { showDatePicker = true },
                        onManageWidgets: { showWidgetManager = true }
                    )
                    dashboardStatus
                    if enabledWidgets.isEmpty {
                        emptyWidgetState
                    } else {
                        ForEach(enabledWidgets) { widget in
                            widgetView(widget.key)
                        }
                    }
                }
                .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                .padding(.top, JieziSpacing.md)
                .padding(.bottom, JieziSpacing.xl3)
            }
            .scrollIndicators(.hidden)
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadAccounts()
            }
        }
        .navigationBarHidden(true)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            captureDock
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
        .sensoryFeedback(.selection, trigger: selectedDateKey)
        .sensoryFeedback(.selection, trigger: selectedFinanceCard)
        .sensoryFeedback(.selection, trigger: selectedDomainCard)
    }

    @ViewBuilder
    private var dashboardStatus: some View {
        if appState.isLoadingDashboard && appState.dashboard.monthCount == 0 {
            HStack(spacing: 10) {
                ProgressView()
                Text("正在同步数据")
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
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
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
                                recentSnapshot: recentHomeSnapshot,
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
                .accessibilityLabel("财务状态卡片")
            }
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            sectionHeader(
                title: selectedDateKey == Self.todayKey ? "今日轨迹" : "当天轨迹",
                subtitle: "按发生时间排列的已确认记录"
            ) {
                NavigationLink(value: NativeDayDetailRoute(dateKey: selectedDateKey, kind: .all)) {
                    Label("全部", systemImage: "chevron.right")
                }
            }
            HomeTimelineView(records: timelineRecords, dateKey: selectedDateKey)
        }
    }

    private var financeScopeLabel: String {
        selectedDateKey == Self.todayKey
            ? "账户状态实时 · 今日收支"
            : "账户状态实时 · \(Self.monthDayFormatter.string(from: selectedDate))收支"
    }

    private var pendingSection: some View {
        Menu {
            pendingAction("待补全账单", count: pendingSummary.pendingExpenses, systemImage: "clock.badge.exclamationmark", filter: .pendingExpense)
            pendingAction("待分类", count: pendingSummary.routing, systemImage: "questionmark.folder", filter: .routing)
            pendingAction("待确认", count: pendingSummary.review, systemImage: "checklist", filter: .review)
            pendingAction("识别失败", count: pendingSummary.failed, systemImage: "exclamationmark.triangle", filter: .failed)
            pendingAction("待修补", count: pendingSummary.repair, systemImage: "wrench.and.screwdriver", filter: .repair)
        } label: {
            HStack(spacing: JieziSpacing.md) {
                Image(systemName: pendingSummary.total > 0 ? "tray.full" : "checkmark.circle")
                    .font(JieziFont.title3)
                    .foregroundStyle(pendingSummary.total > 0 ? JieziTheme.gold : JieziTheme.brand)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                    Text("因缘流转")
                        .font(JieziType.cardTitle)
                        .foregroundStyle(JieziTheme.ink)
                    Text(pendingSummary.total > 0 ? "\(pendingSummary.total) 条等待处理，点按查看分类" : "目前没有待处理事项")
                        .font(JieziFont.caption)
                        .foregroundStyle(JieziTheme.muted)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(JieziFont.caption2.weight(.semibold))
                    .foregroundStyle(JieziTheme.muted)
            }
            .padding(JieziSpacing.md)
            .background(JieziTheme.palette.paper.opacity(0.58), in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                    .stroke(JieziTheme.brand.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(JieziPressableButtonStyle())
        .accessibilityLabel("因缘流转，\(pendingSummary.total) 条待处理")
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            sectionHeader(title: "生活切面", subtitle: "来自所选月份的稳定数据") {
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
                .accessibilityLabel("生活数据卡片")
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

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.xl2) {
            VStack(alignment: .leading, spacing: JieziSpacing.md) {
                sectionHeader(title: "近 14 天", subtitle: "只统计已确认记录，点按日期可回看")
                HomeActivityDensityView(
                    days: activityDays,
                    selectedDateKey: selectedDateKey,
                    onSelectDate: selectDateKey
                )
            }

            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                sectionHeader(title: "早前历史", subtitle: "所选日期之前的最近记录")
                HomeEarlierHistoryView(summaries: earlierSummaries)
            }
        }
    }

    private var captureDock: some View {
        HStack {
            Spacer()
            Menu {
                ForEach(NativeHomeCaptureAction.allCases) { action in
                    Button {
                        JieziHaptics.confirm()
                        performCaptureAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                }
            } label: {
                Label(isUploading ? "识别中" : "留下此刻", systemImage: isUploading ? "hourglass" : "camera.badge.ellipsis")
                    .font(JieziType.button)
                    .foregroundStyle(.white)
                    .padding(.horizontal, JieziSpacing.lg)
                    .frame(minHeight: 50)
                    .background(JieziTheme.brand, in: Capsule())
                    .shadow(color: JieziTheme.space.opacity(0.16), radius: 16, x: 0, y: 8)
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.94))
            .disabled(isUploading)
            .accessibilityHint("可选择拍照、相册或手动记录")
        }
        .padding(.horizontal, JieziSpacing.Semantic.page_padding)
        .padding(.vertical, JieziSpacing.sm)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private func pendingAction(
        _ title: String,
        count: Int,
        systemImage: String,
        filter: NativeInboxFilter
    ) -> some View {
        Button {
            appState.openInbox(filter: filter)
        } label: {
            Label("\(title) · \(count)", systemImage: systemImage)
        }
        .disabled(count == 0)
    }

    private func performCaptureAction(_ action: NativeHomeCaptureAction) {
        switch action {
        case .camera: showCameraPicker = true
        case .photoLibrary: showPhotoLibraryPicker = true
        case .manual: showManualRecordSheet = true
        }
    }

    private func selectDateKey(_ dateKey: String) {
        guard let date = Self.dateKeyFormatter.date(from: dateKey) else { return }
        selectedDate = date
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
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

    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let monthDayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "M月d日"; return formatter
    }()
    private static var todayKey: String { dateKeyFormatter.string(from: Date()) }
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
