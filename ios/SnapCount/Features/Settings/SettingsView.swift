import SwiftUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section("账号") {
                    HStack {
                        Label("登录状态", systemImage: "person.crop.circle")
                        Spacer()
                        Text(appState.currentUserEmail.isEmpty ? "已登录" : appState.currentUserEmail)
                            .foregroundStyle(.secondary)
                    }
                    Button(role: .destructive) {
                        appState.signOut()
                    } label: {
                        Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                Section("原生能力") {
                    HStack {
                        Label("Keychain 凭据同步", systemImage: "key")
                        Spacer()
                        Text(appState.hasUploadToken ? "已同步" : "未同步")
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("App Intents / Shortcuts", systemImage: "wand.and.stars")
                        Text("快捷指令里搜索“上传到芥子”。上一步传入截图或照片，芥子会自动读取 Keychain，不需要手动填写 upload_token。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        appState.verifyShortcutCredential()
                    } label: {
                        Label("检查快捷指令凭据", systemImage: "key.viewfinder")
                    }
                    if let message = appState.shortcutCredentialMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(appState.hasUploadToken ? .secondary : JieziTheme.coral)
                    }
                    Button {
                        UIPasteboard.general.string = "上传到芥子"
                    } label: {
                        Label("复制动作名称", systemImage: "doc.on.doc")
                    }
                    Button {
                        if let url = URL(string: "shortcuts://") {
                            openURL(url)
                        }
                    } label: {
                        Label("打开快捷指令 App", systemImage: "arrow.up.forward.app")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("推荐配置")
                            .font(.subheadline.weight(.semibold))
                        Text("1. 新建快捷指令，添加“截屏”或“选择照片”。")
                        Text("2. 添加“上传到芥子”，图片参数选择上一步结果。")
                        Text("3. 先运行“检查芥子凭据”，确认不需要手动 token。")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    Label("相册与相机上传", systemImage: "photo.on.rectangle")
                }

                Section("合规") {
                    Label("隐私政策", systemImage: "hand.raised")
                    Label("服务协议", systemImage: "doc.text")
                    Label("删除账号", systemImage: "trash")
                        .foregroundStyle(JieziTheme.coral)
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("设置")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}
