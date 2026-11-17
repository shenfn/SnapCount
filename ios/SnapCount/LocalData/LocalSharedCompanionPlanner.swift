import Foundation
import JavaScriptCore

/// Runs the bundled PWA Planner against formal records from one local profile.
enum LocalSharedCompanionPlanner {
    static func plan(
        currentID: String, facts: [LocalFact], includeHistory: Bool, includeRelatedRecords: Bool
    ) -> LocalSharedCompanionPlan? {
        guard let current = facts.first(where: { $0.id.uuidString.caseInsensitiveCompare(currentID) == .orderedSame }),
              let source = sourceRecord(current, id: currentID),
              let resource = Bundle.main.url(forResource: "LocalSharedCompanionPlanner", withExtension: "js"),
              let script = try? String(contentsOf: resource, encoding: .utf8),
              let context = JSContext() else { return nil }

        var input: [String: Any] = ["current": source, "includeRelatedRecords": includeRelatedRecords]
        if includeHistory {
            input["history"] = facts.filter { $0.id != current.id && $0.createdAt < current.createdAt }
                .compactMap { sourceRecord($0, id: $0.id.uuidString) }
        }
        context.evaluateScript(script)
        let planner = context.objectForKeyedSubscript("JieziSharedPlanner")
        guard let response = planner?.objectForKeyedSubscript("buildLocalSharedVoiceBrief")?
            .call(withArguments: [input]), context.exception == nil else { return nil }
        if response.isNull { return LocalSharedCompanionPlan(briefJSON: nil) }
        guard let brief = response.toDictionary(),
              let data = try? JSONSerialization.data(withJSONObject: brief, options: [.sortedKeys]),
              data.count <= 16_384 else { return nil }
        return LocalSharedCompanionPlan(briefJSON: String(decoding: data, as: UTF8.self))
    }

    private static func sourceRecord(_ fact: LocalFact, id: String) -> [String: Any]? {
        let payload = LocalCompanionCompositionSupport.jsonObject(fact.payloadJSON) as? [String: Any] ?? [:]
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var source: [String: Any] = [
            "id": id,
            "domain_key": fact.domainKey,
            "record_date": fact.businessDate,
            "created_at": iso.string(from: fact.createdAt),
            "title": fact.title,
            "summary": fact.summary,
            "payload_jsonb": payload.filter { !["companion_message", "ai_feedback", "planner_ai_feedback"].contains($0.key) },
        ]
        source["occurred_at"] = fact.occurredAt
        source["note"] = fact.note
        switch fact.kind {
        case .expense, .income:
            guard payload["currency"] as? String == "CNY",
                  let minor = payload["amount_minor"] as? NSNumber else { return nil }
            source["amount"] = minor.doubleValue / 100
            source["category"] = payload["category"]
            source["image_hash"] = fact.imageHash
            if fact.kind == .expense {
                source["transaction_date"] = fact.businessDate
                source["merchant_name"] = payload["merchant_name"]
                source["platform"] = payload["platform"]
                source["payment_method"] = payload["payment_method"]
                source["status"] = "done"
                source["type"] = "expense"
            } else {
                source["income_date"] = fact.businessDate
                source["source_name"] = payload["source_name"]
            }
        case .record:
            if fact.domainKey == "sleep", let wake = payload["wake_at"] as? String {
                source["occurred_at"] = wake
            }
            if fact.domainKey == "wallet" {
                guard payload["currency"] as? String == "CNY",
                      let minor = payload["snapshot_balance_minor"] as? NSNumber else { return nil }
                source["snapshot_balance"] = minor.doubleValue / 100
                source["linked_account_id"] = payload["linked_account_id"]
                source["account_snapshot_kind"] = payload["account_snapshot_kind"]
                source["snapshot_at"] = fact.occurredAt
            }
        }
        return source
    }
}

struct LocalSharedCompanionPlan: Equatable {
    let briefJSON: String?

    var brief: [String: Any]? {
        LocalCompanionCompositionSupport.jsonObject(briefJSON) as? [String: Any]
    }

    var feedback: NativeAIFeedback? {
        guard var payload = brief, let text = payload["canonical_text"] as? String,
              let fingerprint = payload["claim_fingerprint"] as? String else { return nil }
        payload["emotion_line"] = text
        payload["source"] = "expression_planner"
        payload["presentation_target"] = "feedback_card"
        payload["exposure_event_id"] = "local:\(fingerprint)"
        payload["local_exposure"] = true
        return NativeAIFeedback(payload: payload.mapValues(AnyCodable.init))
    }
}
