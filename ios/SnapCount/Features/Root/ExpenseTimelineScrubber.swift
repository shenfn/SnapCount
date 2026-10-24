import SwiftUI

enum NativeExpenseTimelineSelection {
    static let minutesPerDay = 1_440

    static func minute(for locationX: Double, width: Double) -> Int? {
        guard locationX.isFinite, width.isFinite, width > 0 else { return nil }
        let fraction = min(max(locationX / width, 0), 1)
        return Int((fraction * Double(minutesPerDay)).rounded())
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

    @Binding var selectedEntryID: String?
    @State private var gestureAxis: GestureAxis?
    @State private var isScrubbing = false

    private var selectedEntry: NativeTimelineEntry? {
        selectedEntryID.flatMap { id in entries.first { $0.id == id } }
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    if let selectedEntry {
                        Button {
                            onOpenEntry(selectedEntry)
                        } label: {
                            HStack(spacing: 8) {
                                Text(clockLabel(selectedEntry.minute)).font(JieziFont.caption2.monospacedDigit())
                                Text(selectedEntry.record.title).font(JieziFont.caption)
                                    .lineLimit(1)
                                Text(recordValue(selectedEntry.record)).font(JieziFont.caption.monospacedDigit())
                                Text("\(entryIndex(selectedEntry) + 1)/\(entries.count)")
                                    .font(JieziFont.caption2.monospacedDigit()).foregroundStyle(scene.muted)
                            }
                            .foregroundStyle(scene.surface)
                            .padding(.vertical, 7)
                            .padding(.horizontal, 10)
                            .background(scene.foreground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .shadow(color: scene.foreground.opacity(0.16), radius: 7, y: 4)
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: min(proxy.size.width - 24, 220))
                        .position(x: min(max(trackX(for: selectedEntry.minute, width: proxy.size.width), 52), proxy.size.width - 52), y: 18)
                        .accessibilityHint("打开这笔消费详情")
                    }

                    ZStack {
                        Capsule().fill(scene.foreground.opacity(isScrubbing ? 0.16 : 0.1))
                            .frame(height: 2)
                            .padding(.horizontal, 2)
                        ForEach(entries) { entry in
                            let isSelected = entry.id == selectedEntryID
                            Circle()
                                .fill(isSelected ? scene.foreground : scene.dataAccent.opacity(0.58))
                                .overlay(Circle().stroke(scene.surface, lineWidth: 2))
                                .frame(width: isSelected ? 16 : 12, height: isSelected ? 16 : 12)
                                .position(x: trackX(for: entry.minute, width: proxy.size.width), y: 43)
                                .allowsHitTesting(false)
                        }
                        if let selectedEntry {
                            Rectangle().fill(scene.foreground).frame(width: 1.5, height: 48)
                                .position(x: trackX(for: selectedEntry.minute, width: proxy.size.width), y: 43)
                                .allowsHitTesting(false)
                        }
                        Color.clear
                            .contentShape(Rectangle())
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .simultaneousGesture(scrubGesture(width: proxy.size.width))
                            .accessibilityElement()
                            .accessibilityLabel("消费时间轴")
                            .accessibilityValue(selectedAccessibilityValue)
                            .accessibilityAdjustableAction { direction in
                                selectAdjacent(direction == .increment ? 1 : -1)
                            }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .position(x: proxy.size.width / 2, y: 57)
                }
            }
            .frame(height: 88)

            HStack {
                Text("0"); Spacer(); Text("6"); Spacer(); Text("12"); Spacer(); Text("18"); Spacer(); Text("24")
            }
            .font(JieziFont.caption2.monospacedDigit())
            .foregroundStyle(scene.muted)
        }
    }

    private var selectedAccessibilityValue: String {
        guard let selectedEntry else { return "未选择" }
        return "\(clockLabel(selectedEntry.minute))，\(selectedEntry.record.title)，\(recordValue(selectedEntry.record))，第 \(entryIndex(selectedEntry) + 1) 笔，共 \(entries.count) 笔"
    }

    private func entryIndex(_ entry: NativeTimelineEntry) -> Int {
        entries.firstIndex { $0.id == entry.id } ?? 0
    }

    private func trackX(for minute: Int, width: CGFloat) -> CGFloat {
        CGFloat(min(max(Double(minute) / Double(NativeExpenseTimelineSelection.minutesPerDay), 0), 1)) * width
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
                guard let minute = NativeExpenseTimelineSelection.minute(for: value.location.x, width: width),
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
