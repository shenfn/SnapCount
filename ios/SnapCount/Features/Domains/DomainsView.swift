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
    }
}

private struct DomainDetailView: View {
    @EnvironmentObject private var appState: AppState
    let domain: NativeDomainDefinition
    @State private var snapshotForAccountPicker: NativeWalletSnapshot?
    private var presentation: NativeDomainPresentation { NativeDomainPresentationAdapter.presentation(for: domain, dashboard: appState.dashboard) }
    private var activeAccounts: [NativeAccount] { appState.accounts.filter { !$0.isArchived } }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    domainHero
                    if domain.id == "wallet" { walletSnapshotSection }
                    metricGrid
                    trendSection
                    distributionSection
                    recentRecordsSection
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
                    Button { appState.openDayRecord(record) } label: {
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
                    .buttonStyle(.plain)
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
