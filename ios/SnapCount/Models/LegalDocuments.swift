import SwiftUI

enum LegalDocumentKind: String, Identifiable {
    case privacy
    case terms

    var id: String { rawValue }
    var title: String { self == .privacy ? "隐私政策" : "服务协议" }
    var version: String { self == .privacy ? "2026-11-16" : "2026-07-19" }

    var content: String {
        switch self {
        case .privacy:
            return """
            芥子隐私政策

            版本与生效日期：2026-11-16

            运营者：尹良超（个人开发者）
            联系邮箱：yinliangchao2222@163.com

            1. 处理的信息
            芥子处理邮箱、用户 ID 和登录会话，以及你主动提交的图片、OCR 文本、备注、消费、收入、账户、钱包、运动、睡眠、饮食和阅读记录。为避免重复记录，还会生成图片精确哈希和不可逆的感知指纹；它们仅在同一账户内比较，不能用于还原原图。财务、睡眠等内容可能属于敏感或高度私密信息，芥子仅在你主动提交后处理。

            2. 使用目的
            信息用于身份验证、图片识别、记录归档、统计展示、账户与还款管理、AI 洞察、数据导出、故障排查、安全防护和删除请求。芥子不会出售你的个人信息，也不会用于与功能无关的广告画像。

            3. 服务商与数据位置
            iOS 1.0 的本机流程将记录和关联原图保存在设备上。云同步和自带 API Key（BYOK）在此版本未开放。Supabase 在新加坡（ap-southeast-1）提供身份验证、快捷指令凭据和 Hosted AI 等服务。PWA 及既有云端记录和原图按云端规则处理。

            启用 Hosted AI 前，芥子会说明发送范围并要求确认。你提交识别的照片或截图经芥子在新加坡的服务发往阿里云百炼 Qwen（中国内地）。iOS 本机识别链路不会把原图归档到 Supabase Storage。

            4. 陪伴文案与跨区域处理
            使用 Hosted 陪伴时，芥子会发送当前记录、部分近期同类记录、表达偏好、时间和候选信息，用于生成文案。记录可能含金额、饮食、运动或睡眠信息。请求经新加坡发往阿里云百炼中国内地接口。服务商如何保留和使用收到的数据，取决于适用的 API 服务条款和隐私规则。

            “长期记忆”对新账户默认关闭。启用后，Hosted 陪伴还会附上同类记忆摘要和近期陪伴文案。摘要只用于当前请求，不写入云端业务记录、记忆表或同步队列。关闭长期记忆后不再读取或发送摘要和近期陪伴文案，当前记录和部分近期同类记录仍可用于 Hosted 陪伴。你可在设置关闭 Hosted AI，停止后续 Hosted 图片识别和陪伴请求。

            5. 保存期限
            本机原图按本机记录或收件箱的引用保留。云端原图可设置不保留、保留 7 天、保留 30 天或永久保留，仅适用于云端副本。到期云端图片会进入清理队列，失败任务会重试。

            AI 日志默认关闭。关闭设置会停止新增可选 AI 日志，但不会自动删除此前日志；已有日志可随相关数据或账户删除。

            “参与 AI 改进”默认关闭。只有你主动开启后，芥子才会保存用于评估表达选择的语义键、评分和拒绝原因，并按 30 天期限每日清理；这些后台改进数据不包含原图、金额、商户名或通知原文。关闭后会停止新增并清理未关联你主动点评的后台改进数据。你主动提交点评时，芥子会保存所点评的展示内容、选项和可选说明，以便处理该反馈；相关内容保留至账户删除或你提出删除请求。

            6. 你的权利
            你可以查看、更正、导出和删除记录，调整原图、AI 日志、Prompt 优化和 AI 改进参与设置，并在设置中删除云端账户及关联的云端数据。本机数据库、原图和已导出的备份仍保留。你可以单独删除本机记录，并自行管理导出的文件。若云端清理未完成，应用会提示失败或重试。

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
