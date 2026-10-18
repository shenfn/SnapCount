import SwiftUI

/// 下钻持有自己的日期/领域；返回保留首页选择与原生滚动位置。
struct NativeDomainDrillView: View {
    @EnvironmentObject private var appState: AppState
    @State private var domain: AppDomain
    @State private var dateKey: String

    init(route: NativeDomainDrillRoute) {
        _domain = State(initialValue: route.domain)
        _dateKey = State(initialValue: route.dateKey)
    }

    var body: some View {
        let scene = JieziScene.tokens(for: domain.rawValue)
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([AppDomain.expense, .sleep, .sport]) { item in
                        Button { domain = item } label: {
                            Text(item.title).font(JieziType.chip)
                                .padding(.horizontal, 14).frame(minHeight: 44)
                                .background(item == domain ? scene.accent.opacity(0.2) : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(item == domain ? .isSelected : [])
                    }
                }.padding(.horizontal, JieziPrototypeLayout.page_inset)
            }.scrollIndicators(.hidden)
            HStack {
                Button { moveDay(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    .accessibilityLabel("前一天")
                Spacer()
                Text(dateKey).font(JieziType.cardTitle.monospacedDigit())
                Spacer()
                Button { moveDay(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                    .accessibilityLabel("后一天")
            }.padding(.horizontal, JieziPrototypeLayout.page_inset)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(NativeLocalDate.weekDateKeys(containing: dateKey), id: \.self) { day in
                        Button { dateKey = day } label: {
                            VStack(spacing: 4) {
                                Text(NativeLocalDate.weekdayShortLabel(for: day) ?? "").font(JieziFont.caption2)
                                Text(String(day.suffix(2))).font(JieziType.moneyInline)
                            }
                            .frame(minWidth: 44, minHeight: 48)
                            .padding(.horizontal, 3)
                            .background(day == dateKey ? scene.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain).accessibilityLabel("查看\(day)")
                        .accessibilityAddTraits(day == dateKey ? .isSelected : [])
                    }
                }.padding(.horizontal, JieziPrototypeLayout.page_inset)
            }.scrollIndicators(.hidden)
            NativeDomainPageView(domain: domain, browsingDateKey: dateKey, isDrillDown: true, onSelectDate: { dateKey = $0 })
        }
        .foregroundStyle(scene.foreground)
        .background(scene.surface.ignoresSafeArea())
        .navigationTitle("\(domain.title)明细")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: dateKey) { await appState.loadRecordDateWindow(around: dateKey) }
        .task {
            if appState.isSignedIn { await appState.refreshDashboardIfStale() }
            else { await appState.refreshInboxProjection() }
        }
    }

    private func moveDay(_ offset: Int) {
        if let day = NativeLocalDate.shiftedDateKey(dateKey, byDays: offset) { dateKey = day }
    }
}
