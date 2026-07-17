import Charts
import SwiftUI

struct MonthlyReportContent: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedMonthKey = Self.currentMonthKey
    @State private var selectedDomainKey = "expense"

    private var snapshot: DashboardSnapshot { appState.reportSnapshot(monthKey: selectedMonthKey) }
    private var domains: [NativeDomainDefinition] { snapshot.domains }
    private var selectedDomain: NativeDomainDefinition? {
        domains.first { $0.id == selectedDomainKey } ?? domains.first
    }
    private var presentation: NativeDomainPresentation? {
        selectedDomain.map {
            NativeDomainPresentationAdapter.presentation(
                for: $0,
                dashboard: snapshot,
                now: referenceDate
            )
        }
    }
    private var isLoading: Bool { appState.loadingRecordMonthKey == selectedMonthKey }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            monthSelector
            domainSelector

            if isLoading && snapshot.dayRecordGroups.isEmpty {
                ProgressView("正在加载月度报告…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if let message = appState.recordMonthMessages[selectedMonthKey],
                      snapshot.dayRecordGroups.isEmpty {
                ContentUnavailableView {
                    Label("月度报告加载失败", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
                } description: {
                    Text(message)
                } actions: {
                    Button("重新加载") {
                        Task { await appState.loadRecordMonth(selectedMonthKey, force: true) }
                    }
                }
            } else if let presentation {
                reportSummary(presentation)
                metricGrid(presentation)
                trendSection(presentation)
                distributionSection(presentation)
                if selectedDomainKey == "expense" { financeBreakdown }
                recentRecordsSection(presentation)
            }
        }
        .task(id: selectedMonthKey) {
            await appState.loadRecordMonth(selectedMonthKey)
        }
        .onChange(of: domains.map(\.id)) { ids in
            if !ids.contains(selectedDomainKey) { selectedDomainKey = ids.first ?? "expense" }
        }
    }

    private var monthSelector: some View {
        HStack {
            Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
            Spacer()
            Text(monthTitle).font(.headline.monospacedDigit())
            Spacer()
            Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
                .disabled(selectedMonthKey >= Self.currentMonthKey)
        }
        .padding(.horizontal, 4)
    }

    private var domainSelector: some View {
        HStack {
            Text("数据域").font(.subheadline.weight(.semibold))
            Spacer()
            Picker("选择数据域", selection: $selectedDomainKey) {
                ForEach(domains) { domain in
                    Text(domain.shortName).tag(domain.id)
                }
            }
            .pickerStyle(.menu)
        }
        .padding(14)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    private func reportSummary(_ report: NativeDomainPresentation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(monthTitle) · \(report.definition.shortName)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(JieziTheme.brand)
            Text(report.metrics.first?.value ?? "0")
                .font(.largeTitle.bold().monospacedDigit())
            Text("共 \(report.definition.recordCount) 条记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(JieziTheme.brand.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }

    private func metricGrid(_ report: NativeDomainPresentation) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ForEach(report.metrics.dropFirst()) { metric in
                InsightMetric(label: metric.label, value: metric.value, tint: JieziTheme.ink)
            }
        }
    }

    private func trendSection(_ report: NativeDomainPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("趋势").font(.title3.bold())
                Spacer()
                Text(report.trendScope).font(.caption).foregroundStyle(.secondary)
            }
            Chart(report.trend) { point in
                BarMark(x: .value("日期", point.label), y: .value("数值", point.value))
                    .foregroundStyle(JieziTheme.brand)
            }
            .frame(height: 190)
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    private func distributionSection(_ report: NativeDomainPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("分类排行").font(.title3.bold())
            if report.distribution.isEmpty {
                Text("这个月还没有足够的数据形成排行。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(report.distribution) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text(item.name).font(.subheadline)
                            Spacer()
                            Text(item.displayValue).font(.caption.monospacedDigit())
                        }
                        ProgressView(value: item.fraction).tint(JieziTheme.brand)
                    }
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var financeBreakdown: some View {
        if !platformBreakdown.isEmpty || !paymentBreakdown.isEmpty {
            breakdownSection(title: "消费渠道", items: platformBreakdown)
            breakdownSection(title: "支付方式", items: paymentBreakdown)
        }
    }

    private func breakdownSection(title: String, items: [BreakdownItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.title3.bold())
            ForEach(items) { item in
                HStack {
                    Text(item.name).font(.subheadline)
                    Spacer()
                    Text(String(format: "¥%.0f", item.amount)).font(.caption.monospacedDigit())
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    private func recentRecordsSection(_ report: NativeDomainPresentation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("最近记录").font(.title3.bold())
            if report.recentRecords.isEmpty {
                Text("本月暂无记录").font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(report.recentRecords) { record in
                    NavigationLink {
                        RecordDetailView(reference: record.reference)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(record.title).font(.subheadline.weight(.semibold)).foregroundStyle(JieziTheme.ink)
                                Text(record.dateKey).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(record.value).font(.caption.monospacedDigit()).foregroundStyle(JieziTheme.ink)
                        }
                    }
                    Divider()
                }
            }
        }
        .padding(16)
        .background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 8))
    }

    private var platformBreakdown: [BreakdownItem] { breakdown(keyPath: \.platform) }
    private var paymentBreakdown: [BreakdownItem] { breakdown(keyPath: \.paymentMethod) }

    private func breakdown(keyPath: KeyPath<NativeRecordDetail, String?>) -> [BreakdownItem] {
        let grouped = Dictionary(grouping: snapshot.recordDetails.values.filter { $0.kind == "expense" }) {
            $0[keyPath: keyPath] ?? "其他"
        }
        return grouped.map { name, rows in
            BreakdownItem(name: name, amount: rows.reduce(0) { $0 + ($1.amount ?? 0) })
        }
        .sorted { $0.amount > $1.amount }
        .prefix(6)
        .map { $0 }
    }

    private var monthTitle: String {
        let parts = selectedMonthKey.split(separator: "-")
        guard parts.count == 2 else { return selectedMonthKey }
        return "\(parts[0])年\(Int(parts[1]) ?? 0)月"
    }

    private var referenceDate: Date {
        if selectedMonthKey == Self.currentMonthKey { return Date() }
        return Self.dayFormatter.date(from: "\(selectedMonthKey)-28") ?? Date()
    }

    private func shiftMonth(_ offset: Int) {
        guard let date = Self.monthFormatter.date(from: selectedMonthKey),
              let shifted = Calendar(identifier: .gregorian).date(byAdding: .month, value: offset, to: date) else { return }
        selectedMonthKey = Self.monthFormatter.string(from: shifted)
    }

    private struct BreakdownItem: Identifiable {
        let name: String
        let amount: Double
        var id: String { name }
    }

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        return formatter
    }()
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    private static var currentMonthKey: String { monthFormatter.string(from: Date()) }
}
