import SwiftUI

struct LocalBindingPreviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let preview: LocalBindingPreview

    var body: some View {
        List {
            Section("本机 workspace") {
                LabeledContent("本地消费") { Text("\(preview.localExpenseCount) 条") }
                LabeledContent("本地账户") { Text("\(preview.localAccountCount) 个") }
                LabeledContent("待同步操作") { Text("\(preview.pendingOutboxCount) 条") }
            }

            Section("云端范围") {
                if preview.remoteScope.isEmpty {
                    Text("当前账号没有可读取的同步范围")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(preview.remoteScope, id: \.self) { scope in
                        Label(scopeTitle(scope), systemImage: "checkmark.circle")
                    }
                }
            }

            Section {
                if preview.options.contains(.mergeAndEnable) {
                    Button {
                        appState.confirmLocalBinding()
                        dismiss()
                    } label: {
                        Label("合并并开启同步", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .fontWeight(.semibold)
                }

                if preview.options.contains(.deferSync) {
                    Button("暂不开启同步") {
                        appState.deferLocalSync()
                        dismiss()
                    }
                }

                if preview.options.contains(.signOut) {
                    Button("退出当前账号", role: .destructive) {
                        appState.signOut()
                        dismiss()
                    }
                }
            } footer: {
                Text("登录不会自动上传本地数据。只有确认绑定后，后续同步流程才会获得授权；本片尚未执行首次传输。")
            }
        }
        .navigationTitle("同步预览")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func scopeTitle(_ scope: String) -> String {
        switch scope {
        case "expense": return "消费记录"
        case "accounts": return "账户与流水"
        default: return scope
        }
    }
}
