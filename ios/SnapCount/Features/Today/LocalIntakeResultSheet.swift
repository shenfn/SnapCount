import SwiftUI

enum LocalIntakeResultPresentation {
    static func primaryMessage(
        notificationText: String,
        feedback: NativeAIFeedback?
    ) -> String? {
        guard let feedback else { return nil }
        let emotion = feedback.emotionLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !emotion.isEmpty else { return nil }
        return notificationText
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { $0 == emotion })
    }
}

/// 本机截图识别结果浮层：标题行 + 通知文案 + AI 反馈卡 + 操作按钮。
/// 由 TodayView 以 `.sheet` + `.presentationDetents([.medium])` 呈现，故内容整体可滚动。
struct LocalIntakeResultSheet: View {
    let notificationText: String
    let feedback: NativeAIFeedback?
    let isError: Bool
    let onViewRecord: () -> Void
    let onDismiss: () -> Void

    private var palette: JieziGeneratedPalette { JieziThemeManager.shared.palette }

    /// 按换行拆分逐行渲染，避免单个 Text 内换行的行距无法控制；空行丢弃以免出现双倍空隙。
    private var messageLines: [String] {
        return notificationText
            .components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    private var primaryMessage: String? {
        LocalIntakeResultPresentation.primaryMessage(
            notificationText: notificationText,
            feedback: feedback
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JieziSpacing.lg) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: JieziSpacing.md) {
                    if !messageLines.isEmpty {
                        messageBlock
                    }
                    if let feedback {
                        NativeAIFeedbackCard(
                            feedback: feedback,
                            compact: true,
                            primaryMessage: primaryMessage
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            actions
        }
        .padding(.horizontal, JieziSpacing.Semantic.page_padding)
        .padding(.top, JieziSpacing.xl)
        .padding(.bottom, JieziSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(JieziTheme.pageBackground.ignoresSafeArea())
    }

    private var header: some View {
        HStack(spacing: JieziSpacing.md) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: JieziIcon.sm, weight: .semibold))
                .foregroundStyle(accentColor)
                .frame(width: JieziIcon.xl2, height: JieziIcon.xl2)
                .background(
                    accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: JieziRadius.sm, style: .continuous)
                )
            Text(isError ? "上传失败" : "上传完成")
                .font(JieziType.sectionTitle)
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
        }
    }

    private var messageBlock: some View {
        JieziCard {
            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                ForEach(Array(messageLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(JieziFont.subheadline)
                        .foregroundStyle(palette.ink)
                        .lineSpacing(JieziSpacing.xxs)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        VStack(spacing: JieziSpacing.md) {
            if !isError {
                Button(action: onViewRecord) {
                    Text("查看记录")
                        .font(JieziType.button)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.brand)
                .controlSize(.large)
            }

            Button(action: onDismiss) {
                Text("知道了")
                    .font(JieziType.button)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(palette.brand)
            .controlSize(.large)
        }
    }

    /// 失败态用语义告警色，成功态用品牌色，避免硬编码色值。
    private var accentColor: Color {
        isError ? palette.coral : palette.brand
    }
}
