import SwiftUI

struct LocalExpenseEntryView: View {
    // The local expense surface intentionally has no cloud record-type switch.
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let accounts: [LocalAccount]
    let initialAccountID: UUID?

    @State private var selectedAccountID: UUID?
    @State private var amount = ""
    @State private var merchant = ""
    @State private var platform = "线下消费"
    @State private var category = "other"
    @State private var paymentMethod = "现金"
    @State private var date = Date()
    @State private var note = ""
    @State private var isSaving = false

    init(accounts: [LocalAccount], initialAccountID: UUID? = nil) {
        self.accounts = accounts
        self.initialAccountID = initialAccountID
        _selectedAccountID = State(initialValue: initialAccountID)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("本地支出") {
                    Text("保存成功后会显示“已保存在本机”。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("账户", selection: $selectedAccountID) {
                        Text("请选择账户").tag(UUID?.none)
                        ForEach(accounts) { account in
                            Text(account.name).tag(Optional(account.id))
                        }
                    }
                    TextField("金额（元）", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("商家名称", text: $merchant)
                    TextField("消费渠道", text: $platform)
                    TextField("分类", text: $category)
                    TextField("支付方式", text: $paymentMethod)
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    TextField("备注（可选）", text: $note, axis: .vertical)
                }

                if let message = appState.manualRecordMessage {
                    Section { Text(message).foregroundStyle(.secondary) }
                }
            }
            .navigationTitle("新增本地支出")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { Task { await save() } }
                        .disabled(isSaving || selectedAccountID == nil || amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() async {
        guard !isSaving, let selectedAccountID else { return }
        isSaving = true
        defer { isSaving = false }
        let success = await appState.createLocalExpense(
            amountText: amount,
            accountID: selectedAccountID,
            merchantName: merchant,
            platform: platform,
            category: category,
            paymentMethod: paymentMethod,
            date: date,
            note: note
        )
        if success { dismiss() }
    }
}
