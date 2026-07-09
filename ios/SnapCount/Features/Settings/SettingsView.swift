import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

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
                    Label("App Intents / Shortcuts", systemImage: "wand.and.stars")
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
