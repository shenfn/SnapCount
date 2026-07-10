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
                    HStack {
                        Label("上传结果通知", systemImage: "bell.badge")
                        Spacer()
                        Text(appState.notificationPermissionStatusText)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }
                    Toggle(isOn: Binding(
                        get: { appState.shortcutNotificationsEnabled },
                        set: { appState.setShortcutNotificationsEnabled($0) }
                    )) {
                        Label("快捷指令完成后通知", systemImage: "bell")
                    }
                    Toggle(isOn: Binding(
                        get: { appState.shortcutResultCardEnabled },
                        set: { appState.setShortcutResultCardEnabled($0) }
                    )) {
                        Label("快捷指令结果卡片", systemImage: "rectangle.on.rectangle")
                    }
                    Text("推荐使用通知：上传完成后点通知回到芥子。结果卡片适合作为通知关闭时的兜底确认。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                    Button {
                        Task {
                            await appState.requestShortcutNotificationPermission()
                        }
                    } label: {
                        Label("开启上传结果通知", systemImage: "bell.badge")
                    }
                    Button {
                        Task {
                            await appState.sendTestShortcutNotification()
                        }
                    } label: {
                        Label("发送测试通知", systemImage: "bell.and.waves.left.and.right")
                    }
                    if let message = appState.shortcutCredentialMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(appState.hasUploadToken ? .secondary : JieziTheme.coral)
                    }
                    if let message = appState.notificationPermissionMessage {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        UIPasteboard.general.string = "上传 JPEG 到芥子"
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
                    ShortcutActionRow(title: "上传 JPEG 到芥子", detail: "接收上一部“转换为 JPEG”的结果。点击动作里的 JPEG 图像槽，选择“转换后的图像”。", systemImage: "square.and.arrow.up")
                    ShortcutActionRow(title: "检查芥子凭据", detail: "确认登录后 Keychain 凭据可被快捷指令自动读取。", systemImage: "key.viewfinder")
                }

                Section("一键截图模板") {
                    ShortcutStepRow(index: 1, title: "快捷指令流程", detail: "推荐顺序：截屏 / 拍照 -> 调整大小 -> 转换 JPEG -> 上传 JPEG 到芥子 -> 显示上传结果。")
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
                    ShortcutStepRow(index: 3, title: "结果通知", detail: "推荐开启。上传完成会弹出系统通知；点击通知会回到芥子。")
                    ShortcutStepRow(index: 4, title: "显示结果", detail: "可选兜底。如果你喜欢通知优先，可以在设置里关闭结果卡片，并在快捷指令模板里删掉“显示结果”。")
                    ShortcutStepRow(index: 5, title: "凭据处理", detail: "快捷指令里不放 token。芥子会从 Keychain 自动读取登录后同步的上传凭据。")
                }

                Section {
                    Button {
                        Task {
                            await appState.requestShortcutNotificationPermission()
                        }
                    } label: {
                        Label("开启上传结果通知", systemImage: "bell.badge")
                    }
                    Button {
                        Task {
                            await appState.sendTestShortcutNotification()
                        }
                    } label: {
                        Label("发送测试通知", systemImage: "bell.and.waves.left.and.right")
                    }
                    Button {
                        UIPasteboard.general.string = "上传 JPEG 到芥子"
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

        setupMessage = "当前构建还没有配置新版模板链接。我会先打开快捷指令 App，你可以搜索“上传 JPEG 到芥子”，把“转换后的图像”接给它。"
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
