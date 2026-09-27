import Foundation
import GRDB

protocol LocalWalletSnapshotRepositoryProtocol {
    func createSnapshot(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot
    func updateSnapshot(_ update: LocalWalletSnapshotUpdate, profileID: UUID) throws -> LocalWalletSnapshot
    func deleteSnapshot(
        _ command: LocalWalletSnapshotDeleteCommand,
        profileID: UUID
    ) throws -> LocalWalletSnapshotTombstone
    func snapshot(id: UUID) throws -> LocalWalletSnapshot?
    func snapshots(profileID: UUID, monthKey: String) throws -> [LocalWalletSnapshot]
    func snapshotTombstone(id: UUID) throws -> LocalWalletSnapshotTombstone?
}

final class LocalWalletSnapshotRepository: LocalWalletSnapshotRepositoryProtocol {
    private let database: LocalDatabase

    init(database: LocalDatabase) throws {
        self.database = database
    }

    func createSnapshot(_ draft: LocalWalletSnapshotDraft) throws -> LocalWalletSnapshot {
        try validate(
            snapshotKind: draft.snapshotKind,
            amountMinor: draft.amountMinor,
            minimumPaymentMinor: draft.minimumPaymentMinor,
            currency: draft.currency,
            accountName: draft.accountName,
            accountType: draft.accountType,
            snapshotDate: draft.snapshotDate,
            snapshotTime: draft.snapshotTime,
            dueDate: draft.dueDate,
            billDay: draft.billDay
        )
        return try database.writer.write { db in
            try validateAccount(
                accountID: draft.accountID,
                profileID: draft.profileID,
                snapshotKind: draft.snapshotKind,
                currency: draft.currency,
                database: db
            )
            try db.execute(
                sql: """
                    INSERT INTO local_wallet_snapshots (
                        id, profile_id, account_id, snapshot_kind, amount_minor,
                        minimum_payment_minor, currency, account_name, account_type,
                        snapshot_date, snapshot_time, due_date, bill_day, note,
                        payload_json, image_path, image_hash, source_kind, local_version,
                        created_at, updated_at, deleted_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL)
                    """,
                arguments: [
                    draft.id.uuidString,
                    draft.profileID.uuidString,
                    draft.accountID?.uuidString,
                    draft.snapshotKind,
                    draft.amountMinor,
                    draft.minimumPaymentMinor,
                    draft.currency,
                    draft.accountName,
                    draft.accountType,
                    draft.snapshotDate,
                    draft.snapshotTime,
                    draft.dueDate,
                    draft.billDay,
                    draft.note,
                    draft.payloadJSON,
                    draft.imagePath,
                    draft.imageHash,
                    draft.sourceKind,
                    draft.createdAt,
                    draft.createdAt
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?",
                arguments: [draft.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.snapshot(from: row)
        }
    }

    func updateSnapshot(
        _ update: LocalWalletSnapshotUpdate,
        profileID: UUID
    ) throws -> LocalWalletSnapshot {
        try validate(
            snapshotKind: update.snapshotKind,
            amountMinor: update.amountMinor,
            minimumPaymentMinor: update.minimumPaymentMinor,
            currency: update.currency,
            accountName: update.accountName,
            accountType: update.accountType,
            snapshotDate: update.snapshotDate,
            snapshotTime: update.snapshotTime,
            dueDate: update.dueDate,
            billDay: update.billDay
        )
        return try database.writer.write { db in
            let current = try activeSnapshot(id: update.id, database: db)
            guard current.profileID == profileID else { throw LocalDataError.invalidIdentifier }
            guard current.localVersion == update.expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: update.expectedVersion,
                    actual: current.localVersion
                )
            }
            try validateAccount(
                accountID: update.accountID,
                profileID: profileID,
                snapshotKind: update.snapshotKind,
                currency: update.currency,
                database: db
            )
            try db.execute(
                sql: """
                    UPDATE local_wallet_snapshots
                    SET account_id = ?, snapshot_kind = ?, amount_minor = ?,
                        minimum_payment_minor = ?, currency = ?, account_name = ?,
                        account_type = ?, snapshot_date = ?, snapshot_time = ?,
                        due_date = ?, bill_day = ?, note = ?, payload_json = ?,
                        local_version = local_version + 1, updated_at = ?
                    WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    update.accountID?.uuidString,
                    update.snapshotKind,
                    update.amountMinor,
                    update.minimumPaymentMinor,
                    update.currency,
                    update.accountName,
                    update.accountType,
                    update.snapshotDate,
                    update.snapshotTime,
                    update.dueDate,
                    update.billDay,
                    update.note,
                    update.payloadJSON,
                    update.updatedAt,
                    update.id.uuidString,
                    profileID.uuidString
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?",
                arguments: [update.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.snapshot(from: row)
        }
    }

    func deleteSnapshot(
        _ command: LocalWalletSnapshotDeleteCommand,
        profileID: UUID
    ) throws -> LocalWalletSnapshotTombstone {
        try database.writer.write { db in
            let current = try activeSnapshot(id: command.id, database: db)
            guard current.profileID == profileID else { throw LocalDataError.invalidIdentifier }
            guard current.localVersion == command.expectedVersion else {
                throw LocalDataError.versionConflict(
                    expected: command.expectedVersion,
                    actual: current.localVersion
                )
            }
            try db.execute(
                sql: """
                    UPDATE local_wallet_snapshots
                    SET local_version = local_version + 1, updated_at = ?, deleted_at = ?
                    WHERE id = ? AND profile_id = ? AND deleted_at IS NULL
                    """,
                arguments: [
                    command.deletedAt,
                    command.deletedAt,
                    command.id.uuidString,
                    profileID.uuidString
                ]
            )
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ?",
                arguments: [command.id.uuidString]
            ) else {
                throw LocalDataError.recordNotFound
            }
            return try Self.tombstone(from: row)
        }
    }

    func snapshot(id: UUID) throws -> LocalWalletSnapshot? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND deleted_at IS NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.snapshot(from: row)
        }
    }

    func snapshots(profileID: UUID, monthKey: String) throws -> [LocalWalletSnapshot] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM local_wallet_snapshots
                    WHERE profile_id = ?
                      AND snapshot_date BETWEEN ? AND ?
                      AND deleted_at IS NULL
                    ORDER BY snapshot_date DESC, snapshot_time DESC, created_at DESC, id DESC
                    """,
                arguments: [profileID.uuidString, "\(monthKey)-01", "\(monthKey)-31"]
            ).map { try Self.snapshot(from: $0) }
        }
    }

    func snapshotTombstone(id: UUID) throws -> LocalWalletSnapshotTombstone? {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND deleted_at IS NOT NULL",
                arguments: [id.uuidString]
            ) else { return nil }
            return try Self.tombstone(from: row)
        }
    }

    private func activeSnapshot(id: UUID, database: Database) throws -> LocalWalletSnapshot {
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT * FROM local_wallet_snapshots WHERE id = ? AND deleted_at IS NULL",
            arguments: [id.uuidString]
        ) else { throw LocalDataError.recordNotFound }
        return try Self.snapshot(from: row)
    }

    private static func validate(
        snapshotKind: String,
        amountMinor: Int64,
        minimumPaymentMinor: Int64?,
        currency: String,
        accountName: String,
        accountType: String,
        snapshotDate: String,
        snapshotTime: String?,
        dueDate: String?,
        billDay: Int?
    ) throws {
        let normalizedKind = snapshotKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCurrency = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedName = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedType = canonicalAccountType(accountType)
        guard normalizedKind == "asset" || normalizedKind == "liability",
              amountMinor >= 0,
              minimumPaymentMinor == nil || minimumPaymentMinor! >= 0,
              normalizedCurrency == "CNY",
              !normalizedName.isEmpty,
              allowedAccountTypes.contains(normalizedType),
              !snapshotDate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LocalDataError.invalidRecord
        }
        guard isDateKey(snapshotDate),
              snapshotTime == nil || isTimeKey(snapshotTime!),
              dueDate == nil || isDateKey(dueDate!) else {
            throw LocalDataError.invalidRecord
        }
        let isLiability = normalizedKind == "liability"
        guard isLiability == isLiabilityAccountType(normalizedType) else {
            throw LocalDataError.invalidAccountKind
        }
        guard isLiability || (dueDate == nil && billDay == nil) else {
            throw LocalDataError.invalidRecord
        }
        guard billDay == nil || (1...31).contains(billDay!) else {
            throw LocalDataError.invalidRecord
        }
    }

    private static func isDateKey(_ value: String) -> Bool {
        let parts = value.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              year >= 1,
              (1...12).contains(month),
              (1...31).contains(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return calendar.date(from: DateComponents(year: year, month: month, day: day)) != nil
    }

    private static func isTimeKey(_ value: String) -> Bool {
        let parts = value.split(separator: ":")
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ $0.count == 2 }),
              let hour = Int(parts[0]),
              let minute = Int(parts[1]),
              (0...23).contains(hour),
              (0...59).contains(minute) else { return false }
        if parts.count == 3, let second = Int(parts[2]) {
            return (0...59).contains(second)
        }
        return parts.count == 2
    }

    private static func validateAccount(
        accountID: UUID?,
        profileID: UUID,
        snapshotKind: String,
        currency: String,
        database: Database
    ) throws {
        guard let accountID else { return }
        guard let row = try Row.fetchOne(
            database,
            sql: "SELECT profile_id, kind, currency FROM local_accounts WHERE id = ?",
            arguments: [accountID.uuidString]
        ) else {
            throw LocalDataError.invalidIdentifier
        }
        guard let storedProfileID: String = row["profile_id"], storedProfileID == profileID.uuidString else {
            throw LocalDataError.invalidIdentifier
        }
        guard let kind: String = row["kind"],
              let storedCurrency: String = row["currency"],
              storedCurrency.uppercased() == currency.uppercased() else {
            throw LocalDataError.invalidRecord
        }
        let accountIsLiability = isLiabilityAccountType(canonicalAccountType(kind))
        let snapshotIsLiability = snapshotKind
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "liability"
        guard accountIsLiability == snapshotIsLiability else {
            throw LocalDataError.invalidAccountKind
        }
    }

    private static let allowedAccountTypes: Set<String> = [
        "cash", "wallet_balance", "debit_card", "credit_card", "credit_line", "other"
    ]

    private static func canonicalAccountType(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "balance", "wechat", "alipay": return "wallet_balance"
        case "bank", "bank_card", "debit": return "debit_card"
        case "huabei", "jd_baitiao", "douyin_monthly": return "credit_line"
        default: return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func isLiabilityAccountType(_ value: String) -> Bool {
        ["credit_card", "credit_line"].contains(canonicalAccountType(value))
    }

    private static func snapshot(from row: Row) throws -> LocalWalletSnapshot {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let snapshotKind: String = row["snapshot_kind"],
              let currency: String = row["currency"],
              let accountName: String = row["account_name"],
              let accountType: String = row["account_type"],
              let snapshotDate: String = row["snapshot_date"],
              let payloadJSON: String = row["payload_json"],
              let sourceKind: String = row["source_kind"],
              let createdAt: Date = row["created_at"],
              let updatedAt: Date = row["updated_at"] else {
            throw LocalDataError.invalidRecord
        }
        let accountID: String? = row["account_id"]
        return LocalWalletSnapshot(
            id: id,
            profileID: profileID,
            accountID: accountID.flatMap(UUID.init(uuidString:)),
            snapshotKind: snapshotKind,
            amountMinor: row["amount_minor"],
            minimumPaymentMinor: row["minimum_payment_minor"],
            currency: currency,
            accountName: accountName,
            accountType: accountType,
            snapshotDate: snapshotDate,
            snapshotTime: row["snapshot_time"],
            dueDate: row["due_date"],
            billDay: row["bill_day"],
            note: row["note"],
            payloadJSON: payloadJSON,
            imagePath: row["image_path"],
            imageHash: row["image_hash"],
            sourceKind: sourceKind,
            localVersion: row["local_version"],
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func tombstone(from row: Row) throws -> LocalWalletSnapshotTombstone {
        guard let id = UUID(uuidString: row["id"]),
              let profileID = UUID(uuidString: row["profile_id"]),
              let deletedAt: Date = row["deleted_at"] else {
            throw LocalDataError.invalidRecord
        }
        return LocalWalletSnapshotTombstone(
            id: id,
            profileID: profileID,
            localVersion: row["local_version"],
            deletedAt: deletedAt,
            imagePath: row["image_path"]
        )
    }
}
