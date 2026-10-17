import SwiftUI

/// 五域骨架主场景（IOS-V2-SHELL-001~004）：
/// 域横滑为主体，顶部栏（品牌 / 同步 / 日期选择 /「…」菜单）与底部栏（待确认 / 圆点 / ＋）悬浮其上，
/// 菜单四项与待确认以全屏覆盖层呈现，关闭后回到原域页。
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @State private var showManualRecordSheet = false

    private var scene: JieziSceneTokens { JieziScene.tokens(for: appState.selectedDomain.rawValue) }

    private var overlayItem: Binding<AppOverlay?> {
        Binding(
            get: { appState.presentedOverlay == .none ? nil : appState.presentedOverlay },
            set: { appState.presentedOverlay = $0 ?? .none }
        )
    }

    var body: some View {
        ZStack {
            DomainSceneView(domain: appState.selectedDomain)
            domainPager
        }
        .overlay(alignment: .top) { shellTopBar }
        .overlay(alignment: .bottom) { shellBottomBar }
        .task(id: appState.selectedDateKey) {
            await appState.loadRecordDateWindow(around: appState.selectedDateKey)
        }
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
        VStack(spacing: 8) {
            HStack(spacing: JieziSpacing.md) {
                Image(systemName: "circle.hexagongrid.fill")
                    .font(.headline)
                    .foregroundStyle(scene.accent)
                Text("芥子")
                    .font(JieziType.cardTitle)
                    .foregroundStyle(scene.foreground)

                syncStatusIcon

                Spacer()

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
                        .foregroundStyle(scene.foreground)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .accessibilityLabel("更多功能")
            }
            DomainDatePickerView()
        }
        .padding(.horizontal, JieziPrototypeLayout.page_inset)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            LinearGradient(colors: scene.background, startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: JieziPrototypeMotion.background_ms), value: appState.selectedDomain)
    }

    private var syncStatusIcon: some View {
        Image(systemName: appState.isSignedIn ? "icloud" : "icloud.slash")
            .font(.subheadline)
            .foregroundStyle(scene.muted)
            .accessibilityLabel(appState.isSignedIn ? "已登录" : "本地模式")
    }

    // MARK: - 底部栏（SHELL-003）

    private var shellBottomBar: some View {
        HStack {
            Button {
                appState.presentedOverlay = .inbox
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "tray.full")
                        .font(.system(size: 15, weight: .semibold))
                    Text("待确认")
                        .font(JieziFont.caption)
                    Text("\(appState.dashboard.pendingCount)")
                        .font(JieziType.moneyInline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .foregroundStyle(scene.foreground)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(scene.surface.opacity(0.82), in: Capsule())
                .overlay(Capsule().stroke(scene.accent.opacity(0.12), lineWidth: 1))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("收件箱，\(appState.dashboard.pendingCount) 条待确认")
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: JieziPrototypeLayout.page_dot_gap) {
                ForEach(AppDomain.allCases) { domain in
                    Button {
                        appState.selectedDomain = domain
                    } label: {
                        Capsule()
                            .fill(domain == appState.selectedDomain ? scene.accent : scene.foreground.opacity(0.30))
                            .frame(
                                width: domain == appState.selectedDomain ? JieziPrototypeLayout.selected_page_width : JieziPrototypeLayout.page_dot_size,
                                height: JieziPrototypeLayout.page_dot_size
                            )
                            .frame(minWidth: JieziPrototypeLayout.page_dot_hit_width, minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                        .accessibilityLabel(domain.title)
                        .accessibilityAddTraits(domain == appState.selectedDomain ? .isSelected : [])
                }
            }

            Spacer()

            Button {
                showManualRecordSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: JieziPrototypeLayout.add_button_size, height: JieziPrototypeLayout.add_button_size)
                    .background(scene.accent, in: Circle())
            }
            .accessibilityLabel("记一笔")
        }
        .padding(.horizontal, JieziPrototypeLayout.page_inset)
        .padding(.vertical, 8)
        .background {
            LinearGradient(colors: scene.background, startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: JieziPrototypeMotion.background_ms), value: appState.selectedDomain)
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
