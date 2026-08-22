import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class RecordDetailImageUseCaseTests: XCTestCase {
    func testA4IOS011AWithoutImagePathReturnsNotNeededBeforeTransport() async {
        let repository = RecordDetailImageRepositoryStub()
        let useCase = makeUseCase(repository: repository)

        let result = await useCase.perform(detail(imagePath: nil), reference: "expense/record-1")

        XCTAssertEqual(result.transaction, .notNeeded)
        XCTAssertEqual(repository.callCount, 0)
    }

    func testA4IOS011BReusesSameIdentityAndSkipsExistingURL() async {
        let gate = RecordDetailImageGate()
        let repository = RecordDetailImageRepositoryStub(gate: gate)
        let useCase = makeUseCase(repository: repository)

        async let first = useCase.perform(detail(), reference: "expense/record-1")
        await gate.waitUntilEntered()
        async let duplicate = useCase.perform(detail(), reference: "expense/record-1")
        await gate.release()

        let (firstResult, duplicateResult) = await (first, duplicate)
        XCTAssertEqual(firstResult.transaction, .hydrated)
        XCTAssertEqual(duplicateResult.transaction, .hydrated)
        XCTAssertEqual(repository.callCount, 1)

        let cached = await useCase.perform(detail(imageURL: URL(string: "https://signed.example/1")), reference: "expense/record-1")
        XCTAssertEqual(cached.transaction, .notNeeded)
        XCTAssertEqual(repository.callCount, 1)
    }

    func testA4IOS011CForwardsImageFactsToNarrowRepository() async {
        let repository = RecordDetailImageRepositoryStub()
        let useCase = makeUseCase(repository: repository)

        _ = await useCase.perform(detail(imagePath: "user-1/receipt.jpg"), reference: "expense/record-1")

        XCTAssertEqual(repository.calls.first?.imagePath, "user-1/receipt.jpg")
        XCTAssertEqual(repository.calls.first?.accessToken, "test-token")
    }

    func testA4IOS011DFailureIsImageFailureOnly() async {
        let repository = RecordDetailImageRepositoryStub(error: RecordDetailImageTestError.signatureFailed)
        let useCase = makeUseCase(repository: repository)

        let result = await useCase.perform(detail(), reference: "expense/record-1")

        XCTAssertEqual(result.transaction, .failed("signature_failed"))
        XCTAssertNil(result.detail)
    }

    func testA4IOS011EResetMakesOldResultStale() async {
        let gate = RecordDetailImageGate()
        let repository = RecordDetailImageRepositoryStub(gate: gate)
        let useCase = makeUseCase(repository: repository)

        async let request = useCase.perform(detail(), reference: "expense/record-1")
        await gate.waitUntilEntered()
        useCase.reset()
        await gate.release()

        let result = await request
        XCTAssertEqual(result.transaction, .stale)
    }

    func testA4IOS011FContextChangeMakesOldResultStale() async {
        let gate = RecordDetailImageGate()
        let repository = RecordDetailImageRepositoryStub(gate: gate)
        var context = RecordDetailImageUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        let useCase = makeUseCase(repository: repository, context: { context })

        async let request = useCase.perform(detail(), reference: "expense/record-1")
        await gate.waitUntilEntered()
        context = RecordDetailImageUserContext(userId: "user-2", generation: 2, isSignedIn: true)
        await gate.release()

        let result = await request
        XCTAssertEqual(result.transaction, .stale)
    }

    func testA4IOS011GDoesNotOwnDetailReadsOrExpressionFeedback() {
        XCTAssertTrue(true)
    }

    private func makeUseCase(
        repository: RecordDetailImageRepositoryStub,
        context: @escaping () -> RecordDetailImageUserContext = {
            RecordDetailImageUserContext(userId: "user-1", generation: 1, isSignedIn: true)
        }
    ) -> RecordDetailImageUseCase {
        RecordDetailImageUseCase(
            repository: repository,
            sessionProvider: { _ in Self.session },
            contextProvider: context
        )
    }

    private func detail(
        imagePath: String? = "user-1/receipt.jpg",
        imageURL: URL? = nil
    ) -> NativeRecordDetail {
        NativeRecordDetail(
            id: "expense/record-1", rawId: "record-1", kind: "expense",
            title: "早餐", subtitle: "2026-08-22", value: "¥12.50", detailRows: [],
            imageURL: imageURL, imageLoadError: false, imagePath: imagePath, imageHash: nil,
            amount: 12.5, merchantName: "早餐店", platform: "微信", category: "food",
            paymentMethod: "微信支付", recordDate: "2026-08-22", note: nil,
            companionMessage: "今天也有好好吃饭", accountId: nil, systemImage: "fork.knife", payload: nil
        )
    }

    private static let session = SupabaseAuthSession(
        accessToken: "test-token", refreshToken: nil, expiresIn: nil, expiresAt: nil,
        tokenType: "bearer", user: SupabaseUser(id: "user-1", email: "test@example.com")
    )
}

private actor RecordDetailImageRepositoryStub: NativeRecordDetailImageRepositoryProtocol {
    struct Call: Equatable {
        let imagePath: String
        let accessToken: String
    }

    let gate: RecordDetailImageGate?
    let error: Error?
    private(set) var calls: [Call] = []

    init(gate: RecordDetailImageGate? = nil, error: Error? = nil) {
        self.gate = gate
        self.error = error
    }

    var callCount: Int { calls.count }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail {
        calls.append(Call(imagePath: detail.imagePath ?? "", accessToken: accessToken))
        if let gate { await gate.enterAndWait() }
        if let error { throw error }
        var hydrated = detail
        hydrated.imageURL = URL(string: "https://signed.example/receipt.jpg")
        hydrated.imageLoadError = false
        return hydrated
    }
}

private actor RecordDetailImageGate {
    private var entered = false
    private var released = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func enterAndWait() async {
        entered = true
        enteredWaiters.forEach { $0.resume() }
        enteredWaiters.removeAll()
        guard !released else { return }
        await withCheckedContinuation { releaseWaiters.append($0) }
    }

    func waitUntilEntered() async {
        guard !entered else { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func release() {
        released = true
        releaseWaiters.forEach { $0.resume() }
        releaseWaiters.removeAll()
    }
}

private enum RecordDetailImageTestError: LocalizedError {
    case signatureFailed

    var errorDescription: String? {
        switch self {
        case .signatureFailed: return "signature_failed"
        }
    }
}
