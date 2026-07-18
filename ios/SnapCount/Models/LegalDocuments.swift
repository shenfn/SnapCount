import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }
    var title: String { self == .privacy ? "隐私政策" : "服务协议" }

    var content: String {
        switch self {
        case .privacy:
            return """
            芥子隐私政策

            更新日期：2026 年 7 月

            芥子用于保存个人记录、消费与收入数据，以及运动、睡眠、饮食、阅读和钱包等数据域信息。

            图片处理
            当你主动拍照、选择图片或通过快捷指令上传时，图片会发送到芥子服务进行识别，并可能由你选择的模型服务处理。图片是否长期保留由设置中的原图留存策略决定。关闭长期留存后，图片仅为完成识别临时存储，清理任务会删除云端原图及对应引用。

            数据使用
            识别结果用于生成你的记录、统计、账户流水和 AI 洞察。除提供服务、排查故障和你主动开启的 AI 日志外，芥子不会把个人数据用于与功能无关的用途。

            数据安全
            账户数据按用户身份隔离访问。签名图片地址只在短时间内有效。你可以在设置中导出数据、调整原图留存策略或删除账户。

            账户删除
            删除账户会删除云端记录、账户数据、识别日志、AI 洞察、原图和快捷指令上传凭据，完成后无法恢复。

            联系方式
            若你对隐私处理有疑问，请通过芥子产品支持渠道联系我们。
            """
        case .terms:
            return """
            芥子服务协议

            更新日期：2026 年 7 月

            使用芥子前，请确认你已阅读并同意本协议。芥子提供个人记录、图片识别、数据统计、账户管理和 AI 辅助分析功能。

            识别结果
            AI 识别仅作为记录整理辅助。金额、日期、账户、还款和其他重要信息可能存在错误，你应在归档或使用前检查并修正。芥子不会把 AI 结果视为财务、医疗或其他专业建议。

            用户责任
            你应保证上传内容合法，并对自己的账户、上传图片和记录内容负责。不得利用芥子处理他人隐私或实施违法行为。

            数据与账户
            你可以使用设置中的导出和删除账户功能管理自己的数据。删除账户后，相关云端数据和登录凭据将按删除流程处理，通常无法恢复。

            服务变更
            为修复问题、提升安全性或适配系统变化，芥子可能调整功能和服务方式。涉及重要数据处理变化时，会在应用内提供相应说明。

            联系方式
            若你对本协议有疑问，请通过芥子产品支持渠道联系我们。
            """
        }
    }
}

struct LegalDocumentView: View {
    let kind: LegalDocumentKind

    var body: some View {
        ScrollView {
            Text(kind.content)
                .font(.body)
                .foregroundStyle(JieziTheme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(20)
        }
        .background(JieziTheme.pageBackground.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
