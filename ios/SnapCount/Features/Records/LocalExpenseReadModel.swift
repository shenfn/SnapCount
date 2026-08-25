import Foundation

enum LocalExpenseReadModel {
    static func detail(from expense: LocalExpense) -> NativeRecordDetail {
        let reference = "local-expense/\(expense.id.uuidString)"
        let timeLabel = expense.transactionTime.map { " \($0)" } ?? ""
        let dateLabel = "\(expense.transactionDate)\(timeLabel)"
        let amount = Double(expense.amountMinor) / 100
        var rows = [
            NativeDetailRow(label: "商户", value: expense.merchantName),
            NativeDetailRow(label: "分类", value: expense.category),
            NativeDetailRow(label: "支付方式", value: expense.paymentMethod),
            NativeDetailRow(label: "日期", value: dateLabel)
        ]
        if !expense.platform.isEmpty {
            rows.insert(NativeDetailRow(label: "平台", value: expense.platform), at: 2)
        }
        if let note = expense.note, !note.isEmpty {
            rows.append(NativeDetailRow(label: "备注", value: note))
        }
        return NativeRecordDetail(
            id: reference,
            rawId: expense.id.uuidString,
            kind: "expense",
            title: expense.merchantName,
            subtitle: dateLabel,
            value: String(format: "¥%.2f", amount),
            detailRows: rows,
            imageURL: nil,
            imageLoadError: false,
            imagePath: nil,
            imageHash: nil,
            amount: amount,
            merchantName: expense.merchantName,
            platform: expense.platform,
            category: expense.category,
            paymentMethod: expense.paymentMethod,
            recordDate: expense.transactionDate,
            note: expense.note,
            companionMessage: nil,
            accountId: expense.accountID.uuidString,
            systemImage: "creditcard",
            payload: nil,
            occurredAt: NativeLocalDate.financeOccurredAt(
                dateKey: expense.transactionDate,
                timeKey: expense.transactionTime
            ),
            transactionTime: expense.transactionTime,
            domainKey: nil,
            source: "local",
            status: "local"
        )
    }

    static func groups(from month: LocalExpenseMonth) -> [NativeDayRecordGroup] {
        let grouped = Dictionary(grouping: month.expenses, by: \.transactionDate)
        return grouped.map { dateKey, expenses in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: expenses.map { expense in
                    NativeDayRecord(
                        id: expense.id.uuidString,
                        reference: "local-expense/\(expense.id.uuidString)",
                        dateKey: expense.transactionDate,
                        kind: .expense,
                        domainKey: nil,
                        title: expense.merchantName,
                        subtitle: expense.category,
                        value: String(format: "¥%.2f", Double(expense.amountMinor) / 100),
                        timeLabel: expense.transactionTime,
                        systemImage: "creditcard",
                        transactionType: "expense",
                        status: "local"
                    )
                }.sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }
            )
        }.sorted { $0.dateKey > $1.dateKey }
    }
}
