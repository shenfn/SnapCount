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

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let trialID = await ShortcutTrialStore.shared.claim()
        guard let image else {
            if let trialID { await ShortcutTrialStore.shared.complete(id: trialID, outcome: .failed) }
            let message = "请把“转换后的图像”或上一部 JPEG 变量传给芥子。"
            return .result(value: message)
        }

        if #available(iOS 18.0, *) {
            do {
                let rawImageData = try await image.data(contentType: .image)
                let imageData = try ImageUploadPreprocessor.jpegData(from: rawImageData)
                let mode = LocalVisionModeStore().mode
                let uploadToken: String?
                if mode == .hosted {
                    uploadToken = try? KeychainStore.shared.string(for: KeychainKeys.uploadToken)
                } else {
                    uploadToken = nil
                }
                let provider: LocalImageRecognitionProvider
                var isRecognitionRequestCurrent: () -> Bool = { true }
                switch mode {
                case .disabled, .hosted:
                    provider = HostedAIImageRecognitionProvider()
                case .byok:
                    let credentialStore = KeychainStore.shared
                    let apiKey = (try? credentialStore.string(for: KeychainKeys.byokQwenAPIKey)) ?? ""
                    provider = QwenBYOKImageRecognitionProvider(
                        apiKey: apiKey
                    )
                    isRecognitionRequestCurrent = {
                        (try? credentialStore.string(for: KeychainKeys.byokQwenAPIKey)) == apiKey
                    }
                }
                let recognition = try LocalImageRecognitionUseCase.makeDefault(
                    provider: provider,
                    isRecognitionRequestCurrent: isRecognitionRequestCurrent
                )
                let result: ShortcutUploadResult
                let trialOutcome: ShortcutTrialOutcome
                do {
                    if mode == .disabled {
                        _ = try recognition.receiveForManual(
                            imageData: imageData, captureKind: "screenshot", filename: "shortcut-jpeg.jpg"
                        )
                        result = ShortcutUploadResult(
                            displayText: "AI 识别已关闭；图片仅保存在本机，请打开芥子手动处理。",
                            notificationText: "图片已保存在本机，请打开芥子手动处理。",
                            route: "inbox"
                        )
                        trialOutcome = .staged
                    } else {
                        let outcome = try await recognition.ingest(
                            imageData: imageData,
                            captureKind: "screenshot",
                            filename: "shortcut-jpeg.jpg",
                            uploadToken: uploadToken
                        )
                        switch outcome.result {
                        case .archived:
                            trialOutcome = .archived
                            result = ShortcutUploadResult(
                                displayText: "AI 识别结果已自动记录到本机。",
                                notificationText: "AI 识别结果已自动记录到本机。",
                                route: "records"
                            )
                        case .staged, .financialPending:
                            trialOutcome = .staged
                            result = ShortcutUploadResult(
                                displayText: "AI 识别结果已保存到本地收件箱，请打开芥子确认。",
                                notificationText: "AI 识别结果已保存到本地收件箱，请打开芥子确认。",
                                route: "inbox"
                            )
                        }
                    }
                } catch {
                    trialOutcome = .failed
                    result = ShortcutUploadResult(
                        displayText: "识别未完成；图片保留在本机，请打开收件箱重试或手动处理。",
                        notificationText: "识别未完成；图片保留在本机，请打开收件箱重试或手动处理。",
                        route: "inbox"
                    )
                }
                if let trialID { await ShortcutTrialStore.shared.complete(id: trialID, outcome: trialOutcome) }
                await ShortcutNotificationService.shared.notifyUploadResult(result)
                let value = ShortcutFeedbackPreferences.resultCardEnabled ? result.displayText : result.compactDisplayText
                return .result(value: value)
            } catch {
                if let trialID { await ShortcutTrialStore.shared.complete(id: trialID, outcome: .failed) }
                let message = "上传失败：\(error.localizedDescription)"
                return .result(value: message)
            }
        }

        let message = "快捷指令图片上传需要 iOS 18 或更高版本。"
        if let trialID { await ShortcutTrialStore.shared.complete(id: trialID, outcome: .failed) }
        return .result(value: message)
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
