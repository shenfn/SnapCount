import SwiftUI

struct HomeMastheadView: View {
    let selectedDate: Date
    let isToday: Bool
    let summary: NativeDailySummary
    let stableRecordCount: Int
    let isLoading: Bool
    let isShowingCachedData: Bool
    let onSelectDate: () -> Void
    let onManageWidgets: () -> Void

    private var palette: JieziGeneratedPalette { JieziTheme.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.lg) {
            HStack(alignment: .center, spacing: JieziSpacing.md) {
                VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                    Text("芥子")
                        .font(JieziType.display)
                        .foregroundStyle(palette.ink)
                    Text(Self.dateFormatter.string(from: selectedDate))
                        .font(JieziFont.caption)
                        .foregroundStyle(palette.muted)
                }
                Spacer(minLength: JieziSpacing.md)
                mastheadButton(systemImage: "calendar", label: "选择日期", action: onSelectDate)
                mastheadButton(systemImage: "slider.horizontal.3", label: "管理首页", action: onManageWidgets)
            }

            VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                Text(headline)
                    .font(JieziType.displayLarge)
                    .foregroundStyle(palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(brief)
                    .font(JieziFont.subheadline)
                    .foregroundStyle(palette.muted)
                    .contentTransition(.numericText())
            }

            Rectangle()
                .fill(palette.light.opacity(0.72))
                .frame(width: 48, height: 1)

            HStack(alignment: .top, spacing: JieziSpacing.xl2) {
                metric(label: "支出", value: money(summary.expense), tint: palette.coral)
                metric(label: "收入", value: money(summary.income, signed: true), tint: palette.brand)
                metric(label: "记录", value: "\(stableRecordCount) 条", tint: palette.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private var headline: String {
        guard isToday else { return "回看这一天" }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 0..<6: return "夜深了，慢慢记"
        case 6..<12: return "早上好，今天开始了"
        case 12..<18: return "下午好，看看此刻"
        default: return "晚上好，收拢一天"
        }
    }

    private var brief: String {
        if isLoading && stableRecordCount == 0 { return "正在同步你的记录" }
        if isShowingCachedData { return "当前展示本机缓存，最新数据正在后台同步" }
        if stableRecordCount == 0, summary.pendingCount > 0 {
            return "有 \(summary.pendingCount) 条记录等待确认"
        }
        if stableRecordCount == 0 { return "这一天还没有已确认记录" }
        if summary.pendingCount > 0 {
            return "已有 \(stableRecordCount) 条记录，另有 \(summary.pendingCount) 条等待处理"
        }
        return "已有 \(stableRecordCount) 条可追溯记录"
    }

    private func mastheadButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Image(systemName: systemImage)
                .font(JieziFont.headline)
                .frame(width: 44, height: 44)
                .foregroundStyle(palette.ink)
                .background(palette.paper.opacity(0.78), in: Circle())
                .overlay(Circle().stroke(palette.brand.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.9))
        .accessibilityLabel(label)
    }

    private func metric(label: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
            Text(label)
                .font(JieziType.metricLabel)
                .foregroundStyle(palette.muted)
            Text(value)
                .font(JieziType.moneyInline)
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func money(_ value: Double, signed: Bool = false) -> String {
        let prefix = signed && value > 0 ? "+" : ""
        return "\(prefix)¥\(Int(value.rounded()))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()
}
