import SwiftUI

enum NativeAIFeedbackCardVisibility {
    static let minimumVisibleRatio: CGFloat = 0.01

    static func visibleRatio(cardFrame: CGRect, viewportFrame: CGRect) -> CGFloat {
        guard !cardFrame.isNull,
              !cardFrame.isInfinite,
              !cardFrame.isEmpty,
              !viewportFrame.isNull,
              !viewportFrame.isInfinite,
              !viewportFrame.isEmpty else { return 0 }

        let intersection = cardFrame.intersection(viewportFrame)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        let cardArea = cardFrame.width * cardFrame.height
        guard cardArea > 0 else { return 0 }
        return (intersection.width * intersection.height) / cardArea
    }

    static func isVisible(
        cardFrame: CGRect,
        viewportFrame: CGRect,
        minimumVisibleRatio: CGFloat = NativeAIFeedbackCardVisibility.minimumVisibleRatio
    ) -> Bool {
        let threshold = min(max(minimumVisibleRatio, 0), 1)
        let ratio = visibleRatio(cardFrame: cardFrame, viewportFrame: viewportFrame)
        return ratio > 0 && ratio >= threshold
    }
}

enum NativeAIFeedbackReviewPresentation: Equatable {
    case form(isRevision: Bool)
    case submitting
    case submitted

    static func resolve(
        reviewState: NativeAIFeedbackReviewState,
        isRevisingSubmittedReview: Bool
    ) -> NativeAIFeedbackReviewPresentation {
        switch reviewState {
        case .submitting:
            return .submitting
        case .submitted:
            return isRevisingSubmittedReview ? .form(isRevision: true) : .submitted
        case .idle:
            return .form(isRevision: false)
        case .failed:
            return .form(isRevision: isRevisingSubmittedReview)
        }
    }

    static func shouldShowSection(
        reviewable: Bool,
        requiresExposureAcknowledgement: Bool
    ) -> Bool {
        reviewable || requiresExposureAcknowledgement
    }
}

private struct NativeAIFeedbackCardFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect { .null }

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct NativeAIFeedbackCardVisibilityModifier: ViewModifier {
    let viewportFrame: CGRect
    let minimumVisibleRatio: CGFloat
    let onVisibilityChange: (Bool) -> Void

    @State private var cardFrame = CGRect.null
    @State private var lastReportedVisibility = false

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NativeAIFeedbackCardFramePreferenceKey.self,
                        value: proxy.frame(in: .global)
                    )
                }
            }
            .onPreferenceChange(NativeAIFeedbackCardFramePreferenceKey.self) { frame in
                cardFrame = frame
                reportVisibility(cardFrame: frame, viewportFrame: viewportFrame)
            }
            .onChange(of: viewportFrame) { _, frame in
                reportVisibility(cardFrame: cardFrame, viewportFrame: frame)
            }
            .onDisappear {
                reportVisibility(false)
            }
    }

    private func reportVisibility(cardFrame: CGRect, viewportFrame: CGRect) {
        reportVisibility(
            NativeAIFeedbackCardVisibility.isVisible(
                cardFrame: cardFrame,
                viewportFrame: viewportFrame,
                minimumVisibleRatio: minimumVisibleRatio
            )
        )
    }

    private func reportVisibility(_ isVisible: Bool) {
        guard isVisible != lastReportedVisibility else { return }
        lastReportedVisibility = isVisible
        onVisibilityChange(isVisible)
    }
}

extension View {
    func onNativeAIFeedbackCardVisibilityChange(
        in viewportFrame: CGRect,
        minimumVisibleRatio: CGFloat = NativeAIFeedbackCardVisibility.minimumVisibleRatio,
        perform action: @escaping (Bool) -> Void
    ) -> some View {
        modifier(
            NativeAIFeedbackCardVisibilityModifier(
                viewportFrame: viewportFrame,
                minimumVisibleRatio: minimumVisibleRatio,
                onVisibilityChange: action
            )
        )
    }
}

struct NativeAIFeedbackCard: View {
    let feedback: NativeAIFeedback
    var compact = false
    var reviewable = false
    var reviewState: NativeAIFeedbackReviewState = .idle
    var exposureState: NativeRecordExpressionPlanExposureState = .idle
    var onRetryExposure: (() -> Void)?
    var onSubmit: ((NativeAIFeedbackReviewChoice, String) -> Void)?

    @State private var showReason = false
    @State private var selectedChoice: NativeAIFeedbackReviewChoice?
    @State private var reviewText = ""
    @State private var isRevisingSubmittedReview = false

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

            if NativeAIFeedbackReviewPresentation.shouldShowSection(
                reviewable: reviewable,
                requiresExposureAcknowledgement: feedback.requiresExposureAcknowledgement
            ) {
                Divider()
                if reviewable {
                    reviewContent
                } else {
                    pendingReviewContent
                }
            }
        }
        .padding(compact ? 14 : 16)
        .background(bandBackground, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(bandColor.opacity(0.18), lineWidth: 1)
        }
        .onChange(of: reviewState) { _, state in
            if case .submitted = state {
                isRevisingSubmittedReview = false
            }
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
        switch NativeAIFeedbackReviewPresentation.resolve(
            reviewState: reviewState,
            isRevisingSubmittedReview: isRevisingSubmittedReview
        ) {
        case .submitting:
            Label("已收到，正在后台更新偏好…", systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
        case .submitted:
            VStack(alignment: .leading, spacing: 10) {
                Label("已记录，会用于后续表达调整", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(JieziTheme.brand)
                Button {
                    isRevisingSubmittedReview = true
                } label: {
                    Label("修改点评", systemImage: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ai-feedback-edit-review")
            }
        case .form(let isRevision):
            reviewForm(isRevision: isRevision)
        }
    }

    private var pendingReviewContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("点评这条反馈")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            if exposureState == .failed {
                Button {
                    onRetryExposure?()
                } label: {
                    Label("重新开启点评", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ai-feedback-retry-exposure")
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在开启点评…")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(JieziTheme.brand)
                }
                .accessibilityIdentifier("ai-feedback-awaiting-exposure")
            }
        }
    }

    private func reviewForm(isRevision: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isRevision ? "修改这条点评" : "点评这条反馈")
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
                    Label(isRevision ? "保存修改" : "提交点评", systemImage: "paperplane.fill")
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
