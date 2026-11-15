import SwiftUI

// 芥子对比组件族：把「当期 / 上一期」这类两期对照，从纯文字段落
// 升级为有容器、有层级、有可视化的卡片。
//
// 版式借自系统天气的分组卡：小字标题在上 → 大数字 → 一条可视化 → 一句说明。
// 这里只负责容器与排版，配色全部由调用方从 scene 传入，不引入新的品牌色。
//
// 三个层次：
//   JieziComparePanel  宽卡，承载一个主指标（大数字 + 差额胶囊 + 双条）
//   JieziCompareTile   双列小卡，承载次要指标（图标标签 + 中号数字 + 补充说明 + 可视化）
//   JieziCompareBars   两条等基线对比条，长度按两期最大值取比例

/// 两期差额胶囊：箭头 + 差额文案，支出变多用警示色、变少用正向色。
struct JieziDeltaPill: View {
    enum Direction {
        case up, down, flat

        var glyph: String {
            switch self {
            case .up: return "arrow.up.right"
            case .down: return "arrow.down.right"
            case .flat: return "equal"
            }
        }
    }

    let direction: Direction
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: direction.glyph)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(JieziFont.caption2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.13), in: Capsule())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// 两期对比条。每一项两行：标签与数值左右对齐，下面一条按比例填充的轨道。
/// 比例基于本组最大值，所以两期差得越大、长短差异越明显。
struct JieziCompareBars: View {
    struct Item: Identifiable {
        let id = UUID()
        let label: String
        let value: Double
        let text: String
        let emphasized: Bool
    }

    let items: [Item]
    let tint: Color
    let muted: Color
    var barHeight: CGFloat = 7
    var spacing: CGFloat = 10

    private var maximum: Double {
        max(items.map { abs($0.value) }.max() ?? 0, 0.0001)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(items) { item in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.label)
                            .font(JieziFont.caption2)
                            .foregroundStyle(muted)
                        Spacer(minLength: 4)
                        Text(item.text)
                            .font(JieziFont.caption2.monospacedDigit())
                            .fontWeight(item.emphasized ? .semibold : .regular)
                            .foregroundStyle(item.emphasized ? tint : muted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(tint.opacity(0.09))
                            Capsule()
                                .fill(item.emphasized ? tint : tint.opacity(0.32))
                                .frame(width: barWidth(in: geo.size.width, item: item))
                        }
                    }
                    .frame(height: barHeight)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.label)，\(item.text)")
            }
        }
    }

    private func barWidth(in total: CGFloat, item: Item) -> CGFloat {
        guard total > 0, item.value > 0 else { return barHeight }
        return max(barHeight, total * CGFloat(item.value / maximum))
    }
}

/// 宽卡容器：标题 + 可选右上角对照日期 + 内容。
struct JieziComparePanel<Content: View>: View {
    let title: String
    var subtitle: String?
    var titleTint: Color
    var muted: Color
    var surface: Color
    @ViewBuilder var content: () -> Content

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(titleTint)
                Spacer(minLength: 4)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(JieziFont.caption2.monospacedDigit())
                        .foregroundStyle(muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.78)
                }
            }
            content()
        }
        .padding(JieziPrototypeLayout.card_inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: shape)
        .overlay { shape.strokeBorder(muted.opacity(0.13), lineWidth: 0.8) }
    }
}

/// 单值比例条：一个比例 + 一句说明，用于「占当日支出 40%」这类补充信息。
/// 和 JieziCompareBars 同基线、同圆角，保证并列时视觉节奏一致。
struct JieziMeterRow: View {
    let ratio: Double
    let text: String
    let tint: Color
    let muted: Color
    var barHeight: CGFloat = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(tint.opacity(0.09))
                    Capsule()
                        .fill(tint.opacity(0.68))
                        .frame(width: max(barHeight, geo.size.width * CGFloat(min(max(ratio, 0), 1))))
                }
            }
            .frame(height: barHeight)
            Text(text)
                .font(JieziFont.caption2)
                .foregroundStyle(muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// 双列指标小卡。视觉区由调用方给，可以是小的对比条、点阵或纯说明。
struct JieziCompareTile<Visual: View>: View {
    let label: String
    var glyph: String = "circle"
    let value: String
    var valueTint: Color
    var caption: String?
    /// 说明文字的语气色；差额类说明用它区分「多花 / 少花」。
    var captionTint: Color?
    var tint: Color
    var muted: Color
    var surface: Color
    var minHeight: CGFloat = 156
    @ViewBuilder var visual: () -> Visual

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 5) {
                Image(systemName: glyph)
                    .font(.system(size: 10, weight: .semibold))
                Text(label)
                    .font(JieziFont.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(muted)

            Text(value)
                .font(JieziType.moneyCard.monospacedDigit())
                .foregroundStyle(valueTint)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(JieziFont.caption2.weight(captionTint == nil ? .regular : .semibold))
                    .foregroundStyle(captionTint ?? muted)
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            visual()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(minHeight: minHeight, alignment: .topLeading)
        .background(surface, in: shape)
        .overlay { shape.strokeBorder(muted.opacity(0.13), lineWidth: 0.8) }
    }
}
