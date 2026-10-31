import Foundation

enum LocalIncomeReadModel {
    static func detail(from income: LocalIncome, imageStore: LocalImageStore? = nil) -> NativeRecordDetail {
        let reference = "local-income/\(income.id.uuidString)"
        // 本机已有的原图优先直接读文件：走远端签名等于每次看图都要联网，
        // 而迁移落库的 image_path 是本机路径，云端根本没有这个对象。
        let imageURL = localImageURL(income.imagePath, imageStore: imageStore)
        let amount = Double(income.amountMinor) / 100
        let sourceName = income.sourceName.isEmpty ? "收入记录" : income.sourceName
        let time = income.occurredAt.map { NativeLocalDate.timeKey($0) }
        let dateLabel = [income.incomeDate, time].compactMap { $0 }.joined(separator: " ")
        var rows = [
            NativeDetailRow(label: "来源", value: sourceName),
            NativeDetailRow(label: "分类", value: income.category),
            NativeDetailRow(label: "日期", value: dateLabel)
        ]
        if let note = income.note, !note.isEmpty {
            rows.append(NativeDetailRow(label: "备注", value: note))
        }
        return NativeRecordDetail(
            id: reference, rawId: income.id.uuidString, kind: "income",
            title: sourceName, subtitle: dateLabel,
            value: String(format: "+¥%.2f", amount), detailRows: rows,
            imageURL: imageURL, imageLoadError: income.imagePath != nil && imageURL == nil,
            imagePath: income.imagePath, imageHash: income.imageHash,
            amount: amount, merchantName: sourceName, platform: nil,
            category: income.category, paymentMethod: nil, recordDate: income.incomeDate,
            note: income.note, companionMessage: income.companionMessage, accountId: income.accountID?.uuidString,
            systemImage: "arrow.down.circle", payload: nil,
            occurredAt: income.occurredAt.map { ISO8601DateFormatter().string(from: $0) },
            transactionTime: time, domainKey: "income", source: "local", status: "local",
            localVersion: income.localVersion
        )
    }

    static func groups(from month: LocalIncomeMonth) -> [NativeDayRecordGroup] {
        Dictionary(grouping: month.incomes, by: \.incomeDate).map { dateKey, incomes in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: incomes.map { income in
                    NativeDayRecord(
                        id: income.id.uuidString,
                        reference: "local-income/\(income.id.uuidString)",
                        dateKey: income.incomeDate, kind: .income, domainKey: "income",
                        title: income.sourceName.isEmpty ? "收入记录" : income.sourceName, subtitle: income.category,
                        value: String(format: "+¥%.2f", Double(income.amountMinor) / 100),
                        timeLabel: income.occurredAt.map { NativeLocalDate.timeKey($0) },
                        systemImage: "arrow.down.circle", status: "local",
                        amount: Double(income.amountMinor) / 100
                    )
                }.sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }
            )
        }.sorted { $0.dateKey > $1.dateKey }
    }

    private static func localImageURL(_ path: String?, imageStore: LocalImageStore?) -> URL? {
        guard let path, let imageStore, imageStore.contains(path: path) else { return nil }
        return imageStore.url(for: path)
    }
}
