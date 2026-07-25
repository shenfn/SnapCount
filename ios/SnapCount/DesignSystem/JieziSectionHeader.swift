import SwiftUI

// 芥子区块头：标题（sectionTitle）+ 副题（muted）+ 可选尾部入口。
// 用法：
//   JieziSectionHeader(title: "财务状态", subtitle: "净额估算") {
//       Label("账户", systemImage: "chevron.right")
//   }
//   JieziSectionHeader(title: "今日记录")   // 无 accessory 时传 EmptyView()

struct JieziSectionHeader<Accessory: View>: View {
    var palette: JieziGeneratedPalette = .defaultPalette
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                Text(title)
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(palette.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(JieziFont.subheadline)
                        .foregroundStyle(palette.muted)
                }
            }
            Spacer()
            accessory()
                .font(JieziFont.subheadline.weight(.semibold))
                .foregroundStyle(palette.brand)
        }
    }
}

extension JieziSectionHeader where Accessory == EmptyView {
    init(palette: JieziGeneratedPalette = .defaultPalette, title: String, subtitle: String? = nil) {
        self.palette = palette
        self.title = title
        self.subtitle = subtitle
        self.accessory = { EmptyView() }
    }
}
