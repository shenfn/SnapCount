import Foundation

enum LocalImageRecognitionError: Error, Equatable, LocalizedError {
    case invalidCandidate
    case unsupportedDomain(String)
    case missingUploadCredential
    case missingBYOKKey
    case invalidFinancialAmount
    case retryLimitReached
    case alreadyInProgress
    case alreadyCompleted

    var errorDescription: String? {
        switch self {
        case .invalidCandidate:
            return "AI 返回的图片识别候选无效"
        case .unsupportedDomain(let domainKey):
            return "本地首片暂不支持数据域：\(domainKey)"
        case .missingUploadCredential:
            return "当前没有可用的 Hosted AI 凭据"
        case .missingBYOKKey:
            return "未找到 BYOK API Key；图片仍保存在本机，可手动处理"
        case .invalidFinancialAmount:
            return "识别结果没有有效金额；原图已保留，请手动补录"
        case .retryLimitReached:
            return "已达到三次重试上限，请手动处理或丢弃图片"
        case .alreadyInProgress:
            return "这张图片正在处理，请稍后查看收件箱"
        case .alreadyCompleted:
            return "这张图片已处理，请查看本地记录或收件箱"
        }
    }
}

struct LocalImageRecognitionRequest {
    let imageData: Data
    let captureKind: String
    let filename: String
    let uploadToken: String?
}

struct LocalRecognitionCandidate {
    let id: String
    let domainKey: String
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let confidence: Double?
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let evidenceFields: [String]
    let missingFields: [String]
    let imageHash: String?
    let companionMessage: String?
    let aiFeedback: [String: AnyCodable]?

    init(
        id: String,
        domainKey: String,
        title: String,
        summary: String,
        payload: [String: AnyCodable],
        confidence: Double?,
        recordDate: String,
        recordTime: String?,
        occurredAt: String?,
        evidenceFields: [String],
        missingFields: [String],
        imageHash: String?,
        companionMessage: String? = nil,
        aiFeedback: [String: AnyCodable]? = nil
    ) {
        self.id = id
        self.domainKey = domainKey
        self.title = title
        self.summary = summary
        self.payload = payload
        self.confidence = confidence
        self.recordDate = recordDate
        self.recordTime = recordTime
        self.occurredAt = occurredAt
        self.evidenceFields = evidenceFields
        self.missingFields = missingFields
        self.imageHash = imageHash
        self.companionMessage = companionMessage
        self.aiFeedback = aiFeedback
    }

    var persistedPayload: [String: AnyCodable] {
        var result = payload
        if let companionMessage = companionMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !companionMessage.isEmpty {
            result["companion_message"] = AnyCodable(companionMessage)
        }
        if let aiFeedback {
            result["ai_feedback"] = AnyCodable(aiFeedback.mapValues(\.value))
        }
        return result
    }
}

protocol LocalImageRecognitionProvider {
    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate
}

struct LocalImageIntakeOutcome: Equatable {
    let result: LocalRecordIntakeOutcome
    let imageHash: String
    /// 供通知横幅与 App 内结果浮层展示；nil 时调用方回退到旧写死文案。
    var notificationText: String? = nil
    /// 已解析的结构化反馈，供结果浮层直接渲染卡片。
    var feedback: NativeAIFeedback? = nil
}

final class LocalImageRecognitionUseCase {
    private let localRecordUseCase: LocalRecordUseCaseProtocol
    private let imageStore: LocalImageStore
    private let intakeRepository: LocalImageIntakeRepository
    private let provider: LocalImageRecognitionProvider
    private let isRecognitionRequestCurrent: @MainActor () -> Bool
    private let pendingRepository: LocalPendingFinancialRepository?
    private let expenseRepository: LocalExpenseRepositoryProtocol?
    private let duplicateReviewRepository: LocalFinancialDuplicateReviewRepository?

    init(
        localRecordUseCase: LocalRecordUseCaseProtocol,
        imageStore: LocalImageStore,
        intakeRepository: LocalImageIntakeRepository,
        provider: LocalImageRecognitionProvider,
        isRecognitionRequestCurrent: @escaping @MainActor () -> Bool = { true },
        pendingRepository: LocalPendingFinancialRepository? = nil,
        expenseRepository: LocalExpenseRepositoryProtocol? = nil,
        duplicateReviewRepository: LocalFinancialDuplicateReviewRepository? = nil
    ) {
        self.localRecordUseCase = localRecordUseCase
        self.imageStore = imageStore
        self.intakeRepository = intakeRepository
        self.provider = provider
        self.isRecognitionRequestCurrent = isRecognitionRequestCurrent
        self.pendingRepository = pendingRepository
        self.expenseRepository = expenseRepository
        self.duplicateReviewRepository = duplicateReviewRepository
    }

    static func makeDefault(
        provider: LocalImageRecognitionProvider,
        isRecognitionRequestCurrent: @escaping @MainActor () -> Bool = { true }
    ) throws -> LocalImageRecognitionUseCase {
        let database = try LocalDatabase()
        let imageStore = try LocalImageStore()
        let repository = try LocalRecordRepository(database: database)
        let recordUseCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: repository,
            imageStore: imageStore
        )
        return LocalImageRecognitionUseCase(
            localRecordUseCase: recordUseCase,
            imageStore: imageStore,
            intakeRepository: LocalImageIntakeRepository(database: database),
            provider: provider,
            isRecognitionRequestCurrent: isRecognitionRequestCurrent,
            pendingRepository: LocalPendingFinancialRepository(database: database),
            expenseRepository: try LocalExpenseRepository(database: database),
            duplicateReviewRepository: LocalFinancialDuplicateReviewRepository(database: database)
        )
    }

    func hasPersistedOriginal(imageData: Data) -> Bool {
        guard let profile = try? intakeRepository.activeProfile(),
              let intake = try? intakeRepository.intake(id: Self.intakeID(profileID: profile.id, imageHash: LocalImageStore.sha256(imageData)), profileID: profile.id),
              let bytes = try? imageStore.data(at: intake.imagePath) else { return false }
        return bytes == imageData
    }

    func ingest(
        imageData: Data,
        captureKind: String,
        filename: String,
        uploadToken: String? = nil,
        createdAt: Date = Date()
    ) async throws -> LocalImageIntakeOutcome {
        let imageHash = LocalImageStore.sha256(imageData)
        let profile = try intakeRepository.activeProfile()
        let intakeID = Self.intakeID(profileID: profile.id, imageHash: imageHash)
        if let completed = try intakeRepository.intake(id: intakeID, profileID: profile.id),
           completed.status == .completed {
            let recordID = Self.uuidFromHash(imageHash)
            if let status = try pendingRepository?.processedStatus(profileID: profile.id, id: recordID) {
                switch status {
                case "pending", "done", "converted":
                    // 幂等重传：文案与首次保持一致，所以从锚点行读回已存的反馈与金额。
                    let row = try pendingRepository?.recordIgnoringStatus(profileID: profile.id, id: recordID)
                    let composed = row.map { record in
                        composeNotification(
                            domainKey: record.preferredKind.rawValue,
                            feedbackPayload: Self.decodeFeedback(record.aiFeedbackJSON),
                            confidence: nil,
                            companionMessage: record.companionMessage,
                            amountMinor: record.amountMinor,
                            merchantName: record.merchantName,
                            category: record.preferredKind == .expense ? record.category : record.incomeCategory,
                            sourceName: record.preferredKind == .income ? record.merchantName : nil,
                            isPending: status == "pending",
                            profileID: profile.id,
                            dateKey: record.transactionDate
                        )
                    }
                    return LocalImageIntakeOutcome(
                        result: status == "pending" ? .financialPending(recordID) : .financialArchived(recordID),
                        imageHash: imageHash,
                        notificationText: composed?.text,
                        feedback: composed?.feedback
                    )
                default:
                    // 已删除的财务事实按新图重新识别。
                    break
                }
            }
            if let record = try await localRecordUseCase.record(id: recordID) {
                let composed = composeNotification(for: record, profileID: profile.id)
                return LocalImageIntakeOutcome(
                    result: .archived(LocalRecordOutcome(record: record, profileID: profile.id)),
                    imageHash: imageHash,
                    notificationText: composed.text,
                    feedback: composed.feedback
                )
            }
            if let staging = try await localRecordUseCase.staging(id: "local-ai-\(imageHash)"),
               staging.status == .pendingReview {
                let payload = (try? LocalRecordCodec.decode(staging.payloadJSON)) ?? [:]
                let composed = composeNotification(
                    domainKey: staging.domainKey,
                    feedbackPayload: payload.dictionary("ai_feedback"),
                    confidence: nil,
                    companionMessage: payload.string("companion_message"),
                    amountMinor: nil,
                    merchantName: nil,
                    category: nil,
                    sourceName: nil,
                    isPending: false,
                    profileID: profile.id,
                    dateKey: staging.recordDate
                )
                return LocalImageIntakeOutcome(
                    result: .staged(LocalStagingOutcome(record: staging, profileID: profile.id)),
                    imageHash: imageHash,
                    notificationText: composed.text,
                    feedback: composed.feedback
                )
            }
            if let staging = try await localRecordUseCase.staging(id: "local-ai-\(imageHash)"),
               staging.status == .archived,
               let targetRecordID = staging.targetRecordID,
               let record = try await localRecordUseCase.record(id: targetRecordID) {
                let composed = composeNotification(for: record, profileID: profile.id)
                return LocalImageIntakeOutcome(
                    result: .archived(LocalRecordOutcome(record: record, profileID: profile.id)),
                    imageHash: imageHash,
                    notificationText: composed.text,
                    feedback: composed.feedback
                )
            }
        }
        let intakeOwner = "recognition-\(profile.id.uuidString)-\(imageHash)"
        let intakePath = LocalImageStore.relativePath(owner: intakeOwner, bucket: "intake")
        let operationID = try intakeRepository.beginAttempt(
            id: intakeID,
            profileID: profile.id,
            captureKind: captureKind,
            filename: filename,
            imagePath: intakePath,
            imageHash: imageHash,
            at: createdAt
        )
        let intakeReference: LocalImageReference
        do {
            intakeReference = try imageStore.save(data: imageData, owner: intakeOwner, bucket: "intake")
        } catch {
            if !imageStore.contains(path: intakePath) {
                try? intakeRepository.removeMissingIntake(id: intakeID, profileID: profile.id)
            } else {
                try? intakeRepository.markFailed(
                    id: intakeID,
                    profileID: profile.id,
                    operationID: operationID,
                    message: "本地图片写入未完成，可重试或手动处理",
                    at: Date()
                )
            }
            throw error
        }

        do {
            return try await recognizeAndSave(
                imageData: imageData,
                imageHash: imageHash,
                intakeID: intakeID,
                profileID: profile.id,
                operationID: operationID,
                imageReference: intakeReference,
                captureKind: captureKind,
                filename: filename,
                uploadToken: uploadToken,
                createdAt: createdAt
            )
        } catch {
            try? intakeRepository.markFailed(
                id: intakeID,
                profileID: profile.id,
                operationID: operationID,
                message: Self.safeFailureMessage(for: error),
                at: Date()
            )
            throw error
        }
    }

    func receiveForManual(
        imageData: Data,
        captureKind: String,
        filename: String,
        createdAt: Date = Date()
    ) throws -> LocalImageIntake {
        let imageHash = LocalImageStore.sha256(imageData)
        let profile = try intakeRepository.activeProfile()
        let intakeID = Self.intakeID(profileID: profile.id, imageHash: imageHash)
        if let existing = try intakeRepository.intake(id: intakeID, profileID: profile.id),
           existing.status == .completed {
            throw LocalImageRecognitionError.alreadyCompleted
        }
        let owner = "recognition-\(profile.id.uuidString)-\(imageHash)"
        let imagePath = LocalImageStore.relativePath(owner: owner, bucket: "intake")
        let operationID = try intakeRepository.beginAttempt(
            id: intakeID, profileID: profile.id, captureKind: captureKind,
            filename: filename, imagePath: imagePath, imageHash: imageHash,
            at: createdAt, allowRetryLimit: true
        )
        do {
            _ = try imageStore.save(data: imageData, owner: owner, bucket: "intake")
            try intakeRepository.markFailed(
                id: intakeID, profileID: profile.id, operationID: operationID,
                message: "AI 识别已关闭；原图仅保存在本机，可手动处理或在开启识别后重试。",
                at: createdAt
            )
            guard let intake = try intakeRepository.intake(id: intakeID, profileID: profile.id) else {
                throw LocalDataError.recordNotFound
            }
            return intake
        } catch {
            if !imageStore.contains(path: imagePath) {
                try? intakeRepository.removeMissingIntake(id: intakeID, profileID: profile.id)
            } else {
                try? intakeRepository.markFailed(
                    id: intakeID, profileID: profile.id, operationID: operationID,
                    message: "本地手工处理准备未完成，原图仍保留在本机。", at: Date()
                )
            }
            throw error
        }
    }

    func retry(intakeID: String, uploadToken: String? = nil, at date: Date = Date()) async throws -> LocalImageIntakeOutcome {
        let profile = try intakeRepository.activeProfile()
        guard let intake = try intakeRepository.intake(id: intakeID, profileID: profile.id),
              intake.status == .failed,
              imageStore.contains(path: intake.imagePath) else {
            throw LocalDataError.recordNotFound
        }
        guard intake.retryCount < 3 else { throw LocalImageRecognitionError.retryLimitReached }
        let imageData = try imageStore.data(at: intake.imagePath)
        let imageHash = LocalImageStore.sha256(imageData)
        guard imageHash == intake.imageHash else { throw LocalDataError.invalidRecord }
        let operationID = try intakeRepository.beginAttempt(
            id: intake.id,
            profileID: profile.id,
            captureKind: intake.captureKind,
            filename: intake.filename,
            imagePath: intake.imagePath,
            imageHash: intake.imageHash,
            at: date
        )
        do {
            return try await recognizeAndSave(
                imageData: imageData,
                imageHash: imageHash,
                intakeID: intake.id,
                profileID: profile.id,
                operationID: operationID,
                imageReference: LocalImageReference(path: intake.imagePath, hash: imageHash),
                captureKind: intake.captureKind,
                filename: intake.filename,
                uploadToken: uploadToken,
                createdAt: date
            )
        } catch {
            try? intakeRepository.markFailed(
                id: intake.id,
                profileID: profile.id,
                operationID: operationID,
                message: Self.safeFailureMessage(for: error),
                at: Date()
            )
            throw error
        }
    }

    private func recognizeAndSave(
        imageData: Data,
        imageHash: String,
        intakeID: String,
        profileID: UUID,
        operationID: UUID,
        imageReference: LocalImageReference,
        captureKind: String,
        filename: String,
        uploadToken: String?,
        createdAt: Date
    ) async throws -> LocalImageIntakeOutcome {
        let recognized = try await provider.recognize(LocalImageRecognitionRequest(
            imageData: imageData,
            captureKind: captureKind,
            filename: filename,
            uploadToken: uploadToken
        ))
        guard await isRecognitionRequestCurrent() else { throw CancellationError() }
        guard try intakeRepository.isReceiving(id: intakeID, profileID: profileID, operationID: operationID) else {
            throw CancellationError()
        }
        if ["expense", "income"].contains(recognized.domainKey), let pendingRepository {
            let id = Self.uuidFromHash(imageHash)
            let recognizedPayload = recognized.persistedPayload
            let amount: Int64
            do {
                amount = try LocalExpenseMapper.amountMinor(from: recognizedPayload["amount"])
            } catch {
                throw LocalImageRecognitionError.invalidFinancialAmount
            }
            let merchantName = recognizedPayload["merchant_name"]?.stringValue
                ?? recognizedPayload["source_name"]?.stringValue
                ?? recognized.title
            let kind = NativePendingEntryKind(rawValue: recognized.domainKey) ?? .expense

            // 感知判重：重新截图同一笔账单时字节全变，精确哈希挡不住，这里补感知指纹。
            // 命中后一律不进自动归档，交给用户在待确认里核对。
            let perceptualHash = LocalPerceptualHash.compute(from: imageData)
            let duplicateCandidates = Self.duplicateCandidates(
                repository: duplicateReviewRepository,
                profileID: profileID,
                recordDate: recognized.recordDate
            )
            let duplicateFacts = Self.duplicateFacts(
                kind: kind,
                amountMinor: amount,
                merchantName: merchantName,
                payload: recognizedPayload,
                recordDate: recognized.recordDate,
                occurredAt: recognized.occurredAt,
                perceptualHash: perceptualHash
            )
            let duplicateMatch = LocalFinancialDuplicateRule.findLikelyDuplicate(
                duplicateFacts, candidates: duplicateCandidates
            )
            // 第二道只在图片判重没命中时才跑，与后端「先 perceptual 后 business」的顺序一致。
            let businessDuplicate: LocalFinancialDuplicateCandidate? = duplicateMatch == nil
                ? LocalFinancialDuplicateRule.findBusinessDuplicate(
                    duplicateFacts, candidates: duplicateCandidates, now: createdAt
                )
                : nil
            // PWA 在判重命中时把 companion 置空、改用「疑似重复」反馈，iOS 保持同一口径。
            let feedbackPayload = duplicateMatch == nil
                ? recognized.aiFeedback
                : Self.duplicateFeedbackPayload(for: recognized)
            let companionMessage = duplicateMatch == nil ? recognized.companionMessage : nil

            let financial = LocalPendingFinancialRecord(id: id, profileID: profileID,
                amountMinor: amount, currency: "CNY", merchantName: merchantName,
                transactionDate: recognized.recordDate, transactionTime: recognized.recordTime,
                occurredAt: recognized.occurredAt.flatMap { ISO8601DateFormatter().date(from: $0) },
                createdAt: createdAt, imagePath: imageReference.path, imageHash: imageHash,
                preferredKind: kind,
                platform: recognizedPayload.string("platform"),
                category: recognizedPayload.string("category"),
                paymentMethod: recognizedPayload.string("payment_method"),
                incomeCategory: recognizedPayload.string("income_category"),
                companionMessage: companionMessage,
                aiFeedbackJSON: Self.encodeFeedback(feedbackPayload),
                perceptualHash: perceptualHash,
                reviewReason: duplicateMatch == nil ? nil : "possible_duplicate")
            let autoArchive = duplicateMatch == nil && LocalFinancialAutoArchiveRule.shouldArchive(
                kind: kind, amountMinor: amount, payload: recognizedPayload, confidence: recognized.confidence)
            if autoArchive {
                try pendingRepository.archiveDirectly(financial)
            } else {
                try pendingRepository.stage(financial)
            }
            // 原图归这条财务事实所有；不要再按通用域的中转副本清理掉。
            try intakeRepository.markCompleted(id: intakeID, profileID: profileID,
                operationID: operationID, cleanupMessage: nil, at: Date())
            let outcome: LocalRecordIntakeOutcome = autoArchive ? .financialArchived(id) : .financialPending(id)
            // PWA 判重命中时通知是固定两行（`index.ts:7321`），不参与 feedback 的三行拼装；
            // 「疑似重复」那条 ai_feedback 只用于待处理页与卡片。
            let baseComposed: (text: String, feedback: NativeAIFeedback?) = duplicateMatch != nil
                ? (text: Self.duplicateNotificationText, feedback: NativeAIFeedback(payload: feedbackPayload))
                : composeNotification(
                    domainKey: recognized.domainKey,
                    feedbackPayload: feedbackPayload,
                    confidence: recognized.confidence,
                    companionMessage: companionMessage,
                    amountMinor: amount,
                    merchantName: merchantName,
                    category: kind == .expense
                        ? recognizedPayload.string("category")
                        : recognizedPayload.string("income_category"),
                    sourceName: kind == .income ? merchantName : nil,
                    isPending: !autoArchive,
                    profileID: profileID,
                    dateKey: recognized.recordDate
                )
            let composed = businessDuplicate == nil
                ? baseComposed
                : (
                    text: Self.appendingBusinessDuplicateSuffix(baseComposed.text),
                    feedback: baseComposed.feedback
                )
            return LocalImageIntakeOutcome(
                result: outcome,
                imageHash: imageHash,
                notificationText: composed.text,
                feedback: composed.feedback
            )
        }
        guard !recognized.domainKey.isEmpty,
              !recognized.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              LocalRecordValidation.supportedStagingDomainKeys.contains(recognized.domainKey) else {
            throw LocalImageRecognitionError.unsupportedDomain(recognized.domainKey)
        }

        let sourceDate = NativeLocalDate.financeDateKey(
            occurredAt: recognized.occurredAt,
            legacyDate: recognized.recordDate
        )
        let recordDate = sourceDate ?? NativeLocalDate.dateKey(createdAt)
        let recordTime = sourceDate == nil
            ? nil
            : (recognized.recordTime ?? recognized.occurredAt.flatMap { NativeLocalDate.timeKey($0) })

        let candidate = LocalRecordCandidate(
            id: "local-ai-\(imageHash)",
            domainKey: recognized.domainKey,
            title: recognized.title,
            summary: recognized.summary,
            payload: recognized.persistedPayload,
            confidence: recognized.confidence,
            recordDate: recordDate,
            recordTime: recordTime,
            imageData: imageData,
            createdAt: createdAt,
            evidenceFields: recognized.evidenceFields,
            missingFields: recognized.missingFields
        )
        let recordID = Self.uuidFromHash(imageHash)
        let result = try await localRecordUseCase.ingest(candidate, recordID: recordID)
        var cleanupMessage: String?
        do {
            try imageStore.remove(path: imageReference.path)
        } catch {
            do {
                try intakeRepository.enqueueImageCleanup(
                    profileID: profileID,
                    imagePath: imageReference.path,
                    at: Date()
                )
            } catch {
                cleanupMessage = "记录已保存；输入副本清理待恢复"
            }
        }
        try intakeRepository.markCompleted(
            id: intakeID,
            profileID: profileID,
            operationID: operationID,
            cleanupMessage: cleanupMessage,
            at: Date()
        )
        _ = try? localRecordUseCase.retryPendingImageCleanups()
        let composed = composeNotification(
            domainKey: recognized.domainKey,
            feedbackPayload: recognized.aiFeedback,
            confidence: recognized.confidence,
            companionMessage: recognized.companionMessage,
            amountMinor: nil,
            merchantName: nil,
            category: nil,
            sourceName: nil,
            isPending: false,
            profileID: profileID,
            dateKey: recordDate
        )
        return LocalImageIntakeOutcome(
            result: result,
            imageHash: imageHash,
            notificationText: composed.text,
            feedback: composed.feedback
        )
    }

    private static func intakeID(profileID: UUID, imageHash: String) -> String {
        "\(profileID.uuidString)-\(imageHash)"
    }

    /// 反馈以 JSON 文本落一列，避免为字段集合再拆表；读回见 `LocalPendingFinancialRepository.feedbackPayload`。
    private static func encodeFeedback(_ payload: [String: AnyCodable]?) -> String? {
        guard let payload, !payload.isEmpty,
              let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// 判重是防错辅助，读候选失败时放行记账而不是阻断识别。
    private static func duplicateCandidates(
        repository: LocalFinancialDuplicateReviewRepository?,
        profileID: UUID,
        recordDate: String
    ) -> [LocalFinancialDuplicateCandidate] {
        guard let repository else { return [] }
        return (try? repository.candidates(profileID: profileID, recordDate: recordDate)) ?? []
    }

    private static func duplicateFacts(
        kind: NativePendingEntryKind,
        amountMinor: Int64,
        merchantName: String,
        payload: [String: AnyCodable],
        recordDate: String,
        occurredAt: String?,
        perceptualHash: String?
    ) -> LocalFinancialDuplicateFacts {
        LocalFinancialDuplicateFacts(
            recordType: kind.rawValue,
            amountMinor: amountMinor,
            merchantOrSource: kind == .income
                ? (payload.string("source_name") ?? merchantName)
                : merchantName,
            platform: payload.string("platform"),
            paymentMethod: payload.string("payment_method"),
            occurredAt: occurredAt.flatMap { ISO8601DateFormatter().date(from: $0) },
            occurredDate: recordDate,
            perceptualHash: perceptualHash
        )
    }

    /// 业务层判重只改通知里的金额行，与后端 `index.ts:7815` 一致：
    /// 后端改的是 `_expenseNotif` 这一行，companion / 反馈行不受影响。
    private static func appendingBusinessDuplicateSuffix(_ text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard !lines.isEmpty else { return text }
        let index = lines.firstIndex { $0.hasPrefix("💸 -") || $0.hasPrefix("⚠️ -") } ?? 0
        let stripped = lines[index].replacingOccurrences(
            of: #"^[💸⚠️]\s*"#, with: "", options: .regularExpression
        )
        lines[index] = "⚠️ \(stripped) · 疑似 3 分钟内重复"
        return lines.joined(separator: "\n")
    }

    /// PWA 判重命中的通知是固定两行（`index.ts:7321`），第二行对应 keepSourceImages=true 的口径。
    /// iOS 本地优先，原图本就留在本机，不跟随服务端隐私配置。
    private static let duplicateNotificationText = "⚠️ 这张图可能和已有记录重复\n图片已保留并等待确认"

    /// 复刻后端 `buildExpenseAIFeedback(..., possibleDuplicate: true)`（`index.ts:2710`）
    /// 与收入侧的覆盖文案（`index.ts:7229`）。文案里的时间窗按实现写 10 分钟，
    /// 后端写的是「3 分钟内」，那是文档与实现不一致，不照抄。
    private static func duplicateFeedbackPayload(
        for recognized: LocalRecognitionCandidate
    ) -> [String: AnyCodable] {
        let isIncome = recognized.domainKey == "income"
        let existingEmotion = recognized.aiFeedback?.string("emotion_line")
        let existingSource = recognized.aiFeedback?.string("source")
        return [
            "version": AnyCodable("feedback-v1"),
            "domain_key": AnyCodable(recognized.domainKey),
            "badge": AnyCodable("疑似重复"),
            "icon": AnyCodable(isIncome ? "💰" : "💸"),
            "band": AnyCodable("watch"),
            "tone": AnyCodable("verify_gently"),
            "emotion_line": AnyCodable(existingEmotion ?? (isIncome
                ? "这笔和刚才那笔收入很像，先别急着收两次。"
                : "这笔和刚才的消费很像，先别急着算两次。")),
            "utility_line": AnyCodable(isIncome
                ? "轻确认：对照原图，确认这是另一笔收入再收下。"
                : "轻确认：点进 App 看一眼是不是重复记账。"),
            "detail_reason": AnyCodable(isIncome
                ? "图片与已有收入记录相似，需要人工确认是否重复。"
                : "10 分钟内存在同金额、同支付方式且商家相近的支出。"),
            "internal_score": AnyCodable(50),
            "confidence": AnyCodable(0.82),
            "source": AnyCodable(existingSource ?? "rule")
        ]
    }

    private static func decodeFeedback(_ json: String?) -> [String: AnyCodable]? {
        guard let json, !json.isEmpty, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: AnyCodable].self, from: data)
    }

    /// 幂等重传时从已落库的通用域记录复现同一份文案。
    private func composeNotification(
        for record: LocalRecord,
        profileID: UUID
    ) -> (text: String, feedback: NativeAIFeedback?) {
        let payload = (try? LocalRecordCodec.decode(record.payloadJSON)) ?? [:]
        return composeNotification(
            domainKey: record.domainKey,
            feedbackPayload: payload.dictionary("ai_feedback"),
            confidence: nil,
            companionMessage: payload.string("companion_message"),
            amountMinor: nil,
            merchantName: nil,
            category: nil,
            sourceName: nil,
            isPending: false,
            profileID: profileID,
            dateKey: record.recordDate
        )
    }

    /// 通知文案与结构化反馈一起产出：文案给横幅，反馈给 App 内结果浮层。
    /// 汇总行取本地口径（已删除记录不计入），与 PWA 的展示格式一致。
    private func composeNotification(
        domainKey: String,
        feedbackPayload: [String: AnyCodable]?,
        confidence: Double?,
        companionMessage: String?,
        amountMinor: Int64?,
        merchantName: String?,
        category: String?,
        sourceName: String?,
        isPending: Bool,
        profileID: UUID,
        dateKey: String
    ) -> (text: String, feedback: NativeAIFeedback?) {
        var todaySpendMinor: Int64 = 0
        var todaySpendCount = 0
        var monthIncomeMinor: Int64 = 0
        if let expenseRepository, let monthKey = NativeLocalDate.monthKey(from: dateKey) {
            let expenses = (try? expenseRepository.expenses(profileID: profileID, monthKey: monthKey)) ?? []
            let todays = expenses.filter { $0.transactionDate == dateKey }
            todaySpendCount = todays.count
            todaySpendMinor = todays.reduce(0) { $0 + $1.amountMinor }
            monthIncomeMinor = ((try? expenseRepository.incomes(profileID: profileID, monthKey: monthKey)) ?? [])
                .reduce(0) { $0 + $1.amountMinor }
        }
        let feedback = NativeAIFeedback(payload: feedbackPayload)
        let text = LocalIntakeNotificationText.compose(LocalIntakeNotificationInput(
            domainKey: domainKey,
            feedback: feedback,
            confidence: confidence,
            companionMessage: companionMessage,
            amountMinor: amountMinor,
            merchantName: merchantName,
            category: category,
            sourceName: sourceName,
            todaySpendMinor: todaySpendMinor,
            todaySpendCount: todaySpendCount,
            monthIncomeMinor: monthIncomeMinor,
            isPending: isPending
        ))
        return (text, feedback)
    }

    private static func safeFailureMessage(for error: Error) -> String {
        if let providerError = error as? QwenBYOKError,
           providerError == .invalidImage {
            return providerError.localizedDescription
        }
        if let recognitionError = error as? LocalImageRecognitionError,
           case .unsupportedDomain(let domainKey) = recognitionError {
            return "本地暂不支持数据域：\(domainKey)"
        }
        if let recognitionError = error as? LocalImageRecognitionError,
           recognitionError == .invalidFinancialAmount {
            return recognitionError.localizedDescription
        }
        if error is CancellationError {
            return "识别已取消，可重试或手动处理"
        }
        return "AI 识别未完成，可重试或手动处理"
    }

    private static func uuidFromHash(_ hash: String) -> UUID {
        let hex = Array(hash.prefix(32))
        var bytes = [UInt8](repeating: 0, count: 16)
        for index in 0..<min(16, hex.count / 2) {
            let start = index * 2
            bytes[index] = UInt8(String(hex[start...(start + 1)]), radix: 16) ?? 0
        }
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

final class HostedAIImageRecognitionProvider: LocalImageRecognitionProvider {
    private let uploadService: SnapCountUploadService
    private let decoder = JSONDecoder()

    init(uploadService: SnapCountUploadService = SnapCountUploadService()) {
        self.uploadService = uploadService
    }

    func recognize(_ request: LocalImageRecognitionRequest) async throws -> LocalRecognitionCandidate {
        let responseData = try await uploadService.recognizeNativeImage(
            data: request.imageData,
            uploadToken: request.uploadToken,
            captureKind: request.captureKind,
            filename: request.filename,
            mimeType: "image/jpeg"
        )
        let envelope = try decoder.decode(HostedAIRecognitionEnvelope.self, from: responseData)
        guard envelope.operation == "recognize_only", envelope.schemaVersion == "local-recognition-candidate-v1",
              let candidate = envelope.candidate,
              let domainKey = candidate.domainKey,
              let title = candidate.title,
              let summary = candidate.summary else {
            throw LocalImageRecognitionError.invalidCandidate
        }
        let payload = candidate.payload ?? [:]
        return LocalRecognitionCandidate(
            id: candidate.id ?? UUID().uuidString,
            domainKey: domainKey,
            title: title,
            summary: summary,
            payload: payload,
            confidence: candidate.confidence,
            recordDate: candidate.recordDate ?? "",
            recordTime: candidate.recordTime,
            occurredAt: candidate.occurredAt,
            evidenceFields: candidate.evidenceFields ?? [],
            missingFields: candidate.missingFields ?? [],
            imageHash: candidate.imageHash,
            companionMessage: candidate.companionMessage ?? payload.string("companion_message"),
            aiFeedback: candidate.aiFeedback ?? payload.dictionary("ai_feedback")
        )
    }
}

private struct HostedAIRecognitionEnvelope: Decodable {
    let schemaVersion: String?
    let operation: String?
    let candidate: HostedAIRecognitionCandidate?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case operation
        case candidate
    }
}

private struct HostedAIRecognitionCandidate: Decodable {
    let id: String?
    let domainKey: String?
    let title: String?
    let summary: String?
    let payload: [String: AnyCodable]?
    let confidence: Double?
    let recordDate: String?
    let recordTime: String?
    let occurredAt: String?
    let evidenceFields: [String]?
    let missingFields: [String]?
    let imageHash: String?
    let companionMessage: String?
    let aiFeedback: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case id
        case domainKey = "domain_key"
        case title
        case summary
        case payload
        case confidence
        case recordDate = "record_date"
        case recordTime = "record_time"
        case occurredAt = "occurred_at"
        case evidenceFields = "evidence_fields"
        case missingFields = "missing_fields"
        case imageHash = "image_hash"
        case companionMessage = "companion_message"
        case aiFeedback = "ai_feedback"
    }
}
