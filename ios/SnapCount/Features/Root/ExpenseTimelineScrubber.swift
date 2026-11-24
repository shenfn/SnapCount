import SwiftUI

enum NativeExpenseTimelineSelection {
    static let minutesPerDay = 1_440

    static func minute(for locationX: Double, width: Double) -> Int? {
        minute(for: locationX, width: width, domain: 0...minutesPerDay)
    }

    static func minute(for locationX: Double, width: Double, domain: ClosedRange<Int>) -> Int? {
        guard locationX.isFinite, width.isFinite, width > 0 else { return nil }
        let span = max(1, domain.upperBound - domain.lowerBound)
        let fraction = min(max(locationX / width, 0), 1)
        return domain.lowerBound + Int((fraction * Double(span)).rounded())
    }

    /// 当天消费集中在较窄时间段时自动聚焦到对应区间，避免多笔记录挤成一团看不清刻度
    static func adaptiveDomain(for entries: [NativeTimelineEntry]) -> ClosedRange<Int> {
        guard let minMinute = entries.map(\.minute).min(),
              let maxMinute = entries.map(\.minute).max() else {
            return 0...minutesPerDay
        }
        let spread = maxMinute - minMinute
        if spread >= 600 {
            return 0...minutesPerDay
        }
        var lower = max(0, (minMinute / 60 - 1) * 60)
        var upper = min(minutesPerDay, ((maxMinute / 60) + 2) * 60)
        let minimumSpan = 240
        if upper - lower < minimumSpan {
            let deficit = minimumSpan - (upper - lower)
            lower = max(0, lower - deficit / 2)
            upper = min(minutesPerDay, lower + minimumSpan)
            lower = max(0, upper - minimumSpan)
        }
        return lower...upper
    }

    /// 生成 5 个均匀可读的刻度分钟值
    static func tickMinutes(for domain: ClosedRange<Int>) -> [Int] {
        let span = max(60, domain.upperBound - domain.lowerBound)
        let step = span / 4
        return (0...4).map { idx in
            idx == 4 ? domain.upperBound : min(domain.upperBound, domain.lowerBound + step * idx)
        }
    }

    static func nearestEntry(in entries: [NativeTimelineEntry], to minute: Int) -> NativeTimelineEntry? {
        entries.min { left, right in
            let leftDistance = abs(left.minute - minute)
            let rightDistance = abs(right.minute - minute)
            if leftDistance != rightDistance { return leftDistance < rightDistance }
            if left.minute != right.minute { return left.minute < right.minute }
            return left.id < right.id
        }
    }

    /// 拖动时在密集/同分钟簇内按触点相对偏移顺序切换，避免永远卡在同一笔
    static func entryForScrub(
        in entries: [NativeTimelineEntry],
        locationX: Double,
        width: Double,
        domain: ClosedRange<Int>
    ) -> NativeTimelineEntry? {
        guard !entries.isEmpty, locationX.isFinite, width.isFinite, width > 0 else { return nil }
        guard let minute = minute(for: locationX, width: width, domain: domain) else { return nil }
        guard let nearest = nearestEntry(in: entries, to: minute) else { return nil }

        // 找出距离最近点 ±10 分钟内挤在一起的同簇记录，按横向微位移顺序挑选
        let cluster = entries
            .filter { abs($0.minute - nearest.minute) <= 10 }
            .sorted { $0.minute != $1.minute ? $0.minute < $1.minute : $0.id < $1.id }
        guard cluster.count > 1 else { return nearest }

        let span = max(1.0, Double(domain.upperBound - domain.lowerBound))
        let centerX = Double(nearest.minute - domain.lowerBound) / span * width
        let clusterHalfWidth = min(max(Double(cluster.count) * 14.0, 22.0), 64.0)
        let ratio = min(max((locationX - (centerX - clusterHalfWidth)) / (clusterHalfWidth * 2.0), 0), 0.9999)
        let idx = min(max(Int(ratio * Double(cluster.count)), 0), cluster.count - 1)
        return cluster[idx]
    }
}

struct ExpenseTimelineScrubber: View {
    private enum GestureAxis {
        case horizontal
        case vertical
    }

    let entries: [NativeTimelineEntry]
    let scene: JieziSceneTokens
    let clockLabel: (Int) -> String
    let recordValue: (NativeDayRecord) -> String
    let onOpenEntry: (NativeTimelineEntry) -> Void
    var imageURLProvider: ((NativeDayRecord) async -> URL?)?

    @Binding var selectedEntryID: String?
    @State private var gestureAxis: GestureAxis?
    @State private var isScrubbing = false
    @State private var previewImageURL: URL?

    private var domain: ClosedRange<Int> {
        NativeExpenseTimelineSelection.adaptiveDomain(for: entries)
    }

    private var ticks: [Int] {
        NativeExpenseTimelineSelection.tickMinutes(for: domain)
    }

    private var selectedEntry: NativeTimelineEntry? {
        selectedEntryID.flatMap { id in entries.first { $0.id == id } }
    }

    private var isZoomed: Bool {
        domain.lowerBound > 0 || domain.upperBound < NativeExpenseTimelineSelection.minutesPerDay
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                ZStack(alignment: .topLeading) {
                    if let selectedEntry {
                        floatingCallout(entry: selectedEntry, containerWidth: width)
                            .position(
                                x: min(max(trackX(for: selectedEntry.minute, width: width), 108), max(108, width - 108)),
                                y: 24
                            )
                    }

                    ZStack {
                        // 刻度底线 + 竖向小刻度（位置严格固定，拖动不抖动）
                        Capsule()
                            .fill(scene.foreground.opacity(isScrubbing ? 0.16 : 0.1))
                            .frame(height: 2)
                            .padding(.horizontal, 2)

                        ForEach(ticks, id: \.self) { tick in
                            Rectangle()
                                .fill(scene.foreground.opacity(0.18))
                                .frame(width: 1, height: 8)
                                .position(x: trackX(for: tick, width: width), y: 26)
                                .allowsHitTesting(false)
                        }

                        ForEach(entries) { entry in
                            let isSelected = entry.id == selectedEntryID
                            Circle()
                                .fill(isSelected ? scene.foreground : scene.dataAccent.opacity(0.58))
                                .overlay(Circle().stroke(scene.surface, lineWidth: 2))
                                .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                                .position(x: trackX(for: entry.minute, width: width), y: 26)
                                .allowsHitTesting(false)
                        }

                        if let selectedEntry {
                            Rectangle()
                                .fill(scene.foreground)
                                .frame(width: 1.5, height: 48)
                                .position(x: trackX(for: selectedEntry.minute, width: width), y: 26)
                                .allowsHitTesting(false)
                        }

                        Color.clear
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(scrubGesture(width: width))
                            .accessibilityElement()
                            .accessibilityLabel("消费时间轴")
                            .accessibilityValue(selectedAccessibilityValue)
                            .accessibilityAdjustableAction { direction in
                                selectAdjacent(direction == .increment ? 1 : -1)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .position(x: width / 2, y: 74)
                }
            }
            .frame(height: 102)

            // 具体时间刻度标签
            HStack {
                ForEach(Array(ticks.enumerated()), id: \.offset) { idx, tick in
                    Text(formatTickLabel(tick))
                    if idx < ticks.count - 1 { Spacer() }
                }
            }
            .font(JieziFont.caption2.monospacedDigit())
            .foregroundStyle(scene.muted)

            if isZoomed {
                HStack(spacing: 4) {
                    Image(systemName: "scope")
                        .font(.system(size: 10))
                    Text("已聚焦 \(formatTickLabel(domain.lowerBound))–\(formatTickLabel(domain.upperBound)) 区间，便于区分相邻记录")
                }
                .font(JieziFont.caption2)
                .foregroundStyle(scene.muted.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task(id: selectedEntryID) {
            previewImageURL = nil
            guard let selectedEntry, let imageURLProvider else { return }
            let url = await imageURLProvider(selectedEntry.record)
            guard !Task.isCancelled else { return }
            previewImageURL = url
        }
    }

    private func floatingCallout(entry: NativeTimelineEntry, containerWidth: CGFloat) -> some View {
        HStack(spacing: 6) {
            if entries.count > 1 {
                Button {
                    selectAdjacent(-1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(scene.surface.opacity(entryIndex(entry) > 0 ? 0.9 : 0.3))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entryIndex(entry) == 0)
                .accessibilityLabel("上一笔记录")
            }

            Button {
                onOpenEntry(entry)
            } label: {
                HStack(spacing: 8) {
                    if let previewImageURL {
                        CachedRemoteImage(url: previewImageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Color.white.opacity(0.15)
                        } failure: {
                            Image(systemName: "photo")
                                .font(.caption2)
                                .foregroundStyle(scene.surface.opacity(0.7))
                        }
                        .frame(width: 34, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .stroke(scene.surface.opacity(0.25), lineWidth: 0.75)
                        )
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(clockLabel(entry.minute))
                                .font(JieziFont.caption2.monospacedDigit().weight(.semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(scene.surface.opacity(0.16), in: Capsule())
                            Text(recordValue(entry.record))
                                .font(JieziFont.caption.monospacedDigit().weight(.semibold))
                            if entries.count > 1 {
                                Text("\(entryIndex(entry) + 1)/\(entries.count)")
                                    .font(JieziFont.caption2.monospacedDigit())
                                    .foregroundStyle(scene.surface.opacity(0.65))
                            }
                        }
                        Text(entry.record.title)
                            .font(JieziFont.caption2)
                            .foregroundStyle(scene.surface.opacity(0.86))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("打开这笔消费详情")

            if entries.count > 1 {
                Button {
                    selectAdjacent(1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(scene.surface.opacity(entryIndex(entry) < entries.count - 1 ? 0.9 : 0.3))
                        .frame(width: 22, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(entryIndex(entry) >= entries.count - 1)
                .accessibilityLabel("下一笔记录")
            }
        }
        .foregroundStyle(scene.surface)
        .frame(height: 44)
        .padding(.horizontal, entries.count > 1 ? 6 : 10)
        .background(scene.foreground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: scene.foreground.opacity(0.18), radius: 8, y: 4)
        .frame(maxWidth: min(containerWidth - 8, 286))
    }

    private func formatTickLabel(_ minute: Int) -> String {
        let clamped = min(max(minute, 0), NativeExpenseTimelineSelection.minutesPerDay)
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    private var selectedAccessibilityValue: String {
        guard let selectedEntry else { return "未选择" }
        return "\(clockLabel(selectedEntry.minute))，\(selectedEntry.record.title)，\(recordValue(selectedEntry.record))，第 \(entryIndex(selectedEntry) + 1) 笔，共 \(entries.count) 笔"
    }

    private func entryIndex(_ entry: NativeTimelineEntry) -> Int {
        entries.firstIndex { $0.id == entry.id } ?? 0
    }

    private func trackX(for minute: Int, width: CGFloat) -> CGFloat {
        let span = max(1.0, Double(domain.upperBound - domain.lowerBound))
        let fraction = min(max(Double(minute - domain.lowerBound) / span, 0), 1)
        let inset: CGFloat = 8
        let usable = max(width - inset * 2, 1)
        return inset + CGFloat(fraction) * usable
    }

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if gestureAxis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= 4 else { return }
                    gestureAxis = dx >= dy ? .horizontal : .vertical
                }
                guard gestureAxis == .horizontal else { return }
                isScrubbing = true
                guard let minute = NativeExpenseTimelineSelection.minute(for: value.location.x, width: width, domain: domain),
                      let entry = NativeExpenseTimelineSelection.nearestEntry(in: entries, to: minute) else { return }
                if selectedEntryID != entry.id {
                    selectedEntryID = entry.id
                    JieziHaptics.tap()
                }
            }
            .onEnded { _ in
                gestureAxis = nil
                isScrubbing = false
            }
    }

    private func selectAdjacent(_ offset: Int) {
        guard !entries.isEmpty else { return }
        let current = selectedEntryID.flatMap { id in entries.firstIndex { $0.id == id } } ?? 0
        let index = min(max(current + offset, 0), entries.count - 1)
        guard selectedEntryID != entries[index].id else { return }
        selectedEntryID = entries[index].id
        JieziHaptics.tap()
    }
}
