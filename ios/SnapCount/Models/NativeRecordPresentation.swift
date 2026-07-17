import Foundation

struct NativeRecordDetailSection: Identifiable {
    let title: String
    let rows: [NativeDetailRow]

    var id: String { title }
}

struct NativeFoodDish: Identifiable {
    let name: String
    let calories: Double?
    let estimatedGrams: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?

    var id: String { name }
}

enum NativeRecordAccountBindingStatus: Equatable {
    case bound
    case recommended
    case unbound
}

struct NativeRecordAccountBindingPresentation {
    let status: NativeRecordAccountBindingStatus
    let title: String
    let reason: String
    let recommendedAccount: NativeAccount?
}

enum NativeRecordDetailPresentationAdapter {
    static func basicRows(for detail: NativeRecordDetail, accountName: String?) -> [NativeDetailRow] {
        var rows = [
            NativeDetailRow(label: "数据域", value: domainLabel(for: detail)),
            NativeDetailRow(label: "记录时间", value: detail.createdAt ?? detail.subtitle),
            NativeDetailRow(label: "发生时间", value: eventTime(for: detail)),
            NativeDetailRow(label: "来源", value: sourceLabel(for: detail))
        ]
        if detail.kind == "expense" {
            rows.append(NativeDetailRow(label: "状态", value: detail.status == "pending" ? "待补充" : "已完成"))
        }
        if detail.kind == "expense" || detail.kind == "income" {
            rows.append(NativeDetailRow(label: detail.kind == "income" ? "到账账户" : "出资账户", value: accountName ?? "未绑定"))
        }
        return rows.filter { !$0.value.isEmpty }
    }

    static func extractedRows(
        for detail: NativeRecordDetail,
        domain: NativeDomainDefinition? = nil
    ) -> [NativeDetailRow] {
        if detail.kind == "income" {
            return [
                NativeDetailRow(label: "金额", value: detail.amount.map { String(format: "+¥%.2f", $0) } ?? "--"),
                NativeDetailRow(label: "收入类型", value: incomeCategoryLabel(detail.category)),
                NativeDetailRow(label: "来源名称", value: detail.merchantName ?? "未填写"),
                NativeDetailRow(label: "到账日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "备注", value: detail.note ?? "无")
            ]
        }

        if detail.kind == "data" {
            return universalRows(for: detail, domain: domain)
        }

        return [
            NativeDetailRow(label: "金额", value: detail.amount.map { String(format: "-¥%.2f", $0) } ?? "--"),
            NativeDetailRow(label: "商家", value: detail.merchantName ?? "未识别商家"),
            NativeDetailRow(label: "消费渠道", value: detail.platform ?? "未知"),
            NativeDetailRow(label: "消费分类", value: detail.category ?? "未知"),
            NativeDetailRow(label: "支付方式", value: detail.paymentMethod ?? "未知"),
            NativeDetailRow(label: "交易日期", value: detail.recordDate ?? "--"),
            NativeDetailRow(label: "备注", value: detail.note ?? "无")
        ]
    }

    static func foodDishes(for detail: NativeRecordDetail) -> [NativeFoodDish] {
        guard detail.kind == "data", detail.domainKey == "food",
              let dishes = detail.payload?.array("dishes") else { return [] }
        return dishes.compactMap { item in
            guard let values = item as? [String: Any] else { return nil }
            let payload = values.mapValues(AnyCodable.init)
            let name = payload.string("name") ?? payload.string("dish_name") ?? "未命名菜品"
            return NativeFoodDish(
                name: name,
                calories: payload.double("calorie_kcal")
                    ?? payload.double("calories")
                    ?? payload.double("calories_kcal"),
                estimatedGrams: payload.double("estimated_grams"),
                protein: payload.double("protein_g"),
                carbs: payload.double("carb_g"),
                fat: payload.double("fat_g")
            )
        }
    }

    static func accountBinding(
        for detail: NativeRecordDetail,
        accounts: [NativeAccount]
    ) -> NativeRecordAccountBindingPresentation? {
        guard detail.kind == "expense" || detail.kind == "income" else { return nil }

        if let accountId = detail.accountId {
            let account = accounts.first { $0.id == accountId }
            return NativeRecordAccountBindingPresentation(
                status: .bound,
                title: account.map { "已绑定到 \($0.title)" } ?? "已绑定账户",
                reason: detail.kind == "income" ? "这笔收入已计入到账账户流水" : "这笔支出已计入出资账户流水",
                recommendedAccount: nil
            )
        }

        let kind: NativeUnboundRecordKind = detail.kind == "income" ? .income : .expense
        let record = NativeUnboundRecord(
            id: detail.rawId,
            kind: kind,
            title: detail.title,
            amount: detail.amount ?? 0,
            date: detail.recordDate ?? "",
            time: detail.transactionTime,
            platform: detail.platform,
            category: detail.category,
            paymentMethod: detail.paymentMethod,
            note: detail.note,
            source: detail.source,
            imagePath: detail.imagePath,
            imageHash: detail.imageHash,
            companionMessage: detail.companionMessage
        )
        if let recommendation = NativeAccountRecommendationEngine.recommendation(for: record, accounts: accounts) {
            return NativeRecordAccountBindingPresentation(
                status: .recommended,
                title: "推荐绑定到 \(recommendation.account.title)",
                reason: recommendation.reason,
                recommendedAccount: recommendation.account
            )
        }

        return NativeRecordAccountBindingPresentation(
            status: .unbound,
            title: "尚未绑定账户",
            reason: "编辑记录并选择账户后，会自动生成对应账户流水",
            recommendedAccount: nil
        )
    }

    static func aiSummary(for detail: NativeRecordDetail) -> String {
        if let summary = detail.aiSummary, !summary.isEmpty { return summary }
        if detail.kind == "income" {
            return "系统记录了一笔\(incomeCategoryLabel(detail.category))，金额 \(String(format: "%.2f", detail.amount ?? 0)) 元，来源为 \(detail.merchantName ?? "未命名来源")。"
        }
        if detail.kind == "data" {
            if let summary = detail.note, !summary.isEmpty { return summary }
            return "\(domainLabel(for: detail))中记录了“\(detail.title)”。"
        }
        return "系统记录了一笔支出，商家为 \(detail.merchantName ?? "未识别商家")，金额 \(String(format: "%.2f", detail.amount ?? 0)) 元，渠道 \(detail.platform ?? "未知")，分类 \(detail.category ?? "未知")。"
    }

    static func domainLabel(for detail: NativeRecordDetail) -> String {
        switch detail.domainKey ?? detail.kind {
        case "expense": return "消费"
        case "income": return "收入"
        case "sport": return "运动"
        case "sleep": return "睡眠"
        case "reading": return "阅读"
        case "food": return "饮食"
        case "wallet": return "钱包"
        default: return detail.domainKey ?? "通用记录"
        }
    }

    private static func universalRows(
        for detail: NativeRecordDetail,
        domain: NativeDomainDefinition?
    ) -> [NativeDetailRow] {
        let payload = detail.payload ?? [:]
        switch detail.domainKey {
        case "food":
            let mealLabels = ["breakfast": "早餐", "lunch": "午餐", "dinner": "晚餐", "snack": "加餐"]
            return [
                NativeDetailRow(label: "标题", value: detail.title),
                NativeDetailRow(label: "餐次", value: mealLabels[payload.string("meal_type") ?? ""] ?? "未分类"),
                NativeDetailRow(
                    label: "总热量",
                    value: (payload.double("total_calorie_kcal") ?? payload.double("total_calories"))
                        .map { String(format: "%.0f 千卡（估算）", $0) } ?? "--"
                ),
                NativeDetailRow(label: "菜品数", value: "\(payload.array("dishes")?.count ?? 0) 道"),
                NativeDetailRow(label: "记录日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "估算依据", value: payload.string("confidence_note") ?? "无"),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        case "sleep":
            let minutes = durationMinutes(
                payload: payload,
                minuteKeys: ["sleep_minutes", "duration_minutes"],
                hourKeys: ["sleep_hours", "duration_hours"]
            )
            return [
                NativeDetailRow(label: "标题", value: detail.title),
                NativeDetailRow(label: "质量等级", value: payload.string("quality_level") ?? "未填写"),
                NativeDetailRow(label: "睡眠时长", value: durationLabel(minutes)),
                NativeDetailRow(label: "睡眠评分", value: payload.double("quality_score").map { String(Int($0.rounded())) } ?? "--"),
                NativeDetailRow(label: "入睡时间", value: payload.string("sleep_start_at") ?? "--"),
                NativeDetailRow(label: "醒来时间", value: payload.string("wake_at") ?? "--"),
                NativeDetailRow(label: "发生日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        case "sport":
            return [
                NativeDetailRow(label: "运动类型", value: payload.string("sport_type") ?? payload.string("activity_type") ?? detail.title),
                NativeDetailRow(label: "运动时长", value: durationLabel(payload.double("duration_minutes"))),
                NativeDetailRow(label: "距离", value: payload.double("distance_km").map { String(format: "%.2f km", $0) } ?? "--"),
                NativeDetailRow(label: "消耗热量", value: (payload.double("calories") ?? payload.double("calories_kcal")).map { String(format: "%.0f 千卡", $0) } ?? "--"),
                NativeDetailRow(label: "发生日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        case "reading":
            return [
                NativeDetailRow(label: "书名", value: payload.string("book_name") ?? detail.title),
                NativeDetailRow(label: "阅读时长", value: durationLabel(durationMinutes(
                    payload: payload,
                    minuteKeys: ["reading_minutes", "duration_minutes"],
                    hourKeys: ["reading_hours", "duration_hours"]
                ))),
                NativeDetailRow(label: "阅读页数", value: (payload.double("pages") ?? payload.double("pages_read")).map { "\(Int($0.rounded())) 页" } ?? "--"),
                NativeDetailRow(label: "发生日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        case "wallet":
            let amount = payload.double("amount")
                ?? payload.double("snapshot_balance")
                ?? payload.double("current_balance")
            return [
                NativeDetailRow(label: "标题", value: detail.title),
                NativeDetailRow(label: "账户/平台", value: payload.string("account_name") ?? payload.string("institution") ?? "未填写"),
                NativeDetailRow(label: "金额", value: amount.map { String(format: "¥%.2f", $0) } ?? "--"),
                NativeDetailRow(label: "记录类型", value: walletRecordKindLabel(payload.string("record_kind"))),
                NativeDetailRow(label: "还款日", value: payload.string("due_date") ?? "--"),
                NativeDetailRow(label: "关联账户", value: payload.string("linked_account_id") ?? "未绑定"),
                NativeDetailRow(label: "发生日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        default:
            let metadata = NativeManualDomainMetadata.resolve(domain, fallbackDomainKey: detail.domainKey ?? "")
            return [
                NativeDetailRow(label: "标题", value: detail.title),
                NativeDetailRow(label: metadata.dimensionLabel, value: payload.string(metadata.dimensionKey) ?? "未填写"),
                NativeDetailRow(label: metadata.primaryLabel, value: payload.double(metadata.primaryKey).map { String(format: "%.2f", $0) } ?? "--"),
                NativeDetailRow(label: "发生日期", value: detail.recordDate ?? "--"),
                NativeDetailRow(label: "模板版本", value: detail.domainVersion ?? "1.0"),
                NativeDetailRow(label: "来源类型", value: sourceLabel(for: detail)),
                NativeDetailRow(label: "备注", value: payload.string("note") ?? detail.note ?? "无")
            ]
        }
    }

    private static func eventTime(for detail: NativeRecordDetail) -> String {
        if detail.kind == "expense", let time = detail.transactionTime, !time.isEmpty {
            return [detail.recordDate, time].compactMap { $0 }.joined(separator: " ")
        }
        return detail.occurredAt ?? detail.recordDate ?? ""
    }

    private static func sourceLabel(for detail: NativeRecordDetail) -> String {
        switch detail.source {
        case "ai_scan": return "截图识别"
        case "staging": return "中转站归档"
        case "manual", nil, "": return "手动录入"
        default: return detail.source ?? "手动录入"
        }
    }

    private static func incomeCategoryLabel(_ value: String?) -> String {
        switch value {
        case "salary": return "工资"
        case "bonus": return "奖金"
        case "freelance": return "副业"
        case "investment": return "投资"
        case "reimbursement": return "报销"
        default: return "其他收入"
        }
    }

    private static func durationLabel(_ minutes: Double?) -> String {
        guard let minutes, minutes > 0 else { return "--" }
        let rounded = Int(minutes.rounded())
        if rounded >= 60 { return "\(rounded / 60) 小时 \(rounded % 60) 分钟" }
        return "\(rounded) 分钟"
    }

    private static func durationMinutes(
        payload: [String: AnyCodable],
        minuteKeys: [String],
        hourKeys: [String]
    ) -> Double? {
        for key in minuteKeys {
            if let value = payload.double(key) { return value }
        }
        for key in hourKeys {
            if let value = payload.double(key) { return value * 60 }
        }
        return nil
    }

    private static func walletRecordKindLabel(_ value: String?) -> String {
        switch value {
        case "cash_snapshot": return "资产快照"
        case "liability_snapshot": return "负债快照"
        case "repayment": return "还款记录"
        default: return value ?? "未分类"
        }
    }
}
