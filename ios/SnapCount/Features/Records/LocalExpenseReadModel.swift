import Foundation

enum LocalExpenseReadModel {
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
