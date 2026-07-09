import SwiftUI

struct RecordsView: View {
    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section("数据域") {
                    Label("消费", systemImage: "creditcard")
                    Label("饮食", systemImage: "fork.knife")
                    Label("运动", systemImage: "figure.run")
                    Label("睡眠", systemImage: "moon")
                    Label("阅读", systemImage: "book")
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("记录")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
