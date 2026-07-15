import SwiftUI

struct DomainsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""

    private var domains: [NativeDomainDefinition] {
        guard !searchText.isEmpty else { return appState.dashboard.domains }
        return appState.dashboard.domains.filter { $0.name.localizedCaseInsensitiveContains(searchText) || $0.description.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            List {
                if domains.isEmpty {
                    ContentUnavailableView("没有匹配的数据域", systemImage: "square.stack.3d.up.slash", description: Text("试试搜索收入、运动或其他关键字。"))
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(domains) { domain in
                        NavigationLink(value: domain.id) {
                            HStack(spacing: 14) {
                                Text(domain.icon.isEmpty ? "·" : domain.icon).font(.title2).frame(width: 42, height: 42).background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 4) { Text(domain.name).font(.headline); Text("本月 \(domain.recordCount) 条\(domain.isSystem ? " · 系统内置" : "")").font(.caption).foregroundStyle(.secondary); if !domain.description.isEmpty { Text(domain.description).font(.caption2).foregroundStyle(.secondary).lineLimit(2) } }
                            }.padding(.vertical, 4)
                        }
                    }
                }
            }.scrollContentBackground(.hidden).searchable(text: $searchText, prompt: "搜索数据域")
        }
        .navigationTitle("数据域")
        .navigationDestination(for: String.self) { key in if let domain = appState.dashboard.domains.first(where: { $0.id == key }) { DomainDetailView(domain: domain) } }
    }
}

private struct DomainDetailView: View {
    @EnvironmentObject private var appState: AppState
    let domain: NativeDomainDefinition
    @State private var snapshotForAccountPicker: NativeWalletSnapshot?
    private var presentation: NativeDomainPresentation { NativeDomainPresentationAdapter.presentation(for: domain, groups: appState.dashboard.dayRecordGroups) }
    private var activeAccounts: [NativeAccount] { appState.accounts.filter { !$0.isArchived } }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) { Text(domain.icon.isEmpty ? domain.shortName : domain.icon).font(.system(size: 42)); Text(domain.name).font(.largeTitle.bold()); Text(domain.description).foregroundStyle(JieziTheme.muted); Text("DOMAIN WORKSPACE").font(.caption.bold()).foregroundStyle(JieziTheme.brand) }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
                    HStack { ForEach(presentation.metrics) { metric in VStack(alignment: .leading, spacing: 5) { Text(metric.label).font(.caption).foregroundStyle(JieziTheme.muted); Text(metric.value).font(.headline.monospacedDigit()) }.frame(maxWidth: .infinity, alignment: .leading) } }.padding(18).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 20))
                    if domain.id == "wallet" { walletSnapshotSection }
                    Text("最近记录").font(.title3.bold())
                    if presentation.recentRecords.isEmpty { ContentUnavailableView("这个数据域还没有记录", systemImage: domain.systemImage) } else { ForEach(presentation.recentRecords) { record in Button { appState.openDayRecord(record) } label: { HStack { Image(systemName: record.systemImage).frame(width: 34); VStack(alignment: .leading) { Text(record.title).font(.headline); Text(record.subtitle).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(record.value).font(.subheadline.monospacedDigit()) }.padding(15).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 16)) }.buttonStyle(.plain) } }
                }.padding(16)
            }
            .refreshable {
                await appState.refreshDashboard()
                if domain.id == "wallet" { await appState.loadWalletSnapshots() }
            }
        }
        .navigationTitle(domain.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $snapshotForAccountPicker) { snapshot in
            WalletSnapshotAccountPicker(snapshot: snapshot, accounts: activeAccounts)
        }
        .task(id: domain.id) {
            if domain.id == "wallet" { await appState.loadWalletSnapshots() }
        }
    }

    @ViewBuilder
    private var walletSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("未关联快照").font(.title3.bold())
                Spacer()
                if appState.isLoadingWalletSnapshots { ProgressView() }
            }

            if let message = appState.walletSnapshotMessage {
                Text(message).font(.footnote).foregroundStyle(JieziTheme.brand)
            }

            if appState.walletSnapshots.isEmpty, !appState.isLoadingWalletSnapshots {
                Text("没有待关联的钱包快照")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ForEach(appState.walletSnapshots.prefix(5)) { snapshot in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(snapshot.accountName).font(.headline)
                                Text(snapshot.kind == .liability ? "负债快照" : "资产快照")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "¥%.2f", snapshot.balance))
                                .font(.headline.monospacedDigit())
                        }
                        HStack(spacing: 10) {
                            Button {
                                Task { _ = await appState.createAccountFromWalletSnapshot(snapshot) }
                            } label: {
                                Label("创建账户", systemImage: "plus.circle")
                            }
                            .buttonStyle(.borderedProminent)

                            Button {
                                snapshotForAccountPicker = snapshot
                            } label: {
                                Label("关联已有", systemImage: "link")
                            }
                            .buttonStyle(.bordered)
                            .disabled(activeAccounts.isEmpty)
                        }
                        .disabled(appState.walletSnapshotActionId != nil)
                    }
                    .padding(15)
                    .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}

private struct WalletSnapshotAccountPicker: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let snapshot: NativeWalletSnapshot
    let accounts: [NativeAccount]

    var body: some View {
        NavigationStack {
            List(accounts) { account in
                Button {
                    Task {
                        if await appState.linkWalletSnapshot(snapshot, to: account) {
                            dismiss()
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.title).font(.headline)
                            Text(account.type.title + (account.institution.isEmpty ? "" : " · \(account.institution)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "¥%.2f", account.currentBalance))
                            .font(.subheadline.monospacedDigit())
                    }
                }
                .disabled(appState.walletSnapshotActionId != nil)
            }
            .navigationTitle("关联已有账户")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                        .disabled(appState.walletSnapshotActionId != nil)
                }
            }
            .overlay {
                if appState.walletSnapshotActionId == snapshot.id {
                    ProgressView("正在关联…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
}
