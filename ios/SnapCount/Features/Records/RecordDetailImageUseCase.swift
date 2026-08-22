import Foundation

protocol NativeRecordDetailImageRepositoryProtocol {
    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail
}

struct RecordDetailImageUserContext: Equatable {
    let userId: String
    let generation: Int
    let isSignedIn: Bool
    let activeRecordReference: String?

    init(
        userId: String,
        generation: Int,
        isSignedIn: Bool,
        activeRecordReference: String? = nil
    ) {
        self.userId = userId
        self.generation = generation
        self.isSignedIn = isSignedIn
        self.activeRecordReference = activeRecordReference
    }
}

enum RecordDetailImageTransaction: Equatable {
    case hydrated
    case notNeeded
    case failed(String)
    case stale
}

struct RecordDetailImageResult {
    let transaction: RecordDetailImageTransaction
    let detail: NativeRecordDetail?

    static func hydrated(_ detail: NativeRecordDetail) -> Self {
        Self(transaction: .hydrated, detail: detail)
    }

    static var notNeeded: Self {
        Self(transaction: .notNeeded, detail: nil)
    }

    static func failed(_ message: String) -> Self {
        Self(transaction: .failed(message), detail: nil)
    }

    static var stale: Self {
        Self(transaction: .stale, detail: nil)
    }
}

@MainActor
final class RecordDetailImageUseCase {
    typealias ContextProvider = () -> RecordDetailImageUserContext

    private struct Identity: Hashable {
        let userId: String
        let generation: Int
        let reference: String
        let imagePath: String
    }

    private struct InFlight {
        let token: UUID
        let task: Task<RecordDetailImageResult, Never>
    }

    private let repository: NativeRecordDetailImageRepositoryProtocol
    private let sessionProvider: NativeSessionProvider
    private let contextProvider: ContextProvider
    private var inFlight: [Identity: InFlight] = [:]
    private var resetGeneration = 0

    init(
        repository: NativeRecordDetailImageRepositoryProtocol,
        sessionProvider: @escaping NativeSessionProvider,
        contextProvider: @escaping ContextProvider
    ) {
        self.repository = repository
        self.sessionProvider = sessionProvider
        self.contextProvider = contextProvider
    }

    func perform(_ detail: NativeRecordDetail, reference: String) async -> RecordDetailImageResult {
        guard let imagePath = detail.imagePath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !imagePath.isEmpty,
              detail.imageURL == nil else {
            return .notNeeded
        }

        let context = contextProvider()
        guard context.isSignedIn, !context.userId.isEmpty else {
            return .failed("unauthenticated")
        }
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        let identity = Identity(
            userId: context.userId,
            generation: context.generation,
            reference: canonicalReference,
            imagePath: imagePath
        )
        if let existing = inFlight[identity] {
            return await existing.task.value
        }

        let token = UUID()
        let expectedResetGeneration = resetGeneration
        let task = Task { [weak self] in
            guard let self else { return RecordDetailImageResult.stale }
            return await self.execute(
                detail,
                reference: canonicalReference,
                context: context,
                expectedResetGeneration: expectedResetGeneration
            )
        }
        inFlight[identity] = InFlight(token: token, task: task)
        let result = await task.value
        if inFlight[identity]?.token == token {
            inFlight.removeValue(forKey: identity)
        }
        return result
    }

    func reset() {
        resetGeneration += 1
        inFlight.removeAll()
    }

    private func execute(
        _ detail: NativeRecordDetail,
        reference: String,
        context: RecordDetailImageUserContext,
        expectedResetGeneration: Int
    ) async -> RecordDetailImageResult {
        guard isCurrent(context, reference: reference, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        let session: SupabaseAuthSession
        do {
            session = try await sessionProvider(false)
        } catch {
            return currentOrStale(
                context,
                reference: reference,
                expectedResetGeneration: expectedResetGeneration,
                result: .failed(error.localizedDescription)
            )
        }
        guard session.user.id == context.userId,
              isCurrent(context, reference: reference, expectedResetGeneration: expectedResetGeneration) else {
            return .stale
        }

        do {
            let hydrated = try await repository.hydrateDetailImage(detail, accessToken: session.accessToken)
            return currentOrStale(
                context,
                reference: reference,
                expectedResetGeneration: expectedResetGeneration,
                result: .hydrated(hydrated)
            )
        } catch {
            return currentOrStale(
                context,
                reference: reference,
                expectedResetGeneration: expectedResetGeneration,
                result: .failed(error.localizedDescription)
            )
        }
    }

    private func isCurrent(
        _ context: RecordDetailImageUserContext,
        reference: String,
        expectedResetGeneration: Int
    ) -> Bool {
        let current = contextProvider()
        return resetGeneration == expectedResetGeneration
            && current.isSignedIn
            && current.userId == context.userId
            && current.generation == context.generation
            && (current.activeRecordReference == nil || current.activeRecordReference == reference)
    }

    private func currentOrStale(
        _ context: RecordDetailImageUserContext,
        reference: String,
        expectedResetGeneration: Int,
        result: RecordDetailImageResult
    ) -> RecordDetailImageResult {
        isCurrent(context, reference: reference, expectedResetGeneration: expectedResetGeneration)
            ? result
            : .stale
    }
}
