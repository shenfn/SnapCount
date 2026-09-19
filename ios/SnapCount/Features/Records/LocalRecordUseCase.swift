import Foundation

protocol LocalRecordUseCaseProtocol {
    func create(_ command: LocalRecordCommand) async throws -> LocalRecordOutcome
    func update(_ command: LocalRecordUpdateCommand) async throws -> LocalRecordOutcome
    func delete(_ command: LocalRecordDeleteCommand) async throws -> LocalRecordDeleteOutcome
    func record(id: UUID) async throws -> LocalRecord?
    func tombstone(id: UUID) async throws -> LocalRecordTombstone?
    func month(_ monthKey: String) async throws -> LocalRecordMonth
    func records(monthKey: String) async throws -> [LocalRecord]
    func stage(_ candidate: LocalRecordCandidate) async throws -> LocalStagingOutcome
    func ingest(_ candidate: LocalRecordCandidate, recordID: UUID?) async throws -> LocalRecordIntakeOutcome
    func staging(id: String) async throws -> LocalStagingRecord?
    func stagingRecords() async throws -> [LocalStagingRecord]
    func confirmStaging(id: String, recordID: UUID) async throws -> LocalRecordOutcome
    func discardStaging(id: String) async throws
}

final class LocalRecordUseCase: LocalRecordUseCaseProtocol {
    private let profileStore: LocalProfileStoreProtocol
    private let repository: LocalRecordRepositoryProtocol
    private let imageStore: LocalImageStore?

    init(
        profileStore: LocalProfileStoreProtocol,
        repository: LocalRecordRepositoryProtocol,
        imageStore: LocalImageStore? = nil
    ) {
        self.profileStore = profileStore
        self.repository = repository
        self.imageStore = imageStore
    }

    func create(_ command: LocalRecordCommand) async throws -> LocalRecordOutcome {
        let profile = try profileStore.activeProfile()
        try LocalRecordValidation.validate(
            domainKey: command.domainKey,
            title: command.title,
            recordDate: command.recordDate,
            recordTime: command.recordTime
        )
        let payloadJSON = try LocalRecordCodec.encode(
            LocalRecordCodec.normalizedPayload(domainKey: command.domainKey, payload: command.payload)
        )
        if (command.imageData != nil || command.imageReference != nil), imageStore == nil {
            throw LocalDataError.invalidRecord
        }
        let imageReference: LocalImageReference?
        if let existingReference = command.imageReference {
            guard let imageStore else { throw LocalDataError.invalidRecord }
            imageReference = try imageStore.move(existingReference, to: "records")
        } else if let imageData = command.imageData {
            imageReference = try imageStore?.save(
                data: imageData,
                owner: "record-\(command.id.uuidString)-\(UUID().uuidString)",
                bucket: "records"
            )
        } else {
            imageReference = nil
        }
        let draft = LocalRecordDraft(
            id: command.id,
            profileID: profile.id,
            domainKey: command.domainKey,
            title: command.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: command.summary,
            payloadJSON: payloadJSON,
            recordDate: command.recordDate,
            recordTime: command.recordTime,
            note: command.note,
            imagePath: imageReference?.path,
            imageHash: imageReference?.hash,
            createdAt: command.createdAt,
            sourceKind: command.sourceKind,
            domainVersion: 1
        )
        do {
            let record = try repository.createRecord(draft)
            return LocalRecordOutcome(record: record, profileID: profile.id)
        } catch {
            try? imageStore?.remove(path: imageReference?.path)
            throw error
        }
    }

    func update(_ command: LocalRecordUpdateCommand) async throws -> LocalRecordOutcome {
        let profile = try profileStore.activeProfile()
        let domainKey = try currentDomainKey(for: command.id, profileID: profile.id)
        try LocalRecordValidation.validate(
            domainKey: domainKey,
            title: command.title,
            recordDate: command.recordDate,
            recordTime: command.recordTime
        )
        let normalized = LocalRecordUpdateCommand(
            id: command.id,
            expectedVersion: command.expectedVersion,
            title: command.title,
            summary: command.summary,
            payload: try LocalRecordCodec.normalizedPayload(domainKey: domainKey, payload: command.payload),
            recordDate: command.recordDate,
            recordTime: command.recordTime,
            note: command.note,
            updatedAt: command.updatedAt
        )
        let record = try repository.updateRecord(normalized, profileID: profile.id)
        return LocalRecordOutcome(record: record, profileID: profile.id)
    }

    func delete(_ command: LocalRecordDeleteCommand) async throws -> LocalRecordDeleteOutcome {
        let profile = try profileStore.activeProfile()
        let tombstone = try repository.deleteRecord(command, profileID: profile.id)
        try? imageStore?.remove(path: tombstone.imagePath)
        return LocalRecordDeleteOutcome(tombstone: tombstone, profileID: profile.id)
    }

    func record(id: UUID) async throws -> LocalRecord? {
        let profile = try profileStore.activeProfile()
        guard let record = try repository.record(id: id) else { return nil }
        guard record.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return record
    }

    func tombstone(id: UUID) async throws -> LocalRecordTombstone? {
        let profile = try profileStore.activeProfile()
        guard let tombstone = try repository.recordTombstone(id: id) else { return nil }
        guard tombstone.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return tombstone
    }

    func month(_ monthKey: String) async throws -> LocalRecordMonth {
        let profile = try profileStore.activeProfile()
        return LocalRecordMonth(
            profileID: profile.id,
            records: try repository.records(profileID: profile.id, monthKey: monthKey)
        )
    }

    func records(monthKey: String) async throws -> [LocalRecord] {
        let month = try await month(monthKey)
        return month.records
    }

    func stage(_ candidate: LocalRecordCandidate) async throws -> LocalStagingOutcome {
        let profile = try profileStore.activeProfile()
        try LocalRecordValidation.validate(
            domainKey: candidate.domainKey,
            title: candidate.title,
            recordDate: candidate.recordDate,
            recordTime: candidate.recordTime
        )
        let payloadJSON = try LocalRecordCodec.encode(
            LocalRecordCodec.normalizedPayload(
                domainKey: candidate.domainKey,
                payload: candidate.payload,
                requireFacts: false
            )
        )
        if (candidate.imageData != nil || candidate.imageReference != nil), imageStore == nil {
            throw LocalDataError.invalidRecord
        }
        let imageReference: LocalImageReference?
        if let existingReference = candidate.imageReference {
            guard let imageStore else { throw LocalDataError.invalidRecord }
            imageReference = try imageStore.move(existingReference, to: "staging")
        } else if let imageData = candidate.imageData {
            imageReference = try imageStore?.save(
                data: imageData,
                owner: "staging-\(candidate.id)-\(UUID().uuidString)",
                bucket: "staging"
            )
        } else {
            imageReference = nil
        }
        let draft = LocalStagingDraft(
            id: candidate.id,
            profileID: profile.id,
            domainKey: candidate.domainKey,
            status: .pendingReview,
            confidence: candidate.confidence,
            title: candidate.title.trimmingCharacters(in: .whitespacesAndNewlines),
            summary: candidate.summary,
            payloadJSON: payloadJSON,
            recordDate: candidate.recordDate,
            recordTime: candidate.recordTime,
            imagePath: imageReference?.path,
            imageHash: imageReference?.hash,
            evidenceFields: candidate.evidenceFields,
            missingFields: candidate.missingFields,
            createdAt: candidate.createdAt,
            sourceKind: .aiCandidate,
            domainVersion: 1
        )
        do {
            let record = try repository.createStaging(draft)
            return LocalStagingOutcome(record: record, profileID: profile.id)
        } catch {
            try? imageStore?.remove(path: imageReference?.path)
            throw error
        }
    }

    func ingest(_ candidate: LocalRecordCandidate, recordID: UUID? = nil) async throws -> LocalRecordIntakeOutcome {
        if let recordID, let existing = try await record(id: recordID) {
            return .archived(LocalRecordOutcome(record: existing, profileID: existing.profileID))
        }
        if let existingStaging = try await staging(id: candidate.id) {
            switch existingStaging.status {
            case .pendingReview:
                return .staged(LocalStagingOutcome(record: existingStaging, profileID: existingStaging.profileID))
            case .archived:
                if let targetRecordID = existingStaging.targetRecordID,
                   let existing = try await record(id: targetRecordID) {
                    return .archived(LocalRecordOutcome(record: existing, profileID: existing.profileID))
                }
            case .discarded, .failed:
                break
            }
        }
        switch LocalRecordIntakeRouter.route(
            domainKey: candidate.domainKey,
            confidence: candidate.confidence,
            payload: candidate.payload
        ) {
        case .autoArchive:
            let command = LocalRecordCommand(
                id: recordID ?? UUID(),
                domainKey: candidate.domainKey,
                title: candidate.title,
                summary: candidate.summary,
                payload: candidate.payload,
                recordDate: candidate.recordDate,
                recordTime: candidate.recordTime,
                note: candidate.payload.string("note"),
                imageData: candidate.imageData,
                imageReference: candidate.imageReference,
                createdAt: candidate.createdAt,
                sourceKind: .aiAutoArchive
            )
            return .archived(try await create(command))
        case .staging:
            return .staged(try await stage(candidate))
        }
    }

    func staging(id: String) async throws -> LocalStagingRecord? {
        let profile = try profileStore.activeProfile()
        guard let record = try repository.staging(id: id) else { return nil }
        guard record.profileID == profile.id else { throw LocalDataError.invalidIdentifier }
        return record
    }

    func stagingRecords() async throws -> [LocalStagingRecord] {
        let profile = try profileStore.activeProfile()
        return try repository.stagingRecords(profileID: profile.id)
    }

    func confirmStaging(id: String, recordID: UUID) async throws -> LocalRecordOutcome {
        let profile = try profileStore.activeProfile()
        let record = try repository.archiveStaging(
            id: id,
            recordID: recordID,
            updatedAt: Date(),
            profileID: profile.id
        )
        return LocalRecordOutcome(record: record, profileID: profile.id)
    }

    func discardStaging(id: String) async throws {
        let profile = try profileStore.activeProfile()
        let staging = try repository.staging(id: id)
        try repository.discardStaging(id: id, updatedAt: Date(), profileID: profile.id)
        try? imageStore?.remove(path: staging?.imagePath)
    }

    private func currentDomainKey(for id: UUID, profileID: UUID) throws -> String {
        guard let record = try repository.record(id: id) else { throw LocalDataError.recordNotFound }
        guard record.profileID == profileID else { throw LocalDataError.invalidIdentifier }
        return record.domainKey
    }
}
