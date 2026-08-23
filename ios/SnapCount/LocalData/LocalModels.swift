import Foundation

struct LocalProfile: Equatable {
    let id: UUID
    let createdAt: Date
    let cloudUserID: String?
    let syncEnabled: Bool
}

struct LocalAccountDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let createdAt: Date
}

struct LocalAccount: Equatable {
    let id: UUID
    let profileID: UUID
    let name: String
    let kind: String
    let currency: String
    let openingBalanceMinor: Int64
    let createdAt: Date
}

struct LocalExpenseDraft: Equatable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let createdAt: Date
}

struct LocalExpense: Equatable {
    let id: UUID
    let profileID: UUID
    let accountID: UUID
    let amountMinor: Int64
    let currency: String
    let merchantName: String
    let platform: String
    let category: String
    let paymentMethod: String
    let transactionDate: String
    let transactionTime: String?
    let note: String?
    let localVersion: Int64
    let createdAt: Date
    let updatedAt: Date
}

struct LocalOutboxOperation: Equatable {
    let sequence: Int64
    let operationID: UUID
    let profileID: UUID
    let aggregateKind: String
    let aggregateID: UUID
    let operationKind: String
    let aggregateVersion: Int64
    let idempotencyKey: String
    let status: String
    let attemptCount: Int
    let createdAt: Date
}

enum LocalDataError: Error, Equatable {
    case invalidAmount
    case invalidIdentifier
    case invalidRecord
}
