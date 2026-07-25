import SwiftUI

/// 芥子卡片容器：默认使用玻璃卡，列表和小卡可传 solid: true。
struct JieziCard<Content: View>: View {
    var palette: JieziGeneratedPalette = .defaultPalette
    var solid: Bool = false
    let content: Content

    init(
        palette: JieziGeneratedPalette = .defaultPalette,
        solid: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.solid = solid
        self.content = content()
    }

    var body: some View {
        content.jieziCard(palette: palette, solid: solid)
    }
}
