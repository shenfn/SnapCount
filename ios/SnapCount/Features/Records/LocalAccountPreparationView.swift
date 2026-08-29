import SwiftUI

struct LocalAccountPreparationView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let onCreated: (LocalAccount) -> Void

    @State private var name = ""
    @State private var kind = "cash"
    @State private var openingBalance = "0"
    @State private var isSaving = false

    private let kinds = [
        ("cash", "现金"),
        ("wallet_balance", "钱包余额"),
        ("debit_card", "储蓄卡")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("账户名称", text: $name)
                    Picker("账户类型", selection: $kind) {
                        ForEach(kinds, id: \.0) { value, title in
                            Text(title).tag(value)
                        }
                    }
                    TextField("期初余额（元）", text: $openingBalance)
                        .keyboardType(.decimalPad)
                } header: {
                    Text("先准备一个本地账户")
                } footer: {
                    Text("账户默认保存在此 iPhone；开启云端同步后，账户信息会同步到你的云端账号。")
                }

                if let message = appState.localAccountMessage {
                    Section {
                        Text(message).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("准备本地账户")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("继续") { Task { await create() } }
                        .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        let command = LocalAccountSetupCommand(
            id: UUID(),
            name: name,
            kind: kind,
            openingBalanceText: openingBalance,
            createdAt: Date()
        )
        if let account = await appState.createLocalAccount(command) {
            onCreated(account)
            dismiss()
        }
    }
}

struct LocalAccountsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showPreparation = false

    var body: some View {
        List {
            if appState.localAccounts.isEmpty {
                ContentUnavailableView(
                    "还没有本地账户",
                    systemImage: "wallet.pass",
                    description: Text("创建账户后，才能保存本地消费。")
                )
            } else {
                Section("本机账户") {
                    ForEach(appState.localAccounts) { account in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name).font(.headline)
                            Text("\(account.kind) · 当前 ¥\(String(format: "%.2f", Double(appState.localAccountBalances[account.id] ?? account.openingBalanceMinor) / 100))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("本地账户")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showPreparation = true } label: {
                    Label("新建账户", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showPreparation) {
            LocalAccountPreparationView { _ in }
        }
        .task { _ = await appState.prepareLocalWorkspace() }
    }
}
