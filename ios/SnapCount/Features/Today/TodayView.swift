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

    private var enabledWidgets: [NativeHomeWidgetConfiguration] {
        widgetConfiguration.filter(\.isEnabled).sorted { $0.order < $1.order }
    }

    private var financeSummary: NativeHomeFinanceSummary {
        NativeHomeFinanceSummary.make(accounts: appState.accounts, dashboard: appState.dashboard)
    }

    private var pendingSummary: NativeHomePendingSummary {
        NativeHomePendingSummary.make(dashboard: appState.dashboard)
    }

    private var selectedDateKey: String {
        Self.dateKeyFormatter.string(from: selectedDate)
    }

    private var selectedMonthKey: String {
        String(selectedDateKey.prefix(7))
    }

    private var selectedMonthGroups: [NativeDayRecordGroup] {
        appState.recordGroups(monthKey: selectedMonthKey)
    }

    private var selectedDayGroup: NativeDayRecordGroup? {
        selectedMonthGroups.first { $0.dateKey == selectedDateKey }
    }

    private var selectedDaySummary: NativeDailySummary {
        if let summary = appState.dashboard.dailySummaries.first(where: { $0.dateKey == selectedDateKey }) {
            return summary
        }
        return summary(from: selectedDayGroup, dateKey: selectedDateKey)
    }

    private var selectedMonthSummaries: [NativeDailySummary] {
        if selectedMonthKey == Self.currentMonthKey, !appState.dashboard.dailySummaries.isEmpty {
            return appState.dashboard.dailySummaries
        }
        let summaries = selectedMonthGroups.map { summary(from: $0, dateKey: $0.dateKey) }
        return summaries.isEmpty ? [selectedDaySummary] : summaries
    }

    var body: some View {
        ZStack {
            JieziPageBackground()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    header
                    dashboardStatus
                    captureButton
                    widgetManagerHeader
                    if enabledWidgets.isEmpty {
                        emptyWidgetState
                    } else {
                        ForEach(enabledWidgets) { widget in
                            widgetView(widget.key)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
            .refreshable {
                await appState.refreshDashboard()
                await appState.loadAccounts()
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
            HomeWidgetManagerSheet(configuration: $widgetConfiguration)
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
        .task(id: selectedMonthKey) {
            await appState.loadRecordMonth(selectedMonthKey)
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

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("个人数据平台")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(JieziTheme.ink)
                Text(Self.fullDateFormatter.string(from: selectedDate))
                    .font(.subheadline)
                    .foregroundStyle(JieziTheme.muted)
            }
            Spacer()
            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 7) {
                    Text(Self.monthFormatter.string(from: selectedDate))
                        .font(.headline)
                    Image(systemName: "calendar")
                        .font(.caption.bold())
                }
                .foregroundStyle(JieziTheme.ink)
                .padding(.horizontal, 16)
                .frame(minHeight: 44)
                .background(.white.opacity(0.82), in: Capsule())
                .overlay(Capsule().stroke(JieziTheme.brand.opacity(0.08)))
            }
            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
            .accessibilityLabel("选择首页日期")
        }
    }

    private var widgetManagerHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("首页组件")
                    .font(.headline)
                Text("已启用 \(enabledWidgets.count) 个")
                    .font(.caption)
                    .foregroundStyle(JieziTheme.muted)
            }
            Spacer()
            Button {
                showWidgetManager = true
            } label: {
                Label("管理", systemImage: "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
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
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "财务状态", subtitle: financeSummary.statusLabel) {
                NavigationLink {
                    AccountsView()
                } label: {
                    Label("账户", systemImage: "chevron.right")
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("净额估算")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                        Text(money(financeSummary.netWorthEstimate, signed: true))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    }
                    Spacer()
                    Text(financeSummary.statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.brand)
                }

                HStack(spacing: 10) {
                    metric(title: "可用现金", value: money(financeSummary.availableCash))
                    metric(title: "当前欠款", value: money(financeSummary.liabilityTotal))
                }
                HStack(spacing: 10) {
                    metric(title: "今日收入", value: money(financeSummary.todayIncome, signed: true))
                    metric(title: "今日支出", value: money(financeSummary.todayExpense))
                }

                if let liability = financeSummary.nearestLiability {
                    NavigationLink {
                        AccountsView()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("最近待还")
                                    .font(.caption)
                                    .foregroundStyle(JieziTheme.muted)
                                Text(liability.title)
                                    .font(.headline)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(money(liability.currentBalance))
                                    .font(.headline.monospacedDigit())
                                Text(liability.paymentDueDay.map { "每月 \($0) 日" } ?? "未设置还款日")
                                    .font(.caption)
                                    .foregroundStyle(JieziTheme.muted)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption.bold())
                                .foregroundStyle(JieziTheme.muted)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(18)
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var todaySection: some View {
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: selectedDateKey == Self.todayKey ? "今日记录" : "当天记录", subtitle: "按数据域查看所选日期")
            dailyCard(selectedDaySummary)
        }
    }

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "因缘流转", subtitle: "\(pendingSummary.total) 条待处理")
            Button {
                appState.selectedTab = .inbox
            } label: {
                VStack(spacing: 12) {
                    pendingRow("待补全账单", count: pendingSummary.pendingExpenses, systemImage: "clock.badge.exclamationmark")
                    pendingRow("待分类", count: pendingSummary.routing, systemImage: "questionmark.folder")
                    pendingRow("待确认", count: pendingSummary.review, systemImage: "checklist")
                    pendingRow("识别失败", count: pendingSummary.failed, systemImage: "exclamationmark.triangle")
                }
                .padding(18)
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var domainsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(title: "数据域", subtitle: "本月记录分布") {
                NavigationLink {
                    DomainsView()
                } label: {
                    Label("全部", systemImage: "chevron.right")
                }
            }

            NavigationLink {
                DomainsView()
            } label: {
                VStack(spacing: 0) {
                    ForEach(Array(appState.dashboard.domains.prefix(5).enumerated()), id: \.element.id) { index, domain in
                        HStack(spacing: 12) {
                            Text(domain.icon.isEmpty ? "·" : domain.icon)
                                .frame(width: 34, height: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(domain.shortName)
                                    .font(.headline)
                                Text(domain.description)
                                    .font(.caption)
                                    .foregroundStyle(JieziTheme.muted)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Text("\(domain.recordCount) 条")
                                .font(.subheadline.monospacedDigit())
                        }
                        .padding(.vertical, 11)
                        if index < min(appState.dashboard.domains.count, 5) - 1 {
                            Divider()
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionHeader<Accessory: View>(
        title: String,
        subtitle: String,
        @ViewBuilder accessory: () -> Accessory
    ) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title3.bold())
                Text(subtitle).font(.subheadline).foregroundStyle(JieziTheme.muted)
            }
            Spacer()
            accessory()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        }
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        sectionHeader(title: title, subtitle: subtitle) { EmptyView() }
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.caption).foregroundStyle(JieziTheme.muted)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(JieziTheme.ink).lineLimit(1).minimumScaleFactor(0.72)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private var captureButton: some View {
        Button { showUploadOptions = true } label: {
            HStack(spacing: 14) {
                Image(systemName: isUploading ? "hourglass" : "camera.viewfinder")
                    .font(.title2)
                    .frame(width: 48, height: 48)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 3) {
                    Text(isUploading ? "正在识别" : "留下此刻").font(.headline)
                    Text("拍照、选择图片或手动记录").font(.subheadline).opacity(0.72)
                }
                Spacer()
                Image(systemName: "plus").font(.title2)
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(JieziTheme.brand, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isUploading)
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
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(JieziTheme.brand.opacity(0.06)))
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

    private func summary(from group: NativeDayRecordGroup?, dateKey: String) -> NativeDailySummary {
        let records = group?.records ?? []
        let pendingCount = records.filter { $0.kind == .staging }.count
        return NativeDailySummary(
            dateKey: dateKey,
            expense: amountTotal(in: records, kind: .expense),
            income: amountTotal(in: records, kind: .income),
            pendingCount: pendingCount,
            recordCount: records.count
        )
    }

    private func amountTotal(in records: [NativeDayRecord], kind: NativeDayRecordKind) -> Double {
        records.filter { $0.kind == kind }.reduce(0) { partial, record in
            partial + numericAmount(record.value)
        }
    }

    private func numericAmount(_ value: String) -> Double {
        let cleaned = value
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: ",", with: "")
        return Double(cleaned) ?? 0
    }

    private func shiftSelectedMonth(_ offset: Int) {
        guard let shiftedMonth = NativeMonthKey.shifted(selectedMonthKey, by: offset),
              let shiftedDate = Self.dateKeyFormatter.date(from: "\(shiftedMonth)-01") else { return }
        selectedDate = shiftedDate
    }

    private func pendingRow(_ title: String, count: Int, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(count > 0 ? JieziTheme.gold : JieziTheme.muted)
                .frame(width: 28)
            Text(title)
                .foregroundStyle(JieziTheme.ink)
            Spacer()
            Text("\(count)")
                .font(.headline.monospacedDigit())
                .foregroundStyle(JieziTheme.ink)
            Image(systemName: "chevron.right")
                .font(.caption.bold())
                .foregroundStyle(JieziTheme.muted)
        }
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
            uploadMessage = try await SnapCountUploadService().uploadNativeImage(data: data, uploadToken: uploadToken, captureKind: captureKind, filename: filename)
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
    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月"; return formatter
    }()
    private static let dateKeyFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; return formatter
    }()
    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "EEE"; return formatter
    }()
    private static var todayKey: String { dateKeyFormatter.string(from: Date()) }
    private static var currentMonthKey: String { NativeMonthKey.current() }
}

private struct HomeWidgetManagerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var configuration: [NativeHomeWidgetConfiguration]

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
                    Button("恢复默认") {
                        configuration = NativeHomeWidgetPreferences.defaults
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
    }

    private func move(_ index: Int, offset: Int) {
        let destination = index + offset
        guard configuration.indices.contains(index), configuration.indices.contains(destination) else { return }
        configuration.swapAt(index, destination)
        configuration = configuration.enumerated().map { order, item in
            NativeHomeWidgetConfiguration(key: item.key, isEnabled: item.isEnabled, order: order)
        }
    }
}
