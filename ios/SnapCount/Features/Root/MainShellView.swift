import SwiftUI

/// 五域骨架主场景（IOS-V2-SHELL-001~004）：
/// 域横滑为主体，顶部栏（logo / 同步 / 日历占位 /「…」菜单）与底部栏（待确认 / 圆点 / ＋）悬浮其上，
/// 菜单四项与待确认以全屏覆盖层呈现，关闭后回到原域页。
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @State private var showManualRecordSheet = false

    private var overlayItem: Binding<AppOverlay?> {
        Binding(
            get: { appState.presentedOverlay == .none ? nil : appState.presentedOverlay },
            set: { appState.presentedOverlay = $0 ?? .none }
        )
    }

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            domainPager
        }
        .overlay(alignment: .top) { shellTopBar }
        .overlay(alignment: .bottom) { shellBottomBar }
        .fullScreenCover(item: overlayItem) { overlay in
            overlayDestination(overlay)
        }
        .sheet(isPresented: $showManualRecordSheet) {
            UnifiedManualRecordEntry()
        }
    }

    // MARK: - 域横滑（SHELL-001）

    private var domainPager: some View {
        TabView(selection: $appState.selectedDomain) {
            ForEach(AppDomain.allCases) { domain in
                NativeDomainPageView(domain: domain)
                    .tag(domain)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    // MARK: - 顶部栏（SHELL-002）

    private var shellTopBar: some View {
        HStack(spacing: JieziSpacing.md) {
            Image(systemName: "seedling")
                .font(.headline)
                .foregroundStyle(themeManager.palette.brand)

            syncStatusIcon

            Spacer()

            Button {
                // ponytail: 日历热力图为后续阶段；占位期间禁用，避免“点了没反应”的假入口。
            } label: {
                Image(systemName: "calendar")
            }
            .disabled(true)
            .foregroundStyle(themeManager.palette.muted.opacity(0.5))

            Menu {
                Button { appState.presentedOverlay = .insights } label: {
                    Label("观察", systemImage: "chart.xyaxis.line")
                }
                Button { appState.presentedOverlay = .records } label: {
                    Label("记录", systemImage: "list.bullet.rectangle")
                }
                Button { appState.presentedOverlay = .wallet } label: {
                    Label("钱包", systemImage: "wallet.pass")
                }
                Button { appState.presentedOverlay = .settings } label: {
                    Label("设置", systemImage: "gearshape")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.headline)
                    .foregroundStyle(themeManager.palette.ink)
            }
        }
        .padding(.horizontal, JieziSpacing.lg)
        .padding(.vertical, JieziSpacing.sm)
        .background(themeManager.palette.paper.opacity(0.94))
    }

    private var syncStatusIcon: some View {
        Image(systemName: appState.isSignedIn ? "icloud" : "icloud.slash")
            .font(.subheadline)
            .foregroundStyle(themeManager.palette.muted)
            .accessibilityLabel(appState.isSignedIn ? "已登录" : "本地模式")
    }

    // MARK: - 底部栏（SHELL-003）

    private var shellBottomBar: some View {
        HStack {
            Button {
                appState.presentedOverlay = .inbox
            } label: {
                Image(systemName: "tray.full")
                    .font(.body)
                    .foregroundStyle(themeManager.palette.ink)
                    .overlay(alignment: .topTrailing) {
                        if appState.dashboard.pendingCount > 0 {
                            Text("\(appState.dashboard.pendingCount)")
                                .font(.system(size: 10, weight: .bold).monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red, in: Circle())
                                .offset(x: 9, y: -7)
                                .accessibilityLabel("\(appState.dashboard.pendingCount) 条待确认")
                        }
                    }
            }
            .accessibilityLabel("收件箱")

            Spacer()

            HStack(spacing: JieziSpacing.sm) {
                ForEach(AppDomain.allCases) { domain in
                    Circle()
                        .fill(domain == appState.selectedDomain
                              ? themeManager.palette.brand
                              : themeManager.palette.muted.opacity(0.35))
                        .frame(width: 7, height: 7)
                        .animation(.easeInOut(duration: 0.2), value: appState.selectedDomain)
                }
            }

            Spacer()

            Button {
                showManualRecordSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(themeManager.palette.brand, in: Circle())
            }
            .accessibilityLabel("记一笔")
        }
        .padding(.horizontal, JieziSpacing.lg)
        .padding(.vertical, JieziSpacing.sm)
        .background(themeManager.palette.paper.opacity(0.94))
    }

    // MARK: - 覆盖层（SHELL-004）
    // inbox/records 覆盖层沿用 AppState 的 NavigationPath 绑定，
    // 保证 openUnboundRecord / openDayRecord / 快捷指令路由的编程式推栈在覆盖层内继续生效。

    @ViewBuilder
    private func overlayDestination(_ overlay: AppOverlay) -> some View {
        switch overlay {
        case .none:
            EmptyView()
        case .inbox:
            NavigationStack(path: $appState.inboxPath) {
                overlayRoot { InboxView() }
            }
            .environmentObject(appState)
            .environmentObject(themeManager)
        case .records:
            NavigationStack(path: $appState.recordsPath) {
                overlayRoot { RecordsView() }
            }
            .environmentObject(appState)
            .environmentObject(themeManager)
        case .insights:
            NavigationStack {
                overlayRoot { InsightsView() }
            }
            .environmentObject(appState)
            .environmentObject(themeManager)
        case .wallet:
            NavigationStack {
                overlayRoot { AccountsView() }
            }
            .environmentObject(appState)
            .environmentObject(themeManager)
        case .settings:
            NavigationStack {
                overlayRoot { SettingsView() }
            }
            .environmentObject(appState)
            .environmentObject(themeManager)
        }
    }

    /// 覆盖层没有 Tab 栏兜底，左上角必须始终有关闭门禁（§15 导航门禁不可删）。
    private func overlayRoot(@ViewBuilder content: () -> some View) -> some View {
        content()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.presentedOverlay = .none
                    } label: {
                        Label("关闭", systemImage: "xmark")
                    }
                }
            }
    }
}
