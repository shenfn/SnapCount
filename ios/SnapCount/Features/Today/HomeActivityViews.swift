import SwiftUI

struct HomeTimelineView: View {
    let records: [NativeDayRecord]
    let dateKey: String

    private var palette: JieziGeneratedPalette { JieziTheme.palette }
    private var visibleRecords: [NativeDayRecord] { Array(records.prefix(5)) }

    var body: some View {
        if records.isEmpty {
            HStack(spacing: JieziSpacing.md) {
                Image(systemName: "text.line.first.and.arrowtriangle.forward")
                    .font(JieziFont.title2)
                    .foregroundStyle(palette.light)
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(palette.light.opacity(0.72), lineWidth: 0.5))
                VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                    Text("这一天尚未落笔")
                        .font(JieziType.cardTitle)
                        .foregroundStyle(palette.ink)
                    Text("已确认记录会按发生时间汇在这里")
                        .font(JieziFont.caption)
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, JieziSpacing.md)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                    NavigationLink(value: NativeRecordRoute(reference: record.reference)) {
                        timelineRow(record, showsLine: index < visibleRecords.count - 1)
                    }
                    .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.99))
                }

                if records.count > visibleRecords.count {
                    NavigationLink(value: NativeDayDetailRoute(dateKey: dateKey, kind: .all)) {
                        Label("查看当天全部 \(records.count) 条记录", systemImage: "arrow.right")
                            .font(JieziType.button)
                            .foregroundStyle(palette.brand)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, JieziSpacing.md)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func timelineRow(_ record: NativeDayRecord, showsLine: Bool) -> some View {
        HStack(alignment: .top, spacing: JieziSpacing.md) {
            VStack(spacing: 0) {
                Circle()
                    .fill(domainColor(for: record))
                    .frame(width: 9, height: 9)
                    .padding(.top, 7)
                if showsLine {
                    Rectangle()
                        .fill(palette.ink.opacity(0.09))
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 12)

            VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                Text(record.timeLabel ?? "全天")
                    .font(JieziFont.caption2)
                    .foregroundStyle(palette.muted)
                    .monospacedDigit()
                Text(record.title)
                    .font(JieziType.cardTitle)
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                if !record.subtitle.isEmpty {
                    Text(record.subtitle)
                        .font(JieziFont.caption)
                        .foregroundStyle(palette.muted)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: JieziSpacing.sm)

            if !record.value.isEmpty {
                Text(record.value)
                    .font(JieziType.moneyInline)
                    .monospacedDigit()
                    .foregroundStyle(valueColor(for: record.kind))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            Image(systemName: "chevron.right")
                .font(JieziFont.caption2.weight(.semibold))
                .foregroundStyle(palette.muted.opacity(0.7))
                .padding(.top, 6)
        }
        .padding(.vertical, JieziSpacing.sm)
        .contentShape(Rectangle())
    }

    private func domainColor(for record: NativeDayRecord) -> Color {
        JieziDomainColor.color(for: record.domainKey ?? record.kind.rawValue)
    }

    private func valueColor(for kind: NativeDayRecordKind) -> Color {
        switch kind {
        case .expense: return palette.coral
        case .income: return palette.brand
        default: return palette.ink
        }
    }
}

struct HomeActivityDensityView: View {
    let days: [NativeHomeActivityDay]
    let selectedDateKey: String
    let onSelectDate: (String) -> Void

    private var palette: JieziGeneratedPalette { JieziTheme.palette }
    private var maximumCount: Int { max(days.map(\.recordCount).max() ?? 0, 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(days) { day in
                Button {
                    JieziHaptics.tap()
                    onSelectDate(day.dateKey)
                } label: {
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(barColor(for: day))
                            .frame(height: barHeight(for: day))
                        Text(dayLabel(day.dateKey))
                            .font(.system(size: 9, weight: day.dateKey == selectedDateKey ? .semibold : .regular))
                            .foregroundStyle(day.dateKey == selectedDateKey ? palette.brand : palette.muted)
                            .monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 72)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(accessibilityLabel(for: day))
            }
        }
        .padding(.horizontal, JieziSpacing.md)
        .padding(.vertical, JieziSpacing.md)
        .background(palette.paper.opacity(0.62), in: RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.Semantic.card, style: .continuous)
                .stroke(palette.brand.opacity(0.09), lineWidth: 1)
        }
    }

    private func barHeight(for day: NativeHomeActivityDay) -> CGFloat {
        guard day.recordCount > 0 else { return 5 }
        return max(12, 44 * CGFloat(day.recordCount) / CGFloat(maximumCount))
    }

    private func barColor(for day: NativeHomeActivityDay) -> Color {
        if day.dateKey == selectedDateKey { return palette.brand }
        if day.recordCount == 0 { return palette.ink.opacity(0.09) }
        return palette.light.opacity(0.82)
    }

    private func dayLabel(_ dateKey: String) -> String {
        String(Int(dateKey.suffix(2)) ?? 0)
    }

    private func accessibilityLabel(for day: NativeHomeActivityDay) -> String {
        "\(day.dateKey)，\(day.recordCount) 条已确认记录"
    }
}

struct HomeEarlierHistoryView: View {
    let summaries: [NativeDailySummary]

    private var palette: JieziGeneratedPalette { JieziTheme.palette }

    var body: some View {
        if summaries.isEmpty {
            Text("近两周还没有更早的记录")
                .font(JieziFont.footnote)
                .foregroundStyle(palette.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, JieziSpacing.sm)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(summaries.enumerated()), id: \.element.id) { index, day in
                    NavigationLink(value: NativeDayDetailRoute(dateKey: day.dateKey, kind: .all)) {
                        historyRow(day)
                    }
                    .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.99))

                    if index < summaries.count - 1 {
                        Divider().overlay(palette.ink.opacity(0.07))
                    }
                }
            }
        }
    }

    private func historyRow(_ day: NativeDailySummary) -> some View {
        HStack(spacing: JieziSpacing.md) {
            VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                Text(String(day.dateKey.suffix(5)))
                    .font(JieziType.moneyInline)
                    .monospacedDigit()
                    .foregroundStyle(palette.ink)
                Text(weekday(day.dateKey))
                    .font(JieziFont.caption2)
                    .foregroundStyle(palette.muted)
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if day.expense > 0 { fact("支出 \(money(day.expense))", color: palette.coral) }
                if day.income > 0 { fact("收入 \(money(day.income))", color: palette.brand) }
                if day.pendingCount > 0 { fact("待处理 \(day.pendingCount)", color: palette.light) }
                if day.expense == 0, day.income == 0, day.pendingCount == 0 {
                    fact("\(day.recordCount) 条记录", color: palette.brand)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(JieziFont.caption2.weight(.semibold))
                .foregroundStyle(palette.muted)
        }
        .padding(.vertical, JieziSpacing.md)
        .contentShape(Rectangle())
    }

    private func fact(_ text: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(JieziFont.caption)
                .foregroundStyle(palette.ink)
        }
    }

    private func money(_ value: Double) -> String { "¥\(Int(value.rounded()))" }

    private func weekday(_ dateKey: String) -> String {
        guard let date = Self.dateFormatter.date(from: dateKey) else { return "" }
        return Self.weekdayFormatter.string(from: date)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEE"
        return formatter
    }()
}
