import Foundation

struct NativeAIFeedback: Equatable {
    let exposureEventId: String?
    let candidateId: String?
    let source: String
    let icon: String
    let badge: String
    let band: String
    let emotionLine: String
    let utilityLine: String
    let detailReason: String
    let timingLabel: String

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
        self.source = payload.string("source") ?? ""
        self.icon = payload.string("icon") ?? "sparkles"
        self.badge = payload.string("badge") ?? "即时反馈"
        self.band = payload.string("band") ?? "neutral"
        self.emotionLine = emotionLine
        self.utilityLine = utilityLine
        self.detailReason = detailReason
        self.timingLabel = payload.dictionary("timing_signal")?.string("label") ?? ""
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
        [source, candidateId ?? "legacy", exposureEventId ?? "preview", emotionLine]
            .joined(separator: ":")
    }
}

enum NativeRecordExpressionFeedbackPolicy {
    static func hasAcknowledgedPlannerFeedback(_ feedback: [NativeAIFeedback?]) -> Bool {
        feedback.compactMap { $0 }.contains { $0.isAcknowledgedPlannerFeedback }
    }

    static func feedbackToPreserve(
        existing: [NativeAIFeedback?],
        pending: NativeAIFeedback?
    ) -> NativeAIFeedback? {
        if let acknowledged = existing.compactMap({ $0 }).first(where: { $0.isAcknowledgedPlannerFeedback }) {
            return acknowledged
        }
        return pending
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
