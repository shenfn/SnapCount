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
                    NavigationLink {
                        ShortcutSetupView()
                    } label: {
                        Label("快捷指令设置", systemImage: "wand.and.stars")
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
                        UIPasteboard.general.string = "识别截图并记录"
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

private struct ShortcutSetupView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openURL) private var openURL
    @State private var setupMessage: String?

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: appState.hasUploadToken ? "key.fill" : "key.slash")
                            .font(.title2)
                            .foregroundStyle(appState.hasUploadToken ? JieziTheme.mint : JieziTheme.coral)
                            .frame(width: 38, height: 38)
                            .background(.thinMaterial, in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(appState.hasUploadToken ? "凭据已同步" : "凭据未同步")
                                .font(.headline)
                            Text(appState.hasUploadToken ? "快捷指令会自动读取 Keychain，不需要填写 upload_token。" : "请先返回 App 登录一次，再配置快捷指令。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)

                    Button {
                        appState.verifyShortcutCredential()
                    } label: {
                        Label("重新检查凭据", systemImage: "arrow.clockwise")
                    }
                }

                Section("系统内置动作") {
                    ShortcutActionRow(title: "识别截图并记录", detail: "接收“截屏”或“转换后的 JPEG 图像”，上传到芥子 AI 识别。", systemImage: "sparkles.rectangle.stack")
                    ShortcutActionRow(title: "识别拍照并记录", detail: "接收快捷指令相机拍摄的照片，按拍照链路上传识别。", systemImage: "camera.viewfinder")
                    ShortcutActionRow(title: "打开快速捕获", detail: "适合绑定操作按钮：直接打开芥子的拍照 / 相册上传入口。", systemImage: "bolt.fill")
                    ShortcutActionRow(title: "检查芥子凭据", detail: "确认登录后 Keychain 凭据可被快捷指令自动读取。", systemImage: "key.viewfinder")
                }

                Section("一键截图模板") {
                    ShortcutStepRow(index: 1, title: "快捷指令流程", detail: "推荐顺序：截屏 -> 可选转换 JPEG -> 识别截图并记录 -> 显示结果。")
                    Button {
                        openShortcutTemplate()
                    } label: {
                        Label("打开快捷指令 App", systemImage: "arrow.up.forward.app")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JieziTheme.gold)
                    if let setupMessage {
                        Text(setupMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ShortcutStepRow(index: 2, title: "压缩建议", detail: "如果在快捷指令里压缩，建议长边保留 1200 以上；640 容易让小字识别变差。")
                    ShortcutStepRow(index: 3, title: "绑定操作按钮", detail: "想要不选图的入口，优先绑定“打开快速捕获”；想要截屏上传，则绑定你创建的一键截图模板。")
                }

                Section {
                    Button {
                        UIPasteboard.general.string = "识别截图并记录"
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
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("快捷指令")
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }

    private func openShortcutTemplate() {
        if let url = URL(string: AppConfig.shortcutTemplateURL), !AppConfig.shortcutTemplateURL.isEmpty {
            openURL(url)
            return
        }

        setupMessage = "当前构建还没有配置新版模板链接。我会先打开快捷指令 App，你可以搜索“识别截图并记录”，把“转换后的图像”接给它。"
        if let url = URL(string: "shortcuts://") {
            openURL(url)
        }
    }
}

private struct ShortcutActionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(JieziTheme.mint)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ShortcutStepRow: View {
    let index: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(JieziTheme.mint, in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
