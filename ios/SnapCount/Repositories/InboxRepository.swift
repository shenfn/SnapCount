import Foundation

enum InboxArchiveDomains {
    static let all: [NativeArchiveDomain] = [
        NativeArchiveDomain(id: "expense", title: "消费", systemImage: "creditcard"),
        NativeArchiveDomain(id: "income", title: "收入", systemImage: "banknote"),
        NativeArchiveDomain(id: "diet", title: "饮食", systemImage: "fork.knife"),
        NativeArchiveDomain(id: "exercise", title: "运动", systemImage: "figure.run"),
        NativeArchiveDomain(id: "sleep", title: "睡眠", systemImage: "bed.double"),
        NativeArchiveDomain(id: "wallet", title: "钱包", systemImage: "wallet.pass")
    ]
}

protocol InboxRepositoryProtocol {
    func discard(id: String, accessToken: String) async throws
    func retry(id: String, accessToken: String) async throws -> ShortcutUploadResult
    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String
}

final class InboxRepository: InboxRepositoryProtocol {
    private let remoteService: NativeDataService

    init(remoteService: NativeDataService = NativeDataService()) {
        self.remoteService = remoteService
    }

    func discard(id: String, accessToken: String) async throws {
        try await remoteService.discardStagingRecord(id: id, accessToken: accessToken)
    }

    func retry(id: String, accessToken: String) async throws -> ShortcutUploadResult {
        try await remoteService.retryStagingRecord(id: id, accessToken: accessToken)
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String {
        try await remoteService.archiveStagingRecord(record, domainKey: domainKey, accessToken: accessToken)
    }
}
