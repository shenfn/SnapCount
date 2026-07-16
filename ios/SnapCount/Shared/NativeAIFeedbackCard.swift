import SwiftUI

struct NativeAIFeedbackCard: View {
    let feedback: NativeAIFeedback
    var compact = false
    var reviewable = false
    var reviewState: NativeAIFeedbackReviewState = .idle
    var onSubmit: ((NativeAIFeedbackReviewChoice, String) -> Void)?

    @State private var showReason = false
    @State private var selectedChoice: NativeAIFeedbackReviewChoice?
    @State private var reviewText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            HStack(spacing: 12) {
                feedbackIcon
                    .frame(width: compact ? 32 : 38, height: compact ? 32 : 38)
                    .background(JieziTheme.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI 即时反馈")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(feedback.badge)
                        .font(compact ? .subheadline.weight(.bold) : .headline)
                }
                Spacer()
                Text(feedback.bandLabel)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(bandColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(bandColor.opacity(0.1), in: Capsule())
            }

            if !feedback.emotionLine.isEmpty {
                Text(feedback.emotionLine)
                    .font(compact ? .subheadline.weight(.semibold) : .body.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !feedback.utilityLine.isEmpty {
                Text(feedback.utilityLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 8))
            }

            if !feedback.detailReason.isEmpty {
                if compact {
                    Button(showReason ? "收起依据" : "为什么这么说") {
                        showReason.toggle()
                    }
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(JieziTheme.brand)
                }
                if !compact || showReason {
                    Text("判断依据  \(feedback.detailReason)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !feedback.timingLabel.isEmpty {
                Label(feedback.timingLabel, systemImage: "clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
            }

            if reviewable {
                Divider()
                reviewContent
            }
        }
        .padding(compact ? 14 : 16)
        .background(bandBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(bandColor.opacity(0.18), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var feedbackIcon: some View {
        if feedback.icon.allSatisfy({ $0.isLetter || $0 == "." }) {
            Image(systemName: feedback.icon)
                .foregroundStyle(JieziTheme.brand)
        } else {
            Text(feedback.icon)
        }
    }

    @ViewBuilder
    private var reviewContent: some View {
        switch reviewState {
        case .submitting:
            Label("已收到，正在后台更新偏好…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        case .submitted:
            Label("已记录，会用于后续表达调整", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        case .idle, .failed:
            VStack(alignment: .leading, spacing: 10) {
                Text("点评这条反馈")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Picker("反馈原因", selection: $selectedChoice) {
                    Text("请选择").tag(NativeAIFeedbackReviewChoice?.none)
                    ForEach(NativeAIFeedbackReviewChoice.allCases) { choice in
                        Text(choice.title).tag(Optional(choice))
                    }
                }
                .pickerStyle(.menu)

                if selectedChoice != nil {
                    TextField("可以补充原因（选填）", text: $reviewText, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        guard let selectedChoice else { return }
                        onSubmit?(selectedChoice, reviewText.trimmingCharacters(in: .whitespacesAndNewlines))
                    } label: {
                        Label("提交点评", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(JieziTheme.brand)
                }

                if case .failed(let message) = reviewState {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
    }

    private var bandColor: Color {
        switch feedback.band {
        case "positive": return Color(red: 0.09, green: 0.45, blue: 0.24)
        case "watch", "recover": return Color(red: 0.71, green: 0.33, blue: 0.04)
        case "ritual": return Color(red: 0.15, green: 0.39, blue: 0.76)
        default: return JieziTheme.brand
        }
    }

    private var bandBackground: Color {
        bandColor.opacity(0.08)
    }
}
