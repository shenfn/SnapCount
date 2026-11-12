import Foundation
import GRDB

struct GenericImportPreview: Equatable {
    let records: [GenericImportRecordDraft]
    let errors: [GenericImportCSVError]
    let skipped: Int
    var warnings: Int { records.reduce(0) { $0 + $1.warnings.count } }
    var insertableCount: Int { records.count - skipped }
}

struct GenericImportResult: Equatable { let inserted: Int; let skipped: Int; let warnings: Int }

final class GenericImportService {
    private let database: LocalDatabase
    private let profileStore: LocalProfileStore
    private let parser = GenericImportCSVParser()
    init(database: LocalDatabase) { self.database = database; self.profileStore = LocalProfileStore(database: database) }

    func preview(_ data: Data) throws -> GenericImportPreview {
        let parsed = parser.parse(data), profile = try profileStore.activeProfile()
        let skipped = try database.writer.read { db in
            try parsed.records.reduce(into: 0) { count, draft in if try Self.exists(db, draft: draft, profileID: profile.id) { count += 1 } }
        }
        return GenericImportPreview(records: parsed.records, errors: parsed.errors, skipped: skipped)
    }

    func importCSV(_ data: Data) throws -> GenericImportResult {
        let parsed = parser.parse(data)
        guard parsed.errors.isEmpty else { throw GenericImportError.invalidRows(parsed.errors) }
        let profile = try profileStore.activeProfile()
        return try database.writer.write { db in
            var inserted = 0, skipped = 0
            for draft in parsed.records {
                if try Self.exists(db, draft: draft, profileID: profile.id) { skipped += 1; continue }
                let id = UUID(), now = Date()
                let payload = String(decoding: try JSONSerialization.data(withJSONObject: draft.rawFields, options: [.sortedKeys]), as: UTF8.self)
                if draft.kind == .expense {
                    try db.execute(sql: "INSERT INTO local_expenses (id, profile_id, account_id, amount_minor, currency, merchant_name, platform, category, payment_method, transaction_date, transaction_time, note, local_version, created_at, updated_at, deleted_at, companion_message, ai_feedback) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, ?, ?, NULL, NULL, NULL)", arguments: [id.uuidString, profile.id.uuidString, draft.amountMinor, draft.currency, draft.merchant, draft.channel, draft.category, draft.channel, draft.businessDate, draft.occurredAt, draft.note, now, now])
                } else {
                    try db.execute(sql: "INSERT INTO local_income_records (id, profile_id, account_id, amount_minor, currency, source_name, category, income_date, occurred_at, note, local_version, created_at, updated_at, deleted_at, companion_message, ai_feedback) VALUES (?, ?, NULL, ?, ?, ?, ?, ?, NULL, ?, 1, ?, ?, NULL, NULL, NULL)", arguments: [id.uuidString, profile.id.uuidString, draft.amountMinor, draft.currency, draft.merchant, draft.category, draft.businessDate, draft.note, now, now])
                }
                try db.execute(sql: "INSERT INTO local_import_metadata (id, profile_id, target_kind, target_id, source_record_id, source_fingerprint, source_payload_json, imported_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)", arguments: [UUID().uuidString, profile.id.uuidString, draft.kind.rawValue, id.uuidString, draft.sourceRecordID, draft.sourceFingerprint, payload, now])
                inserted += 1
            }
            return GenericImportResult(inserted: inserted, skipped: skipped, warnings: parsed.records.reduce(0) { $0 + $1.warnings.count })
        }
    }
    private static func exists(_ db: Database, draft: GenericImportRecordDraft, profileID: UUID) throws -> Bool {
        try Int.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM local_import_metadata WHERE profile_id = ? AND ((source_record_id IS NOT NULL AND source_record_id = ?) OR source_fingerprint = ?))", arguments: [profileID.uuidString, draft.sourceRecordID, draft.sourceFingerprint]) == 1
    }
}

enum GenericImportError: Error, LocalizedError {
    case invalidRows([GenericImportCSVError])
    var errorDescription: String? { if case .invalidRows(let errors) = self { return errors.map(\.localizedDescription).joined(separator: "\n") }; return nil }
}
