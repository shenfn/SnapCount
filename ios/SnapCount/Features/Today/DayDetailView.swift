import SwiftUI

struct DayDetailView: View {
    @EnvironmentObject private var appState: AppState
    let route: NativeDayDetailRoute
    @State private var selectedKind: NativeDayRecordKind

    init(route: NativeDayDetailRoute) {
        self.route = route
        _selectedKind = State(initialValue: route.kind)
    }

    private var group: NativeDayRecordGroup? { appState.dashboard.dayRecordGroups.first { $0.dateKey == route.dateKey } }
    private var records: [NativeDayRecord] { group?.records(for: selectedKind) ?? [] }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    summary
                    if let group, group.availableKinds.count > 2 {
                        Picker("领域", selection: $selectedKind) {
                            ForEach(group.availableKinds) { Text($0.title).tag($0) }
                        }.pickerStyle(.segmented)
                    }
                    Text("当天明细").font(.title3.bold())
                    if records.isEmpty { ContentUnavailableView("这一天还没有记录", systemImage: "calendar", description: Text("有截图、手动记录或钱包快照后，会自动出现在这里。")) }
                    ForEach(records) { record in
                        recordLink(record)
                    }
                }.padding(16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func recordLink(_ record: NativeDayRecord) -> some View {
        if record.kind == .staging || record.reference.hasPrefix("staging-") {
            Button { appState.openDayRecord(record) } label: { row(record) }
                .buttonStyle(JieziPressableButtonStyle())
        } else {
            NavigationLink(value: NativeRecordRoute(reference: record.reference)) {
                row(record)
            }
            .buttonStyle(JieziPressableButtonStyle())
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(route.dateKey.suffix(5))).font(.system(size: 32, weight: .black, design: .rounded))
            Text("\(selectedKind.title) · \(records.count) 条记录").foregroundStyle(JieziTheme.muted)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(22).background(.white.opacity(0.9), in: RoundedRectangle(cornerRadius: 24))
    }

    private func row(_ record: NativeDayRecord) -> some View {
        HStack(spacing: 14) {
            Image(systemName: record.systemImage).frame(width: 38, height: 38).background(JieziTheme.brand.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 4) { Text(record.title).font(.headline); Text(record.subtitle).font(.caption).foregroundStyle(JieziTheme.muted); Text(record.timeLabel ?? "全天").font(.caption2).foregroundStyle(JieziTheme.muted) }
            Spacer(); Text(record.value).font(.headline.monospacedDigit())
        }.padding(16).background(.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
    }

    private var title: String { route.dateKey }
}
