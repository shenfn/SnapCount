import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }
    var title: String { self == .privacy ? "隐私政策" : "服务协议" }
    var version: String { "2026-07-19" }

    var content: String {
        switch self {
        case .privacy:
            return """
            芥子隐私政策

            版本与生效日期：2026-07-19

            运营者：尹良超（个人开发者）
            联系邮箱：yinliangchao2222@163.com

            1. 处理的信息
            芥子处理邮箱、用户 ID 和登录会话，以及你主动提交的图片、OCR 文本、备注、消费、收入、账户、钱包、运动、睡眠、饮食和阅读记录。财务、睡眠等内容可能属于敏感或高度私密信息，芥子仅在你主动提交后处理。

            2. 使用目的
            信息用于身份验证、图片识别、记录归档、统计展示、账户与还款管理、AI 洞察、数据导出、故障排查、安全防护和删除请求。芥子不会出售你的个人信息，也不会用于与功能无关的广告画像。

            3. 服务商与数据位置
            Supabase 提供身份验证、数据库、Edge Functions 和 Storage，当前项目区域为新加坡（ap-southeast-1）。结构化记录及按设置保留的原图存储在该区域。

            阿里云百炼 Qwen 用于图片识别、文案和联动分析。芥子当前接入中国内地接口，仅使用 Qwen 3.6 Flash 和 Qwen 3.7 Plus。处理时会发送你主动选择的图片、必要提示词和完成当前功能所需的上下文。第三方的具体保留和处理规则以相应 API 服务条款和隐私政策为准。

            4. 跨区域处理
            主要数据存储在新加坡；使用 AI 功能时，相关图片和必要上下文会传输至阿里云百炼当前的中国内地接口。注册时会就敏感数据及该数据路径单独确认。

            5. 保存期限
            结构化记录通常保存至你删除记录或账户。原图可选择不保留、保留 7 天、保留 30 天或永久保留。不保留时会在识别完成后提交删除；到期图片会进入自动清理队列，失败任务会重试。

            AI 日志默认关闭。关闭设置会停止新增可选 AI 日志，但不会自动删除此前日志；已有日志可随相关数据或账户删除。

            6. 你的权利
            你可以查看、更正、导出和删除记录，调整原图与 AI 日志设置，并在设置中删除账户。若图片清理未完成，应用会提示失败或重试，不会将未完成状态显示为全部删除。

            7. 安全与未成年人
            芥子采用 HTTPS、Supabase 行级权限隔离、短时效签名图片地址和服务端密钥隔离。芥子不专门面向未满 18 周岁的未成年人，未成年人应在监护人同意后使用。

            8. 更新与联系
            重要数据处理变化会更新版本日期并提供必要提示。隐私请求请联系 yinliangchao2222@163.com。
            """
        case .terms:
            return """
            芥子服务协议

            版本与生效日期：2026-07-19
            运营者：尹良超（个人开发者）

            1. 服务内容
            芥子提供个人生活记录、图片识别、记录归档、数据统计、账户与还款辅助、数据导出和 AI 联动分析。具体功能可能随版本、地区、设备和服务可用性变化。

            2. 账户与使用资格
            你应提供可用邮箱并妥善保管登录凭据。芥子不专门面向未满 18 周岁的用户；未成年人应在监护人同意后使用。不得冒用身份、共享上传凭据或绕过访问控制。

            3. AI 限制
            AI 可能错误识别金额、日期、账户、睡眠等字段。你应在归档、确认还款或据此行动前核对结果。芥子不提供财务、投资、信贷、医疗、营养或其他专业建议。

            4. 用户内容
            你保留对合法内容的权利，并授权运营者和必要服务商仅为提供你主动使用的功能而传输、存储、识别、展示、导出和删除该内容。不得上传无权处理的他人隐私、违法内容或侵权内容。

            5. 可用性与终止
            网络、设备、Supabase、阿里云百炼或维护可能导致延迟、中断或部分功能不可用。你可以随时停止使用或删除账户；账户删除完成后通常无法恢复。

            6. 责任与争议
            在适用法律允许范围内，运营者不对因未核对 AI 结果、第三方服务中断或用户不当操作造成的间接损失承担责任。本协议适用中华人民共和国法律，但不影响你所在地区不可排除的强制性权利。争议应先通过邮箱协商，再依法向有管辖权的法院处理。

            7. 联系方式
            yinliangchao2222@163.com
            """
        }
    }
}

struct NativeRegistrationConsent: Equatable {
    let legalAcceptedAt: String
    let sensitiveDataAcceptedAt: String
    let termsVersion: String
    let privacyVersion: String

    static func current(at date: Date = Date()) -> NativeRegistrationConsent {
        let acceptedAt = ISO8601DateFormatter().string(from: date)
        return NativeRegistrationConsent(
            legalAcceptedAt: acceptedAt,
            sensitiveDataAcceptedAt: acceptedAt,
            termsVersion: LegalDocumentKind.terms.version,
            privacyVersion: LegalDocumentKind.privacy.version
        )
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
