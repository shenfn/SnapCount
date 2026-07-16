import Charts
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
                        NavigationLink(value: NativeDomainRoute(domainId: domain.id)) {
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
        .navigationDestination(for: NativeDomainRoute.self) { route in
            if let domain = appState.dashboard.domains.first(where: { $0.id == route.domainId }) {
                DomainDetailView(domain: domain)
            }
        }
        .navigationDestination(for: NativeRecordRoute.self) { route in
            RecordDetailView(reference: route.reference)
        }
    }
}

private struct DomainDetailView: View {
    @EnvironmentObject private var appState: AppState
    let domain: NativeDomainDefinition
    @State private var snapshotForAccountPicker: NativeWalletSnapshot?
    @State private var accountDraft: NativeAccountDraft?
    @State private var showWalletRecordSheet = false
    private var presentation: NativeDomainPresentation { NativeDomainPresentationAdapter.presentation(for: domain, dashboard: appState.dashboard) }
    private var activeAccounts: [NativeAccount] { appState.accounts.filter { !$0.isArchived } }
    private var assetAccounts: [NativeAccount] { activeAccounts.filter { !$0.type.isLiability } }
    private var liabilityAccounts: [NativeAccount] { activeAccounts.filter(\.type.isLiability) }
    private var unboundExpenses: [NativeUnboundRecord] { appState.unboundRecords.filter { $0.kind == .expense } }
    private var unboundIncomes: [NativeUnboundRecord] { appState.unboundRecords.filter { $0.kind == .income } }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    domainHero
                    if domain.id == "wallet" {
                        walletActionRow
                        walletAccountSection
                        walletUnboundSection
                    }
                    metricGrid
                    trendSection
                    distributionSection
                    recentRecordsSection
                    if domain.id == "wallet" { walletSnapshotSection }
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
        .sheet(item: $accountDraft) { draft in
            AccountEditSheet(draft: draft)
        }
        .sheet(isPresented: $showWalletRecordSheet) {
            ManualRecordSheet(kind: .universal, domainKey: "wallet")
        }
        .navigationDestination(for: NativeAccountRoute.self) { route in
            if activeAccounts.contains(where: { $0.id == route.accountId }) {
                AccountDetailView(accountId: route.accountId)
            }
        }
        .task(id: domain.id) {
            if domain.id == "wallet" {
                async let accounts: Void = appState.loadAccounts()
                async let snapshots: Void = appState.loadWalletSnapshots()
                async let unbound: Void = appState.loadUnboundRecords(monthKey: Self.currentMonthKey)
                _ = await (accounts, snapshots, unbound)
            }
        }
    }

    private var walletActionRow: some View {
        HStack(spacing: 10) {
            Button {
                accountDraft = NativeAccountDraft()
            } label: {
                Label("新建账户", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(JieziTheme.brand)

            Button {
                showWalletRecordSheet = true
            } label: {
                Label("添加快照", systemImage: "wallet.pass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(JieziTheme.brand)
        }
    }

    private var walletAccountSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("账户与钱包").font(.title3.bold())
            walletAccountGroup(title: "资产账户", accounts: assetAccounts, emptyText: "还没有资产账户")
            walletAccountGroup(title: "负债与待还", accounts: liabilityAccounts, emptyText: "还没有负债账户")
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private func walletAccountGroup(title: String, accounts: [NativeAccount], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if accounts.isEmpty {
                Text(emptyText).font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(accounts) { account in
                    NavigationLink(value: NativeAccountRoute(accountId: account.id)) {
                        HStack(spacing: 12) {
                            Image(systemName: account.type.systemImage)
                                .foregroundStyle(account.type.isLiability ? JieziTheme.coral : JieziTheme.brand)
                                .frame(width: 34, height: 34)
                                .background((account.type.isLiability ? JieziTheme.coral : JieziTheme.brand).opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 5) {
                                    Text(account.title).font(.subheadline.weight(.semibold))
                                    if account.isDefaultExpense { accountTag("默认支出", color: JieziTheme.coral) }
                                    if account.isDefaultIncome { accountTag("默认收入", color: JieziTheme.brand) }
                                }
                                Text([account.type.title, account.institution].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "¥%.2f", account.currentBalance))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(account.type.isLiability ? JieziTheme.coral : JieziTheme.ink)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func accountTag(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
    }

    @ViewBuilder
    private var walletUnboundSection: some View {
        let total = unboundExpenses.count + unboundIncomes.count
        if total > 0 {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("未绑定账户的记录（\(total)）").font(.headline)
                        Text("补绑后会自动生成账户流水").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    NavigationLink {
                        UnboundRecordsView()
                    } label: {
                        Text("去补全").font(.subheadline.weight(.semibold))
                    }
                }
                ForEach((unboundExpenses + unboundIncomes).prefix(6)) { record in
                    Button { appState.openUnboundRecord(record) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(JieziTheme.ink)
                                Text("\(record.date) · \(record.kind.title) · 点击补绑账户")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%@¥%.2f", record.kind == .expense ? "-" : "+", record.amount))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundStyle(record.kind == .expense ? JieziTheme.coral : JieziTheme.brand)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
            .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var domainHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(domain.icon.isEmpty ? domain.shortName : domain.icon)
                    .font(.system(size: 38))
                    .frame(width: 52, height: 52)
                    .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                Spacer()
                Text(domain.isSystem ? "系统内置" : "自定义")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(JieziTheme.brand)
            }
            Text(domain.name).font(.title.bold())
            if !domain.description.isEmpty {
                Text(domain.description).font(.subheadline).foregroundStyle(JieziTheme.muted)
            }
            HStack {
                Text("DOMAIN WORKSPACE")
                Spacer()
                Text("\(domain.recordCount) 条记录")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(JieziTheme.brand)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(presentation.metrics) { metric in
                VStack(alignment: .leading, spacing: 6) {
                    Text(metric.label).font(.caption).foregroundStyle(JieziTheme.muted)
                    Text(metric.value).font(.title3.weight(.bold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                .padding(14)
                .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("趋势").font(.headline)
                Spacer()
                Text(presentation.trendScope).font(.caption).foregroundStyle(.secondary)
            }
            if presentation.recentRecords.isEmpty {
                Text("有记录后会显示本周趋势")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(presentation.trend) { point in
                    LineMark(
                        x: .value("星期", point.label),
                        y: .value(presentation.trendIsCurrency ? "金额" : "记录", point.value)
                    )
                    .foregroundStyle(JieziTheme.brand)
                    .interpolationMethod(.catmullRom)
                    AreaMark(
                        x: .value("星期", point.label),
                        y: .value(presentation.trendIsCurrency ? "金额" : "记录", point.value)
                    )
                    .foregroundStyle(JieziTheme.brand.opacity(0.1))
                    .interpolationMethod(.catmullRom)
                    PointMark(
                        x: .value("星期", point.label),
                        y: .value(presentation.trendIsCurrency ? "金额" : "记录", point.value)
                    )
                    .foregroundStyle(JieziTheme.brand)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(JieziTheme.line)
                        AxisValueLabel {
                            if let number = value.as(Double.self) {
                                Text(presentation.trendIsCurrency ? "¥\(Int(number))" : "\(Int(number))")
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private var distributionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("维度分布").font(.headline)
                Spacer()
                if !presentation.distribution.isEmpty {
                    Text("Top \(presentation.distribution.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if presentation.distribution.isEmpty {
                Text("有记录后会生成分类、来源或状态分布")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                ForEach(presentation.distribution) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.name).font(.subheadline)
                            Spacer()
                            Text(item.displayValue).font(.caption.weight(.semibold).monospacedDigit())
                        }
                        ProgressView(value: item.fraction)
                            .tint(JieziTheme.brand)
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
    }

    private var recentRecordsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近记录").font(.headline)
            if presentation.recentRecords.isEmpty {
                ContentUnavailableView("\(domain.name)暂无记录", systemImage: domain.systemImage)
            } else {
                ForEach(presentation.recentRecords) { record in
                    NavigationLink(value: NativeRecordRoute(reference: record.reference)) {
                        HStack(spacing: 12) {
                            Image(systemName: record.systemImage)
                                .foregroundStyle(JieziTheme.brand)
                                .frame(width: 34, height: 34)
                                .background(JieziTheme.brand.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(JieziTheme.ink)
                                Text(record.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer()
                            if !record.value.isEmpty {
                                Text(record.value).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(JieziTheme.ink)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    Divider()
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
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

    private static let monthKeyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()

    private static var currentMonthKey: String {
        monthKeyFormatter.string(from: Date())
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
