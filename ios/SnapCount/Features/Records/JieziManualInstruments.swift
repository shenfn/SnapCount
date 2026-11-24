import SwiftUI
import UIKit

// MARK: - 1. 防御性金额键盘引擎（纯值状态，可单测）

enum JieziKeypadKey: Equatable {
    case digit(Int)
    case decimal
    case backspace
    case clear
}

enum JieziKeypadAmountEngine {
    static let maxIntegerDigits = 6 // 999,999.99

    static func apply(
        _ key: JieziKeypadKey,
        to current: String,
        replacingFresh: Bool
    ) -> (text: String, isFresh: Bool) {
        let sanitized = sanitize(current)
        switch key {
        case .clear:
            return ("", false)
        case .backspace:
            if replacingFresh || sanitized.isEmpty {
                return ("", false)
            }
            let dropped = String(sanitized.dropLast())
            return (dropped, false)
        case .decimal:
            if replacingFresh || sanitized.isEmpty {
                return ("0.", false)
            }
            if sanitized.contains(".") {
                return (sanitized, false)
            }
            return (sanitized + ".", false)
        case .digit(let value):
            let clamped = min(max(value, 0), 9)
            let char = String(clamped)
            if replacingFresh {
                return (char, false)
            }
            if sanitized == "0" {
                return (char, false)
            }
            if let dotIndex = sanitized.firstIndex(of: ".") {
                let fraction = sanitized[sanitized.index(after: dotIndex)...]
                guard fraction.count < 2 else { return (sanitized, false) }
                return (sanitized + char, false)
            } else {
                guard sanitized.count < maxIntegerDigits else { return (sanitized, false) }
                return (sanitized + char, false)
            }
        }
    }

    static func sanitize(_ raw: String) -> String {
        var result = ""
        var hasDot = false
        for ch in raw.replacingOccurrences(of: ",", with: ".") {
            if ch.isNumber {
                result.append(ch)
            } else if ch == ".", !hasDot {
                hasDot = true
                result.append(ch)
            }
        }
        return result
    }
}

// MARK: - 2. 睡眠夜空双端时间带引擎（20:00 -> 次日 12:00，共 960 分钟跨度）

enum JieziSleepRibbonMath {
    static let spanMinutes = 960 // 20:00 (0) ... 00:00 (240) ... 12:00 (960)
    static let anchorHour = 20
    static let stepMinutes = 15
    static let minimumDurationMinutes = 30

    static func clampRange(bed: Int, wake: Int) -> (bed: Int, wake: Int) {
        let safeBed = min(max(bed, 0), spanMinutes - minimumDurationMinutes)
        let safeWake = min(max(wake, safeBed + minimumDurationMinutes), spanMinutes)
        return (safeBed, safeWake)
    }

    static func snappedOffset(for locationX: CGFloat, width: CGFloat) -> Int {
        guard locationX.isFinite, width.isFinite, width > 0 else { return 0 }
        let ratio = min(max(Double(locationX / width), 0), 1)
        let raw = ratio * Double(spanMinutes)
        let snapped = Int((raw / Double(stepMinutes)).rounded()) * stepMinutes
        return min(max(snapped, 0), spanMinutes)
    }

    static func clockLabel(for offsetMinutes: Int) -> String {
        let clamped = min(max(offsetMinutes, 0), spanMinutes)
        let total = (anchorHour * 60 + clamped) % 1_440
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    static func isNextDay(_ offsetMinutes: Int) -> Bool {
        offsetMinutes >= (24 - anchorHour) * 60
    }

    /// 结合归属日期（醒来所在日）计算 ISO 8601 起止时间戳（Asia/Shanghai +08:00）
    static func isoTimestamps(
        dateKey: String,
        bedOffset: Int,
        wakeOffset: Int
    ) -> (startISO: String, wakeISO: String, durationMinutes: Int) {
        let (safeBed, safeWake) = clampRange(bed: bedOffset, wake: wakeOffset)
        let wakeDateKey = dateKey
        let previousDateKey = NativeLocalDate.shiftedDateKey(dateKey, byDays: -1) ?? dateKey
        // 若入睡在 20:00~23:59（!isNextDay）且醒来在次日（isNextDay），则入睡属于前一天
        let bedDateKey = (!isNextDay(safeBed) && isNextDay(safeWake)) ? previousDateKey : wakeDateKey
        let startClock = clockLabel(for: safeBed)
        let wakeClock = clockLabel(for: safeWake)
        return (
            startISO: "\(bedDateKey)T\(startClock):00+08:00",
            wakeISO: "\(wakeDateKey)T\(wakeClock):00+08:00",
            durationMinutes: max(minimumDurationMinutes, safeWake - safeBed)
        )
    }
}

// MARK: - 3. 物理惯性 + 邻近刻度隆起横向刻度尺（饮食热量 / 运动时长 / 阅读时长 / 睡眠纯时长）

struct JieziInertialRuler: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let majorStep: Double
    let midStep: Double
    let scene: JieziSceneTokens
    let unitLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var continuousValue: Double = 0
    @State private var isDragging = false
    @State private var lastDragX: CGFloat?
    @State private var lastDragTime: TimeInterval = 0
    @State private var velocityPerStep: Double = 0
    @State private var inertiaTask: Task<Void, Never>?

    private let pxPerStep: CGFloat = 11

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width, 1)
            Canvas { context, size in
                drawRuler(in: &context, size: size, currentValue: isDragging || inertiaTask != nil ? continuousValue : value)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { drag in
                        inertiaTask?.cancel()
                        inertiaTask = nil
                        if !isDragging {
                            isDragging = true
                            continuousValue = clamp(value)
                            lastDragX = drag.location.x
                            lastDragTime = Date.timeIntervalSinceReferenceDate
                            velocityPerStep = 0
                        }
                        guard let prevX = lastDragX else { return }
                        let now = Date.timeIntervalSinceReferenceDate
                        let dx = drag.location.x - prevX
                        let dt = max(now - lastDragTime, 0.008)
                        let deltaVal = -Double(dx / pxPerStep) * step
                        continuousValue = clamp(continuousValue + deltaVal)
                        velocityPerStep = (deltaVal / dt) * 0.016
                        lastDragX = drag.location.x
                        lastDragTime = now
                        commitSnapped(continuousValue)
                    }
                    .onEnded { _ in
                        isDragging = false
                        lastDragX = nil
                        startInertia()
                    }
            )
            .frame(width: width, height: 80)
        }
        .frame(height: 80)
        .onAppear { continuousValue = clamp(value) }
        .onChange(of: value) { _, newValue in
            if !isDragging && inertiaTask == nil {
                continuousValue = clamp(newValue)
            }
        }
        .onDisappear {
            inertiaTask?.cancel()
            inertiaTask = nil
        }
        .accessibilityElement()
        .accessibilityLabel(unitLabel)
        .accessibilityValue("\(Int(value.rounded())) \(unitLabel)")
        .accessibilityAdjustableAction { direction in
            let delta = direction == .increment ? step : -step
            let next = clamp(snap(value + delta))
            if next != value {
                value = next
                continuousValue = next
                JieziHaptics.tap()
            }
        }
    }

    private func clamp(_ raw: Double) -> Double {
        guard raw.isFinite else { return range.lowerBound }
        return min(max(raw, range.lowerBound), range.upperBound)
    }

    private func snap(_ raw: Double) -> Double {
        guard step > 0 else { return clamp(raw) }
        let steps = ((raw - range.lowerBound) / step).rounded()
        return clamp(range.lowerBound + steps * step)
    }

    private func commitSnapped(_ raw: Double) {
        let snapped = snap(raw)
        if abs(snapped - value) > 0.0001 {
            value = snapped
            JieziHaptics.tap()
        }
    }

    private func startInertia() {
        inertiaTask?.cancel()
        guard !reduceMotion, abs(velocityPerStep) > step * 0.05 else {
            let target = snap(continuousValue)
            continuousValue = target
            commitSnapped(target)
            return
        }
        inertiaTask = Task { @MainActor in
            var v = velocityPerStep
            var pos = continuousValue
            for _ in 0..<48 {
                if Task.isCancelled { return }
                if abs(v) > step * 0.02 {
                    pos = clamp(pos + v)
                    v *= 0.89
                    if pos <= range.lowerBound || pos >= range.upperBound { v = 0 }
                    continuousValue = pos
                    commitSnapped(pos)
                } else {
                    let target = snap(pos)
                    if abs(target - pos) > step * 0.02 {
                        pos += (target - pos) * 0.32
                        continuousValue = pos
                    } else {
                        continuousValue = target
                        commitSnapped(target)
                        break
                    }
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
            let finalTarget = snap(continuousValue)
            continuousValue = finalTarget
            commitSnapped(finalTarget)
            inertiaTask = nil
        }
    }

    private func drawRuler(in context: inout GraphicsContext, size: CGSize, currentValue: Double) {
        guard step > 0, size.width > 0 else { return }
        let centerX = size.width / 2
        let bottomY = size.height - 22
        let totalSteps = Int(((range.upperBound - range.lowerBound) / step).rounded())
        let currentStepFloat = (clamp(currentValue) - range.lowerBound) / step

        for i in 0...max(0, totalSteps) {
            let x = centerX + CGFloat(Double(i) - currentStepFloat) * pxPerStep
            if x < -16 || x > size.width + 16 { continue }

            let tickValue = range.lowerBound + Double(i) * step
            let isMajor = majorStep > 0 && abs(tickValue.truncatingRemainder(dividingBy: majorStep)) < 0.001
            let isMid = !isMajor && midStep > 0 && abs(tickValue.truncatingRemainder(dividingBy: midStep)) < 0.001

            let dist = abs(x - centerX)
            let lift = max(0, 1 - dist / 46)
            let edgeFade = min(1, min(x, size.width - x) / 36)

            let baseH: CGFloat = isMajor ? 26 : (isMid ? 17 : 10)
            let tickH = baseH + lift * 10
            let baseAlpha = isMajor ? 0.58 : (isMid ? 0.34 : 0.18)
            let alpha = max(0.04, (baseAlpha + Double(lift) * 0.34) * Double(edgeFade))

            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: bottomY))
            tickPath.addLine(to: CGPoint(x: x, y: bottomY - tickH))
            let color = dist < 6 ? scene.dataAccent : scene.foreground
            context.stroke(
                tickPath,
                with: .color(color.opacity(alpha)),
                style: StrokeStyle(lineWidth: isMajor ? 1.6 : 1.1, lineCap: .round)
            )

            if isMajor {
                let text = Text("\(Int(tickValue.rounded()))")
                    .font(.system(size: 10, weight: .medium).monospacedDigit())
                    .foregroundColor(scene.muted.opacity(max(0.12, Double(edgeFade) * 0.85)))
                context.draw(text, at: CGPoint(x: x, y: size.height - 8), anchor: .center)
            }
        }

        // 中心朱陶/暖金指针
        var needle = Path()
        needle.move(to: CGPoint(x: centerX, y: 9))
        needle.addLine(to: CGPoint(x: centerX, y: bottomY + 2))
        context.stroke(needle, with: .color(scene.dataAccent), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))

        let dotRect = CGRect(x: centerX - 3.5, y: 5.5, width: 7, height: 7)
        context.fill(Path(ellipseIn: dotRect), with: .color(scene.dataAccent))
    }
}

// MARK: - 4. 夜空双端睡眠滑轨（呼应睡眠首页入睡/醒来区间图）

struct JieziSleepNightRibbon: View {
    @Binding var bedOffset: Int
    @Binding var wakeOffset: Int
    let scene: JieziSceneTokens

    @State private var activeKnob: Knob?

    private enum Knob {
        case bed
        case wake
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let horizontalInset: CGFloat = 14
                let trackWidth = max(proxy.size.width - horizontalInset * 2, 1)
                let (safeBed, safeWake) = JieziSleepRibbonMath.clampRange(bed: bedOffset, wake: wakeOffset)
                let x1 = horizontalInset + CGFloat(safeBed) / CGFloat(JieziSleepRibbonMath.spanMinutes) * trackWidth
                let x2 = horizontalInset + CGFloat(safeWake) / CGFloat(JieziSleepRibbonMath.spanMinutes) * trackWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(scene.foreground.opacity(0.10))
                        .frame(height: 14)
                        .padding(.horizontal, horizontalInset)
                        .offset(y: 5)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [scene.dataAccent.opacity(0.85), scene.dataAccent, scene.accent],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(12, x2 - x1), height: 14)
                        .offset(x: x1, y: 5)
                        .shadow(color: scene.dataAccent.opacity(0.35), radius: 8, y: 0)

                    knobView(systemImage: "moon.fill", tint: scene.dataAccent, isActive: activeKnob == .bed)
                        .position(x: x1, y: 36)
                        .accessibilityLabel("入睡时间")
                        .accessibilityValue(JieziSleepRibbonMath.clockLabel(for: safeBed))

                    Text("☾ \(JieziSleepRibbonMath.clockLabel(for: safeBed))")
                        .font(JieziFont.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(activeKnob == .bed ? scene.foreground : scene.muted)
                        .position(x: min(max(x1, 28), max(28, proxy.size.width - 28)), y: 10)
                        .allowsHitTesting(false)

                    knobView(systemImage: "sun.max.fill", tint: scene.accent, isActive: activeKnob == .wake)
                        .position(x: x2, y: 36)
                        .accessibilityLabel("醒来时间")
                        .accessibilityValue(JieziSleepRibbonMath.clockLabel(for: safeWake))

                    Text("☼ \(JieziSleepRibbonMath.clockLabel(for: safeWake))")
                        .font(JieziFont.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(activeKnob == .wake ? scene.foreground : scene.muted)
                        .position(x: min(max(x2, 28), max(28, proxy.size.width - 28)), y: 10)
                        .allowsHitTesting(false)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let localX = drag.location.x - horizontalInset
                            if activeKnob == nil {
                                let dBed = abs(drag.location.x - x1)
                                let dWake = abs(drag.location.x - x2)
                                activeKnob = dBed <= dWake ? .bed : .wake
                            }
                            let snapped = JieziSleepRibbonMath.snappedOffset(for: localX, width: trackWidth)
                            switch activeKnob {
                            case .bed:
                                let next = min(snapped, wakeOffset - JieziSleepRibbonMath.minimumDurationMinutes)
                                let clamped = max(0, next)
                                if clamped != bedOffset {
                                    bedOffset = clamped
                                    JieziHaptics.tap()
                                }
                            case .wake:
                                let next = max(snapped, bedOffset + JieziSleepRibbonMath.minimumDurationMinutes)
                                let clamped = min(JieziSleepRibbonMath.spanMinutes, next)
                                if clamped != wakeOffset {
                                    wakeOffset = clamped
                                    JieziHaptics.tap()
                                }
                            case .none:
                                break
                            }
                        }
                        .onEnded { _ in activeKnob = nil }
                )
            }
            .frame(height: 62)

            HStack {
                Text("20:00"); Spacer(); Text("00:00"); Spacer(); Text("04:00"); Spacer(); Text("08:00"); Spacer(); Text("12:00")
            }
            .font(JieziFont.caption2.monospacedDigit())
            .foregroundStyle(scene.muted)
        }
    }

    private func knobView(systemImage: String, tint: Color, isActive: Bool) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(tint)
            .frame(width: 28, height: 28)
            .background(Color(jieziHex: "#F5F1E7"), in: Circle())
            .overlay(Circle().stroke(tint.opacity(0.6), lineWidth: isActive ? 2 : 1))
            .shadow(color: .black.opacity(0.28), radius: 5, y: 2)
            .scaleEffect(isActive ? 1.15 : 1)
            .animation(.easeOut(duration: 0.12), value: isActive)
    }
}

// MARK: - 5. 消费/收入 内嵌纸感数字键盘（避免系统键盘顶飞画面）

struct JieziPaperKeypad: View {
    let scene: JieziSceneTokens
    let primaryTitle: String
    let isWorking: Bool
    let showsPhotoAction: Bool
    let onKey: (JieziKeypadKey) -> Void
    let onPhoto: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 7) {
            VStack(spacing: 7) {
                HStack(spacing: 7) {
                    digitButton(1); digitButton(2); digitButton(3)
                }
                HStack(spacing: 7) {
                    digitButton(4); digitButton(5); digitButton(6)
                }
                HStack(spacing: 7) {
                    digitButton(7); digitButton(8); digitButton(9)
                }
                HStack(spacing: 7) {
                    actionButton("清空") { onKey(.clear) }
                    digitButton(0)
                    digitLabelButton(".") { onKey(.decimal) }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 7) {
                Button {
                    JieziHaptics.tap()
                    onKey(.backspace)
                } label: {
                    Image(systemName: "delete.left")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(scene.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background(scene.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(scene.foreground.opacity(0.08), lineWidth: 1))
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.94))
                .accessibilityLabel("退格")

                if showsPhotoAction {
                    actionButton("图片") { onPhoto() }
                } else {
                    actionButton("清零") { onKey(.clear) }
                }

                Button {
                    JieziHaptics.confirm()
                    onSubmit()
                } label: {
                    Group {
                        if isWorking {
                            ProgressView().tint(.white)
                        } else {
                            Text(primaryTitle)
                                .font(JieziType.cardTitle)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 99)
                    .background(scene.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.96))
                .disabled(isWorking)
            }
            .frame(width: 82)
        }
    }

    private func digitButton(_ value: Int) -> some View {
        digitLabelButton("\(value)") { onKey(.digit(value)) }
    }

    private func digitLabelButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Text(label)
                .font(JieziType.moneyCard.monospacedDigit())
                .foregroundStyle(scene.foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(scene.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(scene.foreground.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.94))
    }

    private func actionButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            JieziHaptics.tap()
            action()
        } label: {
            Text(title)
                .font(JieziFont.footnote.weight(.medium))
                .foregroundStyle(scene.muted)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(scene.surface.opacity(0.88), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(scene.foreground.opacity(0.08), lineWidth: 1))
        }
        .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.94))
    }
}
