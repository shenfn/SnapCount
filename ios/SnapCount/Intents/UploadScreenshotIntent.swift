import AppIntents
import Foundation
import UniformTypeIdentifiers

struct UploadScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "识别截图并记录"
    static var description = IntentDescription("接收快捷指令上一部传入的截图或 JPEG 图像，并上传给芥子进行 AI 识别。")
    static var openAppWhenRun = false

    @Parameter(title: "截图或 JPEG 图像")
    var image: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image else {
            return .result(dialog: "请把“截屏”或“转换后的图像”传给芥子。")
        }

        guard let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken),
              !uploadToken.isEmpty else {
            return .result(dialog: "请先打开芥子登录。")
        }

        if #available(iOS 18.0, *) {
            do {
                let rawImageData = try await image.data(contentType: .image)
                let imageData = try ImageUploadPreprocessor.jpegData(from: rawImageData)
                let message = try await SnapCountUploadService().uploadShortcutImage(
                    data: imageData,
                    uploadToken: uploadToken,
                    captureKind: "screenshot",
                    filename: "shortcut-screenshot.jpg"
                )
                return .result(dialog: "\(message)")
            } catch {
                return .result(dialog: "上传失败：\(error.localizedDescription)")
            }
        }

        return .result(dialog: "快捷指令图片上传需要 iOS 18 或更高版本。")
    }
}

struct UploadCameraPhotoIntent: AppIntent {
    static var title: LocalizedStringResource = "识别拍照并记录"
    static var description = IntentDescription("接收快捷指令相机拍摄或相册传入的照片，并上传给芥子进行 AI 识别。")
    static var openAppWhenRun = false

    @Parameter(title: "照片或 JPEG 图像")
    var image: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let image else {
            return .result(dialog: "请把“拍摄的照片”或“转换后的图像”传给芥子。")
        }

        guard let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken),
              !uploadToken.isEmpty else {
            return .result(dialog: "请先打开芥子登录。")
        }

        if #available(iOS 18.0, *) {
            do {
                let rawImageData = try await image.data(contentType: .image)
                let imageData = try ImageUploadPreprocessor.jpegData(from: rawImageData)
                let message = try await SnapCountUploadService().uploadShortcutImage(
                    data: imageData,
                    uploadToken: uploadToken,
                    captureKind: "camera",
                    filename: "shortcut-camera.jpg"
                )
                return .result(dialog: "\(message)")
            } catch {
                return .result(dialog: "上传失败：\(error.localizedDescription)")
            }
        }

        return .result(dialog: "快捷指令图片上传需要 iOS 18 或更高版本。")
    }
}

struct OpenQuickCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "打开快速捕获"
    static var description = IntentDescription("打开芥子的快速捕获入口，用于拍照或从相册选择截图。")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult & ProvidesDialog {
        return .result(dialog: "已打开芥子快速捕获。")
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
                "用\(.applicationName)识别截图",
                "用\(.applicationName)记录截图"
            ],
            shortTitle: "识别截图",
            systemImageName: "sparkles.rectangle.stack"
        )
        AppShortcut(
            intent: UploadCameraPhotoIntent(),
            phrases: [
                "用\(.applicationName)识别拍照",
                "用\(.applicationName)记录照片"
            ],
            shortTitle: "识别拍照",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: OpenQuickCaptureIntent(),
            phrases: [
                "打开\(.applicationName)快速捕获",
                "用\(.applicationName)快速记录"
            ],
            shortTitle: "快速捕获",
            systemImageName: "bolt.fill"
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
