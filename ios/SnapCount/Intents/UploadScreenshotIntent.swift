import AppIntents
import Foundation
import UniformTypeIdentifiers

struct UploadScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "上传到芥子"
    static var description = IntentDescription("接收快捷指令传入的截图或照片，并上传给芥子进行 AI 识别。")
    static var openAppWhenRun = false

    @Parameter(title: "图片")
    var image: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image else {
            return .result(dialog: "请选择一张截图或照片。")
        }

        guard let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken),
              !uploadToken.isEmpty else {
            return .result(dialog: "请先打开芥子登录。")
        }

        if #available(iOS 18.0, *) {
            do {
                let imageData = try await image.data(contentType: .image)
                let message = try await SnapCountUploadService().uploadShortcutImage(
                    data: imageData,
                    uploadToken: uploadToken
                )
                return .result(dialog: "\(message)")
            } catch {
                return .result(dialog: "上传失败：\(error.localizedDescription)")
            }
        }

        return .result(dialog: "快捷指令图片上传需要 iOS 18 或更高版本。")
    }
}

struct CheckShortcutCredentialIntent: AppIntent {
    static var title: LocalizedStringResource = "检查芥子凭据"
    static var description = IntentDescription("检查芥子是否已经把快捷指令上传所需凭据同步到 Keychain。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken),
              !uploadToken.isEmpty else {
            return .result(dialog: "未找到芥子上传凭据。请先打开芥子并登录。")
        }

        return .result(dialog: "芥子凭据已同步。快捷指令上传时会自动读取，不需要手动填写 upload_token。")
    }
}

struct SnapCountShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        [
            AppShortcut(
                intent: UploadScreenshotIntent(),
                phrases: [
                    "上传到\(.applicationName)",
                    "用\(.applicationName)记录截图"
                ],
                shortTitle: "上传截图",
                systemImageName: "sparkles.rectangle.stack"
            ),
            AppShortcut(
                intent: CheckShortcutCredentialIntent(),
                phrases: [
                    "检查\(.applicationName)凭据",
                    "检查\(.applicationName)快捷指令"
                ],
                shortTitle: "检查凭据",
                systemImageName: "key.viewfinder"
            )
        ]
    }
}
