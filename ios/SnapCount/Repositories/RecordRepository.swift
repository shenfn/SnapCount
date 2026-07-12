import Foundation

protocol RecordRepositoryProtocol {
    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail
    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String
    func delete(reference: String, accessToken: String) async throws
}

final class RecordRepository: RecordRepositoryProtocol {
    private let remoteService: NativeDataService

    init(remoteService: NativeDataService = NativeDataService()) {
        self.remoteService = remoteService
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        try await remoteService.fetchRecordDetail(reference: reference, accessToken: accessToken)
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        try await remoteService.saveRecordDetail(draft, accessToken: accessToken)
    }

    func delete(reference: String, accessToken: String) async throws {
        try await remoteService.deleteRecord(reference: reference, accessToken: accessToken)
    }
}
