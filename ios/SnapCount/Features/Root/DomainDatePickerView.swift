import SwiftUI

struct DomainDatePickerView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var showsCalendar: Bool

    private var scene: JieziSceneTokens { JieziScene.tokens(for: appState.selectedDomain.rawValue) }
    private var selectedForeground: Color {
        switch appState.selectedDomain {
        case .sleep, .reading: return scene.surface
        case .expense, .food, .sport: return .white
        }
    }

    private var weekDates: [String] {
        NativeLocalDate.weekDateKeys(containing: appState.selectedDateKey)
    }

    private var weekGroups: [NativeDayRecordGroup] {
        guard let first = weekDates.first, let last = weekDates.last else { return [] }
        return appState.recordGroups(from: first, through: last)
    }

    var body: some View {
        let groups = weekGroups
        VStack(spacing: 9) {
            HStack(spacing: 6) {
                ForEach(weekDates, id: \.self) { dateKey in
                    let count = groups.first(where: { $0.dateKey == dateKey })?.records.filter(NativeRecordQuery.isFormal).count ?? 0
                    let isSelected = dateKey == appState.selectedDateKey
                    Button {
                        appState.selectedDateKey = dateKey
                        JieziHaptics.tap()
                    } label: {
                        VStack(spacing: 3) {
                            Text(NativeLocalDate.weekdayShortLabel(for: dateKey)?.replacingOccurrences(of: "周", with: "") ?? "")
                                .font(.system(size: 10, weight: .medium))
                            Text("\(NativeLocalDate.dayOfMonth(dateKey) ?? 0)")
                                .font(JieziType.moneyInline.monospacedDigit())
                            Circle()
                                .fill(count > 0 ? (isSelected ? selectedForeground : scene.accent) : .clear)
                                .frame(width: 4, height: 4)
                        }
                        .foregroundStyle(isSelected ? selectedForeground : scene.foreground)
                        .frame(maxWidth: .infinity)
                        .frame(height: JieziPrototypeLayout.week_day_height)
                        .background(
                            isSelected ? scene.accent : .clear,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(dateKey)，\(count) 条正式记录\(isSelected ? "，已选择" : "")")
                }
            }
        }
        .sheet(isPresented: $showsCalendar) {
            DomainCalendarSheet(initialDateKey: appState.selectedDateKey)
                .environmentObject(appState)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(34)
        }
    }
}

struct DomainCalendarSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var previewDateKey: String

    init(initialDateKey: String) {
        _previewDateKey = State(initialValue: initialDateKey)
    }

    private var monthKey: String { String(previewDateKey.prefix(7)) }
    private var days: [String] { NativeLocalDate.monthDateKeys(monthKey) }
    private var leadingBlankCount: Int {
        days.first.flatMap { NativeLocalDate.weekdayMondayFirstIndex(for: $0) } ?? 0
    }
    private var dayGroups: [NativeDayRecordGroup] { appState.recordGroups(monthKey: monthKey) }
    private var dailyExpense: [String: Double] { appState.dailyExpenseAmounts(monthKey: monthKey) }
    private var monthIsLoading: Bool { appState.isLoadingRecordMonth(monthKey) }
    private var monthLoadError: String? { appState.recordMonthMessages[monthKey] }
    private var monthHasLoaded: Bool { appState.hasLoadedRecordMonth(monthKey) }

    var body: some View {
        let groups = dayGroups
        let expenses = dailyExpense
        let maximum = expenses.values.max() ?? 0
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    header
                    weekdayHeader
                    calendarGrid(groups: groups, expenses: expenses, maximum: maximum)
                    Text("深浅表示支出；圆点表示当天任意领域有正式记录")
                        .font(JieziFont.caption2)
                        .foregroundStyle(JieziScene.expense.muted)
                        .fixedSize(horizontal: false, vertical: true)
                    previewSummary(groups: groups)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 10) {
                    JieziSecondaryButton(title: "取消") { dismiss() }
                    JieziPrimaryButton(title: "查看", systemImage: "arrow.right") {
                        appState.selectedDateKey = previewDateKey
                        dismiss()
                    }
                    .accessibilityLabel("查看\(previewDateKey)的记录")
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(JieziTheme.pageBackground)
            }
        }
        .task(id: monthKey) {
            await appState.loadRecordMonth(monthKey)
        }
    }

    private var header: some View {
        HStack {
            Button { moveMonth(by: -1) } label: {
                Image(systemName: "chevron.left")
                    .frame(width: JieziPrototypeLayout.calendar_arrow_hit_size, height: JieziPrototypeLayout.calendar_arrow_hit_size)
                    .background(.white.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("上个月")

            Spacer()
            VStack(spacing: 2) {
                Text(NativeLocalDate.monthTitle(monthKey))
                    .font(JieziType.sectionTitle)
            }
            Spacer()

            Button { moveMonth(by: 1) } label: {
                Image(systemName: "chevron.right")
                    .frame(width: JieziPrototypeLayout.calendar_arrow_hit_size, height: JieziPrototypeLayout.calendar_arrow_hit_size)
                    .background(.white.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("下个月")
        }
        .foregroundStyle(JieziScene.expense.foreground)
    }

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { day in
                Text(day)
                    .font(JieziFont.caption2)
                    .foregroundStyle(JieziScene.expense.muted)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func calendarGrid(groups: [NativeDayRecordGroup], expenses: [String: Double], maximum: Double) -> some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(0..<leadingBlankCount, id: \.self) { _ in
                Color.clear.frame(height: JieziPrototypeLayout.calendar_day_height).accessibilityHidden(true)
            }
            ForEach(days, id: \.self) { dateKey in
                calendarDay(dateKey, groups: groups, expenses: expenses, maximum: maximum)
            }
        }
    }

    private func calendarDay(_ dateKey: String, groups: [NativeDayRecordGroup], expenses: [String: Double], maximum: Double) -> some View {
        let isSelected = previewDateKey == dateKey
        let count = groups.first(where: { $0.dateKey == dateKey })?.records.filter(NativeRecordQuery.isFormal).count ?? 0
        let heat = maximum > 0 ? min((expenses[dateKey] ?? 0) / maximum, 1) : 0
        return Button {
            previewDateKey = dateKey
            JieziHaptics.tap()
        } label: {
            VStack(spacing: 2) {
                Text("\(NativeLocalDate.dayOfMonth(dateKey) ?? 0)")
                    .font(JieziType.moneyInline.monospacedDigit())
                Circle()
                    .fill(count > 0 ? (isSelected ? .white : JieziScene.expense.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .foregroundStyle(isSelected ? .white : JieziScene.expense.foreground)
            .frame(maxWidth: .infinity)
            .frame(height: JieziPrototypeLayout.calendar_day_height)
            .background {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? JieziScene.expense.accent : JieziScene.expense.accent.opacity(heat * 0.32))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(isSelected ? JieziScene.expense.accent : .clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(dateKey)，\(count) 条正式记录\(heat > 0 ? "，有支出" : "")\(isSelected ? "，预览日期" : "")")
    }

    private func previewSummary(groups: [NativeDayRecordGroup]) -> some View {
        let count = groups.first(where: { $0.dateKey == previewDateKey })?.records.filter(NativeRecordQuery.isFormal).count ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("预览 · \(previewDateKey)")
                    .font(JieziType.cardTitle)
                Spacer()
                Text(monthHasLoaded && monthLoadError == nil ? "\(count) 条正式记录" : "记录状态待确认")
                    .font(JieziFont.caption)
                    .foregroundStyle(JieziScene.expense.muted)
            }
            if monthIsLoading {
                Label("正在读取本月记录", systemImage: "arrow.triangle.2.circlepath")
                    .font(JieziFont.caption)
                    .foregroundStyle(JieziScene.expense.muted)
            } else if monthLoadError != nil {
                HStack {
                    Label("读取失败，日期标记可能不完整", systemImage: "exclamationmark.triangle")
                        .font(JieziFont.caption)
                        .foregroundStyle(JieziTheme.coral)
                    Spacer()
                    Button("重试") {
                        Task { await appState.loadRecordMonth(monthKey, force: true) }
                    }
                    .font(JieziFont.caption.weight(.semibold))
                    .foregroundStyle(JieziScene.expense.accent)
                }
            } else if !monthHasLoaded {
                Label("等待读取本月记录", systemImage: "clock")
                    .font(JieziFont.caption)
                    .foregroundStyle(JieziScene.expense.muted)
            }
        }
        .foregroundStyle(JieziScene.expense.foreground)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(JieziScene.expense.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
    }

    private func moveMonth(by offset: Int) {
        guard let targetMonth = NativeMonthKey.shifted(monthKey, by: offset) else { return }
        let targetDays = NativeLocalDate.monthDateKeys(targetMonth)
        guard let first = targetDays.first, let last = targetDays.last else { return }
        let currentDay = NativeLocalDate.dayOfMonth(previewDateKey) ?? 1
        let day = min(currentDay, NativeLocalDate.dayOfMonth(last) ?? currentDay)
        let dayText = String(format: "%02d", day)
        previewDateKey = "\(String(first.prefix(7)))-\(dayText)"
    }
}
