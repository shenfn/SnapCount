import SwiftUI

// MARK: - 用户称呼（本地偏好，Phase 3 再上云同步）

enum NativeUserDisplayPreferences {
    static let nicknameKey = "snapcount-user-nickname"

    static var trimmedNickname: String? {
        let raw = UserDefaults.standard.string(forKey: nicknameKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return raw.isEmpty ? nil : raw
    }
}

// MARK: - 时段问候

enum NativeDayGreeting {
    /// 与 design-tokens 7 时段对应的问候语
    static func phrase(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<8: return "早上好"
        case 8..<11: return "上午好"
        case 11..<13: return "中午好"
        case 13..<17: return "下午好"
        case 17..<19: return "傍晚好"
        case 19..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    static func line(nickname: String?, for date: Date = Date()) -> String {
        let phrase = phrase(for: date)
        if let nickname, !nickname.isEmpty {
            return "\(phrase)，\(nickname)。"
        }
        return "\(phrase)。"
    }
}

// MARK: - 芥子低语（本地取数版）
//
// v0.3 取数链：① 记录 companion_message → ② ai_insights 结论首句 → ③ 引导句 → ④ 时令静态句。
// ①② 依赖远端数据，Phase 3 接入；本版本先落地 ③④ 与基于本地快照的规则句，
// 视图结构（金线引语 + 来源小注 + blurReplace 换句）一次到位。

struct NativeHomeWhisper: Equatable {
    let text: String
    let source: String

    static func make(
        isToday: Bool,
        dayRecordCount: Int,
        pendingCount: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> NativeHomeWhisper {
        let hour = calendar.component(.hour, from: now)

        if isToday && dayRecordCount == 0 && pendingCount == 0 {
            return NativeHomeWhisper(text: "今天还没落笔，第一笔最珍贵。", source: "芥子低语 · 引导")
        }
        if isToday && dayRecordCount == 0 && hour < 12 {
            return NativeHomeWhisper(text: "新的一天，从一笔小账开始。", source: "芥子低语 · 时令")
        }
        if pendingCount > 0 {
            return NativeHomeWhisper(text: "\(pendingCount) 条记录等你安顿，喝杯茶的功夫就好。", source: "芥子低语 · 来自待处理")
        }
        if hour >= 23 || hour < 5 {
            return NativeHomeWhisper(text: "夜深了，明天的账明天再算。", source: "芥子低语 · 时令")
        }
        switch hour {
        case 5..<8:
            return NativeHomeWhisper(text: "清晨的留白，也是对自己的温柔款待。", source: "芥子低语 · 时令")
        case 8..<11:
            return NativeHomeWhisper(text: "上午安好，井井有条的一天开始了。", source: "芥子低语 · 时令")
        case 11..<13:
            return NativeHomeWhisper(text: "午饭时间，好好吃饭也值得记一笔。", source: "芥子低语 · 时令")
        case 13..<17:
            return NativeHomeWhisper(text: "午后的账不拖到晚上，心里会轻一些。", source: "芥子低语 · 时令")
        case 17..<19:
            return NativeHomeWhisper(text: "傍晚了，今天的故事差不多到齐了。", source: "芥子低语 · 时令")
        default:
            return NativeHomeWhisper(text: "灯火可亲，把今天安顿好再睡。", source: "芥子低语 · 时令")
        }
    }
}

// MARK: - 刊头

struct HomeMastheadView: View {
    let dateText: String
    let syncText: String
    let greetingText: String
    let briefText: String
    let whisper: NativeHomeWhisper
    let onCalendar: () -> Void
    let onManageWidgets: () -> Void
    let onWhisperTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            topRow
            Text(greetingText)
                .font(JieziType.displayLarge)
                .foregroundStyle(JieziTheme.space)
            Text(briefText)
                .font(JieziFont.caption)
                .foregroundStyle(JieziTheme.muted)
            whisperLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var topRow: some View {
        HStack(spacing: 10) {
            Text("\(dateText) · \(syncText)")
                .font(JieziFont.caption2)
                .foregroundStyle(JieziTheme.muted)
                .tracking(0.6)
            Spacer()
            mastheadButton(systemImage: "calendar", label: "选择首页日期", action: onCalendar)
            mastheadButton(systemImage: "gearshape", label: "管理首页组件", action: onManageWidgets)
        }
    }

    private func mastheadButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.75), in: Circle())
                .overlay(Circle().stroke(JieziTheme.brand.opacity(0.1)))
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.9))
        .accessibilityLabel(label)
    }

    private var whisperLine: some View {
        Button(action: onWhisperTap) {
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(JieziTheme.gold)
                    .frame(width: 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(whisper.text)
                        .font(.system(size: 15, weight: .medium, design: .serif))
                        .foregroundStyle(JieziTheme.space)
                        .multilineTextAlignment(.leading)
                        .contentTransition(.opacity)
                    Text("\(whisper.source) · 查看洞察")
                        .font(JieziFont.caption2)
                        .foregroundStyle(JieziTheme.muted)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(JieziEasing.standard, value: whisper)
        .accessibilityLabel("芥子低语：\(whisper.text)")
        .accessibilityHint("打开洞察页")
    }
}
