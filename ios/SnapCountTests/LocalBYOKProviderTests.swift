import Foundation
import UIKit
import XCTest
@testable import SnapCount

final class LocalBYOKProviderTests: XCTestCase {
    func testLOCALAI003KHostedValidResponseUsesNormalizedFeedbackSchema() async throws {
        let session = try makeStubSession()
        BYOKURLProtocolStub.configure(
            statusCode: 200,
            responseData: Data(#"{"ok":true,"data":{"companion_message":"  已记下  ","ai_feedback":{"badge":"今日观察","icon":"🌟","band":"positive","emotion_line":"  今天完成得不错  ","utility_line":"可继续保持","detail_reason":"当前记录有明确依据","confidence":1.4}}}"#.utf8)
        )
        let result = try await HostedAICompanionProvider(
            accessToken: "test-access-token",
            service: SnapCountUploadService(session: session, functionsURL: "https://example.test/functions/v1", anonKey: "test-key")
        ).compose(context: makeContext(providerMode: .hosted))

        XCTAssertEqual(result.companionMessage, "已记下")
        let feedback = try XCTUnwrap(result.aiFeedback)
        XCTAssertEqual(Set(feedback.keys), ["version", "domain_key", "badge", "icon", "band", "tone", "emotion_line", "utility_line", "detail_reason", "confidence", "internal_score", "source"])
        XCTAssertEqual(feedback.double("confidence"), 1)
        XCTAssertEqual(feedback.string("band"), "positive")
    }

    func testLOCALAI003KHostedNullLowConfidenceAndMalformedFeedback() async throws {
        let session = try makeStubSession()
        let provider = HostedAICompanionProvider(
            accessToken: "test-access-token",
            service: SnapCountUploadService(session: session, functionsURL: "https://example.test/functions/v1", anonKey: "test-key")
        )

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(#"{"ok":true,"data":{"companion_message":"可选陪伴","ai_feedback":null}}"#.utf8))
        let nullResult = try await provider.compose(context: makeContext(providerMode: .hosted))
        XCTAssertNil(nullResult.aiFeedback)

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(#"{"ok":true,"data":{"companion_message":"可选陪伴","ai_feedback":{"emotion_line":"低置信度","confidence":0.49}}}"#.utf8))
        let lowConfidenceResult = try await provider.compose(context: makeContext(providerMode: .hosted))
        XCTAssertNil(lowConfidenceResult.aiFeedback)

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(#"{"ok":true,"data":{"companion_message":"可选陪伴","ai_feedback":{"confidence":0.9}}}"#.utf8))
        do {
            _ = try await provider.compose(context: makeContext(providerMode: .hosted))
            XCTFail("Malformed feedback should be rejected")
        } catch QwenBYOKError.invalidResponse {
            XCTAssertTrue(true)
        }
    }

    func testLOCALAI003KBYOKValidResponseUsesSameNormalizedSchema() async throws {
        let session = try makeStubSession()
        BYOKURLProtocolStub.configure(
            statusCode: 200,
            responseData: byokResponse(#"{"companion_message":"BYOK 主句","ai_feedback":{"badge":"观察","icon":"💸","band":"bad-band","emotion_line":"BYOK 情绪","utility_line":"","detail_reason":null,"confidence":"0.8"}}"#)
        )
        let result = try await QwenBYOKCompanionProvider(apiKey: "sk-test", session: session)
            .compose(context: makeContext(providerMode: .byok))

        XCTAssertEqual(result.companionMessage, "BYOK 主句")
        let feedback = try XCTUnwrap(result.aiFeedback)
        XCTAssertEqual(Set(feedback.keys), ["version", "domain_key", "badge", "icon", "band", "tone", "emotion_line", "utility_line", "detail_reason", "confidence", "internal_score", "source"])
        XCTAssertEqual(feedback.string("band"), "neutral")
        XCTAssertEqual(feedback.double("confidence"), 0.8)
        XCTAssertTrue(feedback["utility_line"]?.value is NSNull)
    }

    func testLOCALAI003KBYOKRejectsLowConfidenceAndMalformedFeedback() async throws {
        let session = try makeStubSession()
        let provider = QwenBYOKCompanionProvider(apiKey: "sk-test", session: session)

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: byokResponse(#"{"companion_message":"主句","ai_feedback":null}"#))
        let nullResult = try await provider.compose(context: makeContext(providerMode: .byok))
        XCTAssertNil(nullResult.aiFeedback)

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: byokResponse(#"{"companion_message":"主句","ai_feedback":{"emotion_line":"低置信度","confidence":0.4}}"#))
        let lowConfidenceResult = try await provider.compose(context: makeContext(providerMode: .byok))
        XCTAssertNil(lowConfidenceResult.aiFeedback)

        BYOKURLProtocolStub.configure(statusCode: 200, responseData: byokResponse(#"{"companion_message":"主句","ai_feedback":{"confidence":0.9}}"#))
        do {
            _ = try await provider.compose(context: makeContext(providerMode: .byok))
            XCTFail("Malformed feedback should be rejected")
        } catch QwenBYOKError.invalidResponse {
            XCTAssertTrue(true)
        }
    }

    func testLOCALAI003KEmptyCompanionAndRecentLineDeduplication() throws {
        let result = try LocalCompanionResultNormalizer.normalize(
            companionMessage: "重复主句",
            aiFeedback: [
                "emotion_line": AnyCodable("重复情绪"),
                "confidence": AnyCodable(0.9)
            ],
            domainKey: "expense",
            recentCompanionLines: ["重复主句", "重复情绪"]
        )
        XCTAssertNil(result.companionMessage)
        XCTAssertNil(result.aiFeedback)

        let empty = try LocalCompanionResultNormalizer.normalize(
            companionMessage: "   ", aiFeedback: nil, domainKey: "expense", recentCompanionLines: []
        )
        XCTAssertNil(empty.companionMessage)
        XCTAssertNil(empty.aiFeedback)
    }

    func testLOCALAI003KNormalizerAppliesLineCapsAndAllowedBand() throws {
        let result = try LocalCompanionResultNormalizer.normalize(
            companionMessage: String(repeating: "主", count: 40),
            aiFeedback: [
                "badge": AnyCodable(String(repeating: "标", count: 20)),
                "icon": AnyCodable(String(repeating: "图", count: 10)),
                "band": AnyCodable("unsupported"),
                "emotion_line": AnyCodable(String(repeating: "情", count: 40)),
                "utility_line": AnyCodable(String(repeating: "用", count: 40)),
                "detail_reason": AnyCodable(String(repeating: "因", count: 80)),
                "confidence": AnyCodable(0.7)
            ],
            domainKey: "expense",
            recentCompanionLines: []
        )
        XCTAssertEqual(result.companionMessage?.count, 30)
        let feedback = try XCTUnwrap(result.aiFeedback)
        XCTAssertEqual(feedback.string("band"), "neutral")
        XCTAssertEqual(feedback.string("badge")?.count, 10)
        XCTAssertEqual(feedback.string("icon")?.count, 4)
        XCTAssertEqual(feedback.string("emotion_line")?.count, 28)
        XCTAssertEqual(feedback.string("utility_line")?.count, 30)
        XCTAssertEqual(feedback.string("detail_reason")?.count, 60)
    }

    private func makeStubSession() throws -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    private func makeContext(providerMode: LocalExpressionProviderMode) -> LocalExpressionContext {
        let fact = LocalExpressionFact(id: "fact-provider-parity", domainKey: "expense", title: "便利店", summary: "日常用品", recordDate: "2026-11-14", recordTime: nil, amount: 12.8, category: "日用")
        return LocalExpressionContext(
            currentFact: fact,
            recentFacts: [],
            memoryContextJSON: nil,
            plannerCandidates: LocalPlannerCandidateEngine.candidates(for: fact),
            providerMode: providerMode,
            recentCompanionLines: []
        )
    }

    private func byokResponse(_ content: String) -> Data {
        let object: [String: Any] = ["choices": [["message": ["content": content]]]]
        return try! JSONSerialization.data(withJSONObject: object)
    }

    func testLOCALAI003FHostedCompanionSendsCompactMemoryWhenProvided() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        BYOKURLProtocolStub.configure(
            statusCode: 200,
            responseData: Data(#"{"ok":true,"data":{"companion_message":"这笔也稳稳记下了。"}}"#.utf8)
        )
        let memory = #"{"facts":[{"key":"local_ai.expense.merchant_repeat","type":"merchant_pattern","confidence":0.9,"value":"近30天在「便利店」有重复消费记录。","entity_type":"merchant","entity_value":"便利店"}]}"#
        let fact = LocalExpressionFact(
            id: "fact-local-ai-003f", domainKey: "expense", title: "便利店", summary: "日常用品",
            recordDate: "2026-11-10", recordTime: nil, amount: 12.8, category: "日用"
        )
        let context = LocalExpressionContext(
            currentFact: fact, recentFacts: [], memoryContextJSON: memory,
            plannerCandidates: LocalPlannerCandidateEngine.candidates(for: fact, memoryContextJSON: memory),
            providerMode: .hosted
        )
        let provider = HostedAICompanionProvider(
            accessToken: "test-access-token",
            service: SnapCountUploadService(
                session: session,
                functionsURL: "https://example.test/functions/v1",
                anonKey: "test-publishable-key"
            )
        )

        _ = try await provider.compose(context: context)

        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let memoryObject = try XCTUnwrap(object["local_memory_context"] as? [String: Any])
        let facts = try XCTUnwrap(memoryObject["facts"] as? [[String: Any]])
        XCTAssertEqual(facts.first?["key"] as? String, "local_ai.expense.merchant_repeat")
        let candidate = try XCTUnwrap(object["planner_candidate"] as? [String: Any])
        XCTAssertEqual(candidate["dimension"] as? String, "memory_context")
    }

    func testLOCALAI003FHostedCompanionOmitsMemoryWhenDisabled() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        BYOKURLProtocolStub.configure(
            statusCode: 200,
            responseData: Data(#"{"ok":true,"data":{"companion_message":"这笔也稳稳记下了。"}}"#.utf8)
        )
        let fact = LocalExpressionFact(
            id: "fact-local-ai-003f-off", domainKey: "expense", title: "便利店", summary: "日常用品",
            recordDate: "2026-11-10", recordTime: nil, amount: 12.8, category: "日用"
        )
        let context = LocalExpressionContext(
            currentFact: fact, recentFacts: [], memoryContextJSON: nil,
            plannerCandidates: LocalPlannerCandidateEngine.candidates(for: fact), providerMode: .hosted
        )
        let provider = HostedAICompanionProvider(
            accessToken: "test-access-token",
            service: SnapCountUploadService(
                session: session,
                functionsURL: "https://example.test/functions/v1",
                anonKey: "test-publishable-key"
            )
        )

        _ = try await provider.compose(context: context)

        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(object["local_memory_context"])
        let candidate = try XCTUnwrap(object["planner_candidate"] as? [String: Any])
        XCTAssertEqual(candidate["dimension"] as? String, "current_fact")
    }

    func testLF02902BYOKUsesFixedSupplierAndRoutesImageWithSyntheticKey() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let response = #"{"choices":[{"message":{"content":"{\"schema_version\":\"local-recognition-candidate-v1\",\"operation\":\"recognize_only\",\"candidate\":{\"domain_key\":\"wallet\",\"title\":\"已还款截图\",\"summary\":\"还款40元\",\"payload\":{\"record_kind\":\"liability_snapshot\",\"status\":\"paid\",\"amount\":40},\"confidence\":0.8,\"record_date\":\"2026-10-25\",\"evidence_fields\":[\"status\",\"amount\"],\"missing_fields\":[]}}"}}]}"#
        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(response.utf8))
        let fakeKey = "sk-test-synthetic-never-real"
        let image = try syntheticJPEG()
        let provider = QwenBYOKImageRecognitionProvider(apiKey: fakeKey, session: session)

        let candidate = try await provider.recognize(LocalImageRecognitionRequest(
            imageData: image, captureKind: "screenshot", filename: "private-name.jpg", uploadToken: nil
        ))

        let request = try XCTUnwrap(BYOKURLProtocolStub.capturedRequest)
        XCTAssertEqual(request.url, QwenBYOKImageRecognitionProvider.endpoint)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(fakeKey)")
        XCTAssertEqual(candidate.domainKey, "wallet")
        XCTAssertEqual(candidate.title, "已还款截图")
        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBodies.first)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let prompt = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(prompt.contains("account_snapshot_kind=liability"))
        XCTAssertTrue(prompt.contains("status=paid"))
        XCTAssertTrue(prompt.contains("只能交由用户复核"))
        let imageURL = try XCTUnwrap(content.last?["image_url"] as? [String: String])
        XCTAssertEqual(imageURL["url"], "data:image/jpeg;base64,\(image.base64EncodedString())")
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(bodyText.contains(fakeKey))
        XCTAssertFalse(bodyText.contains("private-name.jpg"))
        XCTAssertFalse(request.url!.absoluteString.contains("supabase"))
    }

    func testLF02902BYOKKeepsRecognitionFactsWithoutGeneratedVoice() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let recognition = #"{"schema_version":"local-recognition-candidate-v1","operation":"recognize_only","candidate":{"domain_key":"expense","title":"便利店","summary":"支出8元","payload":{"amount":8,"merchant_name":"便利店","category":"food","platform":"支付宝","payment_method":"余额宝"},"confidence":0.92,"record_date":"2026-10-25","evidence_fields":["amount","merchant_name"],"missing_fields":[]}}"#
        func response(_ content: String) -> Data {
            let object: [String: Any] = [
                "choices": [["message": ["content": content]]]
            ]
            return try! JSONSerialization.data(withJSONObject: object)
        }
        BYOKURLProtocolStub.configure(statusCode: 200, responseData: response(recognition))
        let provider = QwenBYOKImageRecognitionProvider(apiKey: "sk-test-voice", session: session)

        let candidate = try await provider.recognize(LocalImageRecognitionRequest(
            imageData: try syntheticJPEG(), captureKind: "photo_library", filename: "receipt.jpg", uploadToken: nil
        ))

        XCTAssertEqual(BYOKURLProtocolStub.capturedBodies.count, 1)
        XCTAssertNil(candidate.companionMessage)
        XCTAssertNil(candidate.aiFeedback)
    }

    func testLF03004KeychainStoresAndDeletesBYOKCredential() throws {
        let service = "com.jiezi.tests.\(UUID().uuidString)"
        let keychain = KeychainStore(service: service)
        defer { try? keychain.remove(KeychainKeys.byokQwenAPIKey) }
        let sentinel = "sk-test-keychain-only-sentinel"

        do {
            try keychain.setString(sentinel, for: KeychainKeys.byokQwenAPIKey)
        } catch KeychainStoreError.unexpectedStatus(let status) where status == -34_018 {
            throw XCTSkip("This unsigned simulator test runner has no Keychain entitlement; verify persistence on a signed device build.")
        }
        XCTAssertEqual(try keychain.string(for: KeychainKeys.byokQwenAPIKey), sentinel)
        try keychain.remove(KeychainKeys.byokQwenAPIKey)
        XCTAssertNil(try keychain.string(for: KeychainKeys.byokQwenAPIKey))
    }

    func testLF02902BYOKImageRoutesThroughLocalDatabaseAndFileStore() async throws {
        let databaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("byok-database-\(UUID().uuidString)", isDirectory: true)
        let imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("byok-images-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: databaseDirectory)
            try? FileManager.default.removeItem(at: imageDirectory)
        }
        let database = try LocalDatabase(databaseURL: databaseDirectory.appendingPathComponent("local.sqlite"))
        let imageStore = try LocalImageStore(rootDirectory: imageDirectory)
        let repository = try LocalRecordRepository(database: database)
        let localRecordUseCase = LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: repository,
            imageStore: imageStore
        )
        let intakeRepository = LocalImageIntakeRepository(database: database)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let candidateJSON = #"{"schema_version":"local-recognition-candidate-v1","operation":"recognize_only","candidate":{"domain_key":"sport","title":"跑步","summary":"轻运动","payload":{"sport_type":"跑步","duration_minutes":35},"confidence":0.5,"record_date":"2026-10-25","evidence_fields":["sport_type","duration_minutes"],"missing_fields":[]}}"#
        let encodedCandidate = try XCTUnwrap(String(data: JSONEncoder().encode(candidateJSON), encoding: .utf8))
        let response = "{\"choices\":[{\"message\":{\"content\":\(encodedCandidate)}}]}"
        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data(response.utf8))
        let provider = QwenBYOKImageRecognitionProvider(apiKey: "sk-test-local-route", session: session)
        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: localRecordUseCase,
            imageStore: imageStore,
            intakeRepository: intakeRepository,
            provider: provider
        )
        let imageData = try syntheticJPEG()

        let outcome = try await recognition.ingest(
            imageData: imageData, captureKind: "camera", filename: "private-name.jpg", uploadToken: nil
        )

        guard case let .staged(staged) = outcome.result else {
            return XCTFail("low-confidence BYOK candidate must enter the local review queue")
        }
        XCTAssertEqual(staged.record.sourceKind, .aiCandidate)
        let imageHash = try XCTUnwrap(staged.record.imageHash)
        XCTAssertEqual(imageHash, LocalImageStore.sha256(imageData))
        XCTAssertEqual(try imageStore.data(at: try XCTUnwrap(staged.record.imagePath)), imageData)
        let formalRecords = try await localRecordUseCase.records(monthKey: "2026-10")
        XCTAssertTrue(formalRecords.isEmpty)
        let intakeID = "\(staged.profileID.uuidString)-\(imageHash)"
        XCTAssertEqual(try intakeRepository.intake(id: intakeID, profileID: staged.profileID)?.status, .completed)
        let captured = try XCTUnwrap(BYOKURLProtocolStub.capturedRequest)
        XCTAssertEqual(captured.url, QwenBYOKImageRecognitionProvider.endpoint)
        XCTAssertFalse(String(decoding: try XCTUnwrap(BYOKURLProtocolStub.capturedBody), as: UTF8.self).contains("upload_token"))
    }

    func testLF03505CorruptImageIsRejectedBeforeNetworkAndKeptInLocalIntake() async throws {
        let databaseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-image-database-\(UUID().uuidString)", isDirectory: true)
        let imageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-image-files-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: databaseDirectory)
            try? FileManager.default.removeItem(at: imageDirectory)
        }
        let database = try LocalDatabase(databaseURL: databaseDirectory.appendingPathComponent("local.sqlite"))
        let imageStore = try LocalImageStore(rootDirectory: imageDirectory)
        let profileStore = LocalProfileStore(database: database)
        let recordUseCase = LocalRecordUseCase(
            profileStore: profileStore,
            repository: try LocalRecordRepository(database: database),
            imageStore: imageStore
        )
        let intakeRepository = LocalImageIntakeRepository(database: database)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        BYOKURLProtocolStub.configure(statusCode: 400, responseData: Data("synthetic rejection".utf8))
        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: recordUseCase,
            imageStore: imageStore,
            intakeRepository: intakeRepository,
            provider: QwenBYOKImageRecognitionProvider(apiKey: "sk-test-corrupt-image", session: session)
        )
        let corruptBytes = Data("not an encoded image".utf8)

        do {
            _ = try await recognition.ingest(
                imageData: corruptBytes, captureKind: "shortcut", filename: "corrupt.jpg"
            )
            XCTFail("corrupt image bytes must be rejected")
        } catch let error as QwenBYOKError {
            XCTAssertEqual(error, .invalidImage)
        }

        let profile = try profileStore.activeProfile()
        let intakeID = "\(profile.id.uuidString)-\(LocalImageStore.sha256(corruptBytes))"
        let intake = try XCTUnwrap(intakeRepository.intake(id: intakeID, profileID: profile.id))
        XCTAssertEqual(intake.status, .failed)
        XCTAssertEqual(intake.failureMessage, QwenBYOKError.invalidImage.localizedDescription)
        XCTAssertEqual(try imageStore.data(at: intake.imagePath), corruptBytes)
        XCTAssertNil(BYOKURLProtocolStub.capturedRequest)
    }

    func testLF03505BYOKSupplierLimitIsCheckedBeforeRequestCreation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        BYOKURLProtocolStub.configure(statusCode: 200, responseData: Data())
        let provider = QwenBYOKImageRecognitionProvider(apiKey: "sk-test-size-limit", session: session)

        do {
            _ = try await provider.recognize(LocalImageRecognitionRequest(
                imageData: Data(repeating: 0xFF, count: QwenBYOKImageRecognitionProvider.maximumImageBytes + 1),
                captureKind: "shortcut", filename: "oversized.jpg", uploadToken: nil
            ))
            XCTFail("provider size limit must reject oversized input")
        } catch let error as QwenBYOKError {
            XCTAssertEqual(error, .invalidImage)
        }

        XCTAssertNil(BYOKURLProtocolStub.capturedRequest)
    }

    func testLF03101BYOKRejectedKeyIsRedactedFromFailure() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        BYOKURLProtocolStub.configure(statusCode: 401, responseData: Data("synthetic rejection".utf8))
        let fakeKey = "sk-test-rejected-sentinel"
        let provider = QwenBYOKImageRecognitionProvider(apiKey: fakeKey, session: session)

        do {
            _ = try await provider.recognize(LocalImageRecognitionRequest(
                imageData: try syntheticJPEG(), captureKind: "screenshot",
                filename: "private.jpg", uploadToken: nil
            ))
            XCTFail("invalid key response should fail")
        } catch let error as QwenBYOKError {
            XCTAssertEqual(error, .keyRejected)
            XCTAssertFalse(error.localizedDescription.contains(fakeKey))
        }
    }

    private func syntheticJPEG() throws -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8))
        return try XCTUnwrap(renderer.image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }.jpegData(compressionQuality: 0.8))
    }
}

final class BYOKURLProtocolStub: URLProtocol {
    private static let lock = NSLock()
    private static var storedRequest: URLRequest?
    private static var storedBody: Data?
    private static var storedResponseData = Data()
    private static var storedStatusCode = 200
    private static var storedBodies: [Data] = []
    private static var storedResponseQueue: [(Int, Data)] = []

    static var capturedRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return storedRequest
    }

    static var capturedBody: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedBody
    }

    static var capturedBodies: [Data] {
        lock.lock(); defer { lock.unlock() }
        return storedBodies
    }

    static func configure(statusCode: Int, responseData: Data) {
        lock.lock(); defer { lock.unlock() }
        storedRequest = nil
        storedBody = nil
        storedBodies = []
        storedStatusCode = statusCode
        storedResponseData = responseData
        storedResponseQueue = []
    }

    static func configureSequence(_ responses: [(statusCode: Int, responseData: Data)]) {
        lock.lock(); defer { lock.unlock() }
        storedRequest = nil
        storedBody = nil
        storedBodies = []
        storedResponseQueue = responses
        storedStatusCode = responses.last?.statusCode ?? 200
        storedResponseData = responses.last?.responseData ?? Data()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.requestBody(request) ?? Data()
        Self.lock.lock()
        Self.storedRequest = request
        Self.storedBody = body
        Self.storedBodies.append(body)
        let responsePayload = Self.storedResponseQueue.isEmpty
            ? (Self.storedStatusCode, Self.storedResponseData)
            : Self.storedResponseQueue.removeFirst()
        Self.lock.unlock()
        let httpResponse = HTTPURLResponse(
            url: request.url!, statusCode: responsePayload.0, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: httpResponse, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responsePayload.1)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let httpBody = request.httpBody { return httpBody }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let count = buffer.withUnsafeMutableBufferPointer {
                stream.read($0.baseAddress!, maxLength: $0.count)
            }
            if count <= 0 { break }
            data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
