import AppIntents
import Foundation

struct UploadScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "上传 JPEG 到芥子"
    static var description = IntentDescription("接收快捷指令上一部生成的 JPEG 图像，并上传给芥子进行 AI 识别。")
    static var openAppWhenRun = false

    @Parameter(title: "JPEG 图像")
    var image: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("上传 \(\.$image) 到芥子")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        guard let image else {
            let message = "请把“转换后的图像”或上一部 JPEG 变量传给芥子。"
            return .result(value: message, dialog: "\(message)")
        }

        guard let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken),
              !uploadToken.isEmpty else {
            let message = "请先打开芥子登录。"
            return .result(value: message, dialog: "\(message)")
        }

        if #available(iOS 18.0, *) {
            do {
                let rawImageData = try await image.data(contentType: .image)
                let imageData = try ImageUploadPreprocessor.jpegData(from: rawImageData)
                let result = try await SnapCountUploadService().uploadShortcutImageResult(
                    data: imageData,
                    uploadToken: uploadToken,
                    captureKind: "screenshot",
                    filename: "shortcut-jpeg.jpg"
                )
                await ShortcutNotificationService.shared.notifyUploadResult(result)
                return .result(value: result.displayText, dialog: "\(result.displayText)")
            } catch {
                let message = "上传失败：\(error.localizedDescription)"
                return .result(value: message, dialog: "\(message)")
            }
        }

        let message = "快捷指令图片上传需要 iOS 18 或更高版本。"
        return .result(value: message, dialog: "\(message)")
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
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UploadScreenshotIntent(),
            phrases: [
                "用\(.applicationName)上传 JPEG",
                "用\(.applicationName)记录 JPEG"
            ],
            shortTitle: "上传 JPEG",
            systemImageName: "square.and.arrow.up"
        )
        AppShortcut(
            intent: CheckShortcutCredentialIntent(),
            phrases: [
                "检查\(.applicationName)凭据",
                "检查\(.applicationName)快捷指令"
            ],
            shortTitle: "检查凭据",
            systemImageName: "key.viewfinder"
        )
    }
}
