import Foundation

struct LocalWalletSnapshotCommand {
    let id: UUID
    let accountID: UUID?
    let snapshotKind: String
    let amountText: String
    let minimumPaymentText: String?
    let currency: String
    let accountName: String
    let accountType: String
    let snapshotDate: String
    let snapshotTime: String?
    let dueDate: String?
    let billDay: Int?
    let note: String?
    let payload: [String: AnyCodable]
    let imageData: Data?
    let imageReference: LocalImageReference?
    let createdAt: Date

    init(
        id: UUID,
        accountID: UUID?,
        snapshotKind: String,
        amountText: String,
        minimumPaymentText: String?,
        currency: String,
        accountName: String,
        accountType: String,
        snapshotDate: String,
        snapshotTime: String?,
        dueDate: String?,
        billDay: Int?,
        note: String?,
        payload: [String: AnyCodable],
        imageData: Data? = nil,
        imageReference: LocalImageReference? = nil,
        createdAt: Date
    ) {
        self.id = id
        self.accountID = accountID
        self.snapshotKind = snapshotKind
        self.amountText = amountText
        self.minimumPaymentText = minimumPaymentText
        self.currency = currency
        self.accountName = accountName
        self.accountType = accountType
        self.snapshotDate = snapshotDate
        self.snapshotTime = snapshotTime
        self.dueDate = dueDate
        self.billDay = billDay
        self.note = note
        self.payload = payload
        self.imageData = imageData
        self.imageReference = imageReference
        self.createdAt = createdAt
    }
}

struct LocalWalletSnapshotUpdateCommand {
    let id: UUID
    let expectedVersion: Int64
    let accountID: UUID?
    let snapshotKind: String
    let amountText: String
    let minimumPaymentText: String?
    let currency: String
    let accountName: String
    let accountType: String
    let snapshotDate: String
    let snapshotTime: String?
    let dueDate: String?
    let billDay: Int?
    let note: String?
    let payload: [String: AnyCodable]
    let updatedAt: Date
}

struct LocalWalletSnapshotDeleteCommand: Equatable {
    let id: UUID
    let expectedVersion: Int64
    let deletedAt: Date
}

struct LocalWalletSnapshotOutcome: Equatable {
    let snapshot: LocalWalletSnapshot
    let profileID: UUID
}

struct LocalWalletSnapshotDeleteOutcome: Equatable {
    let tombstone: LocalWalletSnapshotTombstone
    let profileID: UUID
}

protocol LocalWalletSnapshotUseCaseProtocol {
    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshotOutcome
    func update(_ command: LocalWalletSnapshotUpdateCommand) async throws -> LocalWalletSnapshotOutcome
    func delete(_ command: LocalWalletSnapshotDeleteCommand) async throws -> LocalWalletSnapshotDeleteOutcome
    func snapshot(id: UUID) async throws -> LocalWalletSnapshot?
    func month(_ monthKey: String) async throws -> [LocalWalletSnapshot]
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

    func create(_ command: LocalWalletSnapshotCommand) async throws -> LocalWalletSnapshotOutcome {
        let profile = try profileStore.activeProfile()
        let imageReference = try saveImage(command.imageData, existing: command.imageReference, id: command.id)
        let draft: LocalWalletSnapshotDraft
        do {
            draft = try Self.draft(command, profileID: profile.id, imageReference: imageReference)
            let snapshot = try repository.createSnapshot(draft)
            return LocalWalletSnapshotOutcome(snapshot: snapshot, profileID: profile.id)
        } catch {
            try? imageStore?.remove(path: imageReference?.path)
            throw error
        }
    }

    func update(_ command: LocalWalletSnapshotUpdateCommand) async throws -> LocalWalletSnapshotOutcome {
        let profile = try profileStore.activeProfile()
        let snapshot = try repository.updateSnapshot(
            try Self.update(command),
            profileID: profile.id
        )
        return LocalWalletSnapshotOutcome(snapshot: snapshot, profileID: profile.id)
    }

    func delete(_ command: LocalWalletSnapshotDeleteCommand) async throws -> LocalWalletSnapshotDeleteOutcome {
        let profile = try profileStore.activeProfile()
        let tombstone = try repository.deleteSnapshot(command, profileID: profile.id)
        try? imageStore?.remove(path: tombstone.imagePath)
        return LocalWalletSnapshotDeleteOutcome(tombstone: tombstone, profileID: profile.id)
    }

    func snapshot(id: UUID) async throws -> LocalWalletSnapshot? {
        let profile = try profileStore.activeProfile()
        guard let snapshot = try repository.snapshot(id: id) else { return nil }
        guard snapshot.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return snapshot
    }

    func month(_ monthKey: String) async throws -> [LocalWalletSnapshot] {
        let profile = try profileStore.activeProfile()
        return try repository.snapshots(profileID: profile.id, monthKey: monthKey)
    }

    private func saveImage(
        _ data: Data?,
        existing: LocalImageReference?,
        id: UUID
    ) throws -> LocalImageReference? {
        guard data != nil || existing != nil else { return nil }
        guard let imageStore else { throw LocalDataError.invalidRecord }
        if let existing {
            return try imageStore.move(existing, to: "records")
        }
        guard let data else { return nil }
        return try imageStore.save(
            data: data,
            owner: "wallet-\(id.uuidString)-\(UUID().uuidString)",
            bucket: "records"
        )
    }

    private static func draft(
        _ command: LocalWalletSnapshotCommand,
        profileID: UUID,
        imageReference: LocalImageReference?
    ) throws -> LocalWalletSnapshotDraft {
        let kind = normalizedKind(command.snapshotKind)
        let currency = normalizedCurrency(command.currency)
        let accountType = normalizedAccountType(command.accountType)
        let amountMinor = try LocalWalletSnapshotMoney.amountMinor(
            command.amountText,
            currency: currency,
            allowZero: true
        )
        let minimumPaymentMinor = try optionalAmountMinor(command.minimumPaymentText, currency: currency)
        let payloadJSON = try payloadJSON(
            command.payload,
            snapshotKind: kind,
            amountMinor: amountMinor,
            minimumPaymentMinor: minimumPaymentMinor,
            currency: currency,
            accountName: command.accountName,
            accountType: accountType,
            accountID: command.accountID,
            snapshotDate: command.snapshotDate,
            snapshotTime: command.snapshotTime,
            dueDate: command.dueDate,
            billDay: command.billDay,
            note: command.note
        )
        return LocalWalletSnapshotDraft(
            id: command.id,
            profileID: profileID,
            accountID: command.accountID,
            snapshotKind: kind,
            amountMinor: amountMinor,
            minimumPaymentMinor: minimumPaymentMinor,
            currency: currency,
            accountName: normalizedText(command.accountName),
            accountType: accountType,
            snapshotDate: normalizedText(command.snapshotDate),
            snapshotTime: normalizedOptionalText(command.snapshotTime),
            dueDate: normalizedOptionalText(command.dueDate),
            billDay: command.billDay,
            note: normalizedOptionalText(command.note),
            payloadJSON: payloadJSON,
            imagePath: imageReference?.path,
            imageHash: imageReference?.hash,
            sourceKind: "manual",
            createdAt: command.createdAt
        )
    }

    private static func update(_ command: LocalWalletSnapshotUpdateCommand) throws -> LocalWalletSnapshotUpdate {
        let kind = normalizedKind(command.snapshotKind)
        let currency = normalizedCurrency(command.currency)
        let accountType = normalizedAccountType(command.accountType)
        let amountMinor = try LocalWalletSnapshotMoney.amountMinor(
            command.amountText,
            currency: currency,
            allowZero: true
        )
        let minimumPaymentMinor = try optionalAmountMinor(command.minimumPaymentText, currency: currency)
        let payloadJSON = try payloadJSON(
            command.payload,
            snapshotKind: kind,
            amountMinor: amountMinor,
            minimumPaymentMinor: minimumPaymentMinor,
            currency: currency,
            accountName: command.accountName,
            accountType: accountType,
            accountID: command.accountID,
            snapshotDate: command.snapshotDate,
            snapshotTime: command.snapshotTime,
            dueDate: command.dueDate,
            billDay: command.billDay,
            note: command.note
        )
        return LocalWalletSnapshotUpdate(
            id: command.id,
            expectedVersion: command.expectedVersion,
            accountID: command.accountID,
            snapshotKind: kind,
            amountMinor: amountMinor,
            minimumPaymentMinor: minimumPaymentMinor,
            currency: currency,
            accountName: normalizedText(command.accountName),
            accountType: accountType,
            snapshotDate: normalizedText(command.snapshotDate),
            snapshotTime: normalizedOptionalText(command.snapshotTime),
            dueDate: normalizedOptionalText(command.dueDate),
            billDay: command.billDay,
            note: normalizedOptionalText(command.note),
            payloadJSON: payloadJSON,
            updatedAt: command.updatedAt
        )
    }

    private static func payloadJSON(
        _ payload: [String: AnyCodable],
        snapshotKind: String,
        amountMinor: Int64,
        minimumPaymentMinor: Int64?,
        currency: String,
        accountName: String,
        accountType: String,
        accountID: UUID?,
        snapshotDate: String,
        snapshotTime: String?,
        dueDate: String?,
        billDay: Int?,
        note: String?
    ) throws -> String {
        var values = payload
        values["snapshot_kind"] = AnyCodable(snapshotKind)
        values["amount_minor"] = AnyCodable(Int(amountMinor))
        values["currency"] = AnyCodable(currency)
        values["account_name"] = AnyCodable(accountName)
        values["account_type"] = AnyCodable(accountType)
        values["snapshot_date"] = AnyCodable(snapshotDate)
        values["account_id"] = accountID.map { AnyCodable($0.uuidString) } ?? AnyCodable(NSNull())
        values["snapshot_time"] = snapshotTime.map { AnyCodable($0) } ?? AnyCodable(NSNull())
        values["due_date"] = dueDate.map { AnyCodable($0) } ?? AnyCodable(NSNull())
        values["bill_day"] = billDay.map { AnyCodable($0) } ?? AnyCodable(NSNull())
        values["note"] = note.map { AnyCodable($0) } ?? AnyCodable(NSNull())
        values["minimum_payment_minor"] = minimumPaymentMinor
            .map { AnyCodable(Int($0)) }
            ?? AnyCodable(NSNull())
        return try LocalRecordCodec.encode(values)
    }

    private static func optionalAmountMinor(_ text: String?, currency: String) throws -> Int64? {
        guard let text else { return nil }
        return try LocalWalletSnapshotMoney.amountMinor(text, currency: currency, allowZero: true)
    }

    private static func normalizedKind(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func normalizedCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }

    private static func normalizedAccountType(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "balance", "wechat", "alipay": return "wallet_balance"
        case "bank", "bank_card", "debit": return "debit_card"
        case "huabei", "jd_baitiao", "douyin_monthly": return "credit_line"
        default: return value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        }
    }

    private static func normalizedText(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedOptionalText(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = normalizedText(value)
        return normalized.isEmpty ? nil : normalized
    }
}

enum LocalWalletSnapshotMoney {
    static func amountMinor(
        _ text: String,
        currency: String,
        allowZero: Bool = false
    ) throws -> Int64 {
        guard currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "CNY" else {
            throw LocalDataError.invalidRecord
        }
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              let decimal = Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0,
              (allowZero || decimal > 0) else {
            throw LocalDataError.invalidAmount
        }
        var scaled = decimal * Decimal(100)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .bankers)
        guard scaled == rounded,
              (allowZero || rounded > 0),
              rounded <= Decimal(Int64.max) else {
            throw LocalDataError.invalidAmount
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
