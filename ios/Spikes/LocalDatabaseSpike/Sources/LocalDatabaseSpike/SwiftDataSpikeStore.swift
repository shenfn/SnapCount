import Foundation
import SwiftData

enum SwiftDataSpikeSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Expense.self, OutboxOperation.self]
    }

    @Model
    final class Expense {
        @Attribute(.unique) var stableID: UUID
        var amountMinor: Int64
        var occurredAt: Date

        init(stableID: UUID, amountMinor: Int64, occurredAt: Date) {
            self.stableID = stableID
            self.amountMinor = amountMinor
            self.occurredAt = occurredAt
        }
    }

    @Model
    final class OutboxOperation {
        @Attribute(.unique) var operationID: UUID
        var recordID: UUID
        var operationKind: String
        var createdAt: Date

        init(operationID: UUID, recordID: UUID, operationKind: String, createdAt: Date) {
            self.operationID = operationID
            self.recordID = recordID
            self.operationKind = operationKind
            self.createdAt = createdAt
        }
    }
}
enum SwiftDataSpikeSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Expense.self, OutboxOperation.self]
    }

    @Model
    final class Expense {
        @Attribute(.unique) var stableID: UUID
        var amountMinor: Int64
        var occurredAt: Date
        var note: String?

        init(stableID: UUID, amountMinor: Int64, occurredAt: Date, note: String? = nil) {
            self.stableID = stableID
            self.amountMinor = amountMinor
            self.occurredAt = occurredAt
            self.note = note
        }
    }

    @Model
    final class OutboxOperation {
        @Attribute(.unique) var operationID: UUID
        var recordID: UUID
        var operationKind: String
        var createdAt: Date

        init(operationID: UUID, recordID: UUID, operationKind: String, createdAt: Date) {
            self.operationID = operationID
            self.recordID = recordID
            self.operationKind = operationKind
            self.createdAt = createdAt
        }
    }
}

enum SwiftDataSpikeMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SwiftDataSpikeSchemaV1.self, SwiftDataSpikeSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [v1ToV2]
    }

    static let v1ToV2 = MigrationStage.lightweight(
        fromVersion: SwiftDataSpikeSchemaV1.self,
        toVersion: SwiftDataSpikeSchemaV2.self
    )
}

final class SwiftDataSpikeStore {
    private let container: ModelContainer

    init(databaseURL: URL) throws {
        let schema = Schema(versionedSchema: SwiftDataSpikeSchemaV2.self)
        let configuration = ModelConfiguration(
            "LocalDatabaseSpike",
            schema: schema,
            url: databaseURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: SwiftDataSpikeMigrationPlan.self,
            configurations: [configuration]
        )
    }

    func insertExpenseAndOutbox(
        stableID: UUID,
        operationID: UUID,
        amountMinor: Int64,
        note: String? = nil,
        injectFailureAfterExpense: Bool = false
    ) throws {
        let context = ModelContext(container)
        context.insert(
            SwiftDataSpikeSchemaV2.Expense(
                stableID: stableID,
                amountMinor: amountMinor,
                occurredAt: Date(),
                note: note
            )
        )

        if injectFailureAfterExpense {
            context.rollback()
            throw LocalDatabaseSpikeError.injectedFailure
        }

        context.insert(
            SwiftDataSpikeSchemaV2.OutboxOperation(
                operationID: operationID,
                recordID: stableID,
                operationKind: "upsert",
                createdAt: Date()
            )
        )
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func insertExpenseOnly(stableID: UUID, amountMinor: Int64, note: String? = nil) throws {
        let context = ModelContext(container)
        context.insert(
            SwiftDataSpikeSchemaV2.Expense(
                stableID: stableID,
                amountMinor: amountMinor,
                occurredAt: Date(),
                note: note
            )
        )
        try context.save()
    }

    func expenseCount() throws -> Int {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<SwiftDataSpikeSchemaV2.Expense>())
    }

    func outboxCount() throws -> Int {
        let context = ModelContext(container)
        return try context.fetchCount(FetchDescriptor<SwiftDataSpikeSchemaV2.OutboxOperation>())
    }

    func expense(stableID: UUID) throws -> SpikeExpenseSnapshot? {
        let context = ModelContext(container)
        return try context.fetch(FetchDescriptor<SwiftDataSpikeSchemaV2.Expense>())
            .first(where: { $0.stableID == stableID })
            .map {
                SpikeExpenseSnapshot(
                    stableID: $0.stableID,
                    amountMinor: $0.amountMinor,
                    note: $0.note
                )
            }
    }

    static func createVersion1Database(
        at databaseURL: URL,
        stableID: UUID,
        amountMinor: Int64
    ) throws {
        let schema = Schema(versionedSchema: SwiftDataSpikeSchemaV1.self)
        let configuration = ModelConfiguration(
            "LocalDatabaseSpike",
            schema: schema,
            url: databaseURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        context.insert(
            SwiftDataSpikeSchemaV1.Expense(
                stableID: stableID,
                amountMinor: amountMinor,
                occurredAt: Date()
            )
        )
        try context.save()
    }
}
