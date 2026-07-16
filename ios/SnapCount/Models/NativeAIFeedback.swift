import Foundation

struct NativeAIFeedback: Equatable {
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
}

enum NativeAIFeedbackReviewChoice: String, CaseIterable, Identifiable {
    case incorrect
    case notHelpful = "not_helpful"
    case repetitive
    case styleDislike = "style_dislike"
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
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
