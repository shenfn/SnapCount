import Foundation

enum LocalDatabaseSpikeError: Error, Equatable {
    case injectedFailure
}
struct SpikeExpenseSnapshot: Equatable {
    let stableID: UUID
    let amountMinor: Int64
    let note: String?
}
