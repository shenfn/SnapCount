import Foundation

struct NativeAIFeedback: Equatable {
    let exposureEventId: String?
    let candidateId: String?
    let semanticKey: String
    let claimFingerprint: String
    let presentationTarget: String
    let hasExplicitPresentationTarget: Bool
    let renderedTextFingerprint: String
    let dimension: String
    let source: String
    let icon: String
    let badge: String
    let band: String
    let emotionLine: String
    let utilityLine: String
    let detailReason: String
    let timingLabel: String
    let expressionCoverageSemanticKeys: [String]
    let expressionCoverageClaimFingerprint: String?

    init?(payload: [String: AnyCodable]?) {
        guard let payload else { return nil }
        let emotionLine = payload.string("emotion_line") ?? ""
        let utilityLine = payload.string("utility_line") ?? ""
        let detailReason = payload.string("detail_reason") ?? ""
        guard !emotionLine.isEmpty || !utilityLine.isEmpty || !detailReason.isEmpty else { return nil }

        let rawExposureEventId = payload.string("exposure_event_id")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.exposureEventId = rawExposureEventId?.isEmpty == false ? rawExposureEventId : nil
        let rawCandidateId = payload.string("candidate_id")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.candidateId = rawCandidateId?.isEmpty == false ? rawCandidateId : nil
        self.semanticKey = payload.string("semantic_key") ?? ""
        self.claimFingerprint = payload.string("claim_fingerprint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let rawPresentationTarget = payload.string("presentation_target")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self.hasExplicitPresentationTarget = !rawPresentationTarget.isEmpty
        self.presentationTarget = rawPresentationTarget.isEmpty
            ? "feedback_card"
            : rawPresentationTarget
        self.renderedTextFingerprint = payload.string("rendered_text_fingerprint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        self.dimension = payload.string("dimension") ?? ""
        self.source = payload.string("source") ?? ""
        self.icon = payload.string("icon") ?? "sparkles"
        self.badge = payload.string("badge") ?? "即时反馈"
        self.band = payload.string("band") ?? "neutral"
        self.emotionLine = emotionLine
        self.utilityLine = utilityLine
        self.detailReason = detailReason
        self.timingLabel = payload.dictionary("timing_signal")?.string("label") ?? ""
        let coverage = payload.dictionary("expression_coverage")
        let rawCoverageClaimFingerprint = coverage?.string("claim_fingerprint")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let coverageIsCurrent = coverage?.string("coverage_version") == "expression-coverage-v1"
            && coverage?.string("planner_version") == "expression-shadow-auto-v0.6"
            && coverage?.string("source_surface") == "record_detail"
            && coverage?.string("packet_fingerprint")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty == false
            && rawCoverageClaimFingerprint?.isEmpty == false
        let rawCoverageKeys = coverageIsCurrent
            ? coverage?.array("expressed_semantic_keys") ?? []
            : []
        var coverageKeys = rawCoverageKeys.compactMap { $0 as? String }
        if coverageIsCurrent, let singleKey = coverage?.string("expressed_semantic_key") {
            coverageKeys.append(singleKey)
        }
        coverageKeys = coverageKeys.compactMap { value -> String? in
            let normalized = Self.normalizedSemanticKey(value)
            return normalized.isEmpty ? nil : normalized
        }
        self.expressionCoverageSemanticKeys = Array(Set(coverageKeys)).sorted()
        self.expressionCoverageClaimFingerprint = coverageIsCurrent
            ? rawCoverageClaimFingerprint
            : nil
    }

    var bandLabel: String {
        switch band {
        case "positive": return "正向"
        case "watch": return "留意"
        case "recover": return "兜底"
        case "ritual": return "时机"
        default: return "观察"
        }
    }

    var isReviewable: Bool {
        source != "expression_planner" || isAcknowledgedPlannerFeedback
    }

    var requiresExposureAcknowledgement: Bool {
        source == "expression_planner" && exposureEventId == nil
    }

    var isAcknowledgedPlannerFeedback: Bool {
        source == "expression_planner" && exposureEventId != nil
    }

    var renderIdentity: String {
        [
            source,
            candidateId ?? "legacy",
            presentationTarget,
            renderedTextFingerprint,
            exposureEventId ?? "preview",
            emotionLine
        ]
            .joined(separator: ":")
    }

    var visibleContentIdentity: String {
        [badge, band, emotionLine, utilityLine, detailReason, timingLabel]
            .joined(separator: "\u{1F}")
    }

    /// A surface may already show the companion message for the current
    /// record. These Planner fallbacks only restate that same fact and should
    /// not occupy a second feedback card; richer candidates still render.
    var isCurrentRecordContextFeedback: Bool {
        let key = Self.normalizedSemanticKey(semanticKey)
        let candidate = (candidateId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return key.hasSuffix("_current_record_context")
            || key.hasSuffix("_current_metric")
            || dimension.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "current_fact"
            || candidate.contains("current-metric")
    }

    var isCompanionMessageDelivery: Bool {
        presentationTarget == "companion_message"
    }

    func matchesVisibleCompanionMessage(_ message: String?) -> Bool {
        guard isCompanionMessageDelivery,
              !claimFingerprint.isEmpty,
              !renderedTextFingerprint.isEmpty else { return false }
        let visibleMessage = message?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !visibleMessage.isEmpty
            && visibleMessage == emotionLine.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func hasSameDeliveryIdentity(as other: NativeAIFeedback) -> Bool {
        guard source == "expression_planner",
              other.source == "expression_planner",
              let candidateId,
              !candidateId.isEmpty,
              other.candidateId == candidateId,
              presentationTarget == other.presentationTarget else { return false }
        if !claimFingerprint.isEmpty, claimFingerprint != other.claimFingerprint {
            return false
        }
        if !renderedTextFingerprint.isEmpty,
           renderedTextFingerprint != other.renderedTextFingerprint {
            return false
        }
        if isCompanionMessageDelivery {
            return !renderedTextFingerprint.isEmpty
                && emotionLine == other.emotionLine
        }
        return true
    }

    fileprivate static func normalizedSemanticKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

}

enum NativeRecordExpressionFeedbackPolicy {
    static func hasAcknowledgedPlannerFeedback(_ feedback: [NativeAIFeedback?]) -> Bool {
        feedback.compactMap { $0 }.contains { $0.isAcknowledgedPlannerFeedback }
    }

    static func feedbackToDisplay(
        existing: NativeAIFeedback?,
        preview: NativeAIFeedback?,
        companionMessage: String? = nil
    ) -> NativeAIFeedback? {
        guard let preview else { return existing }
        if existing?.isAcknowledgedPlannerFeedback == true {
            return existing
        }
        if preview.hasExplicitPresentationTarget {
            if preview.isCompanionMessageDelivery {
                return preview.matchesVisibleCompanionMessage(companionMessage) ? preview : existing
            }
            return preview.presentationTarget == "feedback_card" ? preview : existing
        }
        let hasCompanion = companionMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if hasCompanion && preview.isCurrentRecordContextFeedback {
            return existing
        }
        guard let existing else { return preview }

        let normalizedPreviewKey = NativeAIFeedback.normalizedSemanticKey(preview.semanticKey)
        if let previewSemanticKey = normalizedPreviewKey.isEmpty ? nil : normalizedPreviewKey,
           !preview.claimFingerprint.isEmpty,
           existing.expressionCoverageClaimFingerprint == preview.claimFingerprint,
           existing.expressionCoverageSemanticKeys.contains(previewSemanticKey) {
            return existing
        }

        return preview
    }

    static func feedbackToRender(
        companionMessage: String?,
        feedback: NativeAIFeedback?,
        companionFeedback: NativeAIFeedback? = nil
    ) -> NativeAIFeedback? {
        guard let feedback else { return nil }
        if feedback.hasExplicitPresentationTarget {
            return feedback.presentationTarget == "feedback_card" ? feedback : nil
        }
        let hasCompanion = companionMessage?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false
        if hasCompanion && feedback.source != "expression_planner" {
            return nil
        }
        let normalizedSemanticKey = NativeAIFeedback.normalizedSemanticKey(feedback.semanticKey)
        if hasCompanion,
           !normalizedSemanticKey.isEmpty,
           !feedback.claimFingerprint.isEmpty,
           companionFeedback?.expressionCoverageClaimFingerprint == feedback.claimFingerprint,
           companionFeedback?.expressionCoverageSemanticKeys.contains(normalizedSemanticKey) == true {
            return nil
        }
        if hasCompanion && feedback.isCurrentRecordContextFeedback {
            return nil
        }
        return feedback
    }

    static func companionFeedbackToReview(
        companionMessage: String?,
        feedback: NativeAIFeedback?
    ) -> NativeAIFeedback? {
        guard let feedback,
              feedback.matchesVisibleCompanionMessage(companionMessage) else { return nil }
        return feedback
    }

    static func feedbackToPreserve(
        existing: [NativeAIFeedback?],
        pending: NativeAIFeedback?,
        companionMessage: String? = nil
    ) -> NativeAIFeedback? {
        let acknowledged = existing.compactMap { $0 }
            .first(where: { $0.isAcknowledgedPlannerFeedback })
        let current = acknowledged ?? existing.compactMap { $0 }.first
        return feedbackToDisplay(
            existing: current,
            preview: pending,
            companionMessage: companionMessage
        )
    }
}

enum NativeAIFeedbackReviewChoice: String, CaseIterable, Identifiable {
    case helpful
    case goodAngle = "good_angle"
    case justWhatIWanted = "just_what_i_wanted"
    case noChangeNeeded = "no_change_needed"
    case incorrect
    case notHelpful = "not_helpful"
    case repetitive
    case styleDislike = "style_dislike"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .helpful: return "有帮助"
        case .goodAngle: return "这个角度不错"
        case .justWhatIWanted: return "正是我想看的"
        case .noChangeNeeded: return "这次不用调整"
        case .incorrect: return "说得不对"
        case .notHelpful: return "没什么帮助"
        case .repetitive: return "有点重复"
        case .styleDislike: return "表达不喜欢"
        case .other: return "其他"
        }
    }
}

enum NativeAIFeedbackReviewState: Equatable {
    case idle
    case submitting
    case submitted
    case failed(String)
}

enum NativeRecordExpressionPlanExposureState: Equatable {
    case idle
    case acknowledging
    case failed
}
