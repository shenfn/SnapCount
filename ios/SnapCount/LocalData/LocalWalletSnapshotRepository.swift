import Foundation
import GRDB

enum LocalWalletSnapshotKind: String, Codable, Equatable {
    case asset
    case liability
}

struct LocalWalletSnapshot: Equatable, Identifiable {
    let id: UUID
    let profileID: UUID
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let linkedAccountID: UUID?
    let imagePath: String?
    let imageHash: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date

    var balance: Double { Double(balanceMinor) / 100 }
}

struct LocalWalletSnapshotCommand {
    let id: UUID
    let title: String
    let summary: String
    let payload: [String: AnyCodable]
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let imageData: Data?
    let createdAt: Date
}

struct LocalWalletSnapshotDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let title: String
    let summary: String
    let payloadJSON: String
    let recordDate: String
    let recordTime: String?
    let occurredAt: String?
    let balanceMinor: Int64
    let currency: String
    let kind: LocalWalletSnapshotKind
    let imagePath: String?
    let imageHash: String?
    let createdAt: Date
}

protocol LocalWalletSnapshotRepositoryProtocol {
    func create(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot
    func unlinked(profileID: UUID) throws -> [LocalWalletSnapshot]
}

final class LocalWalletSnapshotRepository: LocalWalletSnapshotRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) {
        self.database = database
    }

    func create(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              draft.balanceMinor >= 0,
              draft.currency == "CNY",
              NativeLocalDate.monthKey(from: draft.recordDate) != nil,
              (draft.recordTime == nil || draft.occurredAt != nil),
              draft.occurredAt.map({ NativeLocalDate.financeDateKey(occurredAt: $0, legacyDate: nil) == draft.recordDate }) ?? true,
              draft.occurredAt.map({ NativeLocalDate.financeTimeKey(occurredAt: $0) == draft.recordTime }) ?? true,
              (draft.imagePath == nil) == (draft.imageHash == nil) else {
            throw LocalDataError.invalidRecord
        }

        return try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO local_wallet_snapshots (
                        id, profile_id, title, summary, payload_json, record_date, record_time,
                        occurred_at, snapshot_balance_minor, currency, account_snapshot_kind,
                        linked_account_id, image_path, image_hash, local_version, created_at,
                        updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString, draft.profileID.uuidString, title, draft.summary,
                    draft.payloadJSON, draft.recordDate, draft.recordTime, draft.occurredAt,
                    draft.balanceMinor, draft.currency, draft.kind.rawValue,
                    draft.imagePath, draft.imageHash, draft.createdAt, draft.createdAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND profile_id = ?",
                arguments: [draft.id.uuidString, draft.profileID.uuidString]
            ) else { throw LocalDataError.recordNotFound }
            return try Self.snapshot(from: row)
        }
    }

    func unlinked(profileID: UUID) throws -> [LocalWalletSnapshot] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_wallet_snapshots
                    WHERE profile_id = ? AND linked_account_id IS NULL AND deleted_at IS NULL
                    ORDER BY record_date DESC, occurred_at DESC, created_at DESC, id
                    """,
                arguments: [profileID.uuidString]
            ).map(Self.snapshot(from:))
        }
    }

    private static func snapshot(from row: Row) throws -> LocalWalletSnapshot {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let kind = LocalWalletSnapshotKind(rawValue: row["account_snapshot_kind"]),
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let linkedAccountText: String? = row["linked_account_id"]
        return LocalWalletSnapshot(
            id: id,
            profileID: profileID,
            title: row["title"],
            summary: row["summary"],
            payloadJSON: row["payload_json"],
            recordDate: row["record_date"],
            recordTime: row["record_time"],
            occurredAt: row["occurred_at"],
            balanceMinor: row["snapshot_balance_minor"],
            currency: row["currency"],
            kind: kind,
            linkedAccountID: linkedAccountText.flatMap(UUID.init(uuidString:)),
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

protocol LocalWalletSnapshotUseCaseProtocol {
    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshot
    func unlinked() async throws -> [LocalWalletSnapshot]
}

final class LocalWalletSnapshotUseCase: LocalWalletSnapshotUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalWalletSnapshotRepositoryProtocol
    private let imageStore: LocalImageStore?

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalWalletSnapshotRepositoryProtocol,
        imageStore: LocalImageStore? = nil
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.imageStore = imageStore
    }

    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshot {
        let profile = try profileStore.activeProfile()
        let payloadJSON = try LocalRecordCodec.encode(command.payload)
        let imageReference: LocalImageReference?
        if let imageData = command.imageData {
            guard let imageStore else { throw LocalDataError.invalidRecord }
            imageReference = try imageStore.save(
                data: imageData,
                owner: "wallet-snapshot-\(command.id.uuidString)-\(UUID().uuidString)"
            )
        } else {
            imageReference = nil
        }
        do {
            return try repository.create(LocalWalletSnapshotDraft(
                id: command.id,
                profileID: profile.id,
                title: command.title,
                summary: command.summary,
                payloadJSON: payloadJSON,
                recordDate: command.recordDate,
                recordTime: command.recordTime,
                occurredAt: command.occurredAt,
                balanceMinor: command.balanceMinor,
                currency: command.currency,
                kind: command.kind,
                imagePath: imageReference?.path,
                imageHash: imageReference?.hash,
                createdAt: command.createdAt
            ))
        } catch {
            if let path = imageReference?.path { try? imageStore?.remove(path: path) }
            throw error
        }
    }

    func unlinked() async throws -> [LocalWalletSnapshot] {
        let profile = try profileStore.activeProfile()
        return try repository.unlinked(profileID: profile.id)
    }
}
