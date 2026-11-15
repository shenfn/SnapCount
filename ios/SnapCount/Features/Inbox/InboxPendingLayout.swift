import SwiftUI
import UIKit

// MARK: - 展示口径
//
// 这一层只做「事实 -> 版面」的换算，不持有状态，也不读仓库。
// 口径与 PWA（src/domains/pendingQueue.js + styles/pages/pending.css）保持一致：
// 同一张卡片同时给出「记录时间 / 上传时间」，账单再补平台、分类、支付方式三件事。

/// 账单卡片上的一个事实小标签（平台 / 分类 / 支付）。
struct InboxBillFact: Identifiable, Hashable {
    let id: String
    let value: String
    let missing: Bool
}

enum InboxFilmTone {
    case route
    case review
    case retry
    case repair
    case bill

    var color: Color {
        switch self {
        case .route: return JieziTheme.brand
        case .review: return Color(hex: "8A6D2F")
        case .retry: return JieziTheme.coral
        case .repair: return JieziTheme.ink
        case .bill: return Color(hex: "A66A18")
        }
    }
}

extension NativeInboxItem {
    /// 明细页和收件箱都只用这一套时间口径：先发生、后上传，缺哪个就留空。
    var filmOccurredLabel: String? {
        if let pendingExpense {
            return Self.shortDateTime(dateKey: pendingExpense.dateKey, label: pendingExpense.occurredAtLabel)
        }
        guard let record = stagingRecord else { return nil }
        return Self.shortDateTime(
            dateKey: record.dateKey,
            label: record.occurredAtLabel ?? record.createdAtLabel
        )
    }

    var filmUploadedLabel: String? {
        if let pendingExpense {
            return Self.shortDateTime(dateKey: nil, label: pendingExpense.createdAtLabel)
        }
        guard let record = stagingRecord else { return nil }
        return Self.shortDateTime(dateKey: nil, label: record.createdAtLabel)
    }

    var filmDomainLabel: String {
        if kind == .pendingExpense { return "支出账单" }
        guard let record = stagingRecord else { return "记录" }
        if let name = record.domainName, !name.isEmpty { return name }
        return record.domainKey.map(Self.domainTitle(forKey:)) ?? "未归类"
    }

    var filmTone: InboxFilmTone {
        guard let record = stagingRecord else { return .bill }
        switch record.status {
        case "ai_error", "failed", "extraction_failed": return .retry
        case "schema_failed": return .repair
        case "routing_failed", "unrouted", "unassigned": return .route
        default: return .review
        }
    }

    var filmGlyph: String {
        switch kind {
        case .pendingExpense: return "支"
        case .staging:
            switch stagingRecord?.recordType ?? "" {
            case "income": return "收"
            case "expense": return "支"
            default: return "记"
            }
        }
    }

    /// 账单三件事；缺失项用 `missing` 标出来，卡片据此上不同的底色。
    var filmBillFacts: [InboxBillFact] {
        guard let pendingExpense else { return [] }
        let platform = pendingExpense.platform?.trimmingCharacters(in: .whitespaces) ?? ""
        let payment = pendingExpense.paymentMethod?.trimmingCharacters(in: .whitespaces) ?? ""
        let categoryTitle = NativeFinanceOptionCatalog.categoryTitle(for: pendingExpense.category)
            ?? pendingExpense.category?.trimmingCharacters(in: .whitespaces)
            ?? ""
        return [
            InboxBillFact(id: "平台", value: platform.isEmpty ? "平台未知" : platform, missing: platform.isEmpty),
            InboxBillFact(id: "分类", value: categoryTitle.isEmpty ? "分类未知" : categoryTitle, missing: categoryTitle.isEmpty),
            InboxBillFact(id: "支付", value: payment.isEmpty ? "支付未知" : payment, missing: payment.isEmpty)
        ]
    }

    var filmSummary: String? {
        guard let record = stagingRecord else { return nil }
        let summary = record.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return summary.isEmpty ? nil : summary
    }

    static func domainTitle(forKey key: String) -> String {
        switch key {
        case "expense": return "支出"
        case "income": return "收入"
        case "wallet": return "钱包"
        case "food": return "饮食"
        case "sleep": return "睡眠"
        case "sport": return "运动"
        case "reading": return "阅读"
        default: return key
        }
    }

    static func shortDateTime(dateKey: String?, label: String?) -> String? {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.count >= 16, trimmed.contains("-"), trimmed.contains(":") {
            return String(trimmed.dropFirst(5).prefix(11))
        }
        if trimmed.contains(":"), let dateKey, dateKey.count == 10 {
            return "\(dateKey.dropFirst(5)) \(trimmed.prefix(5))"
        }
        if let dateKey, dateKey.count == 10 {
            return String(dateKey.dropFirst(5))
        }
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension NativeInboxFilter {
    /// PWA 的筛选顺序：全部 → 待分类 → 待确认 → 需重试 → 待修补 → 账单补全。
    static let pendingPageOrder: [NativeInboxFilter] = [.all, .routing, .review, .failed, .repair, .pendingExpense]
}

// MARK: - 页头（范围切换）
//
// 只做「副标题 + 全部/今天」。标题交给系统导航栏，避免同一屏出现两行大字。

struct InboxScopeHeader: View {
    let subtitle: String
    @Binding var scope: NativeInboxScope
    let todayCount: Int

    var body: some View {
        HStack(alignment: .center, spacing: JieziSpacing.md) {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(JieziTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                ForEach(NativeInboxScope.allCases) { option in
                    Button {
                        withAnimation(JieziEasing.standard) { scope = option }
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.title)
                            if option == .today {
                                Text("\(todayCount)")
                                    .font(.caption2.monospacedDigit())
                                    .opacity(0.7)
                            }
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(scope == option ? Color.white : JieziTheme.muted)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(scope == option ? JieziTheme.brand : Color.clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(scope == option ? .isSelected : [])
                }
            }
            .padding(3)
            .background(Color.white.opacity(0.54), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(JieziTheme.brand.opacity(0.12), lineWidth: 1)
            }
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.top, JieziSpacing.sm)
        .padding(.bottom, JieziSpacing.md)
    }
}

// MARK: - 状态筛选
//
// 与 PWA 的 chips 一致：白底描边，选中反白；数字用等宽字，避免切换时抖动。

struct InboxFilterChipRow: View {
    let filters: [NativeInboxFilter]
    let counts: [NativeInboxFilter: Int]
    @Binding var filter: NativeInboxFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(filters) { option in
                    Button {
                        withAnimation(JieziEasing.standard) { filter = option }
                    } label: {
                        HStack(spacing: 4) {
                            Text(option.chipTitle)
                            Text("\(counts[option] ?? 0)")
                                .monospacedDigit()
                                .opacity(0.72)
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(filter == option ? Color.white : JieziTheme.ink)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(
                            filter == option ? JieziTheme.brand : Color.white.opacity(0.58),
                            in: Capsule()
                        )
                        .overlay {
                            Capsule().stroke(JieziTheme.brand.opacity(filter == option ? 0 : 0.12), lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(filter == option ? .isSelected : [])
                }
            }
            .padding(.horizontal, JieziSpacing.xl2)
        }
        .padding(.bottom, JieziSpacing.lg)
    }
}

// MARK: - 胶片卡
//
// PWA 的核心差异就在这张卡：3:4 视觉区 + 状态胶囊 + 说明区（记录/上传双时间）。
// 没有原图时不留白，改成「事实说明」区，让文字记录也有同等的视觉重量。

struct InboxFilmCard: View {
    let item: NativeInboxItem

    private var hasImage: Bool {
        (item.stagingRecord?.imageURL ?? item.pendingExpense?.imageURL) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            visual
            caption
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(item.filmTone.color.opacity(0.16), lineWidth: 1)
        }
        .shadow(color: JieziTheme.space.opacity(0.06), radius: 10, x: 0, y: 5)
    }

    private var visual: some View {
        // 用 Color 撑出 3:4 的框，再把图叠上去并裁掉溢出：
        // 否则 scaledToFill 的固有尺寸会把整张卡撑到比栅格列还宽，金额被下一张卡盖住。
        ZStack(alignment: .topLeading) {
            Color(hex: "E7E4D9")
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    if hasImage {
                        imageVisual
                    } else {
                        InboxFactNoteVisual(item: item)
                    }
                }
                .clipped()

            InboxStatusCapsule(item: item)
                .padding(8)
        }
    }

    @ViewBuilder
    private var imageVisual: some View {
        let url = item.stagingRecord?.imageURL ?? item.pendingExpense?.imageURL
        ZStack(alignment: .bottom) {
            if let url {
                CachedRemoteImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        JieziTheme.paper
                        ProgressView().tint(JieziTheme.brand)
                    }
                } failure: {
                    InboxFactNoteVisual(item: item)
                }
            }
            LinearGradient(
                colors: [.clear, Color(hex: "17312D").opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 74)
            // 账单截图本身就有商户名和金额，再压一层说明只会重影；
            // 只有识别候选（原图是聊天/相册截图）才需要这层文字。
            .overlay(alignment: .bottomLeading) {
                if item.kind != .pendingExpense {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                        Text(item.subtitle)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let pending = item.pendingExpense {
                Text("-¥\(String(format: "%.2f", pending.amount))")
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(JieziTheme.coral)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            if item.kind == .pendingExpense {
                InboxBillFactChips(facts: item.filmBillFacts)
            } else {
                Text(item.filmDomainLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 2) {
                if let occurred = item.filmOccurredLabel {
                    timeLine("记录", occurred)
                }
                if let uploaded = item.filmUploadedLabel {
                    timeLine("上传", uploaded)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timeLine(_ label: String, _ value: String) -> some View {
        HStack(spacing: 5) {
            Text(label)
                .foregroundStyle(JieziTheme.muted.opacity(0.7))
            Text(value)
                .foregroundStyle(JieziTheme.muted)
                .monospacedDigit()
        }
        .font(.system(size: 10))
        .lineLimit(1)
    }
}

struct InboxStatusCapsule: View {
    let item: NativeInboxItem

    private var label: String {
        item.kind == .pendingExpense ? "待补全" : (item.stagingRecord?.statusLabel ?? item.statusLabel)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(item.filmTone.color)
                .frame(width: 5, height: 5)
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .lineLimit(1)
        }
        .foregroundStyle(item.filmTone.color)
        .padding(.horizontal, 8)
        .frame(minHeight: 24)
        .background(JieziTheme.paper.opacity(0.9), in: Capsule())
    }
}

/// 没有原图时的「事实说明」底片：横线纸 + 类型印章 + 摘要。
struct InboxFactNoteVisual: View {
    let item: NativeInboxItem

    var body: some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(
                colors: [Color(hex: "F8F4E9"), Color(hex: "F0EAD8")],
                startPoint: .top,
                endPoint: .bottom
            )
            Canvas { context, size in
                var y: CGFloat = 22
                while y < size.height {
                    context.fill(
                        Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                        with: .color(JieziTheme.brand.opacity(0.07))
                    )
                    y += 22
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(item.kind == .pendingExpense ? "原图未保留 · 账单事实" : "原图未保留 · 文字事实")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(JieziTheme.muted)
                HStack(spacing: 8) {
                    Text(item.filmGlyph)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JieziTheme.brand)
                        .frame(width: 30, height: 30)
                        .background(JieziTheme.brand.opacity(0.08), in: Circle())
                        .overlay { Circle().stroke(JieziTheme.brand.opacity(0.16), lineWidth: 1) }
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.ink)
                        .lineLimit(2)
                }
                if let summary = item.filmSummary {
                    Text(summary)
                        .font(.system(size: 10))
                        .foregroundStyle(JieziTheme.muted)
                        .lineLimit(3)
                } else if !item.filmBillFacts.isEmpty {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(item.filmBillFacts) { fact in
                            HStack(spacing: 4) {
                                Text(fact.id)
                                    .foregroundStyle(JieziTheme.muted.opacity(0.7))
                                Text(fact.value)
                                    .foregroundStyle(fact.missing ? Color(hex: "8A6D2F") : JieziTheme.ink)
                            }
                            .font(.system(size: 10))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }
}

struct InboxBillFactChips: View {
    let facts: [InboxBillFact]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(facts) { fact in
                Text(fact.value)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(fact.missing ? Color(hex: "8A6D2F") : Color(hex: "477B4A"))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 7)
                    .frame(minHeight: 20)
                    .background(
                        fact.missing ? Color(hex: "DCBF74").opacity(0.22) : JieziTheme.brand.opacity(0.09),
                        in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                    )
            }
        }
    }
}

// MARK: - 分组列表

struct InboxFilmSections: View {
    let sections: [NativeInboxSection]
    let columns: Int
    let onSelect: (NativeInboxItem) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: JieziSpacing.xl2) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(JieziTheme.muted)
                        .padding(.horizontal, 2)
                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(minimum: 0), spacing: 12, alignment: .top),
                            count: columns
                        ),
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(section.items) { item in
                            Button { onSelect(item) } label: {
                                InboxFilmCard(item: item)
                            }
                            .buttonStyle(JieziPressableButtonStyle(pressedScale: 0.985))
                            .frame(maxWidth: .infinity, alignment: .top)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.bottom, JieziSpacing.xl2)
    }
}

// MARK: - 空态

struct InboxScopeEmptyState: View {
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(JieziTheme.brand.opacity(0.11), lineWidth: 1)
                    .frame(width: 136, height: 136)
                Circle()
                    .fill(JieziTheme.brand.opacity(0.28))
                    .frame(width: 6, height: 6)
                    .offset(x: 0, y: -64)
                Circle()
                    .fill(JieziTheme.brand.opacity(0.28))
                    .frame(width: 6, height: 6)
                    .offset(x: 46, y: 46)
                Circle()
                    .fill(JieziTheme.gold)
                    .frame(width: 8, height: 8)
                    .offset(x: 0, y: 62)
            }
            .padding(.bottom, 8)

            Text(title)
                .font(JieziType.prototypeBrand)
                .foregroundStyle(JieziTheme.ink)
            Text(message)
                .font(.footnote)
                .foregroundStyle(JieziTheme.muted)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .tint(JieziTheme.brand)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.top, 44)
        .padding(.bottom, 92)
    }
}

// MARK: - 未完成的图片
//
// 原来一张图占一屏（12 张就是 12 屏），把真正的候选列表挤到十几屏之后。
// 改成一条可展开的横幅：默认只报数量，展开后是紧凑行。

struct InboxIntakeBanner: View {
    let intakes: [LocalImageIntake]
    @Binding var expanded: Bool
    let dataFor: (LocalImageIntake) -> Data?
    let hasImage: (LocalImageIntake) -> Bool
    let onRetry: (LocalImageIntake) -> Void
    let onManual: (LocalImageIntake) -> Void
    let onDiscard: (LocalImageIntake) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(JieziEasing.standard) { expanded.toggle() }
            } label: {
                HStack(spacing: JieziSpacing.md) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(JieziTheme.gold)
                        .frame(width: 34, height: 34)
                        .background(JieziTheme.gold.opacity(0.14), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(intakes.count) 张图片没有识别完")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(JieziTheme.ink)
                        Text(expanded ? "可以逐张重试、手动补录或丢弃" : "原图仍在本机，展开处理")
                            .font(.caption)
                            .foregroundStyle(JieziTheme.muted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(JieziTheme.muted)
                }
                .padding(JieziSpacing.md)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(spacing: 0) {
                    ForEach(intakes) { intake in
                        row(intake)
                        if intake.id != intakes.last?.id {
                            Divider().opacity(0.4).padding(.leading, 64)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: JieziRadius.md, style: .continuous)
                .stroke(JieziTheme.gold.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, JieziSpacing.xl2)
        .padding(.bottom, JieziSpacing.lg)
    }

    private func row(_ intake: LocalImageIntake) -> some View {
        HStack(alignment: .top, spacing: JieziSpacing.md) {
            thumbnail(intake)
            VStack(alignment: .leading, spacing: 4) {
                Text(intake.filename)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JieziTheme.ink)
                    .lineLimit(1)
                Text(intake.status == .receiving ? "正在处理，请稍后查看" : (intake.failureMessage ?? "识别中断，可重试或手动处理"))
                    .font(.caption2)
                    .foregroundStyle(JieziTheme.muted)
                    .lineLimit(2)
                HStack(spacing: JieziSpacing.sm) {
                    if intake.status == .failed, hasImage(intake) {
                        if intake.retryCount < 3 {
                            Button("重试") { onRetry(intake) }
                                .font(.caption.weight(.semibold))
                                .buttonStyle(.borderedProminent)
                                .tint(JieziTheme.brand)
                                .controlSize(.mini)
                        } else {
                            Text("已达重试上限")
                                .font(.caption2)
                                .foregroundStyle(JieziTheme.muted)
                        }
                        Button("手动补录") { onManual(intake) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                    }
                    if intake.status == .failed {
                        Button("丢弃", role: .destructive) { onDiscard(intake) }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .tint(.red)
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JieziSpacing.md)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func thumbnail(_ intake: LocalImageIntake) -> some View {
        if let data = dataFor(intake), let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        } else {
            Image(systemName: "photo")
                .font(.caption)
                .foregroundStyle(JieziTheme.muted)
                .frame(width: 52, height: 52)
                .background(JieziTheme.paper, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}
