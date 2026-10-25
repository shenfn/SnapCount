import Foundation
import UIKit
import XCTest
@testable import SnapCount

final class LocalBYOKProviderTests: XCTestCase {
    func testLF02902BYOKUsesFixedSupplierAndRoutesImageWithSyntheticKey() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BYOKURLProtocolStub.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let response = #"{"choices":[{"message":{"content":"{\"schema_version\":\"local-recognition-candidate-v1\",\"operation\":\"recognize_only\",\"candidate\":{\"domain_key\":\"food\",\"title\":\"早餐\",\"summary\":\"豆浆\",\"payload\":{\"food_name\":\"豆浆\"},\"confidence\":0.8,\"record_date\":\"2026-10-25\",\"evidence_fields\":[\"food_name\"],\"missing_fields\":[]}}"}}]}"#
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
        XCTAssertEqual(candidate.domainKey, "food")
        XCTAssertEqual(candidate.title, "早餐")
        let body = try XCTUnwrap(BYOKURLProtocolStub.capturedBody)
        let bodyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let messages = try XCTUnwrap(bodyObject["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        let imageURL = try XCTUnwrap(content.last?["image_url"] as? [String: String])
        XCTAssertEqual(imageURL["url"], "data:image/jpeg;base64,\(image.base64EncodedString())")
        let bodyText = String(decoding: body, as: UTF8.self)
        XCTAssertFalse(bodyText.contains(fakeKey))
        XCTAssertFalse(bodyText.contains("private-name.jpg"))
        XCTAssertFalse(request.url!.absoluteString.contains("supabase"))
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

    static var capturedRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return storedRequest
    }

    static var capturedBody: Data? {
        lock.lock(); defer { lock.unlock() }
        return storedBody
    }

    static func configure(statusCode: Int, responseData: Data) {
        lock.lock(); defer { lock.unlock() }
        storedRequest = nil
        storedBody = nil
        storedStatusCode = statusCode
        storedResponseData = responseData
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.requestBody(request)
        Self.lock.lock()
        Self.storedRequest = request
        Self.storedBody = body
        let data = Self.storedResponseData
        let status = Self.storedStatusCode
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
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
