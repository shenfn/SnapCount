import SwiftUI

struct InboxView: View {
    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ContentUnavailableView(
                "暂无待处理记录",
                systemImage: "tray",
                description: Text("上传后的不确定识别结果会先进入这里。")
            )
            .padding()
        }
        .navigationTitle("收件箱")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
