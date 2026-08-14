import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    let route: NativeDayDetailRoute
    @State private var selectedKind: NativeDayRecordKind

    init(route: NativeDayDetailRoute) {
        self.route = route
        _selectedKind = State(initialValue: route.kind)
    }

    private var group: NativeDayRecordGroup? {
        appState.recordGroups(monthKey: monthKey).first { $0.dateKey == route.dateKey }
    }
    private var records: [NativeDayRecord] { group?.records(for: selectedKind) ?? [] }
    private var monthKey: String { String(route.dateKey.prefix(7)) }
    private var palette: JieziGeneratedPalette { themeManager.palette }

    var body: some View {
        ZStack {
            JieziGradient.pageBackground(palette: palette).ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: JieziSpacing.xl2) {
                    summary
                    if let group, group.availableKinds.count > 2 {
                        ScrollView(.horizontal) {
                            HStack(spacing: JieziSpacing.sm) {
                                ForEach(group.availableKinds) { kind in
                                    JieziChip(
                                        palette: palette,
                                        title: kind.title,
                                        isSelected: selectedKind == kind,
                                        tint: kind == .all ? palette.brand : domainColor(for: kind.rawValue)
                                    ) {
                                        selectedKind = kind
                                    }
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                    JieziSectionHeader(
                        palette: palette,
                        title: "当天明细",
                        subtitle: "\(records.count) 条\(selectedKind == .all ? "记录" : selectedKind.title)"
                    )
                    if records.isEmpty {
                        JieziEmptyState(
                            palette: palette,
                            systemImage: "calendar",
                            title: "这一天还没有记录",
                            message: "有截图、手动记录或钱包快照后，会自动出现在这里。"
                        )
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                                recordLink(record, showDivider: index < records.count - 1)
                            }
                        }
                        .background(
                            palette.paper.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                                .stroke(palette.brand.opacity(0.10), lineWidth: 1)
                        }
                        .jieziShadow(JieziShadows.sm(palette))
                    }
                }
                .padding(.horizontal, JieziSpacing.Semantic.page_padding)
                .padding(.vertical, JieziSpacing.sm)
                .padding(.bottom, JieziSpacing.xl5)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: monthKey) {
            await appState.loadRecordMonth(monthKey)
        }
    }

    @ViewBuilder
    private func recordLink(_ record: NativeDayRecord, showDivider: Bool) -> some View {
        if record.kind == .staging || record.reference.hasPrefix("staging-") {
            Button { appState.openDayRecord(record) } label: { row(record, showDivider: showDivider) }
                .buttonStyle(JieziPressableButtonStyle())
        } else {
            NavigationLink(value: NativeRecordRoute(reference: record.reference)) {
                row(record, showDivider: showDivider)
            }
            .buttonStyle(JieziPressableButtonStyle())
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.md) {
            HStack(alignment: .firstTextBaseline) {
                Text(dateTitle)
                    .font(JieziType.display)
                    .foregroundStyle(palette.ink)
                Text(weekdayTitle)
                    .font(JieziFont.subheadline)
                    .foregroundStyle(palette.muted)
            }
            if let daySummary {
                HStack(spacing: JieziSpacing.xl2) {
                    summaryMetric("支出", value: money(daySummary.expense), tint: palette.coral)
                    summaryMetric("收入", value: money(daySummary.income), tint: palette.brand)
                    summaryMetric("记录", value: "\(daySummary.recordCount) 条", tint: palette.ink)
                }
            } else {
                Text("\(records.count) 条记录")
                    .font(JieziFont.subheadline)
                    .foregroundStyle(palette.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jieziCard(palette: palette, solid: true)
    }

    private func row(_ record: NativeDayRecord, showDivider: Bool) -> some View {
        JieziRecordRow(
            palette: palette,
            systemImage: record.systemImage,
            iconTint: domainColor(for: record.domainKey ?? record.kind.rawValue),
            title: record.title,
            subtitle: record.subtitle,
            value: record.value,
            timeLabel: record.timeLabel ?? "上传时间未知",
            valueTint: valueColor(for: record.kind),
            showDivider: showDivider
        )
    }

    private func summaryMetric(_ label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
            Text(label)
                .font(JieziType.metricLabel)
                .foregroundStyle(palette.muted)
            Text(value)
                .font(JieziType.moneyInline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var daySummary: NativeDailySummary? {
        appState.dashboard.dailySummaries.first { $0.dateKey == route.dateKey }
    }

    private var dateTitle: String {
        guard let date = Self.dateFormatter.date(from: route.dateKey) else { return String(route.dateKey.suffix(5)) }
        return Self.dayFormatter.string(from: date)
    }

    private var weekdayTitle: String {
        guard let date = Self.dateFormatter.date(from: route.dateKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private func domainColor(for domain: String) -> Color {
        let supported = ["expense", "income", "sport", "sleep", "reading", "food", "wallet"]
        return supported.contains(domain) ? JieziDomainColor.color(for: domain) : palette.brand
    }

    private func valueColor(for kind: NativeDayRecordKind) -> Color {
        switch kind {
        case .expense: return palette.coral
        case .income: return palette.brand
        default: return palette.ink
        }
    }

    private func money(_ value: Double) -> String { String(format: "¥%.0f", value) }

    private var title: String { route.dateKey }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "MM月dd日"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
