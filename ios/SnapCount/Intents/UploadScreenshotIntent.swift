import AppIntents
import Foundation

struct UploadScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "上传到芥子"
    static var description = IntentDescription("接收快捷指令传入的截图或照片，并上传给芥子进行 AI 识别。")
    static var openAppWhenRun = false

    @Parameter(title: "图片")
    var image: IntentFile?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard image != nil else {
            return .result(dialog: "请选择一张截图或照片。")
        }

        let uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken)
        guard uploadToken?.isEmpty == false else {
            return .result(dialog: "请先打开芥子登录。")
        }

        return .result(dialog: "已读取到芥子登录凭据，下一阶段接入后端上传。")
    }
}

struct SnapCountShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: UploadScreenshotIntent(),
            phrases: [
                "上传到\(.applicationName)",
                "用\(.applicationName)记录截图"
            ],
            shortTitle: "上传截图",
            systemImageName: "sparkles.rectangle.stack"
        )
    }
}
