import Foundation

protocol RecordRepositoryProtocol {
    func fetchGroups(monthKey: String, accessToken: String) async throws -> [NativeDayRecordGroup]
    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail
    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String
    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String
    func delete(reference: String, accessToken: String) async throws
    func submitFeedback(recordId: String, choice: NativeAIFeedbackReviewChoice, freeText: String, accessToken: String) async throws
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

    func fetchGroups(monthKey: String, accessToken: String) async throws -> [NativeDayRecordGroup] {
        try await remoteService.fetchRecordGroups(monthKey: monthKey, accessToken: accessToken)
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        try await remoteService.fetchRecordDetail(reference: reference, accessToken: accessToken)
    }

    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String {
        try await remoteService.createManualRecord(draft, domain: domain, userId: userId, accessToken: accessToken)
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        try await remoteService.saveRecordDetail(draft, accessToken: accessToken)
    }

    func delete(reference: String, accessToken: String) async throws {
        try await remoteService.deleteRecord(reference: reference, accessToken: accessToken)
    }

    func submitFeedback(recordId: String, choice: NativeAIFeedbackReviewChoice, freeText: String, accessToken: String) async throws {
        let response = try await remoteClient.postFunction(
            ExpressionFeedbackResponse.self,
            path: "functions/v1/ingest-receipt",
            body: [
                "action": AnyCodable("submit_expression_feedback"),
                "record_id": AnyCodable(recordId),
                "primary_choice": AnyCodable(choice.rawValue),
                "free_text": AnyCodable(freeText)
            ],
            accessToken: accessToken
        )
        guard response.ok else {
            throw SupabaseRemoteError.requestFailed(response.error ?? "点评提交失败")
        }
    }
}

private struct ExpressionFeedbackResponse: Decodable {
    let ok: Bool
    let error: String?
}
