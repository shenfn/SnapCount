import Foundation

protocol NativeRecordFeedbackRepositoryProtocol {
    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws
}

protocol RecordRepositoryProtocol: NativeRecordFeedbackRepositoryProtocol {
    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot
    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail
    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail
    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup
    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback
    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String
    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String
    func delete(reference: String, accessToken: String) async throws
}

struct NativeRecordExpressionPlan: Equatable {
    let planToken: String
    let candidateId: String
    let feedback: NativeAIFeedback
}

enum NativeRecordExpressionPlanLookup: Equatable {
    case available(NativeRecordExpressionPlan)
    case pending
    case unavailable(reason: String)
}

@MainActor
enum NativeRecordExpressionPlanRetryPolicy {
    static let delaysNanoseconds: [UInt64] = [
        250_000_000,
        500_000_000,
        1_000_000_000,
        1_500_000_000,
        2_000_000_000
    ]

    private static func isRetryable(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotConnectToHost,
            .networkConnectionLost,
            .notConnectedToInternet,
            .dnsLookupFailed,
            .cannotFindHost,
            .secureConnectionFailed,
            .serverCertificateUntrusted
        ].contains(urlError.code)
    }

    static func resolve(
        fetch: () async throws -> NativeRecordExpressionPlanLookup,
        shouldContinue: () -> Bool
    ) async -> NativeRecordExpressionPlan? {
        await resolve(
            fetch: fetch,
            shouldContinue: shouldContinue,
            sleep: { try await Task<Never, Never>.sleep(nanoseconds: $0) }
        )
    }

    static func resolve(
        fetch: () async throws -> NativeRecordExpressionPlanLookup,
        shouldContinue: () -> Bool,
        sleep: (UInt64) async throws -> Void
    ) async -> NativeRecordExpressionPlan? {
        var retryIndex = 0
        while shouldContinue(), !Task.isCancelled {
            let lookup: NativeRecordExpressionPlanLookup
            do {
                lookup = try await fetch()
            } catch {
                guard isRetryable(error),
                      shouldContinue(),
                      !Task.isCancelled,
                      retryIndex < delaysNanoseconds.count else { return nil }
                let delay = delaysNanoseconds[retryIndex]
                retryIndex += 1
                do {
                    try await sleep(delay)
                } catch {
                    return nil
                }
                continue
            }
            guard shouldContinue(), !Task.isCancelled else { return nil }
            switch lookup {
            case .available(let plan):
                return plan
            case .unavailable:
                return nil
            case .pending:
                guard retryIndex < delaysNanoseconds.count else { return nil }
                let delay = delaysNanoseconds[retryIndex]
                retryIndex += 1
                do {
                    try await sleep(delay)
                } catch {
                    return nil
                }
            }
        }
        return nil
    }
}

@MainActor
enum NativeRecordExpressionPlanAcknowledgementRetryPolicy {
    static let delaysNanoseconds: [UInt64] = [
        250_000_000,
        500_000_000,
        1_000_000_000
    ]

    static func resolve(
        acknowledge: () async throws -> NativeAIFeedback,
        shouldContinue: () -> Bool
    ) async -> NativeAIFeedback? {
        await resolve(
            acknowledge: acknowledge,
            shouldContinue: shouldContinue,
            sleep: { try await Task<Never, Never>.sleep(nanoseconds: $0) }
        )
    }

    static func resolve(
        acknowledge: () async throws -> NativeAIFeedback,
        shouldContinue: () -> Bool,
        sleep: (UInt64) async throws -> Void
    ) async -> NativeAIFeedback? {
        var retryIndex = 0
        while shouldContinue(), !Task.isCancelled {
            do {
                let feedback = try await acknowledge()
                return shouldContinue() && !Task.isCancelled ? feedback : nil
            } catch {
                guard shouldContinue(),
                      !Task.isCancelled,
                      retryIndex < delaysNanoseconds.count else { return nil }
                let delay = delaysNanoseconds[retryIndex]
                retryIndex += 1
                do {
                    try await sleep(delay)
                } catch {
                    return nil
                }
            }
        }
        return nil
    }
}

final class RecordRepository: RecordRepositoryProtocol {
    private let remoteService: NativeDataService
    private let remoteClient: SupabaseRemoteClientProtocol

    init(
        remoteService: NativeDataService = NativeDataService(),
        remoteClient: SupabaseRemoteClientProtocol = SupabaseRemoteClient()
    ) {
        self.remoteService = remoteService
        self.remoteClient = remoteClient
    }

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        try await remoteService.fetchRecordMonth(monthKey: monthKey, accessToken: accessToken)
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        try await remoteService.fetchRecordDetail(reference: reference, accessToken: accessToken)
    }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail {
        try await remoteService.hydrateRecordDetailImage(detail, accessToken: accessToken)
    }

    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup {
        let response = try await remoteClient.postFunction(
            RecordExpressionPlanResponse.self,
            path: "functions/v1/ingest-receipt",
            body: Self.expressionPlanPreviewRequestBody(reference: reference),
            accessToken: accessToken
        )
        guard response.ok else {
            throw SupabaseRemoteError.requestFailed(response.error ?? "表达计划读取失败")
        }
        guard response.data?.available == true else {
            let reason = response.data?.reason ?? "not_available"
            return reason == "plan_not_ready" ? .pending : .unavailable(reason: reason)
        }
        guard let data = response.data,
              let planToken = data.planToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !planToken.isEmpty,
              let candidateId = data.candidateId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !candidateId.isEmpty,
              let feedback = NativeAIFeedback(payload: data.feedback),
              feedback.source == "expression_planner",
              feedback.candidateId == candidateId,
              data.hasMatchingDeliveryIdentity(feedback: feedback) else {
            throw SupabaseRemoteError.requestFailed("表达计划响应不完整")
        }
        return .available(
            NativeRecordExpressionPlan(
                planToken: planToken,
                candidateId: candidateId,
                feedback: feedback
            )
        )
    }

    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback {
        let response = try await remoteClient.postFunction(
            RecordExpressionPlanResponse.self,
            path: "functions/v1/ingest-receipt",
            body: Self.expressionPlanAcknowledgementRequestBody(
                recordId: recordId,
                planToken: planToken,
                candidateId: candidateId
            ),
            accessToken: accessToken
        )
        guard response.ok else {
            throw SupabaseRemoteError.requestFailed(response.error ?? "表达曝光确认失败")
        }
        guard let data = response.data,
              let feedback = NativeAIFeedback(payload: data.feedback),
              feedback.isAcknowledgedPlannerFeedback,
              feedback.candidateId == candidateId,
              data.candidateId?.trimmingCharacters(in: .whitespacesAndNewlines) == candidateId,
              data.hasMatchingDeliveryIdentity(feedback: feedback) else {
            throw SupabaseRemoteError.requestFailed("表达曝光确认响应不完整")
        }
        return feedback
    }

    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String {
        try await remoteService.createManualRecord(draft, domain: domain, userId: userId, accessToken: accessToken)
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        try await remoteService.saveRecordDetail(draft, accessToken: accessToken)
    }

    func delete(reference: String, accessToken: String) async throws {
        let response = try await remoteClient.postFunction(
            RecordDeletionResponse.self,
            path: "functions/v1/ingest-receipt",
            body: [
                "action": AnyCodable("delete_record"),
                "reference": AnyCodable(NativeRecordReference(reference).canonicalValue)
            ],
            accessToken: accessToken
        )
        guard response.status == "deleted" else {
            throw SupabaseRemoteError.requestFailed(response.error ?? "删除记录失败")
        }
    }

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {
        let response = try await remoteClient.postFunction(
            ExpressionFeedbackResponse.self,
            path: "functions/v1/ingest-receipt",
            body: Self.feedbackRequestBody(
                recordId: recordId,
                choice: choice,
                freeText: freeText,
                exposureEventId: exposureEventId
            ),
            accessToken: accessToken
        )
        guard response.ok else {
            throw SupabaseRemoteError.requestFailed(response.error ?? "点评提交失败")
        }
    }

    static func feedbackRequestBody(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?
    ) -> [String: AnyCodable] {
        var body: [String: AnyCodable] = [
            "action": AnyCodable("submit_expression_feedback"),
            "record_id": AnyCodable(recordId),
            "primary_choice": AnyCodable(choice.rawValue),
            "free_text": AnyCodable(freeText)
        ]
        if let exposureEventId = exposureEventId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !exposureEventId.isEmpty {
            body["exposure_event_id"] = AnyCodable(exposureEventId)
        }
        return body
    }

    static func expressionPlanPreviewRequestBody(reference: String) -> [String: AnyCodable] {
        let recordReference = NativeRecordReference(reference)
        let recordKind = ["expense", "income"].contains(recordReference.kind) ? recordReference.kind : "data"
        return [
            "action": AnyCodable("get_record_expression_plan"),
            "record_id": AnyCodable(recordReference.rawId),
            "record_kind": AnyCodable(recordKind)
        ]
    }

    static func expressionPlanAcknowledgementRequestBody(
        recordId: String,
        planToken: String,
        candidateId: String
    ) -> [String: AnyCodable] {
        [
            "action": AnyCodable("ack_record_expression_plan"),
            "record_id": AnyCodable(recordId),
            "plan_token": AnyCodable(planToken),
            "candidate_id": AnyCodable(candidateId)
        ]
    }
}

private struct RecordExpressionPlanResponse: Decodable {
    let ok: Bool
    let data: RecordExpressionPlanData?
    let error: String?
}

private struct RecordExpressionPlanData: Decodable {
    let available: Bool?
    let reason: String?
    let planToken: String?
    let candidateId: String?
    let feedback: [String: AnyCodable]?
    let presentationTarget: String?
    let renderedTextFingerprint: String?

    private enum CodingKeys: String, CodingKey {
        case available
        case reason
        case planToken = "plan_token"
        case candidateId = "candidate_id"
        case feedback
        case presentationTarget = "presentation_target"
        case renderedTextFingerprint = "rendered_text_fingerprint"
    }

    func hasMatchingDeliveryIdentity(feedback: NativeAIFeedback) -> Bool {
        let envelopeTarget = presentationTarget?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? "feedback_card"
        let envelopeFingerprint = renderedTextFingerprint?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        guard ["feedback_card", "companion_message"].contains(envelopeTarget),
              envelopeTarget == feedback.presentationTarget else { return false }
        if envelopeTarget == "companion_message" {
            return !envelopeFingerprint.isEmpty
                && envelopeFingerprint == feedback.renderedTextFingerprint
                && !feedback.claimFingerprint.isEmpty
                && !feedback.emotionLine.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return envelopeFingerprint.isEmpty
            || feedback.renderedTextFingerprint.isEmpty
            || envelopeFingerprint == feedback.renderedTextFingerprint
    }
}

private struct ExpressionFeedbackResponse: Decodable {
    let ok: Bool
    let error: String?
}

private struct RecordDeletionResponse: Decodable {
    let status: String
    let cleanupPending: Bool
    let error: String?

    private enum CodingKeys: String, CodingKey {
        case status
        case cleanupPending = "cleanup_pending"
        case error
    }
}
