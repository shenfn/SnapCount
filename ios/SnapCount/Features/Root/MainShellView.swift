import SwiftUI

/// 五域骨架主场景（IOS-V2-SHELL-001~004）：
/// 域横滑为主体，顶部栏（品牌 / 同步 / 日期选择 /「…」菜单）与底部栏（待确认 / 圆点 / ＋）悬浮其上，
/// 菜单四项与待确认以全屏覆盖层呈现，关闭后回到原域页。
struct MainShellView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    @State private var showManualRecordSheet = false
    @State private var showsCalendar = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            if !dynamicTypeSize.isAccessibilitySize {
                DomainCatView(domain: appState.selectedDomain)
                    .padding(.top, 14)
                    .padding(.trailing, JieziPrototypeLayout.metric_inset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            domainPager
        }
        .safeAreaInset(edge: .top, spacing: 0) { shellTopBar }
        .safeAreaInset(edge: .bottom, spacing: 0) { shellBottomBar }
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
                VStack(alignment: .leading, spacing: 1) {
                    Text("芥子").font(JieziType.prototypeBrand)
                    Text("JIEZI").font(JieziFont.caption2).tracking(1.5)
                }
                .foregroundStyle(scene.foreground)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("芥子")

                Button { appState.presentedOverlay = .settings } label: {
                    syncStatusIcon.frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityHint("查看同步设置")

                Spacer()

                Button { showsCalendar = true } label: {
                    Image(systemName: "calendar")
                        .frame(minWidth: 44, minHeight: 44)
                        .background(scene.surface.opacity(0.55), in: Circle())
                }
                .foregroundStyle(scene.foreground)
                .accessibilityLabel("选择日期，当前\(appState.selectedDateKey)")

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
                        .background(scene.surface.opacity(0.55), in: Circle())
                }
                .accessibilityLabel("更多功能")
            }
            DomainDatePickerView(showsCalendar: $showsCalendar)
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
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Image(systemName: appState.isSignedIn ? "icloud" : "iphone")
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Label(appState.isSignedIn ? "已登录" : "本地模式",
                      systemImage: appState.isSignedIn ? "icloud" : "iphone")
                    .fixedSize()
            }
        }
            .font(JieziFont.caption2)
            .foregroundStyle(scene.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(scene.surface.opacity(0.55), in: Capsule())
            .accessibilityLabel(appState.isSignedIn ? "已登录" : "本地模式")
    }

    // MARK: - 底部栏（SHELL-003）

    private var shellBottomBar: some View {
        ViewThatFits(in: .horizontal) {
            bottomControls(compact: false)
            VStack(spacing: 0) {
                domainPageButtons
                bottomControls(compact: true)
            }
            VStack(spacing: 4) {
                domainPageButtons
                Text(appState.selectedDomain.title)
                    .font(JieziFont.caption)
                    .foregroundStyle(scene.foreground)
                HStack {
                    pendingButton
                    Spacer(minLength: 8)
                    addButton
                }
            }
        }
        .padding(.horizontal, JieziPrototypeLayout.page_inset)
        .padding(.vertical, 8)
        .background {
            LinearGradient(colors: scene.background, startPoint: .top, endPoint: .bottom)
        }
        .animation(.easeInOut(duration: JieziPrototypeMotion.background_ms), value: appState.selectedDomain)
    }

    private func bottomControls(compact: Bool) -> some View {
        ShellBottomLayout {
            pendingButton

            VStack(spacing: 5) {
                if !compact {
                    domainPageButtons
                }
                Menu {
                    ForEach(AppDomain.allCases) { domain in
                        Button { appState.selectedDomain = domain } label: {
                            Label(domain.title, systemImage: domain == appState.selectedDomain ? "checkmark" : domain.systemImage)
                        }
                    }
                } label: {
                    VStack(spacing: 1) {
                        Text(appState.selectedDomain.title).font(JieziFont.caption)
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(domainEnglishName).font(JieziFont.caption2)
                        }
                    }
                    .fixedSize()
                    .frame(minWidth: 44, minHeight: 44)
                    .foregroundStyle(scene.foreground)
                }
                .accessibilityLabel("当前\(appState.selectedDomain.title)，选择领域")
            }

            addButton
        }
    }

    private var pendingButton: some View {
        Button {
            appState.presentedOverlay = .inbox
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "tray.full")
                    .font(.system(size: 15, weight: .semibold))
                Text("待确认")
                    .font(JieziFont.caption)
                    .fixedSize()
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
    }

    private var addButton: some View {
        Button {
            showManualRecordSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: JieziPrototypeLayout.add_button_size, height: JieziPrototypeLayout.add_button_size)
                .background(JieziScene.expense.accent, in: Circle())
        }
        .accessibilityLabel("记一笔")
    }

    private var domainPageButtons: some View {
        HStack(spacing: 0) {
            ForEach(AppDomain.allCases) { domain in
                Button { appState.selectedDomain = domain } label: {
                    Capsule()
                        .fill(domain == appState.selectedDomain ? scene.accent : scene.foreground.opacity(0.30))
                        .frame(
                            width: domain == appState.selectedDomain ? JieziPrototypeLayout.selected_page_width : JieziPrototypeLayout.page_dot_size,
                            height: JieziPrototypeLayout.page_dot_size
                        )
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(domain.title)
                .accessibilityAddTraits(domain == appState.selectedDomain ? .isSelected : [])
            }
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var domainEnglishName: String {
        switch appState.selectedDomain {
        case .expense: return "Expense"
        case .sleep: return "Sleep"
        case .food: return "Food"
        case .sport: return "Movement"
        case .reading: return "Reading"
        }
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

/// 左右栏按较宽的一侧留位，中心组始终位于屏幕中线；空间不足交给 ViewThatFits 换行。
private struct ShellBottomLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        assert(subviews.count == 3)
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let side = max(sizes[0].width, sizes[2].width)
        return CGSize(
            width: max(proposal.width ?? 0, side * 2 + sizes[1].width + 16),
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        assert(subviews.count == 3)
        let left = subviews[0].sizeThatFits(.unspecified)
        let right = subviews[2].sizeThatFits(.unspecified)
        subviews[0].place(at: CGPoint(x: bounds.minX + left.width / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[1].place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
        subviews[2].place(at: CGPoint(x: bounds.maxX - right.width / 2, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}
