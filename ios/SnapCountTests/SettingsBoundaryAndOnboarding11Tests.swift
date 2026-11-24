import XCTest
@testable import SnapCount

/// iOS 1.1 设置页与核心边界修复测试。
/// 覆盖场景编号：SET-11-01 ~ SET-11-08、OB-11-01 ~ OB-11-03。
@MainActor
final class SettingsBoundaryAndOnboarding11Tests: XCTestCase {
    // MARK: - 模块 A：Hosted AI 登录门禁

    /// SET-11-01：未登录调用 setLocalVisionMode(.hosted) 拒绝切换，保持 .disabled，不写入 .hosted，并提示需要先登录。
    func testSET1101SignedOutSetLocalVisionModeHostedIsRejected() throws {
        let suiteName = "SnapCountTests.SET1101.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let visionStore = LocalVisionModeStore(defaults: defaults)
        let state = AppState(localVisionModeStore: visionStore)
        state.isSignedIn = false

        state.setLocalVisionMode(.hosted)

        XCTAssertEqual(state.localVisionMode, .disabled)
        XCTAssertEqual(visionStore.mode, .disabled)
        XCTAssertEqual(state.settingsMessage, "使用 Hosted AI 需要先登录账号。")
    }

    /// SET-11-02：未登录在 VisionSettingsView 选择 Hosted AI 状态机：
    /// 未登录点选 -> 弹需要登录 -> 登录成功 -> 弹隐私授权 -> 同意后启用；任一步取消保持 .disabled。
    func testSET1102VisionHostedSelectionFlowRequiresLoginThenConsent() throws {
        let suiteName = "SnapCountTests.SET1102.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let visionStore = LocalVisionModeStore(defaults: defaults)
        let state = AppState(localVisionModeStore: visionStore)
        state.isSignedIn = false

        var flow = VisionHostedActivationFlow()
        flow.requestHostedActivation(isSignedIn: state.isSignedIn)
        XCTAssertTrue(flow.showsNeedLoginAlert)
        XCTAssertFalse(flow.showsLoginSheet)
        XCTAssertFalse(flow.showsHostedConsentAlert)
        XCTAssertEqual(state.localVisionMode, .disabled)

        // 取消登录提示 -> 保持 .disabled
        flow.cancel()
        XCTAssertFalse(flow.showsNeedLoginAlert)
        XCTAssertFalse(flow.pendingHostedConsentAfterLogin)
        XCTAssertEqual(state.localVisionMode, .disabled)

        // 重新触发 -> 去登录 -> 登录成功 -> 自动转入隐私授权弹窗
        flow.requestHostedActivation(isSignedIn: state.isSignedIn)
        flow.proceedToLogin()
        XCTAssertFalse(flow.showsNeedLoginAlert)
        XCTAssertTrue(flow.showsLoginSheet)
        XCTAssertTrue(flow.pendingHostedConsentAfterLogin)

        state.isSignedIn = true
        state.currentUserId = "user-1"
        flow.handleLoginSheetDismissed(isSignedIn: state.isSignedIn)
        XCTAssertFalse(flow.showsLoginSheet)
        XCTAssertTrue(flow.showsHostedConsentAlert)
        XCTAssertEqual(state.localVisionMode, .disabled)

        // 取消隐私授权 -> 保持 .disabled
        flow.cancel()
        XCTAssertFalse(flow.showsHostedConsentAlert)
        XCTAssertEqual(state.localVisionMode, .disabled)

        // 已登录再次点选 -> 直接弹隐私授权 -> 同意后启用 .hosted
        flow.requestHostedActivation(isSignedIn: state.isSignedIn)
        XCTAssertFalse(flow.showsNeedLoginAlert)
        XCTAssertTrue(flow.showsHostedConsentAlert)
        flow.confirmConsent(in: state)
        XCTAssertFalse(flow.showsHostedConsentAlert)
        XCTAssertEqual(state.localVisionMode, .hosted)
        XCTAssertEqual(visionStore.mode, .hosted)
    }

    /// SET-11-03：已登录且开启 Hosted 时退出登录，自动降级为 .disabled 并持久化；提示“已退出登录，Hosted AI 已关闭；本机记录保留”。
    func testSET1103SignOutDowngradesHostedVisionModeToDisabledAndPersists() throws {
        let suiteName = "SnapCountTests.SET1103.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let visionStore = LocalVisionModeStore(defaults: defaults)
        let state = AppState(localVisionModeStore: visionStore)
        state.isSignedIn = true
        state.currentUserId = "user-1"
        state.setLocalVisionMode(.hosted)
        XCTAssertEqual(state.localVisionMode, .hosted)
        XCTAssertEqual(visionStore.mode, .hosted)

        state.signOut()

        XCTAssertFalse(state.isSignedIn)
        XCTAssertEqual(state.localVisionMode, .disabled)
        XCTAssertEqual(visionStore.mode, .disabled)
        XCTAssertEqual(state.settingsMessage, "已退出登录，Hosted AI 已关闭；本机记录保留。")
        XCTAssertEqual(state.presentedOverlay, .none)
    }

    /// SET-11-04：启动或恢复会话后发现 !isSignedIn 但本地持久化为 .hosted，收口为 .disabled 并写回 LocalVisionModeStore。
    func testSET1104ReconcileVisionModeDowngradesPersistedHostedWhenSignedOut() throws {
        let suiteName = "SnapCountTests.SET1104.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let visionStore = LocalVisionModeStore(defaults: defaults)
        visionStore.save(.hosted)
        XCTAssertEqual(visionStore.mode, .hosted)

        let state = AppState(localVisionModeStore: visionStore)
        state.isSignedIn = false
        state.reconcileLocalVisionModeWithAuthentication()

        XCTAssertEqual(state.localVisionMode, .disabled)
        XCTAssertEqual(visionStore.mode, .disabled)
    }

    // MARK: - 模块 B：新用户引导自动弹出与落地首页

    /// OB-11-01 & OB-11-02：全新安装未登录启动保持 presentedOverlay == .none 并弹出引导；完成或跳过引导后保持 .none 且再次冷启动不再弹出。
    func testOB1101And02FreshInstallPresentsOnboardingOnHomeAndPersistsCompletion() throws {
        let suiteName = "SnapCountTests.OB1101.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let onboardingStore = OnboardingProgressStore(defaults: defaults)
        let state = AppState(onboardingProgressStore: onboardingStore)

        XCTAssertEqual(state.presentedOverlay, .none)
        state.presentOnboardingIfNeeded()
        XCTAssertTrue(state.isOnboardingPresented)
        XCTAssertEqual(state.presentedOverlay, .none)

        state.presentedOverlay = .records
        state.finishOnboarding(skipped: true)
        XCTAssertFalse(state.isOnboardingPresented)
        XCTAssertEqual(state.presentedOverlay, .none)
        XCTAssertEqual(onboardingStore.completion(for: .device), .skipped)

        let secondLaunch = AppState(onboardingProgressStore: onboardingStore)
        secondLaunch.presentOnboardingIfNeeded()
        XCTAssertFalse(secondLaunch.isOnboardingPresented)
        XCTAssertEqual(secondLaunch.presentedOverlay, .none)
    }

    /// OB-11-03：外部深链或快捷指令冷启动不打断外部路由。
    func testOB1103ExternalRouteDefersOnboardingAndKeepsTargetOverlay() throws {
        let suiteName = "SnapCountTests.OB1103.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let onboardingStore = OnboardingProgressStore(defaults: defaults)
        let state = AppState(onboardingProgressStore: onboardingStore)

        state.handleDeepLink(URL(string: "jiezi://records")!)
        state.presentOnboardingIfNeeded()

        XCTAssertFalse(state.isOnboardingPresented)
        XCTAssertEqual(state.presentedOverlay, .records)
    }

    // MARK: - 模块 C：设置页信息架构与显隐边界

    /// SET-11-05：未登录且关闭识别时的设置页可见项。
    func testSET1105SignedOutDisabledVisionVisibilityPolicy() {
        let policy = SettingsVisibilityPolicy(
            isSignedIn: false,
            visionMode: .disabled,
            companionEnabled: true,
            companionPersonaTitle: "旁观者",
            hasDiagnostic: false
        )

        XCTAssertEqual(policy.sectionIdentifiers, [.profile, .aiAndShortcuts, .data, .privacy, .helpAndAbout])
        XCTAssertFalse(policy.showsAccountActionsSection)
        XCTAssertFalse(policy.showsSignOutAction)
        XCTAssertFalse(policy.showsDeleteCloudAccountAction)
        XCTAssertFalse(policy.showsCloudPrivacyRow)
        XCTAssertFalse(policy.showsHistoryMigrationRows)
        XCTAssertFalse(policy.showsAppearanceSection)
        XCTAssertFalse(policy.showsDiagnosticsRow)
        XCTAssertFalse(policy.showsVisionModelParameters)
        XCTAssertTrue(policy.isCompanionControlsDisabled)
        XCTAssertEqual(policy.companionRowSubtitle, "未生效 · 需先开启图片识别")
    }

    /// SET-11-06：已登录且开启 Hosted 时的设置页可见项。
    func testSET1106SignedInHostedVisionVisibilityPolicy() {
        let policy = SettingsVisibilityPolicy(
            isSignedIn: true,
            visionMode: .hosted,
            companionEnabled: true,
            companionPersonaTitle: "旁观者",
            hasDiagnostic: false
        )

        XCTAssertEqual(
            policy.sectionIdentifiers,
            [.profile, .aiAndShortcuts, .data, .privacy, .helpAndAbout, .accountActions]
        )
        XCTAssertTrue(policy.showsAccountActionsSection)
        XCTAssertTrue(policy.showsSignOutAction)
        XCTAssertTrue(policy.showsDeleteCloudAccountAction)
        XCTAssertTrue(policy.showsCloudPrivacyRow)
        XCTAssertFalse(policy.showsHistoryMigrationRows)
        XCTAssertFalse(policy.showsAppearanceSection)
        XCTAssertFalse(policy.showsDiagnosticsRow)
        XCTAssertTrue(policy.showsVisionModelParameters)
        XCTAssertFalse(policy.isCompanionControlsDisabled)
        XCTAssertEqual(policy.companionRowSubtitle, "已开启 · 旁观者")
    }

    /// SET-11-07：识别关闭时的 VisionSettingsView 与 CompanionSettingsView 规则。
    func testSET1107DisabledVisionHidesModelParametersAndDisablesCompanion() {
        let signedInDisabledPolicy = SettingsVisibilityPolicy(
            isSignedIn: true,
            visionMode: .disabled,
            companionEnabled: true,
            companionPersonaTitle: "老朋友",
            hasDiagnostic: false
        )

        XCTAssertFalse(signedInDisabledPolicy.showsVisionModelParameters)
        XCTAssertTrue(signedInDisabledPolicy.isCompanionControlsDisabled)
        XCTAssertEqual(signedInDisabledPolicy.companionRowSubtitle, "未生效 · 需先开启图片识别")
        XCTAssertTrue(signedInDisabledPolicy.showsCloudPrivacyRow, "已登录用户仍可管理云端识别数据与原图")
    }

    /// SET-11-08：本机存储或列表刷新异常时，帮助与关于出现诊断信息入口。
    func testSET1108DiagnosticEntryAppearsOnlyWhenDiagnosticExists() {
        let normalPolicy = SettingsVisibilityPolicy(
            isSignedIn: false,
            visionMode: .disabled,
            companionEnabled: false,
            companionPersonaTitle: "旁观者",
            hasDiagnostic: false
        )
        XCTAssertFalse(normalPolicy.showsDiagnosticsRow)

        let faultPolicy = SettingsVisibilityPolicy(
            isSignedIn: false,
            visionMode: .disabled,
            companionEnabled: false,
            companionPersonaTitle: "旁观者",
            hasDiagnostic: true
        )
        XCTAssertTrue(faultPolicy.showsDiagnosticsRow)
    }
}
