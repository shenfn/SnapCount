import SwiftUI
import os

typealias NativeSessionProvider = (_ forceRefresh: Bool) async throws -> SupabaseAuthSession
typealias NativeSleepProvider = (_ nanoseconds: UInt64) async throws -> Void

private struct WalletSnapshotReadModelRefreshError: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

private struct PendingRecordExpressionPlanDelivery {
    let id: UUID
    let recordId: String
    let plan: NativeRecordExpressionPlan
    let previousFeedback: NativeAIFeedback?
    let userId: String
    let generation: Int
}

private struct AppDefaultLocalStorage {
    let expenseUseCase: LocalExpenseUseCaseProtocol
    let recordUseCase: LocalRecordUseCaseProtocol
    let walletSnapshotUseCase: LocalWalletSnapshotUseCaseProtocol
    let factReader: LocalFactReader
    let imageStore: LocalImageStore
    let pendingFinancialRepository: LocalPendingFinancialRepository
    let financialBindingRepository: LocalFinancialBindingRepository
    let historyMigrationCache: LocalHistoryMigrationCache
    let historyMigrationDiagnosticStore: LocalHistoryMigrationDiagnosticStore?
    let historyInventoryReader: LocalHistoryInventoryReader
    let historyUnresolvedRepository: LocalHistoryUnresolvedRepository
}

@MainActor
final class AppState: ObservableObject {
    private static let calendarSignposter = OSSignposter(subsystem: "com.jiezi.app", category: "DomainCalendar")
    private static let recordReadSignposter = OSSignposter(subsystem: "com.jiezi.app", category: "RecordRead")
    @Published var selectedDomain: AppDomain = .expense
    @Published var selectedDateKey = NativeLocalDate.dateKey(Date())
    @Published var presentedOverlay: AppOverlay = .none
    @Published var isSignedIn = false
    @Published var currentUserId = ""
    @Published var currentUserEmail = ""
    @Published var lastShortcutMessage: String?
    @Published var isBootstrapping = true
    @Published var isSigningIn = false
    @Published var isSigningOut = false
    @Published var authMessage: String?
    @Published var authMessageIsError = false
    @Published var hasUploadToken = false
    @Published var dashboard = DashboardSnapshot()
    @Published var failedLocalImageIntakes: [LocalImageIntake] = []
    @Published var pendingLocalImageCleanups: [LocalImageCleanup] = []
    @Published var dashboardMessage: String?
    @Published var isLoadingDashboard = false
    @Published var isShowingCachedDashboard = false
    @Published var shortcutCredentialMessage: String?
    @Published var notificationPermissionMessage: String?
    @Published var notificationPermissionStatusText = "检查中"
    @Published var shortcutNotificationsEnabled = ShortcutFeedbackPreferences.notificationsEnabled
    @Published var shortcutResultCardEnabled = ShortcutFeedbackPreferences.resultCardEnabled
    @Published var isOnboardingPresented = false
    @Published var todayPath = NavigationPath()
    @Published var inboxPath = NavigationPath()
    @Published var recordsPath = NavigationPath()
    @Published var homePath = NavigationPath()
    @Published var selectedRecordDetail: NativeRecordDetail?
    @Published var recordDetailMessage: String?
    @Published var isSavingRecordDetail = false
    @Published var isDeletingRecordDetail = false
    @Published var recordFeedbackState: NativeAIFeedbackReviewState = .idle
    @Published var recordExpressionPlanExposureState: NativeRecordExpressionPlanExposureState = .idle
    @Published var isCreatingManualRecord = false
    @Published var manualRecordMessage: String?
    @Published var localProjectionRefreshMessage: String?
    @Published var localProjectionRefreshDiagnostic: LocalHistoryMigrationDiagnostic?
    private var pendingLocalRefreshMonths: Set<String> = []
    @Published var localStorageInitializationMessage: String?
    @Published var localStorageInitializationDiagnostic: LocalHistoryMigrationDiagnostic?
    @Published var recordMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    @Published var recordMonthMessages: [String: String] = [:]
    @Published var loadingRecordMonthKey: String?
    @Published private var loadingRemoteRecordMonthKeys: Set<String> = []
    @Published var accounts: [NativeAccount] = []
    @Published var localAccounts: [LocalAccount] = []
    @Published var localAccountBalances: [UUID: Int64] = [:]
    @Published var localAccountMessage: String?
    @Published var localSyncState: LocalSyncState?
    @Published var localBindingPreview: LocalBindingPreview?
    @Published var isLoadingLocalBindingPreview = false
    @Published var isSynchronizingLocalData = false
    @Published var localSyncMessage: String?
    @Published var localSyncDiagnostic: LocalSyncDiagnostic?
    @Published var localSyncFailureDiagnostic: LocalHistoryMigrationDiagnostic?
    @Published var financeVocabulary: [NativeFinanceVocabularyEntry] = []
    @Published var selectedAccountDetail: NativeAccountDetail?
    @Published var selectedAccountSourceSnapshot: NativeWalletSnapshot?
    @Published var accountMessage: String?
    @Published var isLoadingAccounts = false
    @Published var isSavingAccount = false
    @Published var isSubmittingRepayment = false
    @Published var repaymentMessage: String?
    @Published var repaymentCandidates: [String: NativeRepaymentCandidate] = [:]
    @Published var stagingRepaymentId: String?
    @Published var inboxFinanceMessage: String?
    @Published var inboxActionRecordId: String?
    @Published var inboxActionMessage: String?
    @Published var inboxActionMessageIsError = false
    @Published var isConfirmingPendingRecord = false
    @Published var pendingResolutionMessage: String?
    @Published var unboundRecords: [NativeUnboundRecord] = []
    @Published var unboundRecordsMessage: String?
    @Published var unboundBindingMessage: String?
    @Published var isLoadingUnboundRecords = false
    @Published var isBindingUnboundRecords = false
    @Published var walletSnapshots: [NativeWalletSnapshot] = []
    @Published var localWalletSnapshots: [LocalWalletSnapshot] = []
    @Published var localWalletSnapshotHistory: [LocalWalletSnapshot] = []
    @Published var isLoadingWalletSnapshots = false
    @Published var walletSnapshotActionId: String?
    @Published var walletSnapshotMessage: String?
    @Published var insightsSnapshot: NativeInsightSnapshot?
    @Published var isLoadingInsights = false
    @Published var insightsMessage: String?
    @Published var aiInsight: NativeAIInsight?
    @Published var isLoadingAIInsight = false
    @Published var aiInsightMessage: String?
    @Published var aiInsightIsCached = false
    @Published var userSettings = NativeUserSettings()
    @Published var localVisionMode = LocalVisionModeStore().mode
    @Published var hasBYOKAPIKey = (try? KeychainStore.shared.string(for: KeychainKeys.byokQwenAPIKey))?.isEmpty == false
    @Published var settingsMessage: String?
    @Published var isLoadingSettings = false
    @Published var isSavingSettings = false
    @Published var isCleaningSourceImages = false
    @Published var isExportingData = false
    @Published var isImportingLocalBackup = false
    @Published var isDeletingAccount = false
    @Published var isPreparingHistoryMigration = false
    @Published var canPauseHistoryMigration = false
    @Published var historyMigrationPreview: String?
    @Published var historyMigrationMessage: String?
    @Published var historyMigrationPhase = ""
    @Published var historyMigrationDiagnostic: LocalHistoryMigrationDiagnostic?
    @Published var historyMigrationProgress: LocalHistoryMigrationProgress?
    @Published var historyMigrationBlockers: [String] = []
    @Published var historyMigrationBlockerCount = 0
    @Published var historyMigrationUnresolvedCount = 0
    @Published var historyMigrationPreservationIssues: [String] = []
    @Published var localHistoryUnresolvedRecords: [LocalHistoryUnresolvedRecord] = []
    @Published var isLoadingHistoryUnresolvedRecords = false
    @Published var historyUnresolvedRecordsError: String?
    @Published var localHistoryInventory: LocalHistoryInventorySnapshot?
    @Published var localHistoryInventoryError: String?
    @Published var isLoadingLocalHistoryInventory = false
    @Published var cloudHistoryInventory = LocalHistoryCloudInventory.notRead
    @Published var isReadingCloudHistoryInventory = false
    private var historyMigrationArchive: Data?
    private var historyMigrationOwner: String?
    private var historyMigrationGeneration: Int?
    private var historyMigrationSourceDigest: Data?
    private var historyMigrationImageDigests: [String: String] = [:]
    private var historyMigrationAttempt = 0
    private var historyMigrationCheckpoint: LocalHistoryMigrationState?
    private var historyMigrationProfileID: UUID?
    private var historyMigrationAttemptID = UUID()
    private var historyMigrationImportError: Error?
    private let historyMigrationDiagnosticStore: LocalHistoryMigrationDiagnosticStore?
    private let historyInventoryReader: LocalHistoryInventoryReader?
    private let historyUnresolvedRepository: LocalHistoryUnresolvedRepository?

    private let authService = SupabaseAuthService()
    private let dashboardRepository: DashboardRepositoryProtocol
    private let recordRepository: RecordRepositoryProtocol
    private let localExpenseUseCase: LocalExpenseUseCaseProtocol?
    private let localRecordUseCase: LocalRecordUseCaseProtocol?
    private let localWalletSnapshotUseCase: LocalWalletSnapshotUseCaseProtocol?
    private let localFactReader: LocalFactReader?
    private let localImageStore: LocalImageStore?
    private let localImageIntakeRepository: LocalImageIntakeRepository?
    private let localRecordPortability: LocalRecordPortability?
    private let localFactPortability: LocalFactPortability?
    private let localCompleteBackupPortability: LocalCompleteBackupPortability?
    private let localPendingFinancialRepository: LocalPendingFinancialRepository?
    private let localFinancialBindingRepository: LocalFinancialBindingRepository?
    private let localHistoryMigrationCache: LocalHistoryMigrationCache?
    private let inboxRepository: InboxRepositoryProtocol
    private let domainRepository: DomainRepositoryProtocol
    private let snapshotStore: DashboardSnapshotStoreProtocol
    private let accountRepository: AccountRepositoryProtocol
    private let accountManagementRepository: AccountManagementRepositoryProtocol
    private let accountReadPreparationRepository: AccountReadPreparationRepositoryProtocol
    private var repaymentActionUseCase: RepaymentActionUseCase?
    private var screenshotRepaymentUseCase: ScreenshotRepaymentUseCase?
    private var accountManagementActionUseCase: AccountManagementActionUseCase?
    private var accountReadPreparationUseCase: AccountReadPreparationUseCase?
    private var accountBindingUseCase: AccountBindingUseCase?
    private var accountBindingUseCaseMonthKey: String?
    private var stagingLifecycleUseCase: StagingLifecycleUseCase?
    private var pendingConfirmationUseCase: PendingConfirmationUseCase?
    private var feedbackSubmissionUseCase: FeedbackSubmissionUseCase?
    private var recordDetailImageUseCase: RecordDetailImageUseCase?
    private var thumbnailImageUseCase: RecordDetailImageUseCase?
    private var dashboardCoreTask: Task<Void, Never>?
    @Published private var loadingLocalReadKeys: Set<String> = []
    private var localMonthReadVersions: [String: Int] = [:]
    private var stagingReadVersion = 0
    private let unboundRecordRepository: UnboundRecordRepositoryProtocol
    private let walletSnapshotRepository: WalletSnapshotRepositoryProtocol
    private var walletSnapshotActionUseCase: WalletSnapshotActionUseCase?
    private let insightsRepository: InsightsRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let financeVocabularyRepository: FinanceVocabularyRepositoryProtocol
    private let localBindingRepository: LocalBindingRepository?
    private let localSyncRunner: LocalSyncRunner?
    private let onboardingProgressStore: OnboardingProgressStore
    private let sessionProvider: NativeSessionProvider?
    private let expressionPlanAcknowledgementSleep: NativeSleepProvider
    private let keychain = KeychainStore.shared
    private let localVisionModeStore = LocalVisionModeStore()
    private let localUserSettingsStore: LocalUserSettingsStore
    private var lastDashboardRefreshAt: Date?
    private var recordDetailCache: [String: NativeRecordDetail] = [:]
    private var recordMonthDetails: [String: [String: NativeRecordDetail]] = [:]
    private var localExpenseMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    private var localIncomeMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    private var localRecordMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    // Remote and local projections have different freshness and deletion
    // semantics. Keep them separate so loading one cannot erase the other.
    private var remoteRecordMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    private var localRecordMonthDetails: [String: [String: NativeRecordDetail]] = [:]
    private var localFactMonths: [String: LocalFactMonth] = [:]
    private var loadingLocalExpenseMonthKey: String?
    private var loadingLocalRecordMonthKey: String?
    private var remoteRecordMonthTasks: [String: Task<Void, Never>] = [:]
    private var activeRecordReference: String?
    private var prefetchingRecordReferences: Set<String> = []
    private var expressionPlanDeliveryTokens: [String: UUID] = [:]
    private var pendingRecordExpressionPlans: [String: PendingRecordExpressionPlanDelivery] = [:]
    private var expressionPlanAcknowledgementTokens: [String: UUID] = [:]
    private var visibleRecordExpressionPlanCards: [String: String] = [:]
    private var insightsLoadedAt: Date?
    private var insightsLoadedLocally = false
    private var dashboardRefreshGeneration = 0
    private var userStateGeneration = 0
    private var dashboardSupplementTask: Task<Void, Never>?
    private var isLoadingFinanceVocabulary = false
    private var shouldDeferOnboardingForExternalRoute = false

    init(
        dashboardRepository: DashboardRepositoryProtocol = DashboardRepository(),
        recordRepository: RecordRepositoryProtocol = RecordRepository(),
        localExpenseUseCase: LocalExpenseUseCaseProtocol? = nil,
        localRecordUseCase: LocalRecordUseCaseProtocol? = nil,
        localStorageInitializationMessage: String? = nil,
        localWalletSnapshotUseCase: LocalWalletSnapshotUseCaseProtocol? = nil,
        localFactReader: LocalFactReader? = nil,
        localImageStore: LocalImageStore? = nil,
        localImageIntakeRepository: LocalImageIntakeRepository? = nil,
        localFactPortability: LocalFactPortability? = nil,
        localCompleteBackupPortability: LocalCompleteBackupPortability? = nil,
        localPendingFinancialRepository: LocalPendingFinancialRepository? = nil,
        localFinancialBindingRepository: LocalFinancialBindingRepository? = nil,
        inboxRepository: InboxRepositoryProtocol = InboxRepository(),
        domainRepository: DomainRepositoryProtocol = DomainRepository(),
        snapshotStore: DashboardSnapshotStoreProtocol = DashboardSnapshotStore(),
        accountRepository: AccountRepositoryProtocol = AccountRepository(),
        accountManagementRepository: AccountManagementRepositoryProtocol? = nil,
        accountReadPreparationRepository: AccountReadPreparationRepositoryProtocol? = nil,
        repaymentActionUseCase: RepaymentActionUseCase? = nil,
        screenshotRepaymentUseCase: ScreenshotRepaymentUseCase? = nil,
        accountManagementActionUseCase: AccountManagementActionUseCase? = nil,
        accountReadPreparationUseCase: AccountReadPreparationUseCase? = nil,
        accountBindingUseCase: AccountBindingUseCase? = nil,
        stagingLifecycleUseCase: StagingLifecycleUseCase? = nil,
        pendingConfirmationUseCase: PendingConfirmationUseCase? = nil,
        feedbackSubmissionUseCase: FeedbackSubmissionUseCase? = nil,
        recordDetailImageUseCase: RecordDetailImageUseCase? = nil,
        unboundRecordRepository: UnboundRecordRepositoryProtocol = UnboundRecordRepository(),
        walletSnapshotRepository: WalletSnapshotRepositoryProtocol = WalletSnapshotRepository(),
        walletSnapshotActionUseCase: WalletSnapshotActionUseCase? = nil,
        insightsRepository: InsightsRepositoryProtocol = InsightsRepository(),
        settingsRepository: SettingsRepositoryProtocol = SettingsRepository(),
        financeVocabularyRepository: FinanceVocabularyRepositoryProtocol = FinanceVocabularyRepository(),
        localBindingRepository: LocalBindingRepository? = nil,
        localSyncRunner: LocalSyncRunner? = nil,
        onboardingProgressStore: OnboardingProgressStore = OnboardingProgressStore(),
        sessionProvider: NativeSessionProvider? = nil,
        localUserSettingsStore: LocalUserSettingsStore = LocalUserSettingsStore(),
        historyMigrationDiagnosticStore: LocalHistoryMigrationDiagnosticStore? = nil,
        historyUnresolvedRepository: LocalHistoryUnresolvedRepository? = nil,
        expressionPlanAcknowledgementSleep: @escaping NativeSleepProvider = {
            try await Task<Never, Never>.sleep(nanoseconds: $0)
        }
    ) {
        self.dashboardRepository = dashboardRepository
        self.recordRepository = recordRepository
        let simulatesLocalStorageInitializationFailure = localStorageInitializationMessage != nil
        let usesDefaultLocalStorage = !simulatesLocalStorageInitializationFailure
            && localExpenseUseCase == nil && localRecordUseCase == nil
        let defaultLocalStorage: AppDefaultLocalStorage?
        var localStorageInitializationError: Error? = nil
        var storageInitializationMessage = localStorageInitializationMessage
        if usesDefaultLocalStorage {
            do {
                defaultLocalStorage = try Self.makeDefaultLocalStorage()
            } catch {
                defaultLocalStorage = nil
                localStorageInitializationError = error
                storageInitializationMessage = nil
            }
        } else {
            defaultLocalStorage = nil
        }
        if let localExpenseUseCase {
            self.localExpenseUseCase = localExpenseUseCase
        } else if usesDefaultLocalStorage {
            self.localExpenseUseCase = defaultLocalStorage?.expenseUseCase
        } else {
            self.localExpenseUseCase = simulatesLocalStorageInitializationFailure
                ? nil
                : Self.defaultLocalExpenseUseCase()
        }
        if let localRecordUseCase {
            self.localRecordUseCase = localRecordUseCase
        } else if usesDefaultLocalStorage {
            self.localRecordUseCase = defaultLocalStorage?.recordUseCase
        } else {
            self.localRecordUseCase = simulatesLocalStorageInitializationFailure
                ? nil
                : Self.defaultLocalRecordUseCase()
        }
        self.localWalletSnapshotUseCase = localWalletSnapshotUseCase
            ?? (usesDefaultLocalStorage ? defaultLocalStorage?.walletSnapshotUseCase : nil)
        self.localFactReader = usesDefaultLocalStorage
            ? (localFactReader ?? defaultLocalStorage?.factReader)
            : localFactReader
        self.localImageStore = localImageStore ?? defaultLocalStorage?.imageStore ?? Self.defaultLocalImageStore()
        self.localImageIntakeRepository = localImageIntakeRepository ?? Self.defaultLocalImageIntakeRepository()
        self.localRecordPortability = Self.defaultLocalRecordPortability()
        self.localFactPortability = usesDefaultLocalStorage
            ? (localFactPortability ?? Self.defaultLocalFactPortability())
            : localFactPortability
        self.localCompleteBackupPortability = localCompleteBackupPortability ?? Self.defaultLocalCompleteBackupPortability()
        self.localPendingFinancialRepository = localPendingFinancialRepository ?? defaultLocalStorage?.pendingFinancialRepository
        self.localFinancialBindingRepository = localFinancialBindingRepository ?? defaultLocalStorage?.financialBindingRepository
        self.localHistoryMigrationCache = defaultLocalStorage?.historyMigrationCache
        self.historyMigrationDiagnosticStore = historyMigrationDiagnosticStore
            ?? defaultLocalStorage?.historyMigrationDiagnosticStore
            ?? (try? LocalHistoryMigrationDiagnosticStore())
        self.historyInventoryReader = defaultLocalStorage?.historyInventoryReader
        self.historyUnresolvedRepository = historyUnresolvedRepository ?? defaultLocalStorage?.historyUnresolvedRepository
        self.inboxRepository = inboxRepository
        self.domainRepository = domainRepository
        self.snapshotStore = snapshotStore
        self.accountRepository = accountRepository
        self.accountManagementRepository = accountManagementRepository
            ?? (accountRepository as? AccountManagementRepositoryProtocol)
            ?? AccountRepository()
        self.accountReadPreparationRepository = accountReadPreparationRepository
            ?? (accountRepository as? AccountReadPreparationRepositoryProtocol)
            ?? AccountRepository()
        self.accountManagementActionUseCase = accountManagementActionUseCase
        self.repaymentActionUseCase = repaymentActionUseCase
        self.screenshotRepaymentUseCase = screenshotRepaymentUseCase
        self.accountReadPreparationUseCase = accountReadPreparationUseCase
        self.accountBindingUseCase = accountBindingUseCase
        self.stagingLifecycleUseCase = stagingLifecycleUseCase
        self.pendingConfirmationUseCase = pendingConfirmationUseCase
        self.feedbackSubmissionUseCase = feedbackSubmissionUseCase
        self.recordDetailImageUseCase = recordDetailImageUseCase
        self.unboundRecordRepository = unboundRecordRepository
        self.walletSnapshotRepository = walletSnapshotRepository
        self.walletSnapshotActionUseCase = walletSnapshotActionUseCase
        self.insightsRepository = insightsRepository
        self.settingsRepository = settingsRepository
        self.financeVocabularyRepository = financeVocabularyRepository
        self.localBindingRepository = localBindingRepository ?? Self.defaultLocalBindingRepository()
        self.localSyncRunner = localSyncRunner ?? Self.defaultLocalSyncRunner()
        self.onboardingProgressStore = onboardingProgressStore
        self.sessionProvider = sessionProvider
        self.localUserSettingsStore = localUserSettingsStore
        self.userSettings = localUserSettingsStore.load()
        self.expressionPlanAcknowledgementSleep = expressionPlanAcknowledgementSleep
        self.localStorageInitializationMessage = storageInitializationMessage
        if let localStorageInitializationError {
            let entry = recordLocalStorageInitializationFailure(localStorageInitializationError)
            self.localStorageInitializationMessage = entry?.userMessage ?? "本地数据初始化失败；原始错误已隐藏。"
        }
    }

    func bootstrap() {
        Task {
            if let localStorageInitializationMessage {
                manualRecordMessage = localStorageInitializationMessage
                presentedOverlay = .settings
                isBootstrapping = false
                return
            }
            do {
                _ = try await localExpenseUseCase?.prepareProfile()
                if let diagnostic = try? historyMigrationDiagnosticStore?.resolveLatest(
                    operation: "local-storage-init",
                    outcome: "本机数据库已就绪。",
                    expectedAccountID: nil
                ) {
                    localStorageInitializationDiagnostic = diagnostic
                }
                refreshLocalSyncState()
            } catch {
                let diagnostic = recordLocalStorageInitializationFailure(error)
                manualRecordMessage = diagnostic?.userMessage ?? "本地数据初始化失败；原始错误已隐藏。"
            }
            await restoreAuthentication()
            if !isSignedIn {
                presentedOverlay = .records
                await loadRecordMonth(Self.currentMonthKey, force: true)
            }
            isBootstrapping = false
            await refreshNotificationPermissionStatus()
            presentOnboardingIfNeeded()
        }
    }

    @discardableResult
    private func recordLocalStorageInitializationFailure(_ error: Error) -> LocalHistoryMigrationDiagnostic? {
        guard let historyMigrationDiagnosticStore else { return nil }
        let entry = historyMigrationDiagnosticStore.record(
            error,
            phase: "本机数据库初始化",
            operation: "local-storage-init",
            codeOverride: "LOCAL-STORAGE-INIT",
            attemptID: UUID(),
            committed: false,
            recoveryAction: "请检查本机存储状态后重启应用；不要清除应用数据。"
        )
        localStorageInitializationDiagnostic = entry
        return entry
    }

    private func restoreAuthentication() async {
        let generation = userStateGeneration
        do {
            let session: SupabaseAuthSession
            do {
                session = try await authService.currentSession()
            } catch {
                guard let legacy = try? requireSession(),
                      let refreshToken = legacy.refreshToken, !refreshToken.isEmpty else {
                    hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
                    updateShortcutCredentialMessage()
                    return
                }
                session = try await authService.restoreSession(accessToken: legacy.accessToken, refreshToken: refreshToken)
            }
            guard generation == userStateGeneration else { return }
            try save(session: session)
            apply(session: session)
            if mayReadRemoteBusinessData { restoreDashboardSnapshot(userId: session.user.id) }
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
            Task {
                await loadAccounts()
                await refreshDashboard()
                await loadRecordMonth(Self.currentMonthKey, force: true)
            }
        } catch {
            guard generation == userStateGeneration else { return }
            if isInvalidRefreshSessionError(error) {
                invalidateSession(message: "登录状态已失效，请重新登录。")
            } else {
                authMessage = error.localizedDescription
                authMessageIsError = true
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningOut else { authMessage = "正在完成上次退出，请稍后重试。"; return }
        guard !isSigningIn else { return }
        isSigningIn = true
        defer { isSigningIn = false }
        authMessage = nil
        authMessageIsError = false

        do {
            let session = try await authService.signIn(email: email, password: password)
            try save(session: session)
            apply(session: session)
            let generation = userStateGeneration
            hasUploadToken = false
            authMessage = "已登录，本机数据可继续使用。"
            do {
                let uploadToken = try await authService.fetchUploadToken(userId: session.user.id, accessToken: session.accessToken)
                guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
                try keychain.setString(uploadToken, for: KeychainKeys.uploadToken)
                hasUploadToken = true
            } catch {
                guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
                authMessage = "已登录；Hosted 快捷指令凭据暂不可用，可在设置中重试。"
            }
            updateShortcutCredentialMessage()
            presentOnboardingIfNeeded()
            await loadAccounts()
            await refreshDashboard()
            await loadRecordMonth(Self.currentMonthKey, force: true)
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
        }

        isSigningIn = false
    }

    func signUp(
        email: String,
        password: String,
        acceptedTerms: Bool,
        acceptedSensitiveData: Bool
    ) async {
        guard !isSigningOut else { authMessage = "正在完成上次退出，请稍后重试。"; return }
        guard !isSigningIn else { return }
        guard acceptedTerms else {
            authMessage = "请先阅读并同意服务协议与隐私政策"
            authMessageIsError = true
            return
        }
        guard acceptedSensitiveData else {
            authMessage = "请确认同意处理主动提交的敏感数据及跨境存储说明"
            authMessageIsError = true
            return
        }
        isSigningIn = true
        authMessage = nil
        authMessageIsError = false
        defer { isSigningIn = false }

        do {
            let result = try await authService.signUp(
                email: email,
                password: password,
                consent: .current()
            )
            switch result {
            case .confirmationRequired(let address):
                authMessage = "注册成功。请前往 \(address) 完成邮箱确认，然后返回登录。"
                authMessageIsError = false

            case .signedIn(let session):
                let uploadToken = try? await fetchUploadTokenAfterRegistration(session: session)
                if let uploadToken, !uploadToken.isEmpty {
                    try save(session: session, uploadToken: uploadToken)
                    hasUploadToken = true
                } else {
                    try save(session: session)
                    hasUploadToken = false
                }
                apply(session: session)
                authMessage = hasUploadToken
                    ? "注册成功，快捷指令凭据已同步。"
                    : "注册成功。上传凭据正在生成，可稍后在设置中重新检查。"
                updateShortcutCredentialMessage()
                presentOnboardingIfNeeded()
                await refreshDashboard()
            }
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
        }
    }

    func signOut() {
        guard !isSigningOut else { return }
        let userId = currentUserId.isEmpty ? (try? requireSession().user.id) : currentUserId
        // Revoke UI/request generations before awaiting the SDK's network work.
        invalidateSession(message: "")
        isSigningOut = true
        let generation = userStateGeneration
        if let userId { try? snapshotStore.remove(userId: userId) }
        Task {
            defer { isSigningOut = false }
            do {
                try await authService.signOut()
            } catch {
                guard generation == userStateGeneration else { return }
                authMessage = "本机已退出；云端会话注销暂未确认：\(error.localizedDescription)"
                authMessageIsError = true
            }
        }
    }

    func verifyShortcutCredential() {
        do {
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
        } catch {
            shortcutCredentialMessage = error.localizedDescription
        }
    }

    func refreshLocalSyncState() {
        guard let localBindingRepository else {
            localSyncState = nil
            return
        }
        do {
            let profile = try localBindingRepository.activeProfile()
            localSyncState = try localBindingRepository.syncState(profileID: profile.id)
            localSyncMessage = nil
        } catch {
            localSyncState = nil
            localSyncMessage = "本地同步状态读取失败：\(error.localizedDescription)"
        }
    }

    func prepareLocalBindingPreview() async {
        guard isSignedIn, !currentUserId.isEmpty else { return }
        guard let localBindingRepository else {
            localSyncMessage = "本地同步服务不可用。"
            return
        }
        guard !isLoadingLocalBindingPreview else { return }
        isLoadingLocalBindingPreview = true
        localSyncMessage = nil
        defer { isLoadingLocalBindingPreview = false }

        do {
            let session = try await validSession()
            let userID = session.user.id
            guard userID == currentUserId else { return }
            let useCase = LocalBindingPreviewUseCase(
                repository: localBindingRepository,
                scopeProvider: DomainRepositoryBindingScopeProvider(
                    repository: domainRepository,
                    accessTokenProvider: { [weak self] in
                        guard let self else { throw SupabaseRemoteError.missingSession }
                        let session = try await self.validSession()
                        return session.accessToken
                    }
                )
            )
            localBindingPreview = try await useCase.makePreview(
                cloudUserID: userID,
                email: session.user.email
            )
        } catch {
            localBindingPreview = nil
            localSyncMessage = "无法读取云端同步范围：\(error.localizedDescription)"
        }
    }

    func deferLocalSync() {
        localBindingPreview = nil
        refreshLocalSyncState()
        localSyncMessage = "已保留本地数据，同步尚未开启。"
    }

    func disableLocalSync() {
        guard let localBindingRepository else { return }
        do {
            let profile = try localBindingRepository.activeProfile()
            localSyncState = try localBindingRepository.disableSync(profileID: profile.id)
            localBindingPreview = nil
            localSyncMessage = "云同步已关闭，本地数据仍保留在此 iPhone。"
        } catch {
            localSyncMessage = "关闭云同步失败：\(error.localizedDescription)"
        }
    }

    func confirmLocalBinding() {
        guard let preview = localBindingPreview,
              let localBindingRepository else { return }
        do {
            localSyncState = try localBindingRepository.confirmBinding(
                profileID: preview.workspaceID,
                cloudUserID: preview.candidateCloudUserID
            )
            localBindingPreview = nil
            localSyncMessage = "已绑定本地 workspace，正在进行首次同步。"
            Task { await synchronizeLocalData() }
        } catch {
            localSyncMessage = error.localizedDescription
        }
    }

    func synchronizeLocalData() async {
        guard !isSynchronizingLocalData else { return }
        guard isSignedIn, !currentUserId.isEmpty else {
            localSyncMessage = "请先登录后再同步。"
            return
        }
        guard let localBindingRepository else {
            localSyncMessage = "本地同步服务不可用。"
            return
        }
        guard let localSyncRunner else {
            localSyncMessage = "本地同步服务不可用。"
            return
        }

        isSynchronizingLocalData = true
        localSyncMessage = nil
        defer { isSynchronizingLocalData = false }

        let syncAttemptID = UUID()
        var diagnosticProfileID: UUID?
        var pendingOperationCount = 0
        do {
            let profile = try localBindingRepository.activeProfile()
            diagnosticProfileID = profile.id
            pendingOperationCount = try localBindingRepository.workspaceSummary(profileID: profile.id).pendingOutboxCount
            localSyncDiagnostic = LocalSyncDiagnostic(
                phase: .preflight,
                profileID: profile.id,
                pendingOperationCount: pendingOperationCount,
                uploadedOperationCount: 0,
                importedRecordCount: 0,
                failure: nil,
                syncStatus: localSyncState?.status
            )
            let session = try await validSession()
            guard session.user.id == currentUserId else {
                throw LocalSyncError.syncNotAuthorized
            }
            localSyncDiagnostic = LocalSyncDiagnostic(
                phase: .transport,
                profileID: profile.id,
                pendingOperationCount: pendingOperationCount,
                uploadedOperationCount: 0,
                importedRecordCount: 0,
                failure: nil,
                syncStatus: .syncing
            )
            let result = try await localSyncRunner.synchronize(
                profileID: profile.id,
                cloudUserID: session.user.id
            )
            localSyncState = result.state
            localSyncDiagnostic = LocalSyncDiagnostic(
                phase: .completed,
                profileID: profile.id,
                pendingOperationCount: pendingOperationCount,
                uploadedOperationCount: result.uploadedOperationCount,
                importedRecordCount: result.importedRecordCount,
                failure: nil,
                syncStatus: result.state.status
            )
            _ = await prepareLocalWorkspace()
            await loadRecordMonth(Self.currentMonthKey, force: true)
            // Refreshing the current dashboard may run concurrently with the
            // sync completion projection. Keep the authoritative runner
            // result visible unless that refresh explicitly invalidated the
            // session (in which case the state was intentionally reset).
            if isSignedIn {
                localSyncState = result.state
            }
            if let diagnostic = try? historyMigrationDiagnosticStore?.resolveLatest(
                operation: "local-sync",
                outcome: "重试同步已完成。",
                expectedAccountID: currentUserId
            ) {
                localSyncFailureDiagnostic = diagnostic
            }
            localSyncMessage = result.importedRecordCount > 0
                ? "同步完成，已合并 \(result.importedRecordCount) 条本地记录。"
                : "同步完成。"
        } catch {
            refreshLocalSyncState()
            if let diagnosticProfileID {
                localSyncDiagnostic = LocalSyncDiagnostic(
                    phase: .failed,
                    profileID: diagnosticProfileID,
                    pendingOperationCount: pendingOperationCount,
                    uploadedOperationCount: 0,
                    importedRecordCount: 0,
                    failure: Self.syncDiagnosticFailure(for: error),
                    syncStatus: localSyncState?.status
                )
            }
            let failure = Self.syncDiagnosticFailure(for: error)
            let entry = historyMigrationDiagnosticStore?.record(
                error,
                phase: "同步请求",
                accountID: currentUserId,
                operation: "local-sync",
                codeOverride: Self.syncDiagnosticCode(for: failure),
                progressSummary: Self.syncProgressSummary(for: error, pendingOperationCount: pendingOperationCount),
                attemptID: syncAttemptID,
                committed: false,
                recoveryAction: "本机事实保留；核对同步状态后可重试当前支持范围。"
            )
            localSyncFailureDiagnostic = entry
            localSyncMessage = entry?.userMessage ?? "云同步未完成；本机数据保留，请检查设置中的同步状态后重试。"
        }
    }

    private static func syncDiagnosticCode(for failure: LocalSyncDiagnosticFailure) -> String {
        switch failure {
        case .transport: return "SYNC-TRANSPORT"
        case .notAuthorized: return "SYNC-NOT-AUTHORIZED"
        case .partialFailure: return "SYNC-PARTIAL-FAILURE"
        case .cursorExpired: return "SYNC-CURSOR-EXPIRED"
        case .conflict: return "SYNC-CONFLICT"
        case .invalidResponse: return "SYNC-INVALID-RESPONSE"
        case .unknown: return "SYNC-UNKNOWN"
        }
    }

    private static func syncProgressSummary(for error: Error, pendingOperationCount: Int) -> String {
        if let syncError = error as? LocalSyncError,
           case .partialFailure(let rejectedOperationIDs) = syncError {
            return "开始时待处理 \(pendingOperationCount) 项；服务端拒绝 \(rejectedOperationIDs.count) 项。"
        }
        return "开始时待处理 \(pendingOperationCount) 项。"
    }

    func loadLatestLocalSyncDiagnostic() {
        guard let historyMigrationDiagnosticStore, !currentUserId.isEmpty else {
            localSyncFailureDiagnostic = nil
            return
        }
        let accountHint = LocalHistoryMigrationDiagnosticStore.identityHint(currentUserId)
        localSyncFailureDiagnostic = (try? historyMigrationDiagnosticStore.recent())?.last {
            $0.operation == "local-sync" && $0.accountHint == accountHint
        }
    }

    private static func syncDiagnosticFailure(for error: Error) -> LocalSyncDiagnosticFailure {
        if let syncError = error as? LocalSyncError {
            switch syncError {
            case .syncNotAuthorized, .bindingMismatch: return .notAuthorized
            case .partialFailure: return .partialFailure
            case .cursorExpired: return .cursorExpired
            case .remoteConflict: return .conflict
            case .invalidResponse: return .invalidResponse
            case .invalidWorkspace, .staleAttempt: return .unknown
            }
        }
        if error is SupabaseRemoteError {
            return .transport
        }
        return .transport
    }

    func refreshDashboard() async {
        if let task = dashboardCoreTask { await task.value; return }
        let generation = userStateGeneration
        let task = Task { @MainActor in
            defer { if generation == self.userStateGeneration { self.dashboardCoreTask = nil } }
            await self.performDashboardRefresh()
        }
        dashboardCoreTask = task
        await task.value
    }

    private func performDashboardRefresh() async {
        guard !isLoadingDashboard else { return }
        dashboardRefreshGeneration += 1
        let generation = dashboardRefreshGeneration
        dashboardSupplementTask?.cancel()
        isLoadingDashboard = true
        dashboardMessage = nil
        lastDashboardRefreshAt = Date()
        defer {
            if generation == dashboardRefreshGeneration {
                isLoadingDashboard = false
            }
        }

        if !mayReadRemoteBusinessData,
           localFactReader != nil || localExpenseUseCase != nil || localRecordUseCase != nil {
            dashboard = DashboardSnapshot()
            dashboard.domains = Self.fallbackDomains
            isShowingCachedDashboard = false
            let monthKey = Self.currentMonthKey
            var monthKeys = Set(localFactMonths.keys)
            monthKeys.formUnion(localExpenseMonthGroups.keys)
            monthKeys.formUnion(localRecordMonthGroups.keys)
            monthKeys.insert(monthKey)
            if localFactReader != nil {
                for key in monthKeys.sorted() {
                    await readDeviceFactMonth(key, force: true)
                }
            } else {
                for key in monthKeys.sorted() {
                    if localExpenseUseCase != nil { await readDeviceExpenseMonth(key, force: true) }
                    if localRecordUseCase != nil { await readDeviceRecordMonth(key, force: true) }
                }
                if monthKey == Self.currentMonthKey {
                    applyLocalRecordMonth()
                    await applyLocalStagingProjection()
                }
            }
            dashboard.domains = domainsWithUpdatedCounts(Self.fallbackDomains, snapshot: dashboard)
            dashboardMessage = recordMonthMessages[monthKey]
            return
        }

        do {
            let (fetchedSnapshot, session) = try await fetchDashboardCoreWithValidSession()
            guard generation == dashboardRefreshGeneration else { return }
            let snapshot = preparedCoreSnapshot(fetchedSnapshot)
            publishDashboard(snapshot, userId: session.user.id)
            await importRemoteExpenseDetails(snapshot.recordDetails.values)
            guard generation == dashboardRefreshGeneration else { return }
            scheduleDashboardSupplement(snapshot, session: session, generation: generation)
            Task { [weak self] in await self?.loadFinanceVocabulary() }
        } catch {
            guard generation == dashboardRefreshGeneration, !(error is CancellationError) else { return }
            if isInvalidRefreshSessionError(error) {
                invalidateSession(message: "登录状态已失效，请重新登录。")
            } else {
                dashboardMessage = isShowingCachedDashboard
                    ? "网络同步暂时失败，正在展示上次保存的数据。"
                    : error.localizedDescription
            }
        }

    }

    private func fetchDashboardCoreWithValidSession() async throws -> (DashboardSnapshot, SupabaseAuthSession) {
        var session = try await validSession()
        do {
            return (try await dashboardRepository.fetchDashboardCore(accessToken: session.accessToken), session)
        } catch {
            guard isExpiredJWTError(error) else { throw error }
            session = try await validSession(forceRefresh: true)
            return (try await dashboardRepository.fetchDashboardCore(accessToken: session.accessToken), session)
        }
    }

    private func preparedCoreSnapshot(_ snapshot: DashboardSnapshot) -> DashboardSnapshot {
        let mergedSnapshot = snapshot.mergingUnavailableSections(from: dashboard)
        var cachedImageURLs: [String: URL] = [:]
        for detail in dashboard.recordDetails.values {
            if let path = detail.imagePath, let url = detail.imageURL { cachedImageURLs[path] = url }
        }
        for record in dashboard.stagingRecords {
            if let path = record.imagePath, let url = record.imageURL { cachedImageURLs[path] = url }
        }
        for expense in dashboard.pendingExpenses {
            if let path = expense.imagePath, let url = expense.imageURL { cachedImageURLs[path] = url }
        }
        for detail in recordDetailCache.values {
            if let path = detail.imagePath, let url = detail.imageURL { cachedImageURLs[path] = url }
        }

        var prepared = mergedSnapshot.applyingSignedImageURLs(
            cachedImageURLs,
            markMissingAsFailure: false
        )
        let definitions = dashboard.domains.isEmpty ? Self.fallbackDomains : dashboard.domains
        prepared.domains = domainsWithUpdatedCounts(definitions, snapshot: prepared)
        return prepared
    }

    private func publishDashboard(_ snapshot: DashboardSnapshot, userId: String) {
        dashboard = snapshot
        isShowingCachedDashboard = false
        try? snapshotStore.save(snapshot, userId: userId)
        for detail in snapshot.recordDetails.values {
            let canonicalReference = NativeRecordReference(detail.id).canonicalValue
            recordDetailCache[canonicalReference] = detailPreservingExpressionFeedback(detail)
        }
    }

    private func scheduleDashboardSupplement(
        _ snapshot: DashboardSnapshot,
        session: SupabaseAuthSession,
        generation: Int
    ) {
        dashboardSupplementTask = Task { [weak self] in
            guard let self else { return }
            async let resolvedDomains = self.resolvedDomains(
                accessToken: session.accessToken,
                snapshot: snapshot
            )
            async let hydratedSnapshot = try? self.dashboardRepository.hydrateDashboardImages(
                snapshot,
                accessToken: session.accessToken
            )
            let (domains, hydrated) = await (resolvedDomains, hydratedSnapshot)
            guard !Task.isCancelled,
                  self.isSignedIn,
                  generation == self.dashboardRefreshGeneration else { return }

            var supplemented = hydrated ?? snapshot
            supplemented.domains = domains
            self.publishDashboard(supplemented, userId: session.user.id)
            await self.importRemoteExpenseDetails(supplemented.recordDetails.values)
            if let selectedId = self.selectedRecordDetail?.id,
               let selected = self.recordDetailCache[NativeRecordReference(selectedId).canonicalValue] {
                self.selectedRecordDetail = selected
            }
            self.prefetchDashboardImages(supplemented)
        }
    }

    private func restoreDashboardSnapshot(userId: String) {
        guard let persisted = try? snapshotStore.load(userId: userId) else { return }
        dashboard = persisted.dashboardSnapshot
        isShowingCachedDashboard = true
        lastDashboardRefreshAt = persisted.savedAt
    }

    private func fetchUploadTokenAfterRegistration(session: SupabaseAuthSession) async throws -> String {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await authService.fetchUploadToken(
                    userId: session.user.id,
                    accessToken: session.accessToken
                )
            } catch {
                lastError = error
                if attempt < 2 {
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
        }
        throw lastError ?? SupabaseAuthServiceError.emptyUploadToken
    }

    private func resolvedDomains(accessToken: String, snapshot: DashboardSnapshot) async -> [NativeDomainDefinition] {
        let definitions = (try? await domainRepository.fetchDefinitions(accessToken: accessToken)) ?? Self.fallbackDomains
        return domainsWithUpdatedCounts(definitions, snapshot: snapshot)
    }

    private func domainsWithUpdatedCounts(
        _ definitions: [NativeDomainDefinition],
        snapshot: DashboardSnapshot
    ) -> [NativeDomainDefinition] {
        let counts = Dictionary(
            grouping: snapshot.dayRecordGroups.flatMap(\.records).filter { $0.kind != .staging }
        ) { $0.domainKey ?? $0.kind.rawValue }.mapValues(\.count)
        return definitions.map { domain in
            NativeDomainDefinition(
                id: domain.id,
                name: domain.name,
                description: domain.description,
                icon: domain.icon,
                isSystem: domain.isSystem,
                schema: domain.schema,
                display: domain.display,
                recordCount: counts[domain.id] ?? 0
            )
        }
    }

    private static let fallbackDomains = InboxArchiveDomains.all.map { NativeDomainDefinition(id: $0.id, name: $0.title, description: "", icon: "", isSystem: true, schema: [:], display: [:], recordCount: 0) }

    private func prefetchDashboardImages(_ snapshot: DashboardSnapshot) {
        let urls = snapshot.recordDetails.values.compactMap(\.imageURL)
            + snapshot.stagingRecords.compactMap(\.imageURL)
            + snapshot.pendingExpenses.compactMap(\.imageURL)
        Task {
            await RemoteImageRepository.shared.prefetch(urls)
        }
    }

    func refreshDashboardIfStale(minInterval: TimeInterval = 3, force: Bool = false) async {
        if !force,
           let lastDashboardRefreshAt,
           Date().timeIntervalSince(lastDashboardRefreshAt) < minInterval {
            return
        }
        let generation = userStateGeneration
        _ = await prepareLocalWorkspace()
        guard generation == userStateGeneration else { return }
        // Intent 可从独立连接写入；回前台先重读当前及已打开月份的本机事实。
        var months = Set(localFactMonths.keys)
            .union(localExpenseMonthGroups.keys)
            .union(localIncomeMonthGroups.keys)
            .union(localRecordMonthGroups.keys)
        months.insert(Self.currentMonthKey)
        if let selectedMonth = NativeLocalDate.monthKey(from: selectedDateKey) {
            months.insert(selectedMonth)
        }
        for month in months.sorted() {
            await refreshLocalMonthProjection(monthKey: month)
            guard generation == userStateGeneration else { return }
        }
        guard isSignedIn else {
            lastDashboardRefreshAt = Date()
            return
        }
        await refreshDashboard()
    }

    func recordGroups(monthKey: String) -> [NativeDayRecordGroup] {
        let local = (localExpenseMonthGroups[monthKey] ?? [])
            + (localIncomeMonthGroups[monthKey] ?? [])
            + (localRecordMonthGroups[monthKey] ?? [])
        // 成功读取的本地月份（包括空月）是未登录态权威，不能把已删除的旧 Dashboard 投影合并回来。
        if !mayReadRemoteBusinessData,
           localExpenseMonthGroups[monthKey] != nil || localIncomeMonthGroups[monthKey] != nil || localRecordMonthGroups[monthKey] != nil {
            return Self.mergeRecordGroups(local: local, remote: [])
        }
        let remote = monthKey == Self.currentMonthKey
            ? dashboard.dayRecordGroups
            : (remoteRecordMonthGroups[monthKey] ?? [])
        guard !local.isEmpty else { return remote }
        return Self.mergeRecordGroups(local: local, remote: remote)
    }

    func hasLoadedRecordMonth(_ monthKey: String) -> Bool {
        if !mayReadRemoteBusinessData {
            return localExpenseMonthGroups[monthKey] != nil || localIncomeMonthGroups[monthKey] != nil || localRecordMonthGroups[monthKey] != nil
        }
        return localExpenseMonthGroups[monthKey] != nil
            || localIncomeMonthGroups[monthKey] != nil
            || localRecordMonthGroups[monthKey] != nil
            || remoteRecordMonthGroups[monthKey] != nil
    }

    func isLoadingRecordMonth(_ monthKey: String) -> Bool {
        loadingRecordMonthKey == monthKey || loadingRemoteRecordMonthKeys.contains(monthKey)
            || loadingLocalReadKeys.contains { $0.hasSuffix(":\(monthKey)") }
            || (monthKey == Self.currentMonthKey && isLoadingDashboard)
    }

    func recordGroups(from startDateKey: String, through endDateKey: String) -> [NativeDayRecordGroup] {
        let monthKeys = NativeLocalDate.monthKeys(from: startDateKey, through: endDateKey)
        guard !monthKeys.isEmpty else { return [] }
        let groups = monthKeys.flatMap { recordGroups(monthKey: $0) }
        return NativeRecordQuery.groups(
            from: groups,
            startingOn: startDateKey,
            through: endDateKey
        )
    }

    func recordDetails(from startDateKey: String, through endDateKey: String) -> [String: NativeRecordDetail] {
        let interval = Self.recordReadSignposter.beginInterval("CollectRecordDetails", id: Self.recordReadSignposter.makeSignpostID())
        defer { Self.recordReadSignposter.endInterval("CollectRecordDetails", interval) }
        let monthKeys = NativeLocalDate.monthKeys(from: startDateKey, through: endDateKey)
        var result = mayReadRemoteBusinessData ? dashboard.recordDetails : [:]
        for monthKey in monthKeys {
            if mayReadRemoteBusinessData {
                result.merge(recordMonthDetails[monthKey] ?? [:], uniquingKeysWith: { _, remote in remote })
            }
            result.merge(localRecordMonthDetails[monthKey] ?? [:], uniquingKeysWith: { _, local in local })
        }
        if mayReadRemoteBusinessData {
            for (reference, detail) in recordDetailCache {
                result[reference] = detail
            }
        }
        return result
    }

    func loadRecordDateWindow(around dateKey: String, force: Bool = false) async {
        // 五域共享浏览日期：一次补齐自然周和截止所选日的近七日，切域无需再等一次跨月读取。
        let days = (NativeLocalDate.weekDateKeys(containing: dateKey)
            + NativeDomainScenePresentation.trendDateKeys(for: .sleep, dateKey: dateKey)
            + [NativeLocalDate.shiftedDateKey(dateKey, byDays: -30) ?? dateKey]).sorted()
        guard let start = days.first, let end = days.last else { return }
        let selectedMonth = String(dateKey.prefix(7))
        let months = NativeLocalDate.monthKeys(from: start, through: end)
        let orderedMonths = months.contains(selectedMonth)
            ? [selectedMonth] + months.filter { $0 != selectedMonth } : months
        for monthKey in orderedMonths {
            if Task.isCancelled { return }
            await loadRecordMonth(monthKey, force: force)
        }
    }

    func dailyExpenseAmounts(monthKey: String) -> [String: Double] {
        let interval = Self.calendarSignposter.beginInterval("AggregateCalendarExpense", id: Self.calendarSignposter.makeSignpostID())
        defer { Self.calendarSignposter.endInterval("AggregateCalendarExpense", interval) }
        let groups = recordGroups(monthKey: monthKey)
        let days = NativeLocalDate.monthDateKeys(monthKey)
        guard let firstDay = days.first, let lastDay = days.last else { return [:] }
        let details = recordDetails(from: firstDay, through: lastDay)
        var totals: [String: Double] = [:]
        for record in groups.flatMap(\.records) where NativeRecordQuery.isFormal(record)
            && record.kind == .expense && record.transactionType != "income" {
            guard let amount = Self.expenseAmount(for: record, details: details) else { continue }
            totals[record.dateKey, default: 0] += amount
        }
        return totals
    }

    private static func expenseAmount(for record: NativeDayRecord, details: [String: NativeRecordDetail]) -> Double? {
        let canonical = NativeRecordReference(record.reference).canonicalValue
        if let detail = details[record.reference]
            ?? details[canonical]
            ?? details.values.first(where: { NativeRecordReference($0.id).canonicalValue == canonical }),
           let amount = detail.amount {
            return amount
        }
        let numeric = record.value.filter { $0.isNumber || $0 == "." || $0 == "-" }
        guard !numeric.isEmpty else { return nil }
        return Double(numeric)
    }

    private static func mergeRecordGroups(
        local: [NativeDayRecordGroup],
        remote: [NativeDayRecordGroup]
    ) -> [NativeDayRecordGroup] {
        let localReferences = Set(
            local.flatMap(\.records).map { NativeRecordReference($0.reference).canonicalValue }
        )
        let merged = local + remote.map { group in
            NativeDayRecordGroup(
                dateKey: group.dateKey,
                records: group.records.filter {
                    !localReferences.contains(NativeRecordReference($0.reference).canonicalValue)
                }
            )
        }
        return Dictionary(grouping: merged.flatMap { group in
            group.records.map { (group.dateKey, $0) }
        }, by: \.0).map { dateKey, entries in
            NativeDayRecordGroup(
                dateKey: dateKey,
                records: entries.map(\.1).sorted { ($0.timeLabel ?? "") > ($1.timeLabel ?? "") }
            )
        }.sorted { $0.dateKey > $1.dateKey }
    }

    func loadRecordMonth(_ monthKey: String, force: Bool = false) async {
        await loadUnifiedRecordMonth(monthKey, force: force)
    }

    private func loadUnifiedRecordMonth(_ monthKey: String, force: Bool = false) async {
        if localFactReader != nil {
            await readDeviceFactMonth(monthKey, force: force)
            if mayReadRemoteBusinessData {
                await loadRemoteRecordMonth(monthKey, force: force)
            }
            return
        }
        if localExpenseUseCase != nil || localRecordUseCase != nil {
            if localExpenseUseCase != nil {
                await readDeviceExpenseMonth(monthKey, force: force)
            }
            if localRecordUseCase != nil {
                await readDeviceRecordMonth(monthKey, force: force)
            }
            if mayReadRemoteBusinessData {
                await loadRemoteRecordMonth(monthKey, force: force)
            }
            return
        }
        await loadRemoteRecordMonth(monthKey, force: force)
    }

    private var mayReadRemoteBusinessData: Bool {
        // The local fact reader is the production authority. Binding authorizes
        // the expense/accounts coordinator, not the legacy five-domain REST loader.
        // Repository-only legacy adapters retain their explicit binding contract.
        guard localFactReader == nil, localStorageInitializationMessage == nil,
              isSignedIn, !currentUserId.isEmpty,
              localSyncState?.binding == .bound(currentUserId),
              localSyncState?.status != .disabled else {
            return false
        }
        return true
    }

    /// SL-02（C4）：所有写路径的"写后当月投影刷新"统一走这里。
    /// FactReader 权威模式刷新统一事实月；降级双 UseCase 模式刷新其拥有的两个本地月缓存。
    /// 读取路径（loadUnifiedRecordMonth、识别投影）不使用本方法。
    private func refreshLocalMonthProjection(monthKey: String) async {
        let generation = userStateGeneration
        let wasMonthPending = pendingLocalRefreshMonths.contains(monthKey)
        let hadPendingRefresh = !pendingLocalRefreshMonths.isEmpty
        insightsLoadedAt = nil
        if localFactReader != nil {
            await readDeviceFactMonth(monthKey, force: true)
        } else if localExpenseUseCase != nil {
            await readDeviceExpenseMonth(monthKey, force: true)
        }
        if localFactReader == nil, localRecordUseCase != nil {
            await readDeviceRecordMonth(monthKey, force: true)
        }
        guard generation == userStateGeneration else { return }
        if recordMonthMessages[monthKey] != nil {
            pendingLocalRefreshMonths.insert(monthKey)
        } else {
            pendingLocalRefreshMonths.remove(monthKey)
        }
        if pendingLocalRefreshMonths.isEmpty {
            localProjectionRefreshMessage = nil
            if wasMonthPending,
               let diagnostic = try? historyMigrationDiagnosticStore?.resolveLatest(
                   operation: "local-write-refresh",
                   outcome: "本机列表已刷新；原保存操作未重放。",
                   expectedAccountID: currentUserId.isEmpty ? nil : currentUserId
               ) {
                localProjectionRefreshDiagnostic = diagnostic
            }
            if wasMonthPending { resolvePostCommitMigrationRefreshIfNeeded() }
        } else if !hadPendingRefresh {
            let entry = historyMigrationDiagnosticStore?.record(
                LocalWriteRefreshError(),
                phase: "本机列表刷新",
                accountID: currentUserId.isEmpty ? nil : currentUserId,
                operation: "local-write-refresh",
                codeOverride: "LOCAL-POST-COMMIT-REFRESH",
                progressSummary: "待读取月份 \(pendingLocalRefreshMonths.count) 个。",
                attemptID: UUID(),
                committed: true,
                recoveryAction: "只重试读取本机列表；不要重复执行原保存操作。"
            )
            localProjectionRefreshDiagnostic = entry
            localProjectionRefreshMessage = entry?.userMessage
                ?? "数据已保存，列表刷新失败；请只重试读取，无需再次保存。"
        } else {
            localProjectionRefreshMessage = "数据已保存，列表刷新失败；请只重试读取，无需再次保存。"
        }
    }

    func retryLocalProjectionRefresh() async {
        for month in pendingLocalRefreshMonths.sorted() {
            await refreshLocalMonthProjection(monthKey: month)
        }
        if pendingLocalRefreshMonths.isEmpty {
            resolvePostCommitMigrationRefreshIfNeeded()
        }
    }

    private func resolvePostCommitMigrationRefreshIfNeeded() {
        if let diagnostic = historyMigrationDiagnostic, diagnostic.code == "HIST-POST-COMMIT-REFRESH" {
            try? historyMigrationDiagnosticStore?.resolve(diagnostic.id, outcome: "本机列表已刷新；迁移入账未重放。", expectedAccountID: currentUserId)
            loadLatestHistoryMigrationDiagnostic()
            if historyMigrationPhase == "已入账" || historyMigrationPhase == "已保留待核对" {
                historyMigrationMessage = historyMigrationUnresolvedCount > 0
                    ? "迁移内容已保存，含 \(historyMigrationUnresolvedCount) 条历史待核对原文；列表刷新完成，未重复提交。"
                    : "历史记录已入账；本机列表刷新完成，未重复提交。"
            }
        }
    }

    private func localWriteMessage(_ message: String) -> String {
        localProjectionRefreshMessage.map { "\(message)。\($0)" } ?? message
    }

    private func refreshAfterRecordWrite(affectedDateKeys: [String] = []) async {
        let generation = userStateGeneration
        var months = Set(remoteRecordMonthGroups.keys).union(recordMonthDetails.keys).union(remoteRecordMonthTasks.keys)
        months.formUnion(affectedDateKeys.compactMap { NativeLocalDate.monthKey(from: $0) })
        if let month = NativeLocalDate.monthKey(from: selectedDateKey) { months.insert(month) }
        if let pending = dashboardCoreTask { await pending.value }
        guard generation == userStateGeneration else { return }
        await refreshDashboard()
        guard generation == userStateGeneration else { return }
        await refreshLocalMonthProjection(monthKey: Self.currentMonthKey)
        for month in months.sorted() where month != Self.currentMonthKey {
            // 写入前的在途读取先结束，随后强制读取写入后的事实。
            if let task = remoteRecordMonthTasks[month] { await task.value }
            guard generation == userStateGeneration else { return }
            await loadRecordMonth(month, force: true)
            guard generation == userStateGeneration else { return }
        }
    }

    // Compatibility name retained for older feature tests; new callers use the unified facade above.
    private func loadLocalExpenseMonth(_ monthKey: String, force: Bool) async {
        await readDeviceExpenseMonth(monthKey, force: force)
    }

    func ingestHostedImageLocally(
        data: Data,
        captureKind: String,
        filename: String,
        uploadToken: String? = nil
    ) async throws -> LocalImageIntakeOutcome {
        guard localVisionMode != .disabled else { throw LocalDataError.invalidRecord }
        guard let localRecordUseCase, let localImageStore, let localImageIntakeRepository else {
            throw LocalDataError.invalidRecord
        }
        let provider: LocalImageRecognitionProvider
        let recognitionUploadToken: String?
        var isRecognitionRequestCurrent: @MainActor () -> Bool = { true }
        switch localVisionMode {
        case .disabled:
            throw LocalDataError.invalidRecord
        case .hosted:
            provider = HostedAIImageRecognitionProvider()
            recognitionUploadToken = uploadToken
        case .byok:
            let apiKey = (try? keychain.string(for: KeychainKeys.byokQwenAPIKey)) ?? ""
            provider = QwenBYOKImageRecognitionProvider(apiKey: apiKey)
            let credentialStore = keychain
            isRecognitionRequestCurrent = {
                (try? credentialStore.string(for: KeychainKeys.byokQwenAPIKey)) == apiKey
            }
            recognitionUploadToken = nil
        }
        let credentialCheck = isRecognitionRequestCurrent
        let generation = userStateGeneration
        let requestedMode = localVisionMode
        isRecognitionRequestCurrent = { [weak self] in
            guard let self, self.userStateGeneration == generation, self.localVisionMode == requestedMode else { return false }
            return credentialCheck()
        }
        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: localRecordUseCase,
            imageStore: localImageStore,
            intakeRepository: localImageIntakeRepository,
            provider: provider,
            isRecognitionRequestCurrent: isRecognitionRequestCurrent,
            pendingRepository: localPendingFinancialRepository
        )
        return try await recognition.ingest(
            imageData: data,
            captureKind: captureKind,
            filename: filename,
            uploadToken: recognitionUploadToken
        )
    }

    func receiveImageForManualProcessing(
        data: Data,
        captureKind: String,
        filename: String
    ) throws -> LocalImageIntake {
        guard let localRecordUseCase, let localImageStore, let localImageIntakeRepository else {
            throw LocalDataError.invalidRecord
        }
        let recognition = LocalImageRecognitionUseCase(
            localRecordUseCase: localRecordUseCase,
            imageStore: localImageStore,
            intakeRepository: localImageIntakeRepository,
            provider: HostedAIImageRecognitionProvider()
        )
        let intake = try recognition.receiveForManual(
            imageData: data, captureKind: captureKind, filename: filename
        )
        Task { await refreshFailedLocalImageIntakes() }
        return intake
    }

    func hasPersistedInputImage(_ data: Data) -> Bool {
        guard let repository = localImageIntakeRepository, let store = localImageStore,
              let profile = try? repository.activeProfile(),
              let intake = try? repository.intake(id: "\(profile.id.uuidString)-\(LocalImageStore.sha256(data))", profileID: profile.id),
              let saved = try? store.data(at: intake.imagePath) else { return false }
        return saved == data
    }

    func setLocalVisionMode(_ mode: LocalVisionMode) {
        if mode == .byok, !hasBYOKAPIKey {
            settingsMessage = "先保存 BYOK API Key，再启用 BYOK。"
            return
        }
        localVisionModeStore.save(mode)
        localVisionMode = mode
    }

    func saveBYOKAPIKey(_ apiKey: String) -> Bool {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            settingsMessage = "API Key 不能为空。"
            return false
        }
        do {
            try keychain.setString(normalized, for: KeychainKeys.byokQwenAPIKey)
            hasBYOKAPIKey = true
            settingsMessage = "API Key 已安全保存；尚未发送任何图片。"
            setLocalVisionMode(.byok)
            return true
        } catch {
            settingsMessage = "API Key 未能保存到 Keychain：\(error.localizedDescription)"
            return false
        }
    }

    func deleteBYOKAPIKey() -> Bool {
        do {
            try keychain.remove(KeychainKeys.byokQwenAPIKey)
            hasBYOKAPIKey = false
            if localVisionMode == .byok { setLocalVisionMode(.disabled) }
            settingsMessage = "本机 BYOK API Key 已删除；供应商账户中的 Key 仍需单独撤销。"
            return true
        } catch {
            settingsMessage = "API Key 未能从 Keychain 删除：\(error.localizedDescription)"
            return false
        }
    }

    var supportsLocalDomainRecords: Bool { localRecordUseCase != nil && localImageStore != nil }

    func localImageDataForRecord(id: String) async throws -> Data {
        guard let recordID = UUID(uuidString: id),
              let localImageStore else {
            throw LocalDataError.recordNotFound
        }
        if let record = try await localRecordUseCase?.record(id: recordID), let path = record.imagePath {
            return try localImageStore.data(at: path)
        }
        if let expense = try await localExpenseUseCase?.expense(id: recordID), let path = expense.imagePath {
            return try localImageStore.data(at: path)
        }
        if let income = try await localExpenseUseCase?.income(id: recordID), let path = income.imagePath {
            return try localImageStore.data(at: path)
        }
        throw LocalDataError.recordNotFound
    }

    func localImageDataForWalletSnapshot(id: UUID) throws -> Data {
        guard let snapshot = localWalletSnapshotHistory.first(where: { $0.id == id }),
              let imagePath = snapshot.imagePath,
              let localImageStore else {
            throw LocalDataError.recordNotFound
        }
        return try localImageStore.data(at: imagePath)
    }

    func refreshLocalRecognitionProjection(monthKey requestedMonthKey: String? = nil) async {
        let monthKey = requestedMonthKey ?? Self.currentMonthKey
        if localFactReader != nil {
            await readDeviceFactMonth(monthKey, force: true)
            if monthKey == Self.currentMonthKey, let month = localFactMonths[monthKey] {
                applyLocalFactMonth(month)
            }
        } else {
            await readDeviceRecordMonth(monthKey, force: true)
            if monthKey == Self.currentMonthKey {
                applyLocalRecordMonth()
            }
        }
        if monthKey == Self.currentMonthKey {
            await applyLocalStagingProjection()
        }
    }

    /// Rebuilds the Inbox from the authoritative local projection when no
    /// cloud session is available. Remote repayment candidates remain
    /// session-scoped and are intentionally loaded only when signed in.
    func refreshInboxProjection() async {
        await refreshFailedLocalImageIntakes()
        await refreshLocalImageCleanups()
        if !mayReadRemoteBusinessData {
            await refreshLocalRecognitionProjection()
        }
        await loadInboxRepaymentCandidates()
    }

    func refreshLocalImageCleanups() async {
        guard let localRecordUseCase else {
            pendingLocalImageCleanups = []
            return
        }
        do {
            pendingLocalImageCleanups = try localRecordUseCase.retryPendingImageCleanups()
        } catch {
            inboxActionMessage = "本地图片清理状态读取失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
        }
    }

    func retryLocalImageCleanups() async {
        await refreshLocalImageCleanups()
        if pendingLocalImageCleanups.isEmpty {
            inboxActionMessage = "本机图片清理已完成"
            inboxActionMessageIsError = false
        } else {
            inboxActionMessage = "仍有 \(pendingLocalImageCleanups.count) 张图片待清理"
            inboxActionMessageIsError = true
        }
    }

    func refreshFailedLocalImageIntakes() async {
        guard let repository = localImageIntakeRepository,
              let profile = try? repository.activeProfile() else {
            failedLocalImageIntakes = []
            return
        }
        do {
            try repository.recoverInterrupted(profileID: profile.id, before: Date().addingTimeInterval(-120))
            failedLocalImageIntakes = try repository.failedIntakes(profileID: profile.id)
        } catch {
            dashboardMessage = "本地图片收件箱读取失败：\(error.localizedDescription)"
        }
    }

    func retryLocalImageIntake(_ intake: LocalImageIntake) async -> Bool {
        guard localVisionMode != .disabled else {
            inboxActionMessage = "AI 识别已关闭；请开启后重试，或手动处理原图。"
            inboxActionMessageIsError = true
            return false
        }
        guard let localRecordUseCase, let localImageStore, let localImageIntakeRepository else { return false }
        do {
            let provider: LocalImageRecognitionProvider
            let uploadToken: String?
            var isRecognitionRequestCurrent: @MainActor () -> Bool = { true }
            switch localVisionMode {
            case .disabled:
                return false
            case .hosted:
                provider = HostedAIImageRecognitionProvider()
                uploadToken = try? keychain.string(for: KeychainKeys.uploadToken)
            case .byok:
                let apiKey = (try? keychain.string(for: KeychainKeys.byokQwenAPIKey)) ?? ""
                provider = QwenBYOKImageRecognitionProvider(apiKey: apiKey)
                let credentialStore = keychain
                isRecognitionRequestCurrent = {
                    (try? credentialStore.string(for: KeychainKeys.byokQwenAPIKey)) == apiKey
                }
                uploadToken = nil
            }
            let credentialCheck = isRecognitionRequestCurrent
            let generation = userStateGeneration
            let requestedMode = localVisionMode
            isRecognitionRequestCurrent = { [weak self] in
                guard let self, self.userStateGeneration == generation, self.localVisionMode == requestedMode else { return false }
                return credentialCheck()
            }
            let recognition = LocalImageRecognitionUseCase(
                localRecordUseCase: localRecordUseCase,
                imageStore: localImageStore,
                intakeRepository: localImageIntakeRepository,
                provider: provider,
                isRecognitionRequestCurrent: isRecognitionRequestCurrent,
                pendingRepository: localPendingFinancialRepository
            )
            _ = try await recognition.retry(intakeID: intake.id, uploadToken: uploadToken)
            await refreshFailedLocalImageIntakes()
            await refreshLocalRecognitionProjection()
            return true
        } catch {
            await refreshFailedLocalImageIntakes()
            inboxActionMessage = "重试未完成：\(error.localizedDescription)"
            inboxActionMessageIsError = true
            return false
        }
    }

    func discardLocalImageIntake(_ intake: LocalImageIntake) -> Bool {
        guard let repository = localImageIntakeRepository,
              let profile = try? repository.activeProfile() else { return false }
        do {
            try repository.discard(id: intake.id, profileID: profile.id)
            failedLocalImageIntakes.removeAll { $0.id == intake.id }
            pendingLocalImageCleanups = try localRecordUseCase?.retryPendingImageCleanups() ?? []
            return true
        } catch {
            inboxActionMessage = "图片未能丢弃：\(error.localizedDescription)"
            inboxActionMessageIsError = true
            return false
        }
    }

    func localImageData(for intake: LocalImageIntake) throws -> Data {
        guard let repository = localImageIntakeRepository,
              let imageStore = localImageStore,
              let profile = try? repository.activeProfile(),
              intake.profileID == profile.id else {
            throw LocalDataError.invalidIdentifier
        }
        return try imageStore.data(at: intake.imagePath)
    }

    func hasLocalImage(for intake: LocalImageIntake) -> Bool {
        localImageStore?.contains(path: intake.imagePath) == true
    }

    func discardLocalImageIntake(matching imageData: Data) -> Bool {
        guard let repository = localImageIntakeRepository,
              let profile = try? repository.activeProfile() else { return false }
        let id = "\(profile.id.uuidString)-\(LocalImageStore.sha256(imageData))"
        do {
            guard let intake = try repository.intake(id: id, profileID: profile.id) else { return true }
            return discardLocalImageIntake(intake)
        } catch {
            return false
        }
    }

    private func readDeviceFactMonth(_ monthKey: String, force: Bool) async {
        guard let localFactReader else { return }
        guard force || localFactMonths[monthKey] == nil else { return }
        let readKey = "facts:\(monthKey)"
        guard force || !loadingLocalReadKeys.contains(readKey) else { return }
        let readVersion = (localMonthReadVersions[readKey] ?? 0) + 1
        localMonthReadVersions[readKey] = readVersion
        loadingLocalReadKeys.insert(readKey)
        let interval = Self.recordReadSignposter.beginInterval("ReadAndProjectLocalFactMonth", id: Self.recordReadSignposter.makeSignpostID())
        defer { Self.recordReadSignposter.endInterval("ReadAndProjectLocalFactMonth", interval) }
        let generation = userStateGeneration
        loadingLocalExpenseMonthKey = monthKey
        loadingLocalRecordMonthKey = monthKey
        loadingRecordMonthKey = monthKey
        recordMonthMessages.removeValue(forKey: monthKey)
        defer {
            if generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion {
                loadingLocalReadKeys.remove(readKey)
                if loadingLocalExpenseMonthKey == monthKey { loadingLocalExpenseMonthKey = nil }
                if loadingLocalRecordMonthKey == monthKey { loadingLocalRecordMonthKey = nil }
                if loadingRecordMonthKey == monthKey, !loadingRemoteRecordMonthKeys.contains(monthKey),
                   !loadingLocalReadKeys.contains(where: { $0.hasSuffix(":\(monthKey)") }) {
                    loadingRecordMonthKey = nil
                }
            }
        }
        do {
            guard let month = try await localFactReader.activeMonth(monthKey: monthKey) else { return }
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            localFactMonths[monthKey] = month
            localExpenseMonthGroups[monthKey] = LocalFactReadModel.groups(
                from: month,
                including: [.expense, .income]
            )
            localIncomeMonthGroups[monthKey] = []
            localRecordMonthGroups[monthKey] = LocalFactReadModel.groups(
                from: month,
                including: [.record]
            )
            localRecordMonthDetails[monthKey] = LocalFactReadModel.details(
                from: month,
                imageStore: localImageStore
            )
            if monthKey == Self.currentMonthKey && !mayReadRemoteBusinessData {
                applyLocalFactMonth(month)
                await applyLocalStagingProjection()
            }
        } catch {
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            recordMonthMessages[monthKey] = error.localizedDescription
        }
    }

    private func applyLocalFactMonth(_ month: LocalFactMonth) {
        let todayKey = NativeLocalDate.dateKey(Date())
        let groups = recordGroups(monthKey: Self.currentMonthKey)
        let expenses = month.facts.filter { $0.kind == .expense }
        let incomes = month.facts.filter { $0.kind == .income }
        let todayExpenses = expenses.filter { $0.businessDate == todayKey }
        let todayIncomes = incomes.filter { $0.businessDate == todayKey }
        dashboard.dayRecordGroups = groups
        dashboard.dailySummaries = groups.map { group in
            let expense = expenses
                .filter { $0.businessDate == group.dateKey }
                .reduce(0.0) { total, fact in
                    let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                    return total + ((payload.double("amount_minor") ?? 0) / 100)
                }
            let income = incomes
                .filter { $0.businessDate == group.dateKey }
                .reduce(0.0) { total, fact in
                    let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
                    return total + ((payload.double("amount_minor") ?? 0) / 100)
                }
            return NativeDailySummary(
                dateKey: group.dateKey,
                expense: expense,
                income: income,
                pendingCount: 0,
                recordCount: group.records.count
            )
        }
        dashboard.todayCount = groups.first(where: { $0.dateKey == todayKey })?.records.count ?? 0
        dashboard.monthCount = groups.flatMap(\.records).count
        dashboard.todayExpense = todayExpenses.reduce(0) { total, fact in
            let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
            return total + ((payload.double("amount_minor") ?? 0) / 100)
        }
        dashboard.monthExpense = expenses.reduce(0) { total, fact in
            let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
            return total + ((payload.double("amount_minor") ?? 0) / 100)
        }
        dashboard.todayIncome = todayIncomes.reduce(0) { total, fact in
            let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
            return total + ((payload.double("amount_minor") ?? 0) / 100)
        }
        dashboard.monthIncome = incomes.reduce(0) { total, fact in
            let payload = (try? LocalRecordCodec.decode(fact.payloadJSON)) ?? [:]
            return total + ((payload.double("amount_minor") ?? 0) / 100)
        }
        dashboard.pendingCount = 0
        dashboard.recordDetails = localRecordMonthDetails[Self.currentMonthKey] ?? [:]
        dashboard.recentRecords = []
        dashboard.stagingRecords = []
        dashboard.pendingExpenses = []
    }

    private func applyLocalStagingProjection() async {
        stagingReadVersion += 1
        let version = stagingReadVersion
        let generation = userStateGeneration
        if let repository = localPendingFinancialRepository {
            do {
                if let profile = try await localExpenseUseCase?.prepareProfile() {
                    let pending = try repository.pending(profileID: profile.id)
                    guard generation == userStateGeneration else { return }
                    dashboard.pendingExpenses = pending.map { record in
                        NativePendingExpense(id: record.id.uuidString, title: record.merchantName,
                            amount: Double(record.amountMinor) / 100, dateKey: record.transactionDate,
                            reference: "expense/\(record.id.uuidString)", imagePath: record.imagePath,
                            occurredAtLabel: record.transactionTime, createdAtLabel: "本机待确认")
                    }
                }
            } catch { inboxFinanceMessage = "本机待补全读取失败：\(error.localizedDescription)" }
        }
        guard let localRecordUseCase else {
            dashboard.stagingRecords = []
            dashboard.pendingCount = dashboard.pendingExpenses.count
            return
        }
        do {
            let records = try await localRecordUseCase.stagingRecords()
            guard generation == userStateGeneration, version == stagingReadVersion else { return }
            let definitions = dashboard.domains.isEmpty ? Self.fallbackDomains : dashboard.domains
            dashboard.stagingRecords = records.map { record in
                let domainName = definitions.first(where: { $0.id == record.domainKey })?.shortName
                return LocalStagingReadModel.native(
                    from: record,
                    imageStore: localImageStore,
                    domainName: domainName
                )
            }
            dashboard.pendingCount = dashboard.pendingExpenses.count + dashboard.stagingRecords.count
        } catch {
            guard generation == userStateGeneration, version == stagingReadVersion else { return }
            dashboard.stagingRecords = []
            dashboard.pendingCount = dashboard.pendingExpenses.count
            inboxFinanceMessage = "本地中转站暂时无法读取：\(error.localizedDescription)"
        }
    }

    private func readDeviceExpenseMonth(_ monthKey: String, force: Bool) async {
        guard force || localExpenseMonthGroups[monthKey] == nil else { return }
        let readKey = "expense:\(monthKey)"
        guard force || !loadingLocalReadKeys.contains(readKey) else { return }
        let readVersion = (localMonthReadVersions[readKey] ?? 0) + 1
        localMonthReadVersions[readKey] = readVersion
        loadingLocalReadKeys.insert(readKey)
        let generation = userStateGeneration
        loadingLocalExpenseMonthKey = monthKey
        loadingRecordMonthKey = monthKey
        recordMonthMessages.removeValue(forKey: monthKey)
        defer {
            if generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion {
                loadingLocalReadKeys.remove(readKey)
                if loadingLocalExpenseMonthKey == monthKey { loadingLocalExpenseMonthKey = nil }
                if loadingRecordMonthKey == monthKey, !loadingRemoteRecordMonthKeys.contains(monthKey),
                   !loadingLocalReadKeys.contains(where: { $0.hasSuffix(":\(monthKey)") }) {
                    loadingRecordMonthKey = nil
                }
            }
        }
        do {
            guard let localExpenseUseCase else { throw LocalDataError.invalidRecord }
            let month = try await localExpenseUseCase.month(monthKey)
            let incomeMonth = try await localExpenseUseCase.incomes(monthKey)
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            let groups = Self.mergeRecordGroups(
                local: LocalExpenseReadModel.groups(from: month) + LocalIncomeReadModel.groups(from: incomeMonth),
                remote: []
            )
            localExpenseMonthGroups[monthKey] = LocalExpenseReadModel.groups(from: month)
            localIncomeMonthGroups[monthKey] = LocalIncomeReadModel.groups(from: incomeMonth)
            let localDomainDetails = (localRecordMonthDetails[monthKey] ?? [:]).filter {
                $0.value.kind == "data"
            }
            localRecordMonthDetails[monthKey] = Dictionary(
                uniqueKeysWithValues: month.expenses.map {
                    let detail = LocalExpenseReadModel.detail(from: $0)
                    return (detail.id, detail)
                }
            ).merging(
                Dictionary(uniqueKeysWithValues: incomeMonth.incomes.map {
                    let detail = LocalIncomeReadModel.detail(from: $0)
                    return (detail.id, detail)
                }), uniquingKeysWith: { _, income in income }
            ).merging(localDomainDetails, uniquingKeysWith: { local, _ in local })
            if monthKey == Self.currentMonthKey && !isSignedIn {
                applyLocalExpenseMonth(month, incomeMonth: incomeMonth, groups: groups)
            }
        } catch {
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            recordMonthMessages[monthKey] = error.localizedDescription
        }
    }

    private func readDeviceRecordMonth(_ monthKey: String, force: Bool) async {
        guard let localRecordUseCase else { return }
        guard force || localRecordMonthGroups[monthKey] == nil else { return }
        let readKey = "records:\(monthKey)"
        guard force || !loadingLocalReadKeys.contains(readKey) else { return }
        let readVersion = (localMonthReadVersions[readKey] ?? 0) + 1
        localMonthReadVersions[readKey] = readVersion
        loadingLocalReadKeys.insert(readKey)
        let generation = userStateGeneration
        loadingLocalRecordMonthKey = monthKey
        loadingRecordMonthKey = monthKey
        recordMonthMessages.removeValue(forKey: monthKey)
        defer {
            if generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion {
                loadingLocalReadKeys.remove(readKey)
                if loadingLocalRecordMonthKey == monthKey { loadingLocalRecordMonthKey = nil }
                if loadingRecordMonthKey == monthKey,
                   !loadingRemoteRecordMonthKeys.contains(monthKey),
                   !loadingLocalReadKeys.contains(where: { $0.hasSuffix(":\(monthKey)") }) {
                    loadingRecordMonthKey = nil
                }
            }
        }
        do {
            let month = try await localRecordUseCase.month(monthKey)
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            let groups = LocalRecordReadModel.groups(from: month, imageStore: localImageStore)
            localRecordMonthGroups[monthKey] = groups
            let localExpenseDetails = (localRecordMonthDetails[monthKey] ?? [:]).filter {
                $0.value.kind == "expense"
            }
            localRecordMonthDetails[monthKey] = localExpenseDetails.merging(
                Dictionary(uniqueKeysWithValues: month.records.map {
                    let detail = LocalRecordReadModel.detail(from: $0, imageStore: localImageStore)
                    return (detail.id, detail)
                }),
                uniquingKeysWith: { _, local in local }
            )
            if monthKey == Self.currentMonthKey {
                applyLocalRecordMonth()
                if !isSignedIn {
                    await applyLocalStagingProjection()
                }
            }
        } catch {
            guard generation == userStateGeneration, localMonthReadVersions[readKey] == readVersion else { return }
            recordMonthMessages[monthKey] = error.localizedDescription
        }
    }

    private func applyLocalRecordMonth() {
        let mergedGroups = recordGroups(monthKey: Self.currentMonthKey)
        let todayKey = NativeLocalDate.dateKey(Date())
        dashboard.dayRecordGroups = mergedGroups
        dashboard.todayCount = mergedGroups
            .first(where: { $0.dateKey == todayKey })?
            .records.filter { $0.kind != .staging }.count ?? 0
        dashboard.monthCount = mergedGroups.flatMap(\.records).filter { $0.kind != .staging }.count
        dashboard.recordDetails = dashboard.recordDetails.merging(
            localRecordMonthDetails[Self.currentMonthKey] ?? [:],
            uniquingKeysWith: { _, local in local }
        )
        let previousSummaries = Dictionary(uniqueKeysWithValues: dashboard.dailySummaries.map { ($0.dateKey, $0) })
        dashboard.dailySummaries = mergedGroups.map { group in
            let previous = previousSummaries[group.dateKey]
            return NativeDailySummary(
                dateKey: group.dateKey,
                expense: previous?.expense ?? 0,
                income: previous?.income ?? 0,
                pendingCount: group.records.filter { $0.kind == .staging }.count,
                recordCount: group.records.count
            )
        }
    }

    private func applyLocalExpenseMonth(
        _ month: LocalExpenseMonth,
        incomeMonth: LocalIncomeMonth,
        groups: [NativeDayRecordGroup]
    ) {
        let todayKey = NativeLocalDate.dateKey(Date())
        let todayExpenses = month.expenses.filter { $0.transactionDate == todayKey }
        let todayIncomes = incomeMonth.incomes.filter { $0.incomeDate == todayKey }
        dashboard.dayRecordGroups = groups
        dashboard.dailySummaries = groups.map { group in
            let expense = group.records.reduce(0.0) { total, record in
                guard let local = month.expenses.first(where: { $0.id.uuidString == record.id }) else { return total }
                return total + Double(local.amountMinor) / 100
            }
            return NativeDailySummary(
                dateKey: group.dateKey,
                expense: expense,
                income: group.records.filter { $0.kind == .income }.reduce(0) { total, record in
                    total + (incomeMonth.incomes.first(where: { $0.id.uuidString == record.id }).map { Double($0.amountMinor) / 100 } ?? 0)
                },
                pendingCount: 0,
                recordCount: group.records.count
            )
        }
        dashboard.todayCount = todayExpenses.count + todayIncomes.count
        dashboard.monthCount = month.expenses.count + incomeMonth.incomes.count
        dashboard.todayExpense = todayExpenses.reduce(0) { $0 + Double($1.amountMinor) / 100 }
        dashboard.monthExpense = month.expenses.reduce(0) { $0 + Double($1.amountMinor) / 100 }
        dashboard.todayIncome = todayIncomes.reduce(0) { $0 + Double($1.amountMinor) / 100 }
        dashboard.monthIncome = incomeMonth.incomes.reduce(0) { $0 + Double($1.amountMinor) / 100 }
        dashboard.pendingCount = 0
        dashboard.recordDetails = localRecordMonthDetails[Self.currentMonthKey] ?? [:]
        dashboard.recentRecords = []
        dashboard.stagingRecords = []
        dashboard.pendingExpenses = []
    }

    func reportSnapshot(monthKey: String) -> DashboardSnapshot {
        var snapshot = monthKey == Self.currentMonthKey ? dashboard : DashboardSnapshot()
        let groups = recordGroups(monthKey: monthKey)
        let details = (recordMonthDetails[monthKey] ?? [:]).merging(
            localRecordMonthDetails[monthKey] ?? [:],
            uniquingKeysWith: { _, local in local }
        )
        let records = groups.flatMap(\.records).filter { $0.kind != .staging }
        snapshot.dayRecordGroups = groups
        snapshot.recordDetails = details
        snapshot.monthCount = records.count
        snapshot.monthExpense = NativeHomeInsightAnalytics.confirmedExpenseTotal(from: snapshot)
        snapshot.monthIncome = records
            .filter { $0.kind == .income }
            .reduce(0) { total, record in
                total + (details[record.reference]?.amount ?? details[record.id]?.amount ?? record.amount ?? 0)
            }
        let definitions = dashboard.domains.isEmpty ? Self.fallbackDomains : dashboard.domains
        snapshot.domains = domainsWithUpdatedCounts(definitions, snapshot: snapshot)
        return snapshot
    }

    private func loadRemoteRecordMonth(_ monthKey: String, force: Bool = false) async {
        guard monthKey != Self.currentMonthKey else {
            if force || dashboard.dayRecordGroups.isEmpty || dashboardCoreTask != nil {
                await refreshDashboard()
                await refreshLocalMonthProjection(monthKey: monthKey)
            }
            return
        }
        guard force || remoteRecordMonthGroups[monthKey] == nil else { return }
        if let task = remoteRecordMonthTasks[monthKey] {
            await task.value
            return
        }
        let generation = userStateGeneration
        // 月读取属于账号会话；页面取消不取消共享请求，账号重置时集中取消。
        let task = Task { @MainActor in
            await self.performRemoteRecordMonthLoad(monthKey, generation: generation)
        }
        remoteRecordMonthTasks[monthKey] = task
        loadingRemoteRecordMonthKeys.insert(monthKey)
        await task.value
    }

    private func performRemoteRecordMonthLoad(_ monthKey: String, generation: Int) async {
        guard generation == userStateGeneration else { return }
        loadingRecordMonthKey = monthKey
        recordMonthMessages.removeValue(forKey: monthKey)
        defer {
            // 旧身份请求结束时不能移除新身份的同月任务或加载状态。
            if generation == userStateGeneration {
                remoteRecordMonthTasks.removeValue(forKey: monthKey)
                loadingRemoteRecordMonthKeys.remove(monthKey)
                if loadingRecordMonthKey == monthKey,
                   !loadingLocalReadKeys.contains(where: { $0.hasSuffix(":\(monthKey)") }),
                   loadingLocalExpenseMonthKey != monthKey,
                   loadingLocalRecordMonthKey != monthKey {
                    loadingRecordMonthKey = nil
                }
            }
        }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let month = try await recordRepository.fetchMonth(
                monthKey: monthKey,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            recordMonthDetails[monthKey] = month.details
            for (reference, detail) in month.details {
                let canonicalReference = NativeRecordReference(reference).canonicalValue
                recordDetailCache[canonicalReference] = detailPreservingExpressionFeedback(detail)
            }
            remoteRecordMonthGroups[monthKey] = month.groups
            await importRemoteExpenseDetails(month.details.values)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            await refreshLocalMonthProjection(monthKey: monthKey)
        } catch {
            guard generation == userStateGeneration else { return }
            guard !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
            recordMonthMessages[monthKey] = error.localizedDescription
        }
    }

    func loadAccounts() async {
        guard !isLoadingAccounts else { return }
        let generation = userStateGeneration
        isLoadingAccounts = true
        accountMessage = nil
        defer { isLoadingAccounts = false }
        if localExpenseUseCase != nil, !mayReadRemoteBusinessData {
            await loadLocalAccounts()
            if accounts.isEmpty, let localAccountMessage {
                accountMessage = localAccountMessage
            }
            return
        }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let loadedAccounts = try await accountRepository.fetchAccounts(accessToken: session.accessToken)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            accounts = loadedAccounts
            if shouldProjectRemoteData, let localExpenseUseCase {
                let localAccounts = loadedAccounts.compactMap { account -> LocalAccount? in
                    guard let id = UUID(uuidString: account.id) else { return nil }
                    return LocalAccount(
                        id: id,
                        profileID: UUID(),
                        name: account.name,
                        kind: account.type.rawValue,
                        currency: account.currency,
                        openingBalanceMinor: Int64((account.initialBalance * 100).rounded()),
                        createdAt: Date(),
                        institution: account.institution,
                        last4: account.last4,
                        billDay: account.billDay,
                        paymentDueDay: account.paymentDueDay,
                        autoDebitAccountID: account.autoDebitAccountId.flatMap(UUID.init(uuidString:)),
                        autoConfirmRepayment: account.autoConfirmRepayment,
                        gracePeriodDays: account.gracePeriodDays,
                        lastReconciledAt: Self.parseISO8601(account.lastReconciledAt),
                        isDefaultExpense: account.isDefaultExpense,
                        isDefaultIncome: account.isDefaultIncome,
                        isArchived: account.isArchived,
                        sortOrder: account.sortOrder
                    )
                }
                try await localExpenseUseCase.importRemoteAccounts(localAccounts)
                _ = await prepareLocalWorkspace()
            }
        } catch {
            guard generation == userStateGeneration else { return }
            if !isSignedIn {
                await loadLocalAccounts()
                accountMessage = nil
            } else {
                accountMessage = error.localizedDescription
            }
        }
    }

    private func importRemoteExpenseDetails(_ details: Dictionary<String, NativeRecordDetail>.Values) async {
        guard shouldProjectRemoteData, let localExpenseUseCase else { return }
        let referencedAccountIDs = Set(details.compactMap { $0.accountId })
        let missingAccounts = accounts.compactMap { account -> LocalAccount? in
            guard referencedAccountIDs.contains(account.id),
                  let id = UUID(uuidString: account.id),
                  !localAccounts.contains(where: { $0.id == id }) else { return nil }
            return LocalAccount(
                id: id,
                profileID: UUID(),
                name: account.name,
                kind: account.type.rawValue,
                currency: account.currency,
                openingBalanceMinor: Int64((account.initialBalance * 100).rounded()),
                createdAt: Date(),
                institution: account.institution,
                last4: account.last4,
                billDay: account.billDay,
                paymentDueDay: account.paymentDueDay,
                autoDebitAccountID: account.autoDebitAccountId.flatMap(UUID.init(uuidString:)),
                autoConfirmRepayment: account.autoConfirmRepayment,
                gracePeriodDays: account.gracePeriodDays,
                lastReconciledAt: Self.parseISO8601(account.lastReconciledAt),
                isDefaultExpense: account.isDefaultExpense,
                isDefaultIncome: account.isDefaultIncome,
                isArchived: account.isArchived,
                sortOrder: account.sortOrder
            )
        }
        if !missingAccounts.isEmpty {
            try? await localExpenseUseCase.importRemoteAccounts(missingAccounts)
            _ = await prepareLocalWorkspace()
        }
        let drafts = details.compactMap { detail -> LocalExpenseDraft? in
            guard detail.kind == "expense",
                  let id = UUID(uuidString: detail.rawId),
                  let accountID = detail.accountId.flatMap(UUID.init(uuidString:)),
                  let amount = detail.amount, amount > 0,
                  let date = detail.recordDate,
                  let merchant = detail.merchantName else { return nil }
            return LocalExpenseDraft(
                id: id,
                profileID: UUID(),
                accountID: accountID,
                amountMinor: Int64((amount * 100).rounded()),
                currency: "CNY",
                merchantName: merchant,
                platform: detail.platform ?? "",
                category: detail.category ?? "other",
                paymentMethod: detail.paymentMethod ?? "",
                transactionDate: date,
                transactionTime: detail.transactionTime,
                note: detail.note,
                createdAt: Date()
            )
        }
        guard !drafts.isEmpty else { return }
        try? await localExpenseUseCase.importRemoteExpenses(drafts)
        _ = await prepareLocalWorkspace()
    }

    private var shouldProjectRemoteData: Bool {
        guard isSignedIn,
              let state = localSyncState,
              case .bound(let userID) = state.binding else { return false }
        return userID == currentUserId
    }

    private func loadLocalAccounts() async {
        guard let workspace = await prepareLocalWorkspace() else {
            accounts = []
            return
        }
        var projected: [NativeAccount] = []
        for account in workspace.accounts {
            let balance: Int64
            if let useCase = localExpenseUseCase,
               let value = try? await useCase.accountBalanceMinor(account.id) {
                balance = value
            } else {
                balance = account.openingBalanceMinor
            }
            projected.append(Self.nativeAccount(from: account, balanceMinor: balance))
        }
        accounts = projected
    }

    private static func nativeAccount(from account: LocalAccount, balanceMinor: Int64) -> NativeAccount {
        NativeAccount(
            id: account.id.uuidString,
            name: account.name,
            type: NativeAccountType.normalized(account.kind),
            institution: account.institution,
            last4: account.last4,
            currency: account.currency,
            initialBalance: Double(account.openingBalanceMinor) / 100,
            currentBalance: Double(balanceMinor) / 100,
            snapshotBalance: nil,
            snapshotAt: nil,
            sourceRecordTable: "",
            sourceRecordId: "",
            billDay: account.billDay,
            paymentDueDay: account.paymentDueDay,
            autoDebitAccountId: account.autoDebitAccountID?.uuidString,
            autoConfirmRepayment: account.autoConfirmRepayment,
            gracePeriodDays: account.gracePeriodDays,
            lastReconciledAt: account.lastReconciledAt.map { ISO8601DateFormatter().string(from: $0) },
            isDefaultExpense: account.isDefaultExpense,
            isDefaultIncome: account.isDefaultIncome,
            isArchived: account.isArchived,
            sortOrder: account.sortOrder
        )
    }

    private static func nativeRepaymentCycle(from cycle: LocalRepaymentCycle) throws -> NativeRepaymentCycle {
        guard let status = NativeRepaymentStatus(rawValue: cycle.status) else { throw LocalDataError.invalidRecord }
        return NativeRepaymentCycle(
            id: cycle.id.uuidString, accountId: cycle.accountID.uuidString, cycleMonth: cycle.cycleMonth,
            statementStartDate: cycle.statementStartDate, statementEndDate: cycle.statementEndDate,
            dueDate: cycle.dueDate, statementAmount: Double(cycle.statementAmountMinor) / 100,
            paidAmount: Double(cycle.paidAmountMinor) / 100, remainingAmount: Double(cycle.remainingAmountMinor) / 100,
            carriedOverAmount: Double(cycle.carriedOverAmountMinor) / 100,
            originalStatementAmount: cycle.originalStatementAmountMinor.map { Double($0) / 100 },
            minPaymentAmount: cycle.minPaymentAmountMinor.map { Double($0) / 100 },
            refundAppliedAmount: Double(cycle.refundAppliedAmountMinor) / 100, status: status,
            autoDebitAccountId: cycle.autoDebitAccountID?.uuidString,
            autoConfirmRepayment: cycle.autoConfirmRepayment, source: cycle.source,
            evidenceRecordId: cycle.evidenceRecordID?.uuidString, confidence: cycle.confidence,
            note: cycle.note, confirmedAt: cycle.confirmedAt.map { ISO8601DateFormatter().string(from: $0) }
        )
    }

    private static func parseISO8601(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }

    private static func nativeLiabilityPayment(from payment: LocalLiabilityPayment) -> NativeLiabilityPayment {
        NativeLiabilityPayment(
            id: payment.id.uuidString, accountId: payment.accountID.uuidString,
            statementId: payment.statementID?.uuidString, debitAccountId: payment.debitAccountID?.uuidString,
            amount: Double(payment.amountMinor) / 100,
            overpaymentAmount: Double(payment.overpaymentAmountMinor) / 100,
            paidAt: ISO8601DateFormatter().string(from: payment.paidAt), source: payment.source,
            evidenceRecordId: payment.evidenceRecordID?.uuidString, status: payment.status,
            note: payment.note ?? ""
        )
    }

    func loadFinanceVocabulary() async {
        guard mayReadRemoteBusinessData else { financeVocabulary = []; return }
        guard !isLoadingFinanceVocabulary else { return }
        let generation = userStateGeneration
        isLoadingFinanceVocabulary = true
        defer { isLoadingFinanceVocabulary = false }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let entries = try await financeVocabularyRepository.fetch(accessToken: session.accessToken)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            financeVocabulary = entries
        } catch {
            guard generation == userStateGeneration else { return }
        }
    }

    private func scheduleConfirmedExpenseVocabulary(
        platform: String,
        category: String,
        paymentMethod: String,
        accountId: String?,
        userId: String,
        accessToken: String
    ) {
        let generation = userStateGeneration
        Task { [weak self] in
            await self?.recordConfirmedExpenseVocabulary(
                platform: platform,
                category: category,
                paymentMethod: paymentMethod,
                accountId: accountId,
                userId: userId,
                generation: generation,
                accessToken: accessToken
            )
        }
    }

    private func recordConfirmedExpenseVocabulary(
        platform: String,
        category: String,
        paymentMethod: String,
        accountId: String?,
        userId: String,
        generation: Int,
        accessToken: String
    ) async {
        guard mayReadRemoteBusinessData else { return }
        let categoryTitle = NativeFinanceOptionCatalog.categoryTitle(for: category)
        let requests: [(NativeFinanceVocabularyKind, String, String?, String?)] = [
            (.platform, platform, nil, nil),
            (.payment, paymentMethod, nil, accountId),
            (.category, categoryTitle ?? "", categoryTitle, nil)
        ]

        for (kind, rawDisplayName, primaryCategory, linkedAccountId) in requests {
            guard isCurrentUserLoad(generation, userId: userId) else { return }
            let displayName = rawDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !displayName.isEmpty else { continue }
            do {
                let entry = try await financeVocabularyRepository.record(
                    kind: kind,
                    displayName: displayName,
                    primaryCategory: primaryCategory,
                    linkedAccountId: linkedAccountId,
                    accessToken: accessToken
                )
                guard isCurrentUserLoad(generation, userId: userId) else { return }
                if let index = financeVocabulary.firstIndex(where: { $0.id == entry.id }) {
                    financeVocabulary[index] = entry
                } else {
                    financeVocabulary.append(entry)
                }
            } catch {
                continue
            }
        }
    }

    func loadAccountDetail(_ account: NativeAccount) async {
        let generation = userStateGeneration
        selectedAccountDetail = nil
        selectedAccountSourceSnapshot = nil
        accountMessage = nil
        if !mayReadRemoteBusinessData {
            await loadLocalAccountDetail(account)
            return
        }
        let session = try? await validSession()
        guard let session else {
            await loadLocalAccountDetail(account)
            return
        }
        guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
        if account.type.isLiability {
            let preparation = await resolvedAccountReadPreparationUseCase().prepare(monthKey: Self.currentMonthKey)
            guard projectAccountReadPreparationResult(preparation, onFailure: { [weak self] message in
                self?.accountMessage = message
            }) else { return }
        }
        let loadedDetail = await accountRepository.fetchDetail(account: account, accessToken: session.accessToken)
        guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
        selectedAccountDetail = loadedDetail
        if account.sourceRecordTable == "data_records", !account.sourceRecordId.isEmpty {
            let sourceSnapshot = try? await walletSnapshotRepository.fetch(
                id: account.sourceRecordId,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            selectedAccountSourceSnapshot = sourceSnapshot
            let reference = "data/\(account.sourceRecordId)"
            if recordDetailCache[reference] == nil,
               let detail = try? await recordRepository.fetchDetail(
                   reference: reference,
                   accessToken: session.accessToken
               ) {
                guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
                recordDetailCache[reference] = detail
                if let imageURL = detail.imageURL {
                    Task { await RemoteImageRepository.shared.prefetch([imageURL]) }
                }
            }
        }
    }

    private func loadLocalAccountDetail(_ account: NativeAccount) async {
        guard let accountID = UUID(uuidString: account.id),
              let localExpenseUseCase else {
            accountMessage = "本机账户标识无效。"
            return
        }
        do {
            await loadLocalAccounts()
            let currentAccount = accounts.first(where: { $0.id == account.id }) ?? account
            let entries = try await localExpenseUseCase.accountEntries(accountID: accountID)
            let nativeEntries = entries.map { entry in
                NativeAccountEntry(
                    id: entry.id.uuidString,
                    accountId: entry.accountID.uuidString,
                    direction: entry.direction,
                    amount: Double(entry.amountMinor) / 100,
                    entryType: entry.entryKind,
                    sourceTable: entry.sourceKind,
                    sourceId: entry.sourceID.uuidString,
                    occurredAt: entry.occurredAt.map { ISO8601DateFormatter().string(from: $0) } ?? "",
                    note: "",
                    isVoided: entry.voidedAt != nil || entry.isVoided,
                    voidedReason: entry.voidedAt == nil && !entry.isVoided ? "" : "已作废"
                )
            }
            var cycles: [NativeRepaymentCycle] = []
            var payments: [NativeLiabilityPayment] = []
            if currentAccount.type.isLiability {
                _ = try await localExpenseUseCase.ensureRepaymentCycles(Self.currentMonthKey, now: Date())
                cycles = try await localExpenseUseCase.repaymentCycles(accountID: accountID).map(Self.nativeRepaymentCycle(from:))
                payments = try await localExpenseUseCase.liabilityPayments(accountID: accountID).map(Self.nativeLiabilityPayment(from:))
            }
            selectedAccountDetail = NativeAccountDetail(
                account: currentAccount,
                entries: nativeEntries,
                repaymentCycles: cycles,
                payments: payments,
                loadErrors: [:]
            )
            accountMessage = nil
        } catch {
            accountMessage = error.localizedDescription
        }
    }

    func confirmRepayment(
        cycle: NativeRepaymentCycle,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String
    ) async -> Bool {
        if !mayReadRemoteBusinessData {
            return await confirmLocalRepayment(
                cycle: cycle, paidAmount: paidAmount, debitAccountId: debitAccountId,
                status: status, note: note
            )
        }
        return await performRepaymentAction(.confirm(
            cycleId: cycle.id,
            accountId: cycle.accountId,
            paidAmount: paidAmount,
            debitAccountId: debitAccountId,
            status: status,
            note: note
        ))
    }

    func revokeLiabilityPayment(
        payment: NativeLiabilityPayment,
        accountId: String
    ) async -> Bool {
        if !mayReadRemoteBusinessData {
            guard !isSubmittingRepayment,
                  let localExpenseUseCase,
                  let paymentID = UUID(uuidString: payment.id) else { return false }
            isSubmittingRepayment = true
            repaymentMessage = nil
            defer { isSubmittingRepayment = false }
            do {
                _ = try await localExpenseUseCase.revokeLiabilityPayment(
                    id: paymentID, reason: "用户撤销还款", now: Date()
                )
                await loadLocalAccounts()
                if let refreshed = accounts.first(where: { $0.id == accountId }) {
                    await loadLocalAccountDetail(refreshed)
                }
                repaymentMessage = "还款已在此设备撤销"
                return true
            } catch {
                repaymentMessage = error.localizedDescription
                return false
            }
        }
        return await performRepaymentAction(.revoke(
            paymentId: payment.id,
            cycleId: payment.statementId ?? "",
            accountId: accountId
        ))
    }

    private func confirmLocalRepayment(
        cycle: NativeRepaymentCycle,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String
    ) async -> Bool {
        guard !isSubmittingRepayment, paidAmount.isFinite, paidAmount >= 0,
              let localExpenseUseCase,
              let cycleID = UUID(uuidString: cycle.id) else { return false }
        let debitID: UUID?
        if let debitAccountId {
            guard let parsed = UUID(uuidString: debitAccountId) else {
                repaymentMessage = "扣款账户无效。"
                return false
            }
            debitID = parsed
        } else {
            debitID = nil
        }
        let paidAmountMinor: Int64
        do {
            paidAmountMinor = try LocalExpenseMapper.nonnegativeAmountMinor(String(paidAmount))
        } catch {
            repaymentMessage = error.localizedDescription
            return false
        }
        isSubmittingRepayment = true
        repaymentMessage = nil
        defer { isSubmittingRepayment = false }
        do {
            _ = try await localExpenseUseCase.confirmRepayment(
                cycleID: cycleID, paidAmountMinor: paidAmountMinor, debitAccountID: debitID,
                status: status.rawValue, note: note, paidAt: Date()
            )
            await loadLocalAccounts()
            if let refreshed = accounts.first(where: { $0.id == cycle.accountId }) {
                await loadLocalAccountDetail(refreshed)
            }
            repaymentMessage = "还款已保存在此设备"
            return true
        } catch {
            repaymentMessage = error.localizedDescription
            return false
        }
    }

    private func performRepaymentAction(_ command: RepaymentActionCommand) async -> Bool {
        let ownsBusyState = !isSubmittingRepayment
        if ownsBusyState {
            isSubmittingRepayment = true
            repaymentMessage = nil
        }
        defer {
            if ownsBusyState { isSubmittingRepayment = false }
        }

        let result = await resolvedRepaymentActionUseCase().perform(command)
        return projectRepaymentActionResult(result)
    }

    private func resolvedRepaymentActionUseCase() -> RepaymentActionUseCase {
        if let repaymentActionUseCase { return repaymentActionUseCase }
        let useCase = RepaymentActionUseCase(
            repository: accountRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return RepaymentActionUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return RepaymentActionUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            applyAccepted: { [weak self] cycle in
                self?.applyCanonicalRepaymentCycle(cycle)
            },
            refresh: { [weak self] accountId in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                try await self.refreshAfterRepayment(accountId: accountId)
            }
        )
        repaymentActionUseCase = useCase
        return useCase
    }

    private func resolvedAccountReadPreparationUseCase() -> AccountReadPreparationUseCase {
        if let accountReadPreparationUseCase { return accountReadPreparationUseCase }
        let useCase = AccountReadPreparationUseCase(
            repository: accountReadPreparationRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return AccountReadPreparationUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return AccountReadPreparationUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            }
        )
        accountReadPreparationUseCase = useCase
        return useCase
    }

    private func projectAccountReadPreparationResult(
        _ result: AccountReadPreparationResult,
        onFailure: (String) -> Void
    ) -> Bool {
        switch result.transaction {
        case .accepted:
            return true
        case .failed(let message):
            onFailure("还款计划准备失败：\(message)")
            return true
        case .rejected(.unauthenticated):
            onFailure("登录状态已失效，请重新登录。")
            return false
        case .rejected(.invalidInput):
            onFailure("还款计划月份无效")
            return false
        case .stale:
            return false
        }
    }

    private func resolvedScreenshotRepaymentUseCase() -> ScreenshotRepaymentUseCase {
        if let screenshotRepaymentUseCase { return screenshotRepaymentUseCase }
        let useCase = ScreenshotRepaymentUseCase(
            repository: inboxRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return ScreenshotRepaymentUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return ScreenshotRepaymentUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            }
        )
        screenshotRepaymentUseCase = useCase
        return useCase
    }

    private func projectScreenshotRepaymentResult(_ result: ScreenshotRepaymentResult) -> Bool {
        switch result.transaction {
        case .accepted:
            if case .failed(let message) = result.refresh {
                inboxFinanceMessage = "已根据截图确认还款，但刷新失败：\(message)"
            } else {
                inboxFinanceMessage = "已根据截图确认还款"
            }
            return true
        case .rejected(.unauthenticated):
            inboxFinanceMessage = "登录状态已失效，请重新登录。"
        case .rejected(.invalidInput):
            inboxFinanceMessage = "还款参数无效"
        case .conflict(.screenshotRepaymentConflict):
            inboxFinanceMessage = "还款截图正在以另一种方式处理，请稍后重试"
        case .failed(let message):
            inboxFinanceMessage = message
        case .stale:
            return false
        }
        return false
    }

    private func projectRepaymentActionResult(_ result: RepaymentActionResult) -> Bool {
        switch result.transaction {
        case .accepted(let accepted):
            let successMessage: String
            switch accepted.operation {
            case .confirm:
                successMessage = accepted.recordedDebit ? "已确认还款并记录扣款" : "已确认还款"
            case .revoke:
                successMessage = "已撤销还款"
            }
            if case .failed(let message) = result.refresh {
                repaymentMessage = "\(successMessage)，但刷新失败：\(message)"
            } else {
                repaymentMessage = successMessage
            }
            return true
        case .rejected(.unauthenticated):
            repaymentMessage = "登录状态已失效，请重新登录。"
        case .rejected(.invalidInput):
            repaymentMessage = "还款参数无效"
        case .conflict(.repaymentConflict):
            repaymentMessage = "当前账单正在执行另一项还款操作"
        case .failed(let message):
            repaymentMessage = message
        case .stale:
            return false
        }
        return false
    }

    private func applyCanonicalRepaymentCycle(_ cycle: NativeRepaymentCycle) {
        guard let detail = selectedAccountDetail, detail.account.id == cycle.accountId else { return }
        var cycles = detail.repaymentCycles
        if let index = cycles.firstIndex(where: { $0.id == cycle.id }) {
            cycles[index] = cycle
        } else {
            cycles.insert(cycle, at: 0)
        }
        selectedAccountDetail = NativeAccountDetail(
            account: detail.account,
            entries: detail.entries,
            repaymentCycles: cycles,
            payments: detail.payments,
            loadErrors: detail.loadErrors
        )
    }

    func loadInboxRepaymentCandidates() async {
        if !mayReadRemoteBusinessData, localExpenseUseCase != nil {
            await loadLocalInboxRepaymentCandidates()
            return
        }
        guard isSignedIn else {
            repaymentCandidates = [:]
            inboxFinanceMessage = nil
            return
        }
        let generation = userStateGeneration
        let stagingRecords = dashboard.stagingRecords
        guard !stagingRecords.isEmpty else {
            repaymentCandidates = [:]
            return
        }

        do {
            let session = try await validSession()
            let preparation = await resolvedAccountReadPreparationUseCase().prepare(monthKey: Self.currentMonthKey)
            guard projectAccountReadPreparationResult(preparation, onFailure: { [weak self] message in
                self?.inboxFinanceMessage = message
            }) else { return }
            async let accountRows = accountRepository.fetchAccounts(accessToken: session.accessToken)
            async let cycleRows = accountRepository.fetchOpenRepaymentCycles(accessToken: session.accessToken)
            let (loadedAccounts, cycles) = try await (accountRows, cycleRows)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            accounts = loadedAccounts
            repaymentCandidates = Dictionary(
                uniqueKeysWithValues: stagingRecords.compactMap { record in
                    NativeRepaymentCandidateEngine.candidate(
                        for: record,
                        accounts: loadedAccounts,
                        cycles: cycles
                    ).map { (record.id, $0) }
                }
            )
            inboxFinanceMessage = nil
        } catch {
            guard generation == userStateGeneration else { return }
            repaymentCandidates = [:]
            inboxFinanceMessage = "还款候选暂时无法匹配：\(error.localizedDescription)"
        }
    }

    func confirmStagingRepayment(_ record: NativeStagingRecord) async -> Bool {
        guard stagingRepaymentId == nil,
              let candidate = repaymentCandidates[record.id] else {
            return false
        }
        if let localStagingID = LocalStagingReadModel.localID(from: record.id) {
            guard let localExpenseUseCase,
                  let cycleID = UUID(uuidString: candidate.cycle.id) else { return false }
            let debitIDText = candidate.cycle.autoDebitAccountId ?? candidate.account.autoDebitAccountId
            let debitID = debitIDText.flatMap(UUID.init(uuidString:))
            guard debitIDText == nil || debitID != nil else { return false }
            stagingRepaymentId = record.id
            inboxFinanceMessage = nil
            defer { stagingRepaymentId = nil }
            do {
                let paidAmountMinor = try LocalExpenseMapper.amountMinor(String(candidate.amount))
                _ = try await localExpenseUseCase.confirmScreenshotRepayment(
                    stagingID: localStagingID,
                    cycleID: cycleID,
                    paidAmountMinor: paidAmountMinor,
                    debitAccountID: debitID,
                    note: "根据还款截图确认",
                    paidAt: Date()
                )
                repaymentCandidates.removeValue(forKey: record.id)
                removeStagingRecordLocally(record.id)
                await loadLocalAccounts()
                if selectedAccountDetail?.account.id == candidate.account.id,
                   let refreshed = accounts.first(where: { $0.id == candidate.account.id }) {
                    await loadLocalAccountDetail(refreshed)
                }
                await refreshDashboard()
                inboxFinanceMessage = "截图还款已保存在此设备"
                return true
            } catch {
                inboxFinanceMessage = "本地截图还款未确认：\(error.localizedDescription)"
                return false
            }
        }
        stagingRepaymentId = record.id
        inboxFinanceMessage = nil
        defer { stagingRepaymentId = nil }

        let result = await resolvedScreenshotRepaymentUseCase().confirm(
            ScreenshotRepaymentCommand(
                stagingId: record.id,
                cycleId: candidate.cycle.id,
                paidAmount: candidate.amount,
                debitAccountId: candidate.cycle.autoDebitAccountId ?? candidate.account.autoDebitAccountId,
                note: "根据还款截图确认"
            ),
            onAccepted: { [weak self] cycle in
                guard let self else { return }
                self.applyCanonicalRepaymentCycle(cycle)
                self.repaymentCandidates.removeValue(forKey: record.id)
                self.inboxPath = NavigationPath()
            },
            refresh: { [weak self] _ in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                await self.loadAccounts()
                if let message = self.accountMessage, !message.isEmpty {
                    throw WalletSnapshotReadModelRefreshError(message: message)
                }
                await self.refreshDashboard()
                if let message = self.dashboardMessage, !message.isEmpty {
                    throw WalletSnapshotReadModelRefreshError(message: message)
                }
            }
        )
        return projectScreenshotRepaymentResult(result)
    }

    private func loadLocalInboxRepaymentCandidates() async {
        guard let localExpenseUseCase, let localRecordUseCase else {
            repaymentCandidates = [:]
            return
        }
        let generation = userStateGeneration
        do {
            let staging = try await localRecordUseCase.stagingRecords()
            let candidates = staging.map { record in
                LocalStagingReadModel.native(from: record, imageStore: localImageStore)
            }
            await loadLocalAccounts()
            guard generation == userStateGeneration else { return }
            _ = try await localExpenseUseCase.ensureRepaymentCycles(Self.currentMonthKey, now: Date())
            var cycles: [NativeRepaymentCycle] = []
            for account in accounts where account.type.isLiability && !account.isArchived {
                guard let id = UUID(uuidString: account.id) else { continue }
                let localCycles = try await localExpenseUseCase.repaymentCycles(accountID: id)
                cycles += try localCycles.map(Self.nativeRepaymentCycle(from:))
            }
            guard generation == userStateGeneration else { return }
            repaymentCandidates = Dictionary(
                uniqueKeysWithValues: candidates.compactMap { record in
                    NativeRepaymentCandidateEngine.candidate(
                        for: record,
                        accounts: accounts,
                        cycles: cycles
                    ).map { (record.id, $0) }
                }
            )
            inboxFinanceMessage = nil
        } catch {
            guard generation == userStateGeneration else { return }
            repaymentCandidates = [:]
            inboxFinanceMessage = "本地还款候选暂时无法匹配：\(error.localizedDescription)"
        }
    }

    private func refreshAfterRepayment(accountId: String) async throws {
        await loadAccounts()
        if let accountMessage, !accountMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: accountMessage)
        }
        if let account = accounts.first(where: { $0.id == accountId }) {
            let generation = userStateGeneration
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let refreshedDetail = await accountRepository.fetchDetail(
                account: account,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }

            let canonicalCycles = selectedAccountDetail?.account.id == accountId
                ? selectedAccountDetail?.repaymentCycles ?? []
                : []
            if refreshedDetail.loadError(for: .repaymentCycles) != nil, !canonicalCycles.isEmpty {
                selectedAccountDetail = NativeAccountDetail(
                    account: refreshedDetail.account,
                    entries: refreshedDetail.entries,
                    repaymentCycles: canonicalCycles,
                    payments: refreshedDetail.payments,
                    loadErrors: refreshedDetail.loadErrors
                )
            } else {
                selectedAccountDetail = refreshedDetail
            }
            if let message = refreshedDetail.loadErrors.values.first {
                throw WalletSnapshotReadModelRefreshError(message: message)
            }
        }
        await refreshDashboard()
        if let dashboardMessage, !dashboardMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: dashboardMessage)
        }
    }

    func saveAccount(_ draft: NativeAccountDraft) async -> Bool {
        if !mayReadRemoteBusinessData {
            return await saveLocalManagedAccount(draft)
        }
        guard let initialBalance = Double(draft.initialBalanceText.isEmpty ? "0" : draft.initialBalanceText) else {
            accountMessage = "初始余额必须是数字"
            return false
        }
        let command = AccountManagementActionCommand.save(
            AccountManagementSaveCommand(
                accountId: draft.accountId,
                name: draft.name,
                type: draft.type,
                institution: draft.institution,
                last4: draft.last4,
                initialBalance: initialBalance,
                billDay: Int(draft.billDayText),
                paymentDueDay: Int(draft.paymentDueDayText),
                autoDebitAccountId: draft.autoDebitAccountId,
                autoConfirmRepayment: draft.autoConfirmRepayment,
                isDefaultExpense: draft.isDefaultExpense,
                isDefaultIncome: draft.isDefaultIncome
            )
        )
        return await performAccountManagementAction(command)
    }

    func setAccountArchived(_ account: NativeAccount, archived: Bool) async -> Bool {
        if !mayReadRemoteBusinessData {
            _ = await prepareLocalWorkspace()
            guard let id = UUID(uuidString: account.id), let local = localAccounts.first(where: { $0.id == id }) else {
                accountMessage = "本地账户不可用，请刷新后重试。"
                return false
            }
            guard let localExpenseUseCase else {
                accountMessage = "本地账户存储暂不可用。"
                return false
            }
            do {
                _ = try await localExpenseUseCase.updateAccount(LocalAccountEditCommand(
                    id: local.id, expectedVersion: local.localVersion, name: local.name,
                    kind: local.kind, institution: local.institution, last4: local.last4,
                    billDay: local.billDay, paymentDueDay: local.paymentDueDay,
                    autoDebitAccountID: archived ? nil : local.autoDebitAccountID,
                    autoConfirmRepayment: archived ? false : local.autoConfirmRepayment,
                    gracePeriodDays: local.gracePeriodDays,
                    isDefaultExpense: archived ? false : local.isDefaultExpense,
                    isDefaultIncome: archived ? false : local.isDefaultIncome,
                    isArchived: archived, sortOrder: local.sortOrder
                ))
                await loadLocalAccounts()
                accountMessage = archived ? "账户已归档" : "账户已恢复"
                return true
            } catch {
                accountMessage = error.localizedDescription
                return false
            }
        }
        return await performAccountManagementAction(
            .setArchived(accountId: account.id, archived: archived)
        )
    }

    private func saveLocalManagedAccount(_ draft: NativeAccountDraft) async -> Bool {
        guard !isSavingAccount else { return false }
        isSavingAccount = true
        accountMessage = nil
        defer { isSavingAccount = false }
        if let validation = draft.validationMessage {
            accountMessage = validation
            return false
        }
        _ = await prepareLocalWorkspace()
        return await persistLocalManagedAccount(draft)
    }

    private func persistLocalManagedAccount(_ draft: NativeAccountDraft) async -> Bool {
        guard let localExpenseUseCase else {
            accountMessage = "本地账户存储暂不可用。"
            return false
        }
        let autoDebitID: UUID?
        if let value = draft.autoDebitAccountId {
            guard let parsed = UUID(uuidString: value) else {
                accountMessage = "自动扣款账户无效。"
                return false
            }
            autoDebitID = parsed
        } else {
            autoDebitID = nil
        }
        do {
            if let accountIDText = draft.accountId {
                guard let accountID = UUID(uuidString: accountIDText),
                      let local = localAccounts.first(where: { $0.id == accountID }) else {
                    accountMessage = "本地账户不可用，请刷新后重试。"
                    return false
                }
                _ = try await localExpenseUseCase.updateAccount(LocalAccountEditCommand(
                    id: local.id, expectedVersion: local.localVersion,
                    name: draft.name, kind: draft.type.rawValue, institution: draft.institution,
                    last4: draft.last4, billDay: Int(draft.billDayText),
                    paymentDueDay: Int(draft.paymentDueDayText), autoDebitAccountID: autoDebitID,
                    autoConfirmRepayment: draft.autoConfirmRepayment,
                    gracePeriodDays: Int(draft.gracePeriodDaysText) ?? 0,
                    isDefaultExpense: draft.isDefaultExpense, isDefaultIncome: draft.isDefaultIncome,
                    isArchived: local.isArchived, sortOrder: local.sortOrder
                ))
            } else {
                let command = LocalAccountSetupCommand(
                    id: UUID(), name: draft.name, kind: draft.type.rawValue,
                    openingBalanceText: draft.initialBalanceText.isEmpty ? "0" : draft.initialBalanceText,
                    createdAt: Date(), institution: draft.institution, last4: draft.last4,
                    billDay: Int(draft.billDayText), paymentDueDay: Int(draft.paymentDueDayText),
                    autoDebitAccountID: autoDebitID, autoConfirmRepayment: draft.autoConfirmRepayment,
                    gracePeriodDays: Int(draft.gracePeriodDaysText) ?? 0,
                    isDefaultExpense: draft.isDefaultExpense, isDefaultIncome: draft.isDefaultIncome
                )
                _ = try await localExpenseUseCase.createAccount(command)
            }
            await loadLocalAccounts()
            accountMessage = "账户已保存在此设备"
            return true
        } catch {
            accountMessage = error.localizedDescription
            return false
        }
    }

    private func performAccountManagementAction(_ command: AccountManagementActionCommand) async -> Bool {
        guard !isSavingAccount else { return false }
        isSavingAccount = true
        accountMessage = nil
        defer { isSavingAccount = false }

        let result = await resolvedAccountManagementActionUseCase().perform(command)
        switch result.transaction {
        case .accepted:
            switch result.refresh {
            case .notStarted, .succeeded:
                accountMessage = "账户已保存"
            case .failed(let message):
                accountMessage = "账户已保存，但刷新失败：\(message)"
            }
            return true
        case .rejected(.unauthenticated):
            accountMessage = "登录状态已失效，请重新登录。"
        case .rejected(.invalidInput):
            accountMessage = "账户信息不完整，请检查后重试。"
        case .conflict:
            accountMessage = "账户正在保存，请稍后重试。"
        case .failed(let message):
            accountMessage = message
        case .stale:
            return false
        }
        return false
    }

    private func resolvedAccountManagementActionUseCase() -> AccountManagementActionUseCase {
        if let accountManagementActionUseCase { return accountManagementActionUseCase }
        let useCase = AccountManagementActionUseCase(
            repository: accountManagementRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return AccountManagementUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return AccountManagementUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            applyAccepted: { [weak self] account in
                self?.applyCanonicalAccount(account)
            },
            refresh: { [weak self] accountId in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                try await self.refreshAfterAccountManagement(accountId: accountId)
            }
        )
        accountManagementActionUseCase = useCase
        return useCase
    }

    private func applyCanonicalAccount(_ account: NativeAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
        guard selectedAccountDetail?.account.id == account.id,
              let detail = selectedAccountDetail else { return }
        selectedAccountDetail = NativeAccountDetail(
            account: account,
            entries: detail.entries,
            repaymentCycles: detail.repaymentCycles,
            payments: detail.payments,
            loadErrors: detail.loadErrors
        )
    }

    private func refreshAfterAccountManagement(accountId: String) async throws {
        await loadAccounts()
        if let accountMessage, !accountMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: accountMessage)
        }
        guard let account = accounts.first(where: { $0.id == accountId }) else {
            throw WalletSnapshotReadModelRefreshError(message: "账户刷新后未找到")
        }
        let generation = userStateGeneration
        let session = try await validSession()
        guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
        let detail = await accountRepository.fetchDetail(account: account, accessToken: session.accessToken)
        guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
        selectedAccountDetail = detail
        if let message = detail.loadErrors.values.first {
            throw WalletSnapshotReadModelRefreshError(message: message)
        }
        await refreshDashboard()
        if let dashboardMessage, !dashboardMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: dashboardMessage)
        }
    }

    func loadUnboundRecords(monthKey: String) async {
        guard !isLoadingUnboundRecords else { return }
        let generation = userStateGeneration
        isLoadingUnboundRecords = true
        unboundRecordsMessage = nil
        defer { isLoadingUnboundRecords = false }

        if !mayReadRemoteBusinessData {
            do {
                guard let repository = localFinancialBindingRepository,
                      let profile = try await localExpenseUseCase?.prepareProfile() else {
                    unboundRecords = []
                    return
                }
                guard generation == userStateGeneration else { return }
                unboundRecords = try repository.unboundRecords(profileID: profile.id)
            } catch { unboundRecordsMessage = "本机未绑定记录读取失败：\(error.localizedDescription)" }
            return
        }

        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let records = try await unboundRecordRepository.fetch(
                monthKey: monthKey,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            unboundRecords = records
        } catch {
            guard generation == userStateGeneration else { return }
            unboundRecordsMessage = error.localizedDescription
        }
    }

    private func resolvedAccountBindingUseCase(monthKey: String) -> AccountBindingUseCase {
        if let accountBindingUseCase {
            if accountBindingUseCaseMonthKey == nil || accountBindingUseCaseMonthKey == monthKey {
                return accountBindingUseCase
            }
        }
        let useCase = AccountBindingUseCase(
            repository: unboundRecordRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else { throw SupabaseRemoteError.requestFailed("会话已失效") }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return AccountBindingUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return AccountBindingUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            applyAccepted: { [weak self] accepted in
                self?.unboundRecords.removeAll { $0.id == accepted.recordId && $0.kind == accepted.kind }
            },
            refresh: { [weak self] in
                guard let self else { return }
                try await self.refreshAfterAccountBinding(monthKey: monthKey)
            }
        )
        accountBindingUseCase = useCase
        accountBindingUseCaseMonthKey = monthKey
        return useCase
    }

    func bindUnboundRecord(
        _ record: NativeUnboundRecord,
        accountId: String,
        monthKey: String
    ) async -> Bool {
        guard !isBindingUnboundRecords else { return false }
        isBindingUnboundRecords = true
        unboundBindingMessage = nil
        defer { isBindingUnboundRecords = false }
        let generation = userStateGeneration
        if !mayReadRemoteBusinessData {
            do {
                try await bindLocalFinancialRecord(record, accountId: accountId)
                guard generation == userStateGeneration else { return true }
                await loadUnboundRecords(monthKey: monthKey)
                await loadLocalAccounts()
                await refreshLocalMonthProjection(monthKey: String(record.date.prefix(7)))
                guard generation == userStateGeneration else { return true }
                unboundBindingMessage = localWriteMessage("已补绑本机账户并生成流水")
                return true
            } catch {
                guard generation == userStateGeneration else { return false }
                unboundBindingMessage = "本机补绑失败：\(error.localizedDescription)"
                return false
            }
        }
        let result = await resolvedAccountBindingUseCase(monthKey: monthKey).bind(record, accountId: accountId)
        switch result.transaction {
        case .accepted(let accepted):
            unboundRecords.removeAll { $0.id == accepted.recordId && $0.kind == accepted.kind }
            unboundBindingMessage = result.refresh.failureMessage.map { "已补绑账户并生成流水；刷新失败：\($0)" }
                ?? "已补绑账户并生成流水"
            return true
        case .rejected(.unauthenticated):
            unboundBindingMessage = "登录状态已失效，请重新登录"
        case .rejected(.invalidInput):
            unboundBindingMessage = "补绑记录或账户无效"
        case .conflict:
            unboundBindingMessage = "该记录正在使用其他账户补绑"
        case .failed(let message):
            unboundBindingMessage = message
        case .stale:
            return false
        }
        return false
    }

    func batchBindUnboundRecords(
        _ candidates: [NativeUnboundBindingCandidate],
        monthKey: String
    ) async -> Bool {
        guard !isBindingUnboundRecords, !candidates.isEmpty else { return false }
        isBindingUnboundRecords = true
        unboundBindingMessage = nil
        defer { isBindingUnboundRecords = false }
        if !mayReadRemoteBusinessData {
            let generation = userStateGeneration
            var succeeded = 0
            var failures: [String] = []
            var months: Set<String> = []
            for candidate in candidates {
                guard generation == userStateGeneration else { return succeeded > 0 }
                do {
                    try await bindLocalFinancialRecord(candidate.record, accountId: candidate.recommendation.account.id)
                    succeeded += 1
                    months.insert(String(candidate.record.date.prefix(7)))
                } catch { failures.append("\(candidate.record.title)：\(error.localizedDescription)") }
            }
            guard generation == userStateGeneration else { return succeeded > 0 }
            await loadUnboundRecords(monthKey: monthKey)
            await loadLocalAccounts()
            for month in months { await refreshLocalMonthProjection(monthKey: month) }
            guard generation == userStateGeneration else { return succeeded > 0 }
            unboundBindingMessage = localWriteMessage("已补绑 \(succeeded) 条，失败 \(failures.count) 条" + (failures.isEmpty ? "" : "：" + failures.joined(separator: "；")))
            return succeeded > 0
        }
        let result = await resolvedAccountBindingUseCase(monthKey: monthKey).bindBatch(candidates)
        for item in result.items {
            if case .accepted = item.transaction {
                unboundRecords.removeAll { $0.id == item.recordId && $0.kind == item.kind }
            }
        }
        switch result.status {
        case .allSucceeded:
            unboundBindingMessage = "已批量补绑 \(result.successCount) 条记录"
        case .partial:
            unboundBindingMessage = "已补绑 \(result.successCount) 条，\(result.failedCount) 条失败"
        case .failed:
            unboundBindingMessage = "批量补绑失败"
        case .stale:
            return false
        }
        if let message = result.refresh.failureMessage {
            unboundBindingMessage = "\(unboundBindingMessage ?? "已补绑")；刷新失败：\(message)"
        }
        return result.successCount > 0
    }

    private func bindLocalFinancialRecord(_ record: NativeUnboundRecord, accountId: String) async throws {
        let generation = userStateGeneration
        guard let repository = localFinancialBindingRepository,
              let profile = try await localExpenseUseCase?.prepareProfile(),
              let id = UUID(uuidString: record.id), let accountID = UUID(uuidString: accountId) else {
            throw LocalDataError.invalidIdentifier
        }
        guard generation == userStateGeneration else { throw CancellationError() }
        switch record.kind {
        case .expense: try repository.bindExpense(profileID: profile.id, id: id, accountID: accountID)
        case .income: try repository.bindIncome(profileID: profile.id, id: id, accountID: accountID)
        }
    }

    func loadWalletSnapshots() async {
        guard !isLoadingWalletSnapshots else { return }
        let generation = userStateGeneration
        isLoadingWalletSnapshots = true
        walletSnapshotMessage = nil
        defer { isLoadingWalletSnapshots = false }

        if let localWalletSnapshotUseCase {
            do {
                let loaded = try await localWalletSnapshotUseCase.history()
                guard generation == userStateGeneration else { return }
                localWalletSnapshotHistory = loaded
                localWalletSnapshots = loaded.filter { $0.linkedAccountID == nil && $0.deletedAt == nil }
            } catch {
                guard generation == userStateGeneration else { return }
                walletSnapshotMessage = error.localizedDescription
            }
        }
        guard mayReadRemoteBusinessData else {
            walletSnapshots = []
            return
        }
        do {
            let session = try await validSession()
            async let snapshotRows = walletSnapshotRepository.fetchUnlinked(accessToken: session.accessToken)
            async let accountRows = accountRepository.fetchAccounts(accessToken: session.accessToken)
            let (loadedSnapshots, loadedAccounts) = try await (snapshotRows, accountRows)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            walletSnapshots = loadedSnapshots
            accounts = loadedAccounts
        } catch {
            guard generation == userStateGeneration else { return }
            walletSnapshotMessage = error.localizedDescription
        }
    }

    func loadInsights(range: NativeInsightRange, force: Bool = false) async {
        let shouldLoadLocally = !mayReadRemoteBusinessData && localFactReader != nil
        if !force,
           insightsLoadedLocally == shouldLoadLocally,
           insightsSnapshot?.range == range,
           let insightsLoadedAt,
           Date().timeIntervalSince(insightsLoadedAt) < 60 {
            return
        }
        guard !isLoadingInsights else { return }
        let generation = userStateGeneration
        isLoadingInsights = true
        insightsMessage = nil
        defer { isLoadingInsights = false }

        do {
            if !mayReadRemoteBusinessData, let localFactReader {
                let todayKey = NativeLocalDate.dateKey(Date())
                let startKey = NativeLocalDate.shiftedDateKey(todayKey, byDays: -(range.rawValue - 1)) ?? todayKey
                let facts = try await localFactReader.activeRange(from: startKey, to: todayKey)?.facts ?? []
                guard generation == userStateGeneration else { return }
                insightsSnapshot = NativeInsightSnapshot(
                    range: range,
                    rows: LocalInsightAggregator.rows(from: facts)
                )
                aiInsight = nil
                aiInsightIsCached = false
                aiInsightMessage = nil
                insightsLoadedAt = Date()
                insightsLoadedLocally = true
                return
            }
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let snapshot = try await insightsRepository.fetchDailySummary(
                range: range,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            insightsSnapshot = snapshot
            insightsLoadedAt = Date()
            insightsLoadedLocally = false
            Task { await loadLatestAIInsight(range: range, generation: generation, userId: session.user.id) }
        } catch {
            guard generation == userStateGeneration else { return }
            insightsMessage = error.localizedDescription
        }
    }

    func loadLatestAIInsight(
        range: NativeInsightRange,
        generation: Int? = nil,
        userId: String? = nil
    ) async {
        let expectedGeneration = generation ?? userStateGeneration
        do {
            let session = try await validSession()
            let expectedUserId = userId ?? session.user.id
            guard isCurrentUserLoad(expectedGeneration, userId: expectedUserId),
                  session.user.id == expectedUserId else { return }
            let latest = try await insightsRepository.fetchLatestAIInsight(
                range: range,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(expectedGeneration, userId: expectedUserId),
                  insightsSnapshot?.range == range else { return }
            aiInsight = latest
            aiInsightIsCached = latest != nil
            aiInsightMessage = nil
        } catch {
            guard expectedGeneration == userStateGeneration,
                  insightsSnapshot?.range == range else { return }
            aiInsightMessage = nil
        }
    }

    func generateAIInsight(
        range: NativeInsightRange,
        question: String,
        force: Bool = false
    ) async -> Bool {
        guard !isLoadingAIInsight else { return false }
        let generation = userStateGeneration
        let question = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            aiInsightMessage = "请输入你想分析的问题"
            return false
        }
        guard insightsSnapshot?.range == range, insightsSnapshot?.rows.isEmpty == false else {
            aiInsightMessage = "当前范围没有可分析的数据"
            return false
        }

        isLoadingAIInsight = true
        aiInsightMessage = nil
        defer { if generation == userStateGeneration { isLoadingAIInsight = false } }

        do {
            let session = try await validSession()
            let response = try await insightsRepository.generateAIInsight(
                range: range,
                force: force,
                question: question,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id),
                  insightsSnapshot?.range == range else { return false }
            aiInsight = response.insight.scoped(to: range)
            aiInsightIsCached = response.cached
            return true
        } catch {
            guard generation == userStateGeneration else { return false }
            aiInsightMessage = error.localizedDescription
            return false
        }
    }

    func createAccountFromWalletSnapshot(_ snapshot: NativeWalletSnapshot) async -> Bool {
        await performWalletSnapshotAction(
            .create(recordId: snapshot.id),
            snapshot: snapshot
        )
    }

    func linkWalletSnapshot(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount
    ) async -> Bool {
        await performWalletSnapshotAction(
            .link(recordId: snapshot.id, accountId: account.id),
            snapshot: snapshot,
            account: account
        )
    }

    func createLocalAccountFromWalletSnapshot(_ snapshot: LocalWalletSnapshot) async -> Bool {
        await performLocalWalletSnapshotAction(snapshot) {
            try await $0.createAccount(from: snapshot)
        }
    }

    func linkLocalWalletSnapshot(_ snapshot: LocalWalletSnapshot, to accountID: UUID) async -> Bool {
        await performLocalWalletSnapshotAction(snapshot) {
            try await $0.link(snapshot, to: accountID)
        }
    }

    func updateLocalWalletSnapshot(
        _ snapshot: LocalWalletSnapshot,
        title: String,
        summary: String,
        balanceMinor: Int64
    ) async -> Bool {
        await performLocalWalletSnapshotMutation(snapshot, successMessage: "本机快照已更新") {
            try await $0.update(snapshot, title: title, summary: summary, balanceMinor: balanceMinor)
        }
    }

    func deleteLocalWalletSnapshot(_ snapshot: LocalWalletSnapshot) async -> Bool {
        await performLocalWalletSnapshotMutation(snapshot, successMessage: "本机快照已移入删除历史") {
            try await $0.delete(snapshot)
        }
    }

    private func performLocalWalletSnapshotMutation(
        _ snapshot: LocalWalletSnapshot,
        successMessage: String,
        mutation: (LocalWalletSnapshotUseCaseProtocol) async throws -> LocalWalletSnapshot
    ) async -> Bool {
        guard walletSnapshotActionId == nil,
              let localWalletSnapshotUseCase else { return false }
        let actionID = snapshot.id.uuidString
        walletSnapshotActionId = actionID
        walletSnapshotMessage = nil
        defer {
            if walletSnapshotActionId == actionID { walletSnapshotActionId = nil }
        }
        do {
            _ = try await mutation(localWalletSnapshotUseCase)
        } catch {
            walletSnapshotMessage = error.localizedDescription
            return false
        }
        do {
            try await loadLocalWalletSnapshots()
            walletSnapshotMessage = successMessage
        } catch {
            walletSnapshotMessage = "\(successMessage)，但历史刷新失败：\(error.localizedDescription)"
        }
        return true
    }

    private func performLocalWalletSnapshotAction(
        _ snapshot: LocalWalletSnapshot,
        action: (LocalWalletSnapshotUseCaseProtocol) async throws -> LocalWalletSnapshotActionResult
    ) async -> Bool {
        guard walletSnapshotActionId == nil,
              let localWalletSnapshotUseCase else { return false }
        let actionID = snapshot.id.uuidString
        walletSnapshotActionId = actionID
        walletSnapshotMessage = nil
        defer {
            if walletSnapshotActionId == actionID { walletSnapshotActionId = nil }
        }
        do {
            let result = try await action(localWalletSnapshotUseCase)
            let outcomeText: String
            switch result.kind {
            case .created: outcomeText = "已从本机快照创建账户"
            case .linked: outcomeText = "本机快照已关联账户"
            case .replayed: outcomeText = "本机快照关联已存在"
            }
            let confirmationText = result.reviewRequired ? "；账户已关联，账期/还款需要确认" : ""
            var refreshErrors: [String] = []
            do {
                try await loadLocalWalletSnapshots()
            } catch {
                refreshErrors.append("列表刷新失败：\(error.localizedDescription)")
            }
            if mayReadRemoteBusinessData {
                _ = await prepareLocalWorkspace()
            } else {
                await loadLocalAccounts()
            }
            if let localAccountMessage, !localAccountMessage.isEmpty {
                refreshErrors.append("账户刷新失败：\(localAccountMessage)")
            }
            walletSnapshotMessage = ([outcomeText + confirmationText] + refreshErrors).joined(separator: "；")
            return true
        } catch {
            walletSnapshotMessage = error.localizedDescription
            return false
        }
    }

    private func loadLocalWalletSnapshots() async throws {
        guard let localWalletSnapshotUseCase else { return }
        let history = try await localWalletSnapshotUseCase.history()
        localWalletSnapshotHistory = history
        localWalletSnapshots = history.filter { $0.linkedAccountID == nil && $0.deletedAt == nil }
    }

    private func performWalletSnapshotAction(
        _ command: WalletSnapshotActionCommand,
        snapshot: NativeWalletSnapshot,
        account: NativeAccount? = nil
    ) async -> Bool {
        let ownsBusyState = walletSnapshotActionId == nil
        if ownsBusyState {
            walletSnapshotActionId = snapshot.id
            walletSnapshotMessage = nil
        }
        defer {
            if ownsBusyState, walletSnapshotActionId == snapshot.id {
                walletSnapshotActionId = nil
            }
        }

        let result = await resolvedWalletSnapshotActionUseCase().perform(
            command,
            snapshot: snapshot,
            account: account
        )
        return projectWalletSnapshotActionResult(result)
    }

    private func resolvedWalletSnapshotActionUseCase() -> WalletSnapshotActionUseCase {
        if let walletSnapshotActionUseCase { return walletSnapshotActionUseCase }
        let useCase = WalletSnapshotActionUseCase(
            repository: walletSnapshotRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return WalletSnapshotActionUserContext(
                        userId: "",
                        generation: -1,
                        isSignedIn: false
                    )
                }
                return WalletSnapshotActionUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            refresh: { [weak self] in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                try await self.refreshAfterWalletSnapshotLink()
            }
        )
        walletSnapshotActionUseCase = useCase
        return useCase
    }

    private func projectWalletSnapshotActionResult(_ result: WalletSnapshotActionResult) -> Bool {
        switch result.transaction {
        case .accepted(let outcome):
            let successMessage = walletSnapshotSuccessMessage(outcome)
            switch result.refresh {
            case .failed(let message):
                walletSnapshotMessage = "\(successMessage)，但刷新失败：\(message)"
            case .notStarted, .succeeded:
                walletSnapshotMessage = successMessage
            }
            return true
        case .rejected(.unauthenticated):
            walletSnapshotMessage = "登录状态已失效，请重新登录。"
        case .rejected(.invalidInput):
            walletSnapshotMessage = "钱包快照参数无效"
        case .conflict(.walletSnapshotBusy):
            walletSnapshotMessage = "钱包快照正在处理中"
        case .conflict(.walletSnapshotConflict):
            walletSnapshotMessage = "该快照正在执行另一项关联操作"
        case .failed(let message):
            walletSnapshotMessage = message
        case .stale:
            return false
        }
        return false
    }

    private func walletSnapshotSuccessMessage(_ outcome: NativeWalletSnapshotOutcome) -> String {
        switch outcome {
        case .created: return "已从快照创建账户"
        case .linked: return "已关联账户"
        case .replayed: return "快照关联已存在"
        case .needsConfirmation: return "账户已关联，账期/还款需要确认"
        }
    }

    private func refreshAfterWalletSnapshotLink() async throws {
        await loadAccounts()
        if let accountMessage, !accountMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: accountMessage)
        }
        await loadWalletSnapshots()
        if let walletSnapshotMessage, !walletSnapshotMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: walletSnapshotMessage)
        }
        await refreshDashboard()
        if let dashboardMessage, !dashboardMessage.isEmpty {
            throw WalletSnapshotReadModelRefreshError(message: dashboardMessage)
        }
    }

    func openUnboundRecord(_ record: NativeUnboundRecord) {
        presentedOverlay = .records
        recordsPath = NavigationPath([NativeRecordRoute(reference: record.reference)])
    }

    func openWalletSnapshot(_ snapshot: NativeWalletSnapshot) {
        presentedOverlay = .records
        let reference = "data/\(snapshot.id)"
        recordsPath = NavigationPath([NativeRecordRoute(reference: reference)])
    }

    private func refreshAfterAccountBinding(monthKey: String) async throws {
        await loadAccounts()
        await loadUnboundRecords(monthKey: monthKey)
        await refreshDashboard()
        if let message = accountMessage, !message.isEmpty { throw WalletSnapshotReadModelRefreshError(message: message) }
        if let message = unboundRecordsMessage, !message.isEmpty { throw WalletSnapshotReadModelRefreshError(message: message) }
        if let message = dashboardMessage, !message.isEmpty { throw WalletSnapshotReadModelRefreshError(message: message) }
    }

    func prefetchRecordDetails(_ references: [String]) {
        let missing = references
            .map { NativeRecordReference($0).canonicalValue }
            .filter { reference in
                guard !prefetchingRecordReferences.contains(reference) else { return false }
                guard let cached = recordDetailCache[reference] else { return true }
                return cached.imagePath != nil && cached.imageURL == nil && !cached.imageLoadError
            }
            .prefix(4)
        for reference in missing {
            Task { await prefetchRecordDetail(reference: reference) }
        }
    }

    private func prefetchRecordDetail(reference: String) async {
        if let cached = recordDetailCache[reference],
           cached.imagePath == nil || cached.imageURL != nil || cached.imageLoadError {
            return
        }
        guard !prefetchingRecordReferences.contains(reference) else { return }
        let generation = userStateGeneration
        prefetchingRecordReferences.insert(reference)
        defer { prefetchingRecordReferences.remove(reference) }
        do {
            let session = try await validSession()
            let detail = try await recordRepository.fetchDetail(reference: reference, accessToken: session.accessToken)
            guard generation == userStateGeneration,
                  isSignedIn,
                  currentUserId == session.user.id else { return }
            recordDetailCache[reference] = detailPreservingExpressionFeedback(detail)
        } catch {
            return
        }
    }

    func openDayRecord(_ record: NativeDayRecord) {
        if record.reference.hasPrefix("staging-") {
            presentedOverlay = .inbox
            inboxPath = NavigationPath([NativeInboxRoute.staging(recordId: String(record.reference.dropFirst("staging-".count)))])
        } else {
            homePath.append(NativeRecordRoute(reference: record.reference))
        }
    }

    func openDomainDrill(_ domain: AppDomain, dateKey: String) {
        homePath.append(NativeDomainDrillRoute(domain: domain, dateKey: dateKey))
    }

    func openPendingExpense(_ pending: NativePendingExpense) {
        presentedOverlay = .inbox
        // Keep completion inside the inbox queue. The card opens the inline
        // editor, while the queue remains responsible for next-item routing.
        inboxPath = NavigationPath([NativeInboxRoute.category(filter: .pendingExpense)])
    }

    func openInbox(filter: NativeInboxFilter) {
        presentedOverlay = .inbox
        inboxPath = NavigationPath([NativeInboxRoute.category(filter: filter)])
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "jiezi" else { return }
        shouldDeferOnboardingForExternalRoute = true
        isOnboardingPresented = false

        switch url.host {
        case "inbox":
            presentedOverlay = .inbox
        case "records", "record":
            presentedOverlay = .records
        case "settings":
            presentedOverlay = .settings
        default:
            presentedOverlay = .none
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    func handleShortcutNotificationRoute(_ route: String?) {
        shouldDeferOnboardingForExternalRoute = true
        isOnboardingPresented = false
        let parts = (route ?? "")
            .split(separator: "/")
            .map(String.init)
        let target = parts.first
        let detailPath = parts.dropFirst().joined(separator: "/")

        switch target {
        case "inbox":
            presentedOverlay = .inbox
            if !detailPath.isEmpty {
                inboxPath = NavigationPath([NativeInboxRoute.staging(recordId: detailPath)])
            }
        case "records":
            presentedOverlay = .records
            if !detailPath.isEmpty {
                recordsPath = NavigationPath([NativeRecordRoute(reference: detailPath)])
            }
        case "settings":
            presentedOverlay = .settings
        default:
            presentedOverlay = .none
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    @discardableResult
    func discardStagingRecord(
        _ record: NativeStagingRecord,
        preserveInboxNavigation: Bool = false
    ) async -> Bool {
        guard inboxActionRecordId == nil else { return false }
        if let localID = LocalStagingReadModel.localID(from: record.id) {
            return await discardLocalStagingRecord(
                localID,
                record: record,
                preserveInboxNavigation: preserveInboxNavigation
            )
        }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在销毁截图…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        let result = await resolvedStagingLifecycleUseCase().perform(.discard(recordId: record.id))
        switch result.transaction {
        case .accepted:
            if !preserveInboxNavigation { inboxPath = NavigationPath() }
            inboxActionMessage = result.refresh.failureMessage.map {
                "已销毁这条待处理截图，原图将在后台安全清理；刷新失败：\($0)"
            } ?? "已销毁这条待处理截图，原图将在后台安全清理"
            return true
        case .rejected(.unauthenticated):
            inboxActionMessage = "登录状态已失效，请重新登录"
        case .rejected(.invalidInput):
            inboxActionMessage = "待处理截图无效"
        case .conflict:
            inboxActionMessage = "这条待处理截图正在执行其他操作"
        case .failed(let message):
            inboxActionMessage = "销毁失败：\(message)"
        case .stale:
            return false
        }
        inboxActionMessageIsError = true
        return false
    }

    @discardableResult
    func retryStagingRecord(
        _ record: NativeStagingRecord,
        preserveInboxNavigation: Bool = false
    ) async -> Bool {
        guard inboxActionRecordId == nil else { return false }
        if LocalStagingReadModel.localID(from: record.id) != nil {
            inboxActionMessage = "本地候选需重新发起识别"
            inboxActionMessageIsError = true
            return false
        }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在重新识别…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        let result = await resolvedStagingLifecycleUseCase().perform(.retry(recordId: record.id))
        switch result.transaction {
        case .accepted(let accepted):
            let remainsInInbox = dashboard.stagingRecords.contains { $0.id == record.id }
            if !remainsInInbox, !preserveInboxNavigation {
                inboxPath = NavigationPath()
            }
            let actionMessage = remainsInInbox
                ? "重新识别完成，仍需确认或选择归档域"
                : "重新识别成功，记录已自动归档"
            inboxActionMessage = accepted.route?.hasPrefix("inbox") == true
                ? "重新识别完成，仍需确认或选择归档域"
                : actionMessage
            if case .failed(let message) = result.refresh {
                inboxActionMessage = "\(inboxActionMessage ?? actionMessage)；刷新失败：\(message)"
            }
            return true
        case .rejected(.unauthenticated):
            inboxActionMessage = "登录状态已失效，请重新登录"
        case .rejected(.invalidInput):
            inboxActionMessage = "待处理截图无效"
        case .conflict:
            inboxActionMessage = "这条待处理截图正在执行其他操作"
        case .failed(let message):
            inboxActionMessage = "重新识别失败：\(message)"
        case .stale:
            return false
        }
        inboxActionMessageIsError = true
        return false
    }

    @discardableResult
    func archiveStagingRecord(
        _ record: NativeStagingRecord,
        domainKey: String,
        preserveInboxNavigation: Bool = false
    ) async -> String? {
        guard inboxActionRecordId == nil else { return nil }
        if let localID = LocalStagingReadModel.localID(from: record.id) {
            return await archiveLocalStagingRecord(
                localID,
                record: record,
                preserveInboxNavigation: preserveInboxNavigation
            )
        }
        inboxActionRecordId = record.id
        let domainTitle = dashboard.domains.first(where: { $0.id == domainKey })?.shortName
            ?? InboxArchiveDomains.all.first(where: { $0.id == domainKey })?.title
            ?? domainKey
        inboxActionMessage = "正在归档到\(domainTitle)…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        let result = await resolvedStagingLifecycleUseCase().perform(
            .archive(record: record, domainKey: domainKey)
        )
        switch result.transaction {
        case .accepted(let accepted):
            if !preserveInboxNavigation { inboxPath = NavigationPath() }
            inboxActionMessage = result.refresh.failureMessage.map {
                "已归档到\(domainTitle)；刷新失败：\($0)"
            } ?? "已归档到\(domainTitle)"
            return accepted.targetReference
        case .rejected(.unauthenticated):
            inboxActionMessage = "登录状态已失效，请重新登录"
        case .rejected(.invalidInput):
            inboxActionMessage = "待处理截图或归档域无效"
        case .conflict:
            inboxActionMessage = "这条待处理截图正在执行其他操作"
        case .failed(let message):
            inboxActionMessage = "归档失败：\(message)"
        case .stale:
            return nil
        }
        inboxActionMessageIsError = true
        return nil
    }

    @discardableResult
    func archiveStagingRecord(
        _ record: NativeStagingRecord,
        draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?,
        preserveInboxNavigation: Bool = false
    ) async -> String? {
        let adjustedRecord = record.applyingArchiveDraft(draft, domain: domain)
        if let localID = LocalStagingReadModel.localID(from: record.id) {
            guard inboxActionRecordId == nil else { return nil }
            let changes = LocalStagingConfirmation(
                domainKey: draft.domainKey, title: draft.resolvedTitle(domain: domain),
                summary: draft.resolvedSummary(domain: domain), payload: draft.universalPayload(domain: domain),
                recordDate: draft.dateKey, recordTime: draft.timeKey,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note
            )
            return await archiveLocalStagingRecord(
                localID, record: adjustedRecord, preserveInboxNavigation: preserveInboxNavigation, changes: changes
            )
        }
        return await archiveStagingRecord(
            adjustedRecord,
            domainKey: draft.domainKey,
            preserveInboxNavigation: preserveInboxNavigation
        )
    }

    private func discardLocalStagingRecord(
        _ localID: String,
        record: NativeStagingRecord,
        preserveInboxNavigation: Bool
    ) async -> Bool {
        guard let localRecordUseCase else { return false }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在销毁本地候选…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        do {
            try await localRecordUseCase.discardStaging(id: localID)
            removeStagingRecordLocally(record.id)
            if !preserveInboxNavigation { inboxPath = NavigationPath() }
            inboxActionMessage = "已销毁本地候选，原图已清理"
            return true
        } catch {
            inboxActionMessage = "销毁失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
            return false
        }
    }

    private func archiveLocalStagingRecord(
        _ localID: String,
        record: NativeStagingRecord,
        preserveInboxNavigation: Bool,
        changes: LocalStagingConfirmation? = nil
    ) async -> String? {
        guard let localRecordUseCase else { return nil }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在归档本地候选…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        do {
            let outcome = try await localRecordUseCase.confirmStaging(
                id: localID,
                recordID: UUID(),
                changes: changes
            )
            removeStagingRecordLocally(record.id)
            let monthKey = String(outcome.record.recordDate.prefix(7))
            await refreshLocalMonthProjection(monthKey: monthKey)
            if !preserveInboxNavigation { inboxPath = NavigationPath() }
            inboxActionMessage = "已归档到\(record.domainName ?? "本地记录")"
            return "local-data/\(outcome.record.id.uuidString)"
        } catch {
            inboxActionMessage = "归档失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
            return nil
        }
    }

    private func removeStagingRecordLocally(_ recordId: String) {
        stagingReadVersion += 1
        dashboard.stagingRecords.removeAll { $0.id == recordId }
        dashboard.pendingCount = dashboard.pendingExpenses.count + dashboard.stagingRecords.count
    }

    private func resolvedStagingLifecycleUseCase() -> StagingLifecycleUseCase {
        if let stagingLifecycleUseCase { return stagingLifecycleUseCase }
        let useCase = StagingLifecycleUseCase(
            repository: inboxRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else { throw SupabaseRemoteError.requestFailed("会话已失效") }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return StagingLifecycleUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return StagingLifecycleUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            applyAccepted: { [weak self] accepted in
                guard let self else { return }
                if accepted.action == .discard || accepted.action == .archive {
                    self.removeStagingRecordLocally(accepted.recordId)
                }
            },
            refresh: { [weak self] in
                guard let self else { return }
                await self.refreshAfterRecordWrite()
                if let message = self.dashboardMessage, !message.isEmpty {
                    throw WalletSnapshotReadModelRefreshError(message: message)
                }
            }
        )
        stagingLifecycleUseCase = useCase
        return useCase
    }

    private func resolvedPendingConfirmationUseCase() -> PendingConfirmationUseCase {
        if let pendingConfirmationUseCase { return pendingConfirmationUseCase }
        let useCase = PendingConfirmationUseCase(
            repository: inboxRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else { throw SupabaseRemoteError.requestFailed("会话已失效") }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return PendingConfirmationUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return PendingConfirmationUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            },
            applyAccepted: { [weak self] accepted in
                self?.invalidateRecordExpressionPlanState(
                    afterChanging: ["expense/\(accepted.pendingId)", accepted.recordReference]
                )
            },
            refresh: { [weak self] in
                guard let self else { return }
                await self.loadAccounts()
                if let message = self.accountMessage, !message.isEmpty {
                    throw WalletSnapshotReadModelRefreshError(message: message)
                }
                await self.refreshAfterRecordWrite()
                if let message = self.dashboardMessage, !message.isEmpty {
                    throw WalletSnapshotReadModelRefreshError(message: message)
                }
            }
        )
        pendingConfirmationUseCase = useCase
        return useCase
    }

    func resolveStagingImageURL(for record: NativeStagingRecord) async throws -> URL {
        guard let imagePath = record.imagePath, !imagePath.isEmpty else {
            throw SupabaseRemoteError.requestFailed("这条记录没有可查看的截图")
        }
        let session = try await validSession()
        return try await inboxRepository.resolveImageURL(path: imagePath, accessToken: session.accessToken)
    }

    private func loadRemoteRecordDetail(
        reference canonicalReference: String,
        force: Bool,
        generation: Int
    ) async {
        if !force, let cached = recordDetailCache[canonicalReference] {
            selectedRecordDetail = cached
            if let session = try? await validSession() {
                hydrateRecordDetailImageIfNeeded(cached, reference: canonicalReference, session: session, generation: generation)
                await prepareRecordExpressionPlan(
                    for: cached,
                    canonicalReference: canonicalReference,
                    session: session,
                    generation: generation
                )
            }
            return
        }
        if selectedRecordDetail.map({ !NativeRecordReference($0.id).matchesReference(canonicalReference) }) ?? true {
            selectedRecordDetail = nil
        }
        do {
            let session = try await validSession()
            let detail = try await recordRepository.fetchDetail(reference: canonicalReference, accessToken: session.accessToken)
            guard generation == userStateGeneration,
                  isSignedIn,
                  currentUserId == session.user.id else { return }
            let mergedDetail = detailPreservingExpressionFeedback(detail)
            recordDetailCache[canonicalReference] = mergedDetail
            guard activeRecordReference == canonicalReference else { return }
            selectedRecordDetail = mergedDetail
            hydrateRecordDetailImageIfNeeded(mergedDetail, reference: canonicalReference, session: session, generation: generation)
            await prepareRecordExpressionPlan(
                for: mergedDetail,
                canonicalReference: canonicalReference,
                session: session,
                generation: generation
            )
        } catch {
            if activeRecordReference == canonicalReference {
                recordDetailMessage = error.localizedDescription
            }
        }
    }

    func loadRecordDetail(reference: String, force: Bool = false) async {
        let parsedReference = NativeRecordReference(reference)
        let canonicalReference = parsedReference.canonicalValue
        let generation = userStateGeneration
        if let previousReference = activeRecordReference,
           previousReference != canonicalReference {
            deactivateRecordDetail(reference: previousReference)
        }
        activeRecordReference = canonicalReference
        recordDetailMessage = nil
        if parsedReference.kind == "expense", let repository = localPendingFinancialRepository, let imageStore = localImageStore,
           let profile = try? await localExpenseUseCase?.prepareProfile(),
           let id = UUID(uuidString: parsedReference.rawId),
           let detail = try? repository.nativeDetail(profileID: profile.id, id: id, imageStore: imageStore) {
            selectedRecordDetail = detail
            return
        }
        if selectedRecordDetail.map({ !NativeRecordReference($0.id).matchesReference(canonicalReference) }) ?? true {
            recordFeedbackState = .idle
            recordExpressionPlanExposureState = .idle
        }
        if parsedReference.kind == "local-expense"
            || (parsedReference.kind == "expense" && isKnownLocalFactReference(reference)) {
            await loadLocalExpenseDetail(reference: reference, force: force, generation: generation)
            return
        }
        if parsedReference.kind == "local-income" {
            await loadLocalIncomeDetail(reference: reference, force: force, generation: generation)
            return
        }
        if parsedReference.kind == "local-data"
            || (parsedReference.kind == "data" && isKnownLocalFactReference(reference)) {
            await loadLocalDomainDetail(reference: reference, force: force, generation: generation)
            return
        }
        if parsedReference.kind == "data", await hasLocalDomainRecord(reference: reference) {
            await loadLocalDomainDetail(reference: reference, force: force, generation: generation)
            return
        }
        if parsedReference.kind == "expense", await hasLocalExpense(reference: reference) {
            await loadLocalExpenseDetail(reference: reference, force: force, generation: generation)
            return
        }
        if parsedReference.kind == "income", await hasLocalIncome(reference: reference) {
            await loadLocalIncomeDetail(reference: reference, force: force, generation: generation)
            return
        }
        guard mayReadRemoteBusinessData else {
            selectedRecordDetail = nil
            recordDetailMessage = "本机没有这条记录，未授权的云端读取已停止。"
            return
        }
        await loadRemoteRecordDetail(reference: canonicalReference, force: force, generation: generation)
    }

    private func hasLocalDomainRecord(reference: String) async -> Bool {
        guard let localRecordUseCase,
              let id = UUID(uuidString: NativeRecordReference(reference).rawId) else {
            return false
        }
        do {
            return try await localRecordUseCase.record(id: id) != nil
        } catch {
            return false
        }
    }

    private func hasLocalExpense(reference: String) async -> Bool {
        guard let localExpenseUseCase,
              let id = UUID(uuidString: NativeRecordReference(reference).rawId) else {
            return false
        }
        do {
            return try await localExpenseUseCase.expense(id: id) != nil
        } catch {
            return false
        }
    }

    private func hasLocalIncome(reference: String) async -> Bool {
        guard let localExpenseUseCase,
              let id = UUID(uuidString: NativeRecordReference(reference).rawId) else { return false }
        return (try? await localExpenseUseCase.income(id: id)) != nil
    }

    private func isLocalIncomeReference(_ reference: String) -> Bool {
        let parsed = NativeRecordReference(reference)
        return parsed.kind == "local-income"
            || (parsed.kind == "income" && isKnownLocalFactReference(reference))
    }

    private func isLocalExpenseReference(_ reference: String) -> Bool {
        let parsed = NativeRecordReference(reference)
        return parsed.kind == "local-expense"
            || (parsed.kind == "expense" && isKnownLocalFactReference(reference))
    }

    private func loadLocalIncomeDetail(reference: String, force: Bool, generation: Int) async {
        guard let localExpenseUseCase,
              let id = UUID(uuidString: NativeRecordReference(reference).rawId) else {
            recordDetailMessage = "本地收入记录不可用"
            return
        }
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        if !force, let cached = recordDetailCache[canonicalReference] {
            selectedRecordDetail = cached
            return
        }
        do {
            guard let income = try await localExpenseUseCase.income(id: id) else { throw LocalDataError.recordNotFound }
            guard generation == userStateGeneration, activeRecordReference == canonicalReference else { return }
            var detail = LocalIncomeReadModel.detail(from: income)
            if let path = income.imagePath { detail.imageURL = localImageStore?.url(for: path) }
            recordDetailCache[canonicalReference] = detail
            selectedRecordDetail = detail
        } catch {
            if activeRecordReference == canonicalReference { recordDetailMessage = error.localizedDescription }
        }
    }

    private func isLocalDomainReference(_ reference: String) -> Bool {
        let parsed = NativeRecordReference(reference)
        return parsed.kind == "local-data"
            || (parsed.kind == "data" && isKnownLocalFactReference(reference))
    }

    private func isKnownLocalFactReference(_ reference: String) -> Bool {
        let canonical = NativeRecordReference(reference).canonicalValue
        if localRecordMonthDetails.values.contains(where: { details in
            details.keys.contains { NativeRecordReference($0).canonicalValue == canonical }
        }) {
            return true
        }
        return localFactMonths.values.contains { month in
            month.facts.contains { NativeRecordReference($0.reference).canonicalValue == canonical }
        }
    }

    private func loadLocalExpenseDetail(
        reference: String,
        force: Bool,
        generation: Int
    ) async {
        guard let localExpenseUseCase else {
            recordDetailMessage = "本地数据不可用"
            return
        }
        let resolved = NativeRecordReference(reference)
        guard let id = UUID(uuidString: resolved.rawId) else {
            recordDetailMessage = "本地记录标识无效"
            return
        }
        let canonicalReference = resolved.canonicalValue
        if !force, let cached = recordDetailCache[canonicalReference] {
            selectedRecordDetail = cached
            return
        }
        if selectedRecordDetail.map({ !NativeRecordReference($0.id).matchesReference(canonicalReference) }) ?? true {
            selectedRecordDetail = nil
        }
        do {
            guard let expense = try await localExpenseUseCase.expense(id: id) else {
                throw LocalDataError.recordNotFound
            }
            guard generation == userStateGeneration,
                  activeRecordReference == canonicalReference else { return }
            var detail = LocalExpenseReadModel.detail(from: expense)
            if let path = expense.imagePath { detail.imageURL = localImageStore?.url(for: path) }
            recordDetailCache[canonicalReference] = detail
            selectedRecordDetail = detail
        } catch {
            if activeRecordReference == canonicalReference {
                recordDetailMessage = error.localizedDescription
            }
        }
    }

    private func loadLocalDomainDetail(
        reference: String,
        force: Bool,
        generation: Int
    ) async {
        guard let localRecordUseCase else {
            recordDetailMessage = "本地数据不可用"
            return
        }
        let resolved = NativeRecordReference(reference)
        guard let id = UUID(uuidString: resolved.rawId) else {
            recordDetailMessage = "本地记录标识无效"
            return
        }
        let canonicalReference = resolved.canonicalValue
        if !force, let cached = recordDetailCache[canonicalReference] {
            selectedRecordDetail = cached
            return
        }
        if selectedRecordDetail.map({ !NativeRecordReference($0.id).matchesReference(canonicalReference) }) ?? true {
            selectedRecordDetail = nil
        }
        do {
            guard let record = try await localRecordUseCase.record(id: id) else {
                throw LocalDataError.recordNotFound
            }
            guard generation == userStateGeneration,
                  activeRecordReference == canonicalReference else { return }
            let detail = LocalRecordReadModel.detail(from: record, imageStore: localImageStore)
            recordDetailCache[canonicalReference] = detail
            selectedRecordDetail = detail
        } catch {
            if activeRecordReference == canonicalReference {
                recordDetailMessage = error.localizedDescription
            }
        }
    }

    private func hydrateRecordDetailImageIfNeeded(
        _ detail: NativeRecordDetail,
        reference: String,
        session: SupabaseAuthSession?,
        generation: Int
    ) {
        guard detail.imagePath != nil, detail.imageURL == nil, let session else { return }
        Task { [weak self] in
            guard let self else { return }
            let useCase = self.resolvedRecordDetailImageUseCase()
            let result = await useCase.perform(detail, reference: reference)
            switch result.transaction {
            case .hydrated:
                guard let hydrated = result.detail else { return }
                let mergedDetail = self.detailPreservingExpressionFeedback(hydrated)
                self.recordDetailCache[reference] = mergedDetail
                if self.selectedRecordDetail?.id == hydrated.id {
                    self.selectedRecordDetail = mergedDetail
                }
            case .failed:
                var failedDetail = detail
                failedDetail.imageLoadError = true
                let mergedDetail = self.detailPreservingExpressionFeedback(failedDetail)
                guard self.userStateGeneration == generation,
                      self.activeRecordReference == reference,
                      self.isSignedIn,
                      self.currentUserId == session.user.id else { return }
                self.recordDetailCache[reference] = mergedDetail
                if self.selectedRecordDetail?.id == detail.id {
                    self.selectedRecordDetail = mergedDetail
                }
            case .notNeeded, .stale:
                return
            }
        }
    }

    private func resolvedRecordDetailImageUseCase() -> RecordDetailImageUseCase {
        if let recordDetailImageUseCase { return recordDetailImageUseCase }
        let useCase = RecordDetailImageUseCase(
            repository: recordRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return RecordDetailImageUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return RecordDetailImageUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn,
                    activeRecordReference: self.activeRecordReference
                )
            }
        )
        recordDetailImageUseCase = useCase
        return useCase
    }

    func thumbnailImageURL(for record: NativeDayRecord, force: Bool = false) async -> URL? {
        let generation = userStateGeneration
        let reference = NativeRecordReference(record.reference).canonicalValue
        let month = String(record.dateKey.prefix(7))
        func isListed() -> Bool {
            recordGroups(monthKey: month).flatMap(\.records).contains {
                NativeRecordReference($0.reference).canonicalValue == reference
            }
        }
        func currentDetail() -> NativeRecordDetail? {
            let values = recordDetails(from: record.dateKey, through: record.dateKey)
            return values[reference] ?? values[record.reference]
        }
        guard isListed() else { return nil }
        if isLocalDomainReference(record.reference) {
            if force { await refreshLocalMonthProjection(monthKey: month) }
            guard generation == userStateGeneration, isListed() else { return nil }
            return currentDetail()?.imageURL
        }
        guard var detail = currentDetail() else { return nil }
        if !force, let url = detail.imageURL { return url }
        if force { detail.imageURL = nil }
        if thumbnailImageUseCase == nil {
            thumbnailImageUseCase = RecordDetailImageUseCase(
                repository: recordRepository,
                sessionProvider: { [weak self] forceRefresh in
                    guard let self else { throw SupabaseRemoteError.requestFailed("app_state_unavailable") }
                    return try await self.validSession(forceRefresh: forceRefresh)
                },
                contextProvider: { [weak self] in
                    RecordDetailImageUserContext(userId: self?.currentUserId ?? "", generation: self?.userStateGeneration ?? -1,
                                                 isSignedIn: self?.isSignedIn ?? false)
                }
            )
        }
        guard let useCase = thumbnailImageUseCase else { return nil }
        let result = await useCase.perform(detail, reference: reference)
        guard generation == userStateGeneration, isListed(), currentDetail()?.imagePath == detail.imagePath else { return nil }
        return result.detail?.imageURL
    }

    private func prepareRecordExpressionPlan(
        for detail: NativeRecordDetail,
        canonicalReference: String,
        session: SupabaseAuthSession,
        generation: Int
    ) async {
        var currentDetail = detail
        if let pending = pendingRecordExpressionPlans[canonicalReference],
           pending.plan.feedback.isCompanionMessageDelivery,
           !pending.plan.feedback.matchesVisibleCompanionMessage(detail.companionMessage) {
            discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
            if currentDetail.aiFeedback == pending.plan.feedback {
                currentDetail.aiFeedback = pending.previousFeedback
                currentDetail.plannerAiFeedback = nil
            }
        }
        var baseDetail = detailPreservingExpressionFeedback(currentDetail)
        let selectedFeedback = selectedRecordDetail.flatMap { selected -> NativeAIFeedback? in
            NativeRecordReference(selected.id).canonicalValue == canonicalReference
                ? selected.aiFeedback
                : nil
        }
        baseDetail.aiFeedback = NativeRecordExpressionFeedbackPolicy.feedbackToPreserve(
            existing: [
                baseDetail.aiFeedback,
                recordDetailCache[canonicalReference]?.aiFeedback,
                selectedFeedback
            ],
            pending: nil
        )
        guard !NativeRecordExpressionFeedbackPolicy.hasAcknowledgedPlannerFeedback([
            baseDetail.aiFeedback,
            recordDetailCache[canonicalReference]?.aiFeedback,
            selectedFeedback
        ]) else {
            publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            return
        }

        if let pending = pendingRecordExpressionPlans[canonicalReference],
           pending.userId == session.user.id,
           pending.generation == generation {
            let selected = NativeRecordExpressionFeedbackPolicy.plannerFeedbackToDisplayWithoutReplacingVoice(
                existingVoice: baseDetail.voiceAiFeedback,
                plannerPreview: pending.plan.feedback,
                companionMessage: baseDetail.companionMessage
            )
            let plannerIsIndependentCard = pending.plan.feedback.presentationTarget == "feedback_card"
            if !plannerIsIndependentCard, selected != pending.plan.feedback {
                discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
                baseDetail.aiFeedback = selected
                publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            } else {
                baseDetail.aiFeedback = selected
                baseDetail.plannerAiFeedback = pending.plan.feedback
                publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            }
            return
        }
        guard expressionPlanDeliveryTokens[canonicalReference] == nil else { return }
        let deliveryToken = UUID()
        expressionPlanDeliveryTokens[canonicalReference] = deliveryToken
        defer {
            if expressionPlanDeliveryTokens[canonicalReference] == deliveryToken {
                expressionPlanDeliveryTokens.removeValue(forKey: canonicalReference)
            }
        }

        guard let preview = await NativeRecordExpressionPlanRetryPolicy.resolve(
            fetch: {
                try await self.recordRepository.getRecordExpressionPlan(
                    reference: detail.id,
                    accessToken: session.accessToken
                )
            },
            shouldContinue: {
                self.expressionPlanDeliveryTokens[canonicalReference] == deliveryToken
                    && self.isCurrentExpressionPlanDelivery(
                    canonicalReference: canonicalReference,
                    session: session,
                    generation: generation
                )
            }
        ) else {
            if isCurrentExpressionPlanDelivery(
                canonicalReference: canonicalReference,
                session: session,
                generation: generation
            ) {
                publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            }
            return
        }

        guard !Task.isCancelled,
              expressionPlanDeliveryTokens[canonicalReference] == deliveryToken,
              generation == userStateGeneration,
              isSignedIn,
              currentUserId == session.user.id,
              activeRecordReference == canonicalReference else { return }

        guard !NativeRecordExpressionFeedbackPolicy.hasAcknowledgedPlannerFeedback([
            baseDetail.aiFeedback,
            recordDetailCache[canonicalReference]?.aiFeedback
        ]) else {
            publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            return
        }

        let previousFeedback = NativeRecordExpressionFeedbackPolicy.feedbackToPreserve(
            existing: [
                baseDetail.aiFeedback,
                recordDetailCache[canonicalReference]?.aiFeedback
            ],
            pending: nil
        )
        let selected = NativeRecordExpressionFeedbackPolicy.plannerFeedbackToDisplayWithoutReplacingVoice(
            existingVoice: baseDetail.voiceAiFeedback ?? previousFeedback,
            plannerPreview: preview.feedback,
            companionMessage: baseDetail.companionMessage
        )
        baseDetail.aiFeedback = selected
        let plannerIsIndependentCard = preview.feedback.presentationTarget == "feedback_card"
        if selected == preview.feedback || plannerIsIndependentCard {
            baseDetail.plannerAiFeedback = preview.feedback
        }
        guard selected == preview.feedback || plannerIsIndependentCard else {
            publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
            recordExpressionPlanExposureState = .idle
            return
        }

        pendingRecordExpressionPlans[canonicalReference] = PendingRecordExpressionPlanDelivery(
            id: UUID(),
            recordId: detail.rawId,
            plan: preview,
            previousFeedback: previousFeedback,
            userId: session.user.id,
            generation: generation
        )
        publishResolvedRecordDetail(baseDetail, canonicalReference: canonicalReference)
        recordFeedbackState = .idle
        recordExpressionPlanExposureState = .idle
    }

    private func publishResolvedRecordDetail(
        _ detail: NativeRecordDetail,
        canonicalReference: String
    ) {
        let synchronized = synchronizeAIFeedbackSlots(detail)
        recordDetailCache[canonicalReference] = synchronized
        guard activeRecordReference == canonicalReference else { return }
        selectedRecordDetail = synchronized
    }

    func setRecordExpressionPlanCardVisible(
        _ isVisible: Bool,
        reference: String,
        feedbackIdentity: String? = nil
    ) {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        let identity = feedbackIdentity ?? selectedRecordDetail.flatMap { detail -> String? in
            guard NativeRecordReference(detail.id).canonicalValue == canonicalReference else { return nil }
            return detail.aiFeedback?.renderIdentity
        }
        if isVisible {
            guard let identity else { return }
            visibleRecordExpressionPlanCards[canonicalReference] = identity
        } else if feedbackIdentity == nil
                    || visibleRecordExpressionPlanCards[canonicalReference] == feedbackIdentity {
            visibleRecordExpressionPlanCards.removeValue(forKey: canonicalReference)
        }
    }

    func isRecordExpressionPlanCardVisible(
        reference: String,
        feedbackIdentity: String? = nil
    ) -> Bool {
        let visibleIdentity = visibleRecordExpressionPlanCards[
            NativeRecordReference(reference).canonicalValue
        ]
        if let feedbackIdentity {
            return visibleIdentity == feedbackIdentity
        }
        return visibleIdentity != nil
    }

    func acknowledgeRecordExpressionPlanIfVisible(reference: String) async {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        guard let pending = pendingRecordExpressionPlans[canonicalReference] else { return }
        guard expressionPlanAcknowledgementTokens[canonicalReference] == nil else { return }
        guard isPendingExpressionPlanActive(
            pending,
            canonicalReference: canonicalReference
        ) else {
            discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
            return
        }
        guard !Task.isCancelled,
              visibleRecordExpressionPlanCards[canonicalReference]
                == pending.plan.feedback.renderIdentity else { return }

        let acknowledgementToken = UUID()
        expressionPlanAcknowledgementTokens[canonicalReference] = acknowledgementToken
        recordExpressionPlanExposureState = .acknowledging
        defer {
            if expressionPlanAcknowledgementTokens[canonicalReference] == acknowledgementToken {
                expressionPlanAcknowledgementTokens.removeValue(forKey: canonicalReference)
            }
        }

        let session: SupabaseAuthSession
        do {
            session = try await validSession()
        } catch {
            handleExpressionPlanAcknowledgementFailure(
                pending,
                canonicalReference: canonicalReference
            )
            return
        }
        guard session.user.id == pending.userId,
              isPendingExpressionPlanActive(
                pending,
                canonicalReference: canonicalReference
              ) else {
            discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
            return
        }

        guard let acknowledgedFeedback = await NativeRecordExpressionPlanAcknowledgementRetryPolicy.resolve(
            acknowledge: {
                try await self.recordRepository.acknowledgeRecordExpressionPlan(
                    recordId: pending.recordId,
                    planToken: pending.plan.planToken,
                    candidateId: pending.plan.candidateId,
                    accessToken: session.accessToken
                )
            },
            shouldContinue: {
                !Task.isCancelled
                    && self.isPendingExpressionPlanActive(
                        pending,
                        canonicalReference: canonicalReference
                    )
            },
            sleep: expressionPlanAcknowledgementSleep
        ) else {
            handleExpressionPlanAcknowledgementFailure(
                pending,
                canonicalReference: canonicalReference
            )
            return
        }

        guard expressionPlanAcknowledgementTokens[canonicalReference] == acknowledgementToken,
              isPendingExpressionPlanActive(
            pending,
            canonicalReference: canonicalReference
        ) else { return }
        guard pending.plan.feedback.hasSameDeliveryIdentity(as: acknowledgedFeedback) else {
            handleExpressionPlanAcknowledgementFailure(
                pending,
                canonicalReference: canonicalReference
            )
            return
        }
        if pendingRecordExpressionPlans[canonicalReference]?.id == pending.id {
            pendingRecordExpressionPlans.removeValue(forKey: canonicalReference)
        }
        guard var finalDetail = recordDetailCache[canonicalReference] else { return }
        finalDetail.plannerAiFeedback = acknowledgedFeedback
        finalDetail.aiFeedback = acknowledgedFeedback.presentationTarget == "feedback_card"
            ? (finalDetail.voiceAiFeedback ?? acknowledgedFeedback)
            : acknowledgedFeedback
        recordDetailCache[canonicalReference] = finalDetail
        if activeRecordReference == canonicalReference,
           selectedRecordDetail.map({ NativeRecordReference($0.id).canonicalValue == canonicalReference }) == true {
            selectedRecordDetail = finalDetail
            recordFeedbackState = .idle
            recordExpressionPlanExposureState = .idle
        }
    }

    private func restoreUnacknowledgedExpressionPreview(
        _ previewFeedback: NativeAIFeedback,
        previousFeedback: NativeAIFeedback?,
        canonicalReference: String
    ) {
        if var cached = recordDetailCache[canonicalReference],
           cached.aiFeedback == previewFeedback || cached.plannerAiFeedback == previewFeedback {
            if cached.aiFeedback == previewFeedback {
                cached.aiFeedback = previousFeedback
            }
            if cached.plannerAiFeedback == previewFeedback {
                cached.plannerAiFeedback = nil
            }
            recordDetailCache[canonicalReference] = cached
        }
        if activeRecordReference == canonicalReference,
           var selected = selectedRecordDetail,
           selected.aiFeedback == previewFeedback || selected.plannerAiFeedback == previewFeedback {
            if selected.aiFeedback == previewFeedback {
                selected.aiFeedback = previousFeedback
            }
            if selected.plannerAiFeedback == previewFeedback {
                selected.plannerAiFeedback = nil
            }
            selectedRecordDetail = selected
        }
    }

    private func isPendingExpressionPlanActive(
        _ pending: PendingRecordExpressionPlanDelivery,
        canonicalReference: String
    ) -> Bool {
        pendingRecordExpressionPlans[canonicalReference]?.id == pending.id
            && pending.generation == userStateGeneration
            && isSignedIn
            && currentUserId == pending.userId
            && activeRecordReference == canonicalReference
            && selectedRecordDetail.map {
                guard NativeRecordReference($0.id).canonicalValue == canonicalReference else { return false }
                if pending.plan.feedback.presentationTarget == "feedback_card" {
                    return $0.plannerAiFeedback == pending.plan.feedback
                }
                return $0.aiFeedback == pending.plan.feedback
            } == true
    }

    private func handleExpressionPlanAcknowledgementFailure(
        _ pending: PendingRecordExpressionPlanDelivery,
        canonicalReference: String
    ) {
        guard isPendingExpressionPlanActive(
            pending,
            canonicalReference: canonicalReference
        ) else {
            discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
            return
        }
        recordExpressionPlanExposureState = .failed
    }

    private func discardPendingExpressionPlan(
        _ pending: PendingRecordExpressionPlanDelivery,
        canonicalReference: String
    ) {
        guard pendingRecordExpressionPlans[canonicalReference]?.id == pending.id else { return }
        pendingRecordExpressionPlans.removeValue(forKey: canonicalReference)
        expressionPlanAcknowledgementTokens.removeValue(forKey: canonicalReference)
        visibleRecordExpressionPlanCards.removeValue(forKey: canonicalReference)
        restoreUnacknowledgedExpressionPreview(
            pending.plan.feedback,
            previousFeedback: pending.previousFeedback,
            canonicalReference: canonicalReference
        )
        if activeRecordReference == canonicalReference {
            recordExpressionPlanExposureState = .idle
        }
    }

    private func isCurrentExpressionPlanDelivery(
        canonicalReference: String,
        session: SupabaseAuthSession,
        generation: Int
    ) -> Bool {
        !Task.isCancelled
            && generation == userStateGeneration
            && isSignedIn
            && currentUserId == session.user.id
            && activeRecordReference == canonicalReference
    }

    private func detailPreservingExpressionFeedback(
        _ detail: NativeRecordDetail
    ) -> NativeRecordDetail {
        let synchronizedDetail = synchronizeAIFeedbackSlots(detail)
        let canonicalReference = NativeRecordReference(synchronizedDetail.id).canonicalValue
        let selectedFeedback = selectedRecordDetail.flatMap { selected -> NativeAIFeedback? in
            NativeRecordReference(selected.id).canonicalValue == canonicalReference
                ? selected.aiFeedback
                : nil
        }
        guard let feedback = NativeRecordExpressionFeedbackPolicy.feedbackToPreserve(
            existing: [selectedFeedback, recordDetailCache[canonicalReference]?.aiFeedback],
            pending: pendingRecordExpressionPlans[canonicalReference]?.plan.feedback,
            companionMessage: synchronizedDetail.companionMessage
        ) else { return synchronizedDetail }
        var preserved = synchronizedDetail
        preserved.aiFeedback = feedback
        return synchronizeAIFeedbackSlots(preserved)
    }

    private func synchronizeAIFeedbackSlots(
        _ detail: NativeRecordDetail
    ) -> NativeRecordDetail {
        var synchronized = detail
        guard let feedback = synchronized.aiFeedback else { return synchronized }
        if feedback.source == "expression_planner" {
            synchronized.plannerAiFeedback = feedback
        } else if synchronized.legacyAiFeedback == nil {
            synchronized.legacyAiFeedback = feedback
        }
        return synchronized
    }

    func recordDetail(matching reference: String) -> NativeRecordDetail? {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        guard let detail = selectedRecordDetail,
              NativeRecordReference(detail.id).canonicalValue == canonicalReference else { return nil }
        return detail
    }

    func deactivateRecordDetail(reference: String) {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        guard activeRecordReference == canonicalReference else { return }
        if let pending = pendingRecordExpressionPlans[canonicalReference] {
            discardPendingExpressionPlan(pending, canonicalReference: canonicalReference)
        }
        expressionPlanDeliveryTokens.removeValue(forKey: canonicalReference)
        expressionPlanAcknowledgementTokens.removeValue(forKey: canonicalReference)
        visibleRecordExpressionPlanCards.removeValue(forKey: canonicalReference)
        activeRecordReference = nil
        selectedRecordDetail = nil
        recordFeedbackState = .idle
        recordExpressionPlanExposureState = .idle
    }

    func invalidateRecordExpressionPlanState(afterChanging references: [String]) {
        let canonicalReferences = Set(references.map { NativeRecordReference($0).canonicalValue })
        for canonicalReference in canonicalReferences {
            pendingRecordExpressionPlans.removeValue(forKey: canonicalReference)
            expressionPlanDeliveryTokens.removeValue(forKey: canonicalReference)
            expressionPlanAcknowledgementTokens.removeValue(forKey: canonicalReference)
            visibleRecordExpressionPlanCards.removeValue(forKey: canonicalReference)
            recordDetailCache.removeValue(forKey: canonicalReference)
        }
        if let selectedReference = selectedRecordDetail.map({
            NativeRecordReference($0.id).canonicalValue
        }), canonicalReferences.contains(selectedReference) {
            selectedRecordDetail = nil
        }
        if let activeRecordReference, canonicalReferences.contains(activeRecordReference) {
            self.activeRecordReference = nil
            recordFeedbackState = .idle
            recordExpressionPlanExposureState = .idle
        }
    }

    private func localExpenseForReference(_ reference: String) async throws -> LocalExpense {
        guard let localExpenseUseCase else { throw LocalDataError.invalidRecord }
        let resolved = NativeRecordReference(reference)
        guard resolved.kind == "local-expense" || resolved.kind == "expense",
              let id = UUID(uuidString: resolved.rawId) else {
            throw LocalDataError.invalidIdentifier
        }
        guard let expense = try await localExpenseUseCase.expense(id: id) else {
            throw LocalDataError.recordNotFound
        }
        return expense
    }

    private func saveLocalRecordDetail(_ draft: NativeRecordEditDraft) async throws -> Bool {
        guard let localExpenseUseCase else { throw LocalDataError.invalidRecord }
        let current = try await localExpenseForReference(draft.reference)
        guard let expectedVersion = draft.localVersion else { throw LocalDataError.invalidRecord }
        let accountID = draft.accountId.flatMap(UUID.init(uuidString:))
        let command = LocalExpenseUpdateCommand(
            id: current.id,
            expectedVersion: expectedVersion,
            accountID: accountID,
            amountText: draft.amountText,
            currency: current.currency,
            merchantName: draft.title,
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            transactionDate: draft.recordDate,
            transactionTime: draft.transactionTime,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
            updatedAt: Date()
        )
        let outcome = try await localExpenseUseCase.update(command)
        guard let saved = outcome.expense else { throw LocalDataError.invalidRecord }
        let oldMonth = String(current.transactionDate.prefix(7))
        let newMonth = String(saved.transactionDate.prefix(7))
        invalidateRecordExpressionPlanState(afterChanging: [draft.reference])
        _ = await prepareLocalWorkspace()
        await refreshLocalMonthProjection(monthKey: oldMonth)
        if newMonth != oldMonth {
            await refreshLocalMonthProjection(monthKey: newMonth)
        }
        recordDetailCache.removeValue(forKey: NativeRecordReference(draft.reference).canonicalValue)
        await loadRecordDetail(reference: "local-expense/\(saved.id.uuidString)", force: true)
        return true
    }

    private func saveLocalIncomeDetail(_ draft: NativeRecordEditDraft) async throws -> Bool {
        guard let localExpenseUseCase,
              let id = UUID(uuidString: NativeRecordReference(draft.reference).rawId),
              let current = try await localExpenseUseCase.income(id: id),
              let expectedVersion = draft.localVersion else {
            throw LocalDataError.recordNotFound
        }
        let eventTime: Date?
        if let time = draft.transactionTime {
            guard let timestamp = NativeLocalDate.financeOccurredAt(dateKey: draft.recordDate, timeKey: time),
                  let parsed = ISO8601DateFormatter().date(from: timestamp),
                  NativeLocalDate.dateKey(parsed) == draft.recordDate else {
                throw LocalDataError.invalidRecord
            }
            eventTime = parsed
        } else {
            eventTime = nil
        }
        let profile = try await localExpenseUseCase.prepareProfile()
        let saved = try await localExpenseUseCase.updateIncome(LocalIncomeUpdate(
            id: current.id,
            profileID: profile.id,
            expectedVersion: expectedVersion,
            accountID: draft.accountId.flatMap(UUID.init(uuidString:)),
            amountMinor: try LocalExpenseMapper.amountMinor(draft.amountText),
            currency: current.currency,
            sourceName: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            category: draft.category,
            incomeDate: draft.recordDate,
            occurredAt: eventTime,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
            updatedAt: Date()
        ))
        let oldMonth = String(current.incomeDate.prefix(7))
        let newMonth = String(saved.incomeDate.prefix(7))
        invalidateRecordExpressionPlanState(afterChanging: [draft.reference])
        _ = await prepareLocalWorkspace()
        await refreshLocalMonthProjection(monthKey: oldMonth)
        if oldMonth != newMonth { await refreshLocalMonthProjection(monthKey: newMonth) }
        recordDetailCache.removeValue(forKey: NativeRecordReference(draft.reference).canonicalValue)
        await loadRecordDetail(reference: "local-income/\(saved.id.uuidString)", force: true)
        return true
    }

    private func deleteLocalIncome(reference: String) async throws -> Bool {
        guard let localExpenseUseCase,
              let id = UUID(uuidString: NativeRecordReference(reference).rawId),
              let current = try await localExpenseUseCase.income(id: id) else {
            throw LocalDataError.recordNotFound
        }
        _ = try await localExpenseUseCase.deleteIncome(id: current.id, expectedVersion: current.localVersion, deletedAt: Date())
        invalidateRecordExpressionPlanState(afterChanging: [reference])
        recordsPath = NavigationPath()
        _ = await prepareLocalWorkspace()
        await refreshLocalMonthProjection(monthKey: String(current.incomeDate.prefix(7)))
        return true
    }

    private func deleteLocalRecord(reference: String) async throws -> Bool {
        guard let localExpenseUseCase else { throw LocalDataError.invalidRecord }
        let current = try await localExpenseForReference(reference)
        _ = try await localExpenseUseCase.delete(LocalExpenseDeleteCommand(
            id: current.id,
            expectedVersion: current.localVersion,
            deletedAt: Date()
        ))
        let monthKey = String(current.transactionDate.prefix(7))
        invalidateRecordExpressionPlanState(afterChanging: [reference])
        recordsPath = NavigationPath()
        _ = await prepareLocalWorkspace()
        await refreshLocalMonthProjection(monthKey: monthKey)
        return true
    }

    private func localDomainRecordForReference(_ reference: String) async throws -> LocalRecord {
        guard let localRecordUseCase else { throw LocalDataError.invalidRecord }
        let resolved = NativeRecordReference(reference)
        guard resolved.kind == "local-data" || resolved.kind == "data",
              let id = UUID(uuidString: resolved.rawId) else {
            throw LocalDataError.invalidIdentifier
        }
        guard let record = try await localRecordUseCase.record(id: id) else {
            throw LocalDataError.recordNotFound
        }
        return record
    }

    private func saveLocalDomainRecord(_ draft: NativeRecordEditDraft) async throws -> Bool {
        guard let localRecordUseCase else { throw LocalDataError.invalidRecord }
        let current = try await localDomainRecordForReference(draft.reference)
        guard let expectedVersion = draft.localVersion else { throw LocalDataError.invalidRecord }
        var payload = (try? LocalRecordCodec.decode(current.payloadJSON)) ?? [:]
        let trimmedNote = draft.note.trimmingCharacters(in: .whitespacesAndNewlines)
        payload["note"] = trimmedNote.isEmpty
            ? AnyCodable(NSNull())
            : AnyCodable(trimmedNote)
        let command = LocalRecordUpdateCommand(
            id: current.id,
            expectedVersion: expectedVersion,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? current.title
                : draft.title,
            summary: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? current.summary
                : draft.note,
            payload: payload,
            recordDate: draft.recordDate,
            recordTime: draft.transactionTime,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
            updatedAt: Date()
        )
        let outcome = try await localRecordUseCase.update(command)
        let oldMonth = String(current.businessDate.prefix(7))
        let newMonth = String(outcome.record.recordDate.prefix(7))
        invalidateRecordExpressionPlanState(afterChanging: [draft.reference])
        await refreshLocalMonthProjection(monthKey: oldMonth)
        if newMonth != oldMonth {
            await refreshLocalMonthProjection(monthKey: newMonth)
        }
        recordDetailCache.removeValue(forKey: NativeRecordReference(draft.reference).canonicalValue)
        await loadRecordDetail(reference: "local-data/\(outcome.record.id.uuidString)", force: true)
        return true
    }

    private func deleteLocalDomainRecord(reference: String) async throws -> Bool {
        guard let localRecordUseCase else { throw LocalDataError.invalidRecord }
        let current = try await localDomainRecordForReference(reference)
        _ = try await localRecordUseCase.delete(LocalRecordDeleteCommand(
            id: current.id,
            expectedVersion: current.localVersion,
            deletedAt: Date()
        ))
        invalidateRecordExpressionPlanState(afterChanging: [reference])
        recordsPath = NavigationPath()
        await refreshLocalMonthProjection(monthKey: String(current.businessDate.prefix(7)))
        return true
    }

    private func saveRemoteRecordDetail(_ draft: NativeRecordEditDraft) async throws -> Bool {
        let session = try await validSession()
        let reference = try await recordRepository.saveDetail(draft, accessToken: session.accessToken)
        let oldReference = NativeRecordReference(draft.reference).canonicalValue
        let savedReference = NativeRecordReference(reference).canonicalValue
        invalidateRecordExpressionPlanState(
            afterChanging: [oldReference, savedReference]
        )
        await refreshAfterRecordWrite(affectedDateKeys: [draft.recordDate])
        await loadAccounts()
        recordDetailCache.removeValue(forKey: savedReference)
        await loadRecordDetail(reference: savedReference, force: true)
        return true
    }

    private func deleteRemoteRecord(reference: String) async throws -> Bool {
        let session = try await validSession()
        try await recordRepository.delete(reference: reference, accessToken: session.accessToken)
        invalidateRecordExpressionPlanState(afterChanging: [reference])
        recordsPath = NavigationPath()
        await loadAccounts()
        await refreshAfterRecordWrite()
        return true
    }

    func saveRecordDetail(_ draft: NativeRecordEditDraft) async -> Bool {
        guard !isSavingRecordDetail else { return false }
        isSavingRecordDetail = true
        recordDetailMessage = nil
        defer { isSavingRecordDetail = false }

        do {
            if isLocalIncomeReference(draft.reference) {
                return try await saveLocalIncomeDetail(draft)
            }
            if isLocalExpenseReference(draft.reference) {
                return try await saveLocalRecordDetail(draft)
            }
            if isLocalDomainReference(draft.reference) {
                return try await saveLocalDomainRecord(draft)
            }
            guard mayReadRemoteBusinessData else { throw LocalDataError.recordNotFound }
            return try await saveRemoteRecordDetail(draft)
        } catch {
            recordDetailMessage = error.localizedDescription
            return false
        }
    }

    func deleteRecord(reference: String) async -> Bool {
        guard !isDeletingRecordDetail else { return false }
        isDeletingRecordDetail = true
        recordDetailMessage = nil
        defer { isDeletingRecordDetail = false }

        do {
            if !mayReadRemoteBusinessData, let repository = localPendingFinancialRepository,
               let profile = try await localExpenseUseCase?.prepareProfile(),
               let id = UUID(uuidString: NativeRecordReference(reference).rawId),
               NativeRecordReference(reference).kind == "expense",
               try repository.record(profileID: profile.id, id: id) != nil {
                try repository.delete(profileID: profile.id, id: id)
                selectedRecordDetail = nil
                await applyLocalStagingProjection()
                await retryLocalImageCleanups()
                return true
            }
            if isLocalIncomeReference(reference) {
                return try await deleteLocalIncome(reference: reference)
            }
            if isLocalExpenseReference(reference) {
                return try await deleteLocalRecord(reference: reference)
            }
            if isLocalDomainReference(reference) {
                return try await deleteLocalDomainRecord(reference: reference)
            }
            guard mayReadRemoteBusinessData else { throw LocalDataError.recordNotFound }
            return try await deleteRemoteRecord(reference: reference)
        } catch {
            recordDetailMessage = error.localizedDescription
            return false
        }
    }

    func confirmPendingRecord(
        _ draft: NativePendingResolutionDraft,
        preserveInboxNavigation: Bool = false
    ) async -> Bool {
        guard !isConfirmingPendingRecord else { return false }
        if let validationMessage = draft.validationMessage {
            pendingResolutionMessage = validationMessage
            return false
        }
        isConfirmingPendingRecord = true
        pendingResolutionMessage = "正在保存…"
        defer { isConfirmingPendingRecord = false }
        let generation = userStateGeneration
        if !mayReadRemoteBusinessData {
            do {
                guard let repository = localPendingFinancialRepository,
                      let profile = try await localExpenseUseCase?.prepareProfile(),
                      let id = UUID(uuidString: draft.pendingId),
                      let source = try repository.record(profileID: profile.id, id: id) else { throw LocalDataError.recordNotFound }
                guard generation == userStateGeneration else { return false }
                _ = try repository.resolve(profileID: profile.id, pendingID: id, draft: draft)
                await loadLocalAccounts()
                await refreshLocalMonthProjection(monthKey: String(source.transactionDate.prefix(7)))
                await applyLocalStagingProjection()
                guard generation == userStateGeneration else { return true }
                if !preserveInboxNavigation { inboxPath = NavigationPath() }
                pendingResolutionMessage = localWriteMessage(draft.kind == .income ? "收入已记录（本机）" : (draft.accountId == nil ? "支出已补全（仅本机，待补绑账户）" : "支出已补全（本机）"))
                return true
            } catch {
                guard generation == userStateGeneration else { return false }
                pendingResolutionMessage = "保存失败：\(error.localizedDescription)"
                return false
            }
        }
        let result = await resolvedPendingConfirmationUseCase().perform(
            draft
        )
        switch result.transaction {
        case .accepted(let accepted):
            if accepted.recordType == "expense" {
                await scheduleConfirmedExpenseVocabularyIfCurrent(draft)
            }
            if !preserveInboxNavigation { inboxPath = NavigationPath() }
            let message = draft.kind == .income ? "收入已记录" : "支出已补全"
            pendingResolutionMessage = result.refresh.failureMessage.map {
                "\(message)，刷新失败：\($0)"
            } ?? message
            return true
        case .rejected(.unauthenticated):
            pendingResolutionMessage = "登录状态已失效，请重新登录"
        case .rejected(.invalidInput):
            pendingResolutionMessage = draft.validationMessage ?? "待补全账单无效"
        case .conflict:
            pendingResolutionMessage = "这条待补全账单正在保存"
        case .failed(let message):
            pendingResolutionMessage = "保存失败：\(message)"
        case .stale:
            return false
        }
        return false
    }

    private func scheduleConfirmedExpenseVocabularyIfCurrent(
        _ draft: NativePendingResolutionDraft
    ) async {
        guard let session = try? await validSession(),
              isCurrentUserLoad(userStateGeneration, userId: session.user.id) else { return }
        scheduleConfirmedExpenseVocabulary(
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            accountId: draft.accountId,
            userId: session.user.id,
            accessToken: session.accessToken
        )
    }

    func submitRecordFeedback(
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        feedbackIdentity: String? = nil
    ) async {
        if case .submitting = recordFeedbackState { return }
        guard let detail = selectedRecordDetail,
              let feedback = NativeRecordExpressionFeedbackPolicy.feedbackForReview(
                  voiceFeedback: detail.voiceAiFeedback,
                  plannerFeedback: detail.expressionPlannerAiFeedback,
                  fallbackFeedback: detail.aiFeedback,
                  renderIdentity: feedbackIdentity
              ) else { return }
        recordFeedbackState = .submitting
        let result = await resolvedFeedbackSubmissionUseCase().perform(
            FeedbackSubmissionInput(
                recordId: detail.rawId,
                feedbackIdentity: feedback.renderIdentity,
                choice: choice,
                freeText: freeText,
                exposureEventId: feedback.exposureEventId
            )
        )
        switch result.transaction {
        case .accepted:
            recordFeedbackState = .submitted
        case .rejected(.unauthenticated):
            recordFeedbackState = .failed("登录状态已失效，请重新登录")
        case .rejected(.invalidInput):
            recordFeedbackState = .failed("反馈参数无效")
        case .failed(let message):
            recordFeedbackState = .failed(message)
        case .stale:
            return
        }
    }

    private func resolvedFeedbackSubmissionUseCase() -> FeedbackSubmissionUseCase {
        if let feedbackSubmissionUseCase { return feedbackSubmissionUseCase }
        let useCase = FeedbackSubmissionUseCase(
            repository: recordRepository,
            sessionProvider: { [weak self] forceRefresh in
                guard let self else {
                    throw SupabaseRemoteError.requestFailed("app_state_unavailable")
                }
                return try await self.validSession(forceRefresh: forceRefresh)
            },
            contextProvider: { [weak self] in
                guard let self else {
                    return FeedbackSubmissionUserContext(userId: "", generation: -1, isSignedIn: false)
                }
                return FeedbackSubmissionUserContext(
                    userId: self.currentUserId,
                    generation: self.userStateGeneration,
                    isSignedIn: self.isSignedIn
                )
            }
        )
        feedbackSubmissionUseCase = useCase
        return useCase
    }

    func loadUserSettings() async {
        userSettings = localUserSettingsStore.load()
        settingsMessage = nil
    }

    func loadCloudPrivacySettings() async {
        guard !isLoadingSettings else { return }
        guard isSignedIn else {
            settingsMessage = "登录后可读取或修改云端策略；本机原图不受这些期限影响。"
            return
        }
        let generation = userStateGeneration
        isLoadingSettings = true
        defer { if generation == userStateGeneration { isLoadingSettings = false } }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let remote = try await settingsRepository.fetch(userId: session.user.id, accessToken: session.accessToken)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            // Display cloud policy without importing ordinary preferences or
            // changing the device AI mode and its explicit consent.
            userSettings.aiLogsEnabled = remote.aiLogsEnabled
            userSettings.promptOptimizationEnabled = remote.promptOptimizationEnabled
            userSettings.expressionImprovementEnabled = remote.expressionImprovementEnabled
            userSettings.keepSourceImages = remote.keepSourceImages
            userSettings.imageRetentionDays = remote.imageRetentionDays
            settingsMessage = nil
        } catch {
            guard generation == userStateGeneration else { return }
            settingsMessage = "未能确认当前云端策略，请联网后重试：\(error.localizedDescription)"
        }
    }

    func setCompanionEnabled(_ enabled: Bool) async {
        await updateSettings(["companion_enabled": AnyCodable(enabled)]) { $0.companionEnabled = enabled }
    }

    func setCompanionMemoryEnabled(_ enabled: Bool) async {
        await updateSettings(["companion_memory_enabled": AnyCodable(enabled)]) { $0.companionMemoryEnabled = enabled }
    }

    func setCompanionPersona(_ value: String) async {
        await updateSettings(["companion_persona": AnyCodable(value)]) { $0.companionPersona = value }
    }

    func setCompanionMemoryStrength(_ value: String) async {
        await updateSettings(["companion_memory_strength": AnyCodable(value)]) { $0.companionMemoryStrength = value }
    }

    func setCompanionExpressionStyle(_ value: String) async {
        await updateSettings(["companion_expression_style": AnyCodable(value)]) { $0.companionExpressionStyle = value }
    }

    func setCompanionCustomNote(_ value: String) async {
        let value = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        await updateSettings(["companion_custom_note": AnyCodable(value)]) { $0.companionCustomNote = value }
    }

    func setInsightProvider(_ value: String) async {
        let provider = NativeSettingsOptions.normalizedInsightProvider(value)
        await updateSettings(["ai_insight_provider": AnyCodable(provider)]) { $0.aiInsightProvider = provider }
    }

    func setVisionProvider(_ value: String, forPhoto: Bool) async {
        let provider = NativeSettingsOptions.normalizedVisionProvider(value, fallback: forPhoto ? "qwen" : "auto")
        let key = forPhoto ? "photo_vision_primary" : "screenshot_vision_primary"
        var values = [key: AnyCodable(provider)]
        if !forPhoto { values["vision_primary"] = AnyCodable(provider) }
        await updateSettings(values) {
            if forPhoto { $0.photoVisionPrimary = provider }
            else { $0.screenshotVisionPrimary = provider }
        }
    }

    func setQwenModel(_ value: String, forPhoto: Bool) async {
        let model = NativeSettingsOptions.normalizedQwenModel(value)
        let key = forPhoto ? "qwen_photo_model" : "qwen_screenshot_model"
        await updateSettings([key: AnyCodable(model)]) {
            if forPhoto { $0.qwenPhotoModel = model }
            else { $0.qwenScreenshotModel = model }
        }
    }

    func setQwenThinking(_ enabled: Bool, forPhoto: Bool) async {
        let key = forPhoto ? "qwen_photo_enable_thinking" : "qwen_screenshot_enable_thinking"
        await updateSettings([key: AnyCodable(enabled)]) {
            if forPhoto { $0.qwenPhotoThinking = enabled }
            else { $0.qwenScreenshotThinking = enabled }
        }
    }

    func setAILogsEnabled(_ enabled: Bool) async {
        await updateSettings(["ai_logs_enabled": AnyCodable(enabled)]) { $0.aiLogsEnabled = enabled }
    }

    func setPromptOptimizationEnabled(_ enabled: Bool) async {
        await updateSettings(["prompt_optimization_enabled": AnyCodable(enabled)]) { $0.promptOptimizationEnabled = enabled }
    }

    func setExpressionImprovementEnabled(_ enabled: Bool) async {
        await updateSettings(["expression_improvement_enabled": AnyCodable(enabled)]) { $0.expressionImprovementEnabled = enabled }
    }

    func setImageRetention(days: Int, cleanupExisting: Bool = false) async {
        let keepImages = days != 0
        let retentionDays = keepImages ? days : 7
        await updateSettings([
            "keep_source_images": AnyCodable(keepImages),
            "image_retention_days": AnyCodable(retentionDays)
        ]) {
            $0.keepSourceImages = keepImages
            $0.imageRetentionDays = retentionDays
        }
        guard cleanupExisting, settingsMessage == nil else { return }
        guard !isCleaningSourceImages else { return }
        isCleaningSourceImages = true
        settingsMessage = "正在清理已有云端原图…"
        defer { isCleaningSourceImages = false }
        do {
            let session = try await validSession()
            let cleanup = try await settingsRepository.cleanupSourceImages(accessToken: session.accessToken)
            await RemoteImageRepository.shared.clear()
            dashboard = dashboard.clearingSignedImageURLs()
            recordDetailCache = recordDetailCache.mapValues { detail in
                var cleared = detail
                cleared.imageURL = nil
                cleared.imageLoadError = false
                return cleared
            }
            if var detail = selectedRecordDetail {
                detail.imageURL = nil
                detail.imageLoadError = false
                selectedRecordDetail = detail
            }
            await refreshDashboard()
            settingsMessage = cleanup.displayMessage
        } catch {
            settingsMessage = "留存设置已保存，但清理已有原图失败：\(error.localizedDescription)"
        }
    }

    func exportData(_ request: NativeDataExportRequest) async -> NativeExportedFile? {
        guard !isExportingData else { return nil }
        isExportingData = true
        settingsMessage = nil
        defer { isExportingData = false }
        do {
            if localFactPortability != nil || request.content == .universal {
                let data: Data
                let filenamePrefix: String
                if let localFactPortability {
                    data = try localFactPortability.exportArchive(request: request)
                    filenamePrefix = "jiezi-local-facts"
                } else if let localRecordPortability {
                    data = try localRecordPortability.exportArchive(request: request)
                    filenamePrefix = "jiezi-local-records"
                } else {
                    throw LocalDataError.invalidRecord
                }
                let filename = "\(filenamePrefix)-\(NativeLocalDate.dateKey(Date())).\(request.format.rawValue)"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
                try data.write(to: url, options: .atomic)
                return NativeExportedFile(url: url)
            }
            throw LocalDataError.invalidRecord
        } catch {
            settingsMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
    }

    func exportCompleteLocalBackup() async -> NativeExportedFile? {
        guard !isExportingData, let portability = localCompleteBackupPortability else { return nil }
        isExportingData = true
        settingsMessage = nil
        defer { isExportingData = false }
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                try portability.exportBackup()
            }.value
            let filename = "jiezi-local-complete-backup-\(NativeLocalDate.dateKey(Date())).json"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try data.write(to: url, options: .atomic)
            return NativeExportedFile(url: url)
        } catch {
            settingsMessage = "完整本地备份失败：\(error.localizedDescription)"
            return nil
        }
    }

    func previewCompleteLocalBackup(_ data: Data) async throws -> LocalCompleteBackupPreview {
        guard let portability = localCompleteBackupPortability else { throw LocalDataError.invalidRecord }
        return try await Task.detached(priority: .userInitiated) {
            try portability.preview(data)
        }.value
    }

    /// Explicit settings action: caches source bytes, never writes business facts or enables sync.
    func prepareCloudHistoryMigration() async {
        guard !isPreparingHistoryMigration, !isImportingLocalBackup else { return }
        loadLatestHistoryMigrationDiagnostic()
        isPreparingHistoryMigration = true
        canPauseHistoryMigration = true
        historyMigrationAttempt += 1
        let attempt = historyMigrationAttempt
        let generation = userStateGeneration
        historyMigrationAttemptID = UUID()
        historyMigrationArchive = nil
        historyMigrationPreview = nil
        historyMigrationMessage = nil
        historyMigrationCheckpoint = nil
        historyMigrationProgress = nil
        historyMigrationBlockers = []
        historyMigrationBlockerCount = 0
        historyMigrationUnresolvedCount = 0
        historyMigrationPreservationIssues = []
        historyMigrationPhase = "验证会话"
        defer {
            if generation == userStateGeneration, attempt == historyMigrationAttempt {
                isPreparingHistoryMigration = false
                canPauseHistoryMigration = false
            }
        }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id),
                  let profile = try await localExpenseUseCase?.prepareProfile(),
                  let portability = localCompleteBackupPortability,
                  let cache = localHistoryMigrationCache,
                  let baseURL = URL(string: AppConfig.supabaseURL) else { throw LocalDataError.invalidRecord }
            guard profile.cloudUserID == nil || profile.cloudUserID == session.user.id else {
                throw LocalHistoryMappingError.unsupported("本机工作区仍绑定另一个云账户，请先核对数据归属。")
            }
            historyMigrationProfileID = profile.id
            let isCurrent = { [weak self] in
                self?.isCurrentUserLoad(generation, userId: session.user.id) == true
                    && self?.historyMigrationAttempt == attempt
            }
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            if let existing = try cache.state(profileID: profile.id) {
                guard existing.cloudUserID == session.user.id else { throw LocalHistoryMigrationError.identityMismatch }
                if existing.status == .completed {
                    try? cache.cleanupAfterCompletion(existing)
                    historyMigrationUnresolvedCount = try historyUnresolvedRepository?.count(profileID: profile.id) ?? 0
                    historyMigrationPhase = historyMigrationUnresolvedCount > 0 ? "已保留待核对" : "已入账"
                    historyMigrationMessage = "此工作区已完成一次历史迁入，历史待核对 \(historyMigrationUnresolvedCount) 条仍不属于正式入账。普通同步只支持其已声明范围，不代表全域云本一致。"
                    return
                }
            }
            historyMigrationPhase = "读取云端源数据与原图"
            let prepared = try await LocalHistoryMigrationCoordinator(
                downloader: LocalHistoryImageDownloader(baseURL: baseURL), cache: cache
            ).prepare(profileID: profile.id, cloudUserID: session.user.id,
                      accessToken: session.accessToken, isCurrent: isCurrent,
                      onProgress: { [weak self] progress in
                          guard let self else { return }
                          self.historyMigrationProgress = progress
                          switch progress.phase {
                          case .readingSource:
                              self.historyMigrationPhase = progress.currentTable.map { "读取 \($0.rawValue)" } ?? "读取云端源数据"
                          case .downloadingImages:
                              self.historyMigrationPhase = "下载历史原图"
                          }
                      })
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            let inspection = prepared.inspection
            historyMigrationCheckpoint = prepared.state
            guard inspection.blockers.isEmpty else {
                try cache.pause(prepared.state)
                historyMigrationPhase = "预检阻塞"
                historyMigrationBlockerCount = inspection.blockers.count
                historyMigrationBlockers = inspection.blockers
                historyMigrationMessage = inspection.summary
                return
            }
            historyMigrationBlockers = []
            historyMigrationBlockerCount = 0
            guard isCurrent(), !Task.isCancelled else { throw CancellationError() }
            historyMigrationPhase = "核对历史字段与转换"
            let archive = try LocalHistoryMigrationMapper(schema: LocalDatabase()).buildArchive(
                inspection, profileID: profile.id, images: prepared.images)
            let preview = try portability.preview(archive)
            historyMigrationUnresolvedCount = preview.tableCounts["local_history_unresolved_records", default: 0]
            historyMigrationPreservationIssues = [LocalHistorySourceTable.records, .staging].flatMap { table in
                inspection.rows[table, default: []].flatMap {
                    LocalHistoryMigrationUseCase.preservationIssues(table: table, row: $0, rows: inspection.rows)
                }
            }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            historyMigrationSourceDigest = try encoder.encode(Dictionary(uniqueKeysWithValues: inspection.rows.map { ($0.key.rawValue, $0.value) }))
            historyMigrationImageDigests = prepared.images.mapValues(LocalImageStore.sha256)
            historyMigrationArchive = archive
            historyMigrationOwner = session.user.id
            historyMigrationGeneration = generation
            historyMigrationPhase = "等待用户确认"
            historyMigrationPreview = "云账户：\(session.user.email ?? session.user.id)。将合并到此 iPhone 现有账本，换号不会另建本机账本。\n" + inspection.summary + "\n" + preview.confirmationText
            historyMigrationMessage = "预检通过，源数据与图片已暂存在本机，尚未提交。确认会一起保存可等价转换的数据与 \(historyMigrationUnresolvedCount) 条历史待核对原文；原文不会计入日统计。确认前重新核对源数据，冲突仍整包拒绝。"
            if let diagnostic = historyMigrationDiagnostic,
               diagnostic.operation == "history-migration", !diagnostic.committed, diagnostic.resolution == nil,
               diagnostic.accountHint == LocalHistoryMigrationDiagnosticStore.identityHint(session.user.id) {
                try? historyMigrationDiagnosticStore?.resolve(diagnostic.id, outcome: "重试预检通过；数据仍待用户确认入账。", expectedAccountID: session.user.id)
                loadLatestHistoryMigrationDiagnostic()
            }
        } catch is CancellationError {
            guard generation == userStateGeneration, attempt == historyMigrationAttempt else { return }
            historyMigrationPhase = "已取消"
            historyMigrationMessage = "预检已取消，尚未入账；已缓存的读取进度保留。"
        } catch {
            guard generation == userStateGeneration, attempt == historyMigrationAttempt else { return }
            if let state = historyMigrationCheckpoint { try? localHistoryMigrationCache?.pause(state) }
            let failedPhase = historyMigrationPhase
            historyMigrationPhase = "预检暂停"
            historyMigrationMessage = recordHistoryMigrationFailure(error, committed: false, phase: failedPhase)
        }
    }

    func loadLocalHistoryUnresolvedRecords() async {
        guard !isLoadingHistoryUnresolvedRecords else { return }
        let generation = userStateGeneration
        isLoadingHistoryUnresolvedRecords = true
        historyUnresolvedRecordsError = nil
        defer { if generation == userStateGeneration { isLoadingHistoryUnresolvedRecords = false } }
        do {
            guard let repository = historyUnresolvedRepository else { throw LocalDataError.invalidRecord }
            guard let profileID = try localFactReader?.activeProfileID() else {
                localHistoryUnresolvedRecords = []
                return
            }
            let records = try await Task.detached(priority: .utility) {
                try repository.records(profileID: profileID)
            }.value
            guard generation == userStateGeneration else { return }
            localHistoryUnresolvedRecords = records
        } catch {
            guard generation == userStateGeneration else { return }
            localHistoryUnresolvedRecords = []
            historyUnresolvedRecordsError = "历史待核对记录读取失败；未按空清单显示，请重试本机读取。"
        }
    }

    func localImageDataForHistoryUnresolvedRecord(id: String) async throws -> Data {
        let generation = userStateGeneration
        guard let repository = historyUnresolvedRepository, let store = localImageStore,
              let profileID = try localFactReader?.activeProfileID(),
              let record = try repository.record(id: id, profileID: profileID),
              let path = record.imagePath, let hash = record.imageHash else { throw LocalDataError.recordNotFound }
        let bytes = try await Task.detached(priority: .utility) { try store.data(at: path) }.value
        guard generation == userStateGeneration else { throw CancellationError() }
        guard LocalImageStore.sha256(bytes) == hash else { throw LocalCompleteBackupError.invalidImage("history-image") }
        return bytes
    }

    func loadLocalHistoryInventory() async {
        guard !isLoadingLocalHistoryInventory else { return }
        guard let historyInventoryReader else {
            localHistoryInventory = nil
            localHistoryInventoryError = localStorageInitializationMessage ?? "本机数据不可读取。"
            return
        }
        isLoadingLocalHistoryInventory = true
        localHistoryInventoryError = nil
        defer { isLoadingLocalHistoryInventory = false }
        do {
            localHistoryInventory = try await Task.detached(priority: .utility) {
                try historyInventoryReader.readLocal()
            }.value
        } catch {
            localHistoryInventory = nil
            let entry = historyMigrationDiagnosticStore?.record(error, phase: "本机数据盘点", operation: "local-inventory", attemptID: historyMigrationAttemptID, committed: false)
            historyMigrationDiagnostic = entry
            localHistoryInventoryError = "本机数据读取失败；未按 0 条显示。\(entry.map { "诊断编号：\($0.id)。" } ?? "")"
        }
    }

    /// Explicit user action. This reads each cloud source table under the current session/RLS and does not download images or write business data.
    func readCloudHistoryInventory() async {
        guard !isReadingCloudHistoryInventory else { return }
        guard isSignedIn else {
            cloudHistoryInventory = LocalHistoryCloudInventory.notRead
            cloudHistoryInventory.status = .failed
            cloudHistoryInventory.message = "请先登录要盘点的云账户。"
            return
        }
        isReadingCloudHistoryInventory = true
        historyMigrationAttemptID = UUID()
        cloudHistoryInventory = LocalHistoryCloudInventory(
            status: .loading, sampledAt: nil, counts: [:], completedTables: [], currentTable: nil,
            currentTableRowsRead: 0, totalRowsRead: 0, pagesRead: 0, message: nil
        )
        defer { isReadingCloudHistoryInventory = false }
        let generation = userStateGeneration
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let inspection = try await LocalHistoryMigrationUseCase().inspect(
                cloudUserID: session.user.id,
                accessToken: session.accessToken,
                isCurrent: { [weak self] in self?.isCurrentUserLoad(generation, userId: session.user.id) == true },
                onProgress: { [weak self] progress in
                    guard let self, self.isCurrentUserLoad(generation, userId: session.user.id) else { return }
                    self.cloudHistoryInventory = LocalHistoryCloudInventory(
                        status: .loading, sampledAt: nil, counts: progress.counts,
                        completedTables: progress.completedTables, currentTable: progress.currentTable,
                        currentTableRowsRead: progress.currentTableRowsRead, totalRowsRead: progress.totalRowsRead,
                        pagesRead: progress.pagesRead, message: nil
                    )
                }
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            cloudHistoryInventory = LocalHistoryCloudInventory(
                status: .complete, sampledAt: Date(), counts: LocalHistoryInventoryCatalog.cloudCounts(inspection.rows),
                completedTables: Set(LocalHistorySourceTable.allCases), currentTable: nil,
                currentTableRowsRead: 0, totalRowsRead: inspection.rows.values.reduce(0) { $0 + $1.count },
                pagesRead: cloudHistoryInventory.pagesRead, message: "已完成本次分页读取；多表读取不是原子云快照。图片仅统计引用与去重路径，未下载验证。"
            )
        } catch is CancellationError {
            guard generation == userStateGeneration else { return }
            cloudHistoryInventory.status = .incomplete
            cloudHistoryInventory.sampledAt = Date()
            cloudHistoryInventory.message = "读取已取消；已完成表可查看，当前表的总量未知。"
        } catch {
            guard generation == userStateGeneration else { return }
            cloudHistoryInventory.status = .failed
            cloudHistoryInventory.sampledAt = Date()
            let entry = historyMigrationDiagnosticStore?.record(error, phase: "云端数量盘点", accountID: currentUserId, operation: "cloud-inventory",
                progressSummary: "已读 \(cloudHistoryInventory.totalRowsRead) 行、\(cloudHistoryInventory.pagesRead) 页；当前表总量未知。",
                attemptID: historyMigrationAttemptID, committed: false)
            historyMigrationDiagnostic = entry
            cloudHistoryInventory.message = "云端读取失败；已完成表可查看，当前表总量未知。\(entry.map { "诊断编号：\($0.id)。" } ?? "")"
        }
    }

    func loadLatestHistoryMigrationDiagnostic() {
        guard let historyMigrationDiagnosticStore else {
            historyMigrationDiagnostic = nil
            return
        }
        let entries = (try? historyMigrationDiagnosticStore.recent()) ?? []
        let operations: Set<String> = ["history-migration", "cloud-inventory", "local-inventory"]
        if currentUserId.isEmpty {
            historyMigrationDiagnostic = entries.last {
                operations.contains($0.operation ?? "history-migration") && $0.accountHint == nil
            }
        } else {
            let currentHint = LocalHistoryMigrationDiagnosticStore.identityHint(currentUserId)
            historyMigrationDiagnostic = entries.last {
                operations.contains($0.operation ?? "history-migration")
                    && ($0.accountHint == nil || $0.accountHint == currentHint)
            }
        }
    }

    func loadLatestLocalStorageInitializationDiagnostic() {
        guard let historyMigrationDiagnosticStore else {
            localStorageInitializationDiagnostic = nil
            return
        }
        localStorageInitializationDiagnostic = (try? historyMigrationDiagnosticStore.recent())?.last {
            $0.operation == "local-storage-init" && $0.accountHint == nil
        }
    }

    func loadLatestLocalProjectionRefreshDiagnostic() {
        guard let historyMigrationDiagnosticStore else {
            localProjectionRefreshDiagnostic = nil
            return
        }
        let accountHint = currentUserId.isEmpty
            ? nil
            : LocalHistoryMigrationDiagnosticStore.identityHint(currentUserId)
        localProjectionRefreshDiagnostic = (try? historyMigrationDiagnosticStore.recent())?.last {
            $0.operation == "local-write-refresh" && $0.accountHint == accountHint
        }
    }

    func pauseCloudHistoryMigration() {
        guard canPauseHistoryMigration else { return }
        if let profileID = historyMigrationProfileID,
           let state = try? localHistoryMigrationCache?.state(profileID: profileID) {
            try? localHistoryMigrationCache?.pause(state)
        }
        historyMigrationAttempt += 1
        canPauseHistoryMigration = false
        historyMigrationPhase = "已暂停"
        isPreparingHistoryMigration = false
        historyMigrationMessage = "已暂停，尚未入账。再次预检将从已缓存的页和图片继续。"
    }

    func restartCloudHistoryMigrationPreview() {
        guard !isPreparingHistoryMigration, !isImportingLocalBackup,
              let profileID = historyMigrationProfileID, let cache = localHistoryMigrationCache else { return }
        do {
            guard let checkpoint = try cache.state(profileID: profileID), checkpoint.cloudUserID == currentUserId else {
                throw LocalHistoryMigrationError.identityMismatch
            }
            try cache.restartSource(checkpoint)
            historyMigrationCheckpoint = nil
            historyMigrationArchive = nil
            historyMigrationPreview = nil
            historyMigrationSourceDigest = nil
            historyMigrationImageDigests = [:]
            historyMigrationBlockers = []
            historyMigrationBlockerCount = 0
            historyMigrationPhase = "预检已丢弃"
            historyMigrationPreservationIssues = []
            historyMigrationUnresolvedCount = 0
            historyMigrationMessage = "已丢弃预检缓存。再次预检会重新读取云端历史，本机原有账目和图片未改变。"
        } catch { historyMigrationMessage = "无法丢弃旧预检：\(error.localizedDescription)" }
    }

    func confirmCloudHistoryMigration() async -> Bool {
        guard !isPreparingHistoryMigration, !isImportingLocalBackup,
              let archive = historyMigrationArchive, let owner = historyMigrationOwner,
              let checkpoint = historyMigrationCheckpoint, let cache = localHistoryMigrationCache,
              let generation = historyMigrationGeneration,
              isCurrentUserLoad(generation, userId: owner) else { return false }
        let attempt = historyMigrationAttempt
        isPreparingHistoryMigration = true
        historyMigrationPhase = "确认前复核云端源数据"
        historyMigrationImportError = nil
        let isCurrentAttempt = { [weak self] in
            self?.isCurrentUserLoad(generation, userId: owner) == true
                && self?.historyMigrationAttempt == attempt
        }
        defer { if isCurrentAttempt() { isPreparingHistoryMigration = false } }
        do {
            let session = try await validSession()
            guard isCurrentAttempt(), session.user.id == owner else { return false }
            let inspection = try await LocalHistoryMigrationUseCase().inspect(cloudUserID: owner,
                accessToken: session.accessToken,
                isCurrent: isCurrentAttempt)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let current = try encoder.encode(Dictionary(uniqueKeysWithValues: inspection.rows.map { ($0.key.rawValue, $0.value) }))
            guard isCurrentAttempt(), !Task.isCancelled else { throw CancellationError() }
            guard inspection.blockers.isEmpty, current == historyMigrationSourceDigest else {
                try cache.restartSource(checkpoint)
                historyMigrationArchive = nil
                historyMigrationPreview = nil
                historyMigrationCheckpoint = nil
                historyMigrationPreservationIssues = []
                historyMigrationMessage = "云端源数据已变化，旧预检缓存已失效。请重新预检；尚未入账。"
                return false
            }
            // Rows may omit a source hash; a stable URL alone cannot prove unchanged image bytes.
            guard let baseURL = URL(string: AppConfig.supabaseURL) else { throw LocalDataError.invalidRecord }
            let downloader = LocalHistoryImageDownloader(baseURL: baseURL)
            var currentImages: [String: Data] = [:]
            var currentImageBytes = 0
            historyMigrationPhase = "确认前复核原图"
            let imagePaths = inspection.sourceImagePaths.sorted()
            let sourceRowsRead = inspection.rows.values.reduce(0) { $0 + $1.count }
            let sourcePagesRead = historyMigrationProgress?.pagesRead ?? 0
            historyMigrationProgress = LocalHistoryMigrationProgress(phase: .downloadingImages, currentTable: nil,
                rowsRead: sourceRowsRead, knownRowTotal: sourceRowsRead, pagesRead: sourcePagesRead,
                imagesProcessed: 0, imagesTotal: imagePaths.count)
            for path in imagePaths {
                guard let reference = inspection.imageReference(for: path) else {
                    throw LocalHistoryMigrationContextError(table: "image_objects", field: "path", recordID: "",
                        underlying: LocalHistoryImageDownloadError.sourceScopeMismatch)
                }
                do {
                    let fetched = try await downloader.download(reference: reference, inspection: inspection,
                        cloudUserID: owner, accessToken: session.accessToken, isCurrent: isCurrentAttempt)
                    guard let data = fetched[path] else { throw LocalHistoryImageDownloadError.sourceScopeMismatch }
                    currentImageBytes = try LocalHistoryMigrationCoordinator.checkedImageByteCount(
                        current: currentImageBytes, adding: data.count)
                    currentImages[path] = data
                    historyMigrationProgress = LocalHistoryMigrationProgress(phase: .downloadingImages, currentTable: nil,
                        rowsRead: sourceRowsRead, knownRowTotal: sourceRowsRead, pagesRead: sourcePagesRead,
                        imagesProcessed: currentImages.count, imagesTotal: imagePaths.count)
                } catch is CancellationError {
                    throw CancellationError()
                } catch let error as LocalHistoryMigrationContextError {
                    throw error
                } catch {
                    throw LocalHistoryMigrationContextError(table: reference.table, field: reference.field,
                        recordID: reference.recordID, underlying: error)
                }
            }
            guard isCurrentAttempt(), !Task.isCancelled else { throw CancellationError() }
            guard currentImages.mapValues(LocalImageStore.sha256) == historyMigrationImageDigests else {
                try cache.restartSource(checkpoint)
                historyMigrationArchive = nil
                historyMigrationPreview = nil
                historyMigrationCheckpoint = nil
                historyMigrationMessage = "云端原图已变化，旧预检缓存已失效。请重新预检；尚未入账。"
                return false
            }
            guard isCurrentAttempt(), !Task.isCancelled else { return false }
            try cache.assertCurrent(checkpoint)
            historyMigrationPhase = "事务入账与本机刷新"
            let imported = await importCompleteLocalBackup(archive, historyMigration: checkpoint)
            if !imported, let error = historyMigrationImportError {
                historyMigrationPhase = "事务入账"
                historyMigrationMessage = recordHistoryMigrationFailure(error, committed: false)
                return false
            }
            if imported { try? cache.cleanupAfterCompletion(checkpoint) }
            guard isCurrentAttempt() else { return false }
            if imported {
                let savedPhase = historyMigrationUnresolvedCount > 0 ? "已保留待核对" : "已入账"
                historyMigrationPhase = savedPhase
                historyMigrationPreservationIssues = []
                historyMigrationBlockers = []
                historyMigrationBlockerCount = 0
                historyMigrationArchive = nil
                historyMigrationPreview = nil
                historyMigrationCheckpoint = nil
                if localProjectionRefreshMessage != nil {
                    historyMigrationPhase = "入账后刷新"
                    historyMigrationMessage = recordHistoryMigrationFailure(LocalHistoryMigrationPostCommitRefreshError(), committed: true)
                    historyMigrationPhase = savedPhase
                } else {
                    historyMigrationMessage = settingsMessage
                }
            } else { historyMigrationMessage = settingsMessage }
            return imported
        } catch {
            guard isCurrentAttempt() else { return false }
            if error is CancellationError {
                historyMigrationPhase = "已取消"
                historyMigrationMessage = "确认前复核已取消，尚未入账；可以重新预检。"
                return false
            }
            if (error as? LocalHistoryMigrationError) == .staleAttempt {
                historyMigrationPhase = "已暂停"
                historyMigrationMessage = "迁移尝试已失效，尚未入账；请重新预检。"
                return false
            }
            historyMigrationMessage = recordHistoryMigrationFailure(error, committed: false)
            return false
        }
    }

    func importCompleteLocalBackup(_ data: Data, historyMigration: LocalHistoryMigrationState? = nil) async -> Bool {
        guard !isImportingLocalBackup, let portability = localCompleteBackupPortability else { return false }
        isImportingLocalBackup = true
        settingsMessage = nil
        insightsLoadedAt = nil
        defer { isImportingLocalBackup = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try portability.importBackupIntoActiveProfile(data, historyMigration: historyMigration)
            }.value
            recordDetailCache.removeAll()
            recordMonthDetails.removeAll()
            localFactMonths.removeAll()
            let monthKeys = Set([Self.currentMonthKey, String(selectedDateKey.prefix(7))])
            if !mayReadRemoteBusinessData {
                await loadLocalAccounts()
                await applyLocalStagingProjection()
            }
            for monthKey in monthKeys { await refreshLocalMonthProjection(monthKey: monthKey) }
            let preserved = result.preservedRows > 0
                ? "包中 \(result.preservedRows) 条历史待核对原文已保留，尚未转为正式记录，不计入日统计。" : ""
            settingsMessage = localWriteMessage("本地恢复完成：新增 \(result.insertedRows) 条，已存在 \(result.skippedRows) 条，恢复 \(result.restoredImages) 张图片。" + preserved)
            await loadLocalHistoryUnresolvedRecords()
            await loadLocalHistoryInventory()
            return true
        } catch {
            if historyMigration != nil { historyMigrationImportError = error }
            settingsMessage = "本地恢复失败：\(error.localizedDescription)"
            return false
        }
    }

    func recordHistoryMigrationFailure(_ error: Error, committed: Bool, phase: String? = nil) -> String {
        let failurePhase = phase ?? historyMigrationPhase
        guard let store = historyMigrationDiagnosticStore else {
            let diagnosticID = UUID().uuidString.lowercased()
            let impact = committed ? "迁移内容已保存（可能包含待核对原文），但后续刷新未完成。" : "本次尚未入账。"
            return "历史迁移在\(failurePhase)暂停。\(impact)请查看错误阶段后处理。诊断编号：\(diagnosticID)。"
        }
        let progressSummary: String? = historyMigrationProgress.map { progress in
            "已读 \(progress.rowsRead) 行、\(progress.pagesRead) 页；原图 \(progress.imagesProcessed)/\(progress.imagesTotal) 张。"
        }
        let entry = store.record(error, phase: failurePhase, accountID: currentUserId.isEmpty ? nil : currentUserId,
            operation: "history-migration", progressSummary: progressSummary,
            attemptID: historyMigrationAttemptID, committed: committed)
        historyMigrationDiagnostic = entry
        return entry.userMessage
    }

    func deleteAccount() async -> Bool {
        guard !isDeletingAccount else { return false }
        let generation = userStateGeneration
        isDeletingAccount = true
        settingsMessage = nil
        defer { isDeletingAccount = false }

        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return false }
            let deletion = try await settingsRepository.deleteAccount(accessToken: session.accessToken)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return false }
            invalidateSession(message: "")
            authMessage = deletion.displayMessage
            authMessageIsError = false
            return true
        } catch {
            guard generation == userStateGeneration else { return false }
            settingsMessage = "账户删除失败：\(error.localizedDescription)"
            return false
        }
    }

    private func updateSettings(
        _ values: [String: AnyCodable],
        apply: (inout NativeUserSettings) -> Void
    ) async {
        guard !isSavingSettings else { return }
        let generation = userStateGeneration
        let previous = userSettings
        apply(&userSettings)
        let consentKeys: Set<String> = ["companion_memory_enabled", "ai_logs_enabled", "prompt_optimization_enabled", "expression_improvement_enabled", "keep_source_images", "image_retention_days"]
        if consentKeys.isDisjoint(with: values.keys) || Set(values.keys).isSubset(of: ["companion_memory_enabled"]) {
            localUserSettingsStore.save(userSettings)
            localUserSettingsStore.saveExplicitConsent(userSettings, keys: Set(values.keys))
            settingsMessage = nil
            return
        }
        isSavingSettings = true
        settingsMessage = nil
        defer { isSavingSettings = false }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            try await settingsRepository.update(
                userId: session.user.id,
                values: values,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            localUserSettingsStore.save(userSettings)
            localUserSettingsStore.saveExplicitConsent(userSettings, keys: Set(values.keys))
        } catch {
            guard generation == userStateGeneration else { return }
            userSettings = previous
            settingsMessage = "设置保存失败：\(error.localizedDescription)"
        }
    }

    func requestShortcutNotificationPermission() async {
        let granted = await ShortcutNotificationService.shared.requestAuthorization()
        ShortcutFeedbackPreferences.applyNotificationAuthorization(granted: granted)
        syncShortcutFeedbackPreferences()
        await refreshNotificationPermissionStatus()
        notificationPermissionMessage = granted
            ? "已开启。快捷指令上传完成后，芥子会弹出结果通知，点击通知可回到 App。"
            : "未开启。请在系统设置里允许芥子通知，快捷指令仍会在“显示结果”里展示摘要。"
    }

    func refreshNotificationPermissionStatus() async {
        notificationPermissionStatusText = await ShortcutNotificationService.shared.authorizationStatusText()
    }

    func presentOnboarding() {
        isOnboardingPresented = true
    }

    func presentOnboardingIfNeeded() {
        guard !shouldDeferOnboardingForExternalRoute else { return }

        if isSignedIn, !currentUserId.isEmpty {
            let deviceCompletion = onboardingProgressStore.completion(for: .device)
            let deviceAccountID = onboardingProgressStore.linkedAccountIDForDeviceProgress()
            if let accountCompletion = onboardingProgressStore.completion(for: .account(currentUserId)) {
                if deviceAccountID == nil || deviceAccountID == currentUserId {
                    if accountCompletion == .completed || deviceCompletion != .completed {
                        onboardingProgressStore.mark(accountCompletion, for: .device)
                    }
                    onboardingProgressStore.linkDeviceProgress(toAccount: currentUserId)
                }
                return
            }

            if let deviceCompletion,
               onboardingProgressStore.linkedAccountIDForDeviceProgress() == currentUserId {
                onboardingProgressStore.mark(deviceCompletion, for: .account(currentUserId))
                return
            }

            if let deviceCompletion,
               onboardingProgressStore.linkedAccountIDForDeviceProgress() == nil {
                onboardingProgressStore.mark(deviceCompletion, for: .account(currentUserId))
                onboardingProgressStore.linkDeviceProgress(toAccount: currentUserId)
                return
            }

            isOnboardingPresented = true
            return
        }

        guard onboardingProgressStore.shouldPresent(for: .device) else { return }
        isOnboardingPresented = true
    }

    func finishOnboarding(skipped: Bool) {
        let completion: NativeOnboardingCompletion = skipped ? .skipped : .completed
        guard isSignedIn, !currentUserId.isEmpty else {
            let deviceExisting = onboardingProgressStore.completion(for: .device)
            if !skipped || deviceExisting != .completed {
                onboardingProgressStore.mark(completion, for: .device)
            }
            isOnboardingPresented = false
            return
        }

        let existing = onboardingProgressStore.completion(for: .account(currentUserId))
        if !skipped || existing != .completed {
            onboardingProgressStore.mark(completion, for: .account(currentUserId))
        }

        let deviceAccountID = onboardingProgressStore.linkedAccountIDForDeviceProgress()
        if deviceAccountID == nil || deviceAccountID == currentUserId {
            let deviceExisting = onboardingProgressStore.completion(for: .device)
            let deviceCompletion = existing == .completed || deviceExisting == .completed
                ? NativeOnboardingCompletion.completed
                : completion
            onboardingProgressStore.mark(deviceCompletion, for: .device)
            onboardingProgressStore.linkDeviceProgress(toAccount: currentUserId)
        }
        isOnboardingPresented = false
    }

    var onboardingScope: OnboardingProgressScope {
        isSignedIn && !currentUserId.isEmpty
            ? .account(currentUserId)
            : .device
    }

    var onboardingStatusText: String {
        onboardingProgressStore.completion(for: onboardingScope)?.statusText ?? "尚未完成"
    }

    func sendTestShortcutNotification() async {
        await ShortcutNotificationService.shared.sendTestNotification()
        await refreshNotificationPermissionStatus()
        notificationPermissionMessage = "已发送测试通知。如果没有声音，请检查静音键、专注模式，以及系统设置里的“声音”开关。"
    }

    func setShortcutNotificationsEnabled(_ enabled: Bool) {
        ShortcutFeedbackPreferences.notificationsEnabled = enabled
        syncShortcutFeedbackPreferences()
    }

    func setShortcutResultCardEnabled(_ enabled: Bool) {
        ShortcutFeedbackPreferences.resultCardEnabled = enabled
        syncShortcutFeedbackPreferences()
    }

    func syncShortcutFeedbackPreferences() {
        shortcutNotificationsEnabled = ShortcutFeedbackPreferences.notificationsEnabled
        shortcutResultCardEnabled = ShortcutFeedbackPreferences.resultCardEnabled
    }

    private func apply(session: SupabaseAuthSession) {
        if !currentUserId.isEmpty, currentUserId != session.user.id {
            resetUserScopedState()
            Task { await RemoteImageRepository.shared.clear() }
        }
        isSignedIn = true
        currentUserId = session.user.id
        ShortcutTrialStore.shared.synchronize(scope: onboardingScope)
        currentUserEmail = session.user.email ?? ""
        refreshLocalSyncState()
    }

    private func updateShortcutCredentialMessage() {
        shortcutCredentialMessage = hasUploadToken
            ? "已同步。快捷指令会自动读取 Keychain，不需要手动填写 upload_token。"
            : "未同步。请先登录芥子。"
    }

    private func save(session: SupabaseAuthSession, uploadToken: String) throws {
        let data = try JSONEncoder().encode(session)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try keychain.setString(json, for: KeychainKeys.authSession)
        try keychain.setString(uploadToken, for: KeychainKeys.uploadToken)
    }

    private func save(session: SupabaseAuthSession) throws {
        let data = try JSONEncoder().encode(session)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try keychain.setString(json, for: KeychainKeys.authSession)
    }

    private func validSession(forceRefresh: Bool = false) async throws -> SupabaseAuthSession {
        if let sessionProvider {
            let session = try await sessionProvider(forceRefresh)
            apply(session: session)
            return session
        }
        if forceRefresh {
            let refreshed = try await authService.refreshSession()
            try save(session: refreshed)
            apply(session: refreshed)
            return refreshed
        }
        let session = try await authService.currentSession()
        try save(session: session)
        apply(session: session)
        return session
    }

    private func isCurrentUserLoad(_ generation: Int, userId: String) -> Bool {
        isSignedIn && generation == userStateGeneration && currentUserId == userId
    }

    private func isExpiredJWTError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("pgrst303") || message.contains("jwt expired")
    }

    private func isInvalidRefreshSessionError(_ error: Error) -> Bool {
        let message = error.localizedDescription.lowercased()
        return message.contains("invalid refresh token")
            || message.contains("refresh token not found")
            || message.contains("refresh_token_not_found")
            || message.contains("already used")
            || message.contains("session_not_found")
    }

    private func invalidateSession(message: String) {
        disableLocalSync()
        try? keychain.remove(KeychainKeys.authSession)
        try? keychain.remove(KeychainKeys.uploadToken)
        isSignedIn = false
        currentUserId = ""
        ShortcutTrialStore.shared.synchronize(scope: onboardingScope)
        currentUserEmail = ""
        hasUploadToken = false
        shortcutCredentialMessage = nil
        resetUserScopedState()
        refreshLocalSyncState()
        presentedOverlay = .records
        Task { await RemoteImageRepository.shared.clear() }
        authMessage = message
        authMessageIsError = !message.isEmpty
    }

    func resetUserScopedState() {
        localHistoryUnresolvedRecords = []
        isLoadingHistoryUnresolvedRecords = false
        historyUnresolvedRecordsError = nil
        historyMigrationUnresolvedCount = 0
        historyMigrationPreservationIssues = []
        cloudHistoryInventory = .notRead
        isReadingCloudHistoryInventory = false
        localSyncFailureDiagnostic = nil
        localProjectionRefreshDiagnostic = nil
        if let profileID = historyMigrationProfileID,
           let state = try? localHistoryMigrationCache?.state(profileID: profileID), state.status == .running {
            try? localHistoryMigrationCache?.pause(state)
        }
        historyMigrationProfileID = nil
        historyMigrationProgress = nil
        historyMigrationBlockers = []
        historyMigrationBlockerCount = 0
        historyMigrationArchive = nil
        historyMigrationPreview = nil
        historyMigrationOwner = nil
        historyMigrationGeneration = nil
        historyMigrationSourceDigest = nil
        historyMigrationImageDigests = [:]
        historyMigrationCheckpoint = nil
        historyMigrationAttempt += 1
        historyMigrationAttemptID = UUID()
        canPauseHistoryMigration = false
        historyMigrationMessage = nil
        isPreparingHistoryMigration = false
        historyMigrationPhase = ""
        historyMigrationDiagnostic = nil
        homePath = NavigationPath()
        dashboardRefreshGeneration += 1
        userStateGeneration += 1
        stagingReadVersion += 1
        localMonthReadVersions.removeAll()
        loadingLocalReadKeys.removeAll()
        walletSnapshotActionUseCase?.reset()
        repaymentActionUseCase?.reset()
        accountManagementActionUseCase?.reset()
        accountReadPreparationUseCase?.reset()
        screenshotRepaymentUseCase?.reset()
        accountBindingUseCase?.reset()
        stagingLifecycleUseCase?.reset()
        pendingConfirmationUseCase?.reset()
        feedbackSubmissionUseCase?.reset()
        recordDetailImageUseCase?.reset()
        thumbnailImageUseCase?.reset()
        dashboardSupplementTask?.cancel()
        dashboardSupplementTask = nil
        dashboardCoreTask?.cancel()
        dashboardCoreTask = nil
        isLoadingDashboard = false
        dashboard = DashboardSnapshot()
        todayPath = NavigationPath()
        inboxPath = NavigationPath()
        recordsPath = NavigationPath()
        selectedRecordDetail = nil
        recordMonthGroups = [:]
        remoteRecordMonthGroups = [:]
        localExpenseMonthGroups = [:]
        localIncomeMonthGroups = [:]
        localRecordMonthGroups = [:]
        localRecordMonthDetails = [:]
        localFactMonths = [:]
        recordMonthDetails = [:]
        recordMonthMessages = [:]
        loadingRecordMonthKey = nil
        loadingLocalExpenseMonthKey = nil
        loadingLocalRecordMonthKey = nil
        for task in remoteRecordMonthTasks.values { task.cancel() }
        remoteRecordMonthTasks.removeAll()
        loadingRemoteRecordMonthKeys.removeAll()
        recordDetailCache.removeAll()
        activeRecordReference = nil
        prefetchingRecordReferences.removeAll()
        expressionPlanDeliveryTokens.removeAll()
        pendingRecordExpressionPlans.removeAll()
        expressionPlanAcknowledgementTokens.removeAll()
        visibleRecordExpressionPlanCards.removeAll()
        recordDetailMessage = nil
        isSavingRecordDetail = false
        isDeletingRecordDetail = false
        recordFeedbackState = .idle
        recordExpressionPlanExposureState = .idle
        manualRecordMessage = nil
        accounts = []
        financeVocabulary = []
        isLoadingFinanceVocabulary = false
        selectedAccountDetail = nil
        selectedAccountSourceSnapshot = nil
        accountMessage = nil
        localSyncState = nil
        localSyncDiagnostic = nil
        localBindingPreview = nil
        isLoadingLocalBindingPreview = false
        isSynchronizingLocalData = false
        localSyncMessage = nil
        isLoadingAccounts = false
        isSavingAccount = false
        isSubmittingRepayment = false
        repaymentMessage = nil
        repaymentCandidates = [:]
        stagingRepaymentId = nil
        inboxFinanceMessage = nil
        inboxActionRecordId = nil
        inboxActionMessage = nil
        inboxActionMessageIsError = false
        unboundRecords = []
        unboundRecordsMessage = nil
        unboundBindingMessage = nil
        walletSnapshots = []
        localWalletSnapshots = []
        localWalletSnapshotHistory = []
        isLoadingWalletSnapshots = false
        walletSnapshotActionId = nil
        walletSnapshotMessage = nil
        insightsSnapshot = nil
        insightsLoadedLocally = false
        isLoadingInsights = false
        insightsMessage = nil
        insightsLoadedAt = nil
        aiInsight = nil
        isLoadingAIInsight = false
        aiInsightMessage = nil
        aiInsightIsCached = false
        userSettings = localUserSettingsStore.load()
        settingsMessage = nil
        isLoadingSettings = false
        isSavingSettings = false
        isCleaningSourceImages = false
        isExportingData = false
        isDeletingAccount = false
        isOnboardingPresented = false
        dashboardMessage = nil
        isShowingCachedDashboard = false
        presentedOverlay = .none
        selectedDomain = .expense
        lastDashboardRefreshAt = nil
    }

    private func requireSession() throws -> SupabaseAuthSession {
        guard let sessionJSON = try keychain.string(for: KeychainKeys.authSession),
              let data = sessionJSON.data(using: .utf8),
              let session = try? JSONDecoder().decode(SupabaseAuthSession.self, from: data) else {
            throw SupabaseRemoteError.missingSession
        }
        return session
    }

    func createManualRecord(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?) async -> Bool {
        guard !isCreatingManualRecord else { return false }
        guard localStorageInitializationMessage == nil else {
            manualRecordMessage = localStorageInitializationMessage
            return false
        }
        isCreatingManualRecord = true
        manualRecordMessage = nil
        defer { isCreatingManualRecord = false }

        do {
            return try await createUnifiedManualRecord(draft, domain: domain)
        } catch {
            manualRecordMessage = error.localizedDescription
            return false
        }
    }

    func prepareLocalWorkspace() async -> LocalExpenseWorkspace? {
        guard let localExpenseUseCase else { return nil }
        do {
            let workspace = try await localExpenseUseCase.prepareWorkspace()
            localAccounts = workspace.accounts
            var balances: [UUID: Int64] = [:]
            for account in workspace.accounts {
                balances[account.id] = try await localExpenseUseCase.accountBalanceMinor(account.id)
            }
            localAccountBalances = balances
            localAccountMessage = nil
            return workspace
        } catch {
            localAccountMessage = error.localizedDescription
            return nil
        }
    }

    func createLocalAccount(_ command: LocalAccountSetupCommand) async -> LocalAccount? {
        guard let localExpenseUseCase else { return nil }
        do {
            let account = try await localExpenseUseCase.createAccount(command)
            await loadLocalAccounts()
            localAccountMessage = nil
            return account
        } catch {
            localAccountMessage = error.localizedDescription
            return nil
        }
    }

    func createLocalExpense(
        amountText: String,
        accountID: UUID,
        merchantName: String,
        platform: String,
        category: String,
        paymentMethod: String,
        date: Date,
        note: String
    ) async -> Bool {
        let draft = NativeManualRecordDraft(
            kind: .expense,
            accountID: accountID,
            amountText: amountText,
            title: merchantName,
            platform: platform,
            category: category,
            paymentMethod: paymentMethod,
            date: date,
            note: note
        )
        return await createManualRecord(draft, domain: nil)
    }

    private func createLocalExpense(_ draft: NativeManualRecordDraft) async throws -> Bool {
        guard draft.existingRawId == nil else { throw LocalDataError.invalidRecord }
        guard let localExpenseUseCase else {
            throw LocalDataError.invalidIdentifier
        }
        let accountText = draft.accountId
        let accountID = accountText.flatMap(UUID.init(uuidString:))
        // A user can open the form while the background account refresh is
        // still running. Ensure a cloud account selected by the unified form
        // exists in the local projection before validating the expense.
        if let accountID, !localAccounts.contains(where: { $0.id == accountID }),
           let cloudAccount = accounts.first(where: { $0.id == accountText }) {
            let mirror = LocalAccount(
                id: accountID,
                profileID: UUID(),
                name: cloudAccount.name,
                kind: cloudAccount.type.rawValue,
                currency: cloudAccount.currency,
                openingBalanceMinor: Int64((cloudAccount.initialBalance * 100).rounded()),
                createdAt: Date(),
                institution: cloudAccount.institution,
                last4: cloudAccount.last4,
                billDay: cloudAccount.billDay,
                paymentDueDay: cloudAccount.paymentDueDay,
                autoDebitAccountID: cloudAccount.autoDebitAccountId.flatMap(UUID.init(uuidString:)),
                autoConfirmRepayment: cloudAccount.autoConfirmRepayment,
                gracePeriodDays: cloudAccount.gracePeriodDays,
                lastReconciledAt: Self.parseISO8601(cloudAccount.lastReconciledAt),
                isDefaultExpense: cloudAccount.isDefaultExpense,
                isDefaultIncome: cloudAccount.isDefaultIncome,
                isArchived: cloudAccount.isArchived,
                sortOrder: cloudAccount.sortOrder
            )
            try await localExpenseUseCase.importRemoteAccounts([mirror])
            _ = await prepareLocalWorkspace()
        }
        let command = LocalExpenseCommand(
            id: UUID(),
            accountID: accountID,
            amountText: draft.amountText,
            currency: "CNY",
            merchantName: draft.title,
            platform: draft.platform,
            category: draft.category,
            paymentMethod: draft.paymentMethod,
            transactionDate: NativeLocalDate.dateKey(draft.date),
            transactionTime: draft.includesTime ? NativeLocalDate.timeKey(draft.time) : nil,
            note: draft.note.isEmpty ? nil : draft.note,
            createdAt: Date(), imageData: draft.imageData
        )
        let outcome = try await localExpenseUseCase.create(command)
        _ = await prepareLocalWorkspace()
        let monthKey = String(command.transactionDate.prefix(7))
        await refreshLocalMonthProjection(monthKey: monthKey)
        manualRecordMessage = outcome.expense == nil ? "本地记录未保存" : localWriteMessage(accountID == nil ? "记录已保存（仅本机，补绑后可同步）" : "记录已保存（本机）")
        return outcome.expense != nil
    }

    private func createLocalIncome(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?
    ) async throws -> Bool {
        guard draft.existingRawId == nil, let localExpenseUseCase else { throw LocalDataError.invalidRecord }
        guard draft.validationMessage(domain: domain) == nil else { throw LocalDataError.invalidRecord }
        let accountID = draft.accountId.flatMap(UUID.init(uuidString:))
        if let accountID, !localAccounts.contains(where: { $0.id == accountID }),
           let cloudAccount = accounts.first(where: { $0.id == accountID.uuidString }) {
            let mirror = LocalAccount(
                id: accountID, profileID: UUID(), name: cloudAccount.name,
                kind: cloudAccount.type.rawValue, currency: cloudAccount.currency,
                openingBalanceMinor: Int64((cloudAccount.initialBalance * 100).rounded()), createdAt: Date(),
                institution: cloudAccount.institution, last4: cloudAccount.last4,
                billDay: cloudAccount.billDay, paymentDueDay: cloudAccount.paymentDueDay,
                autoDebitAccountID: cloudAccount.autoDebitAccountId.flatMap(UUID.init(uuidString:)),
                autoConfirmRepayment: cloudAccount.autoConfirmRepayment, gracePeriodDays: cloudAccount.gracePeriodDays,
                lastReconciledAt: Self.parseISO8601(cloudAccount.lastReconciledAt),
                isDefaultExpense: cloudAccount.isDefaultExpense, isDefaultIncome: cloudAccount.isDefaultIncome,
                isArchived: cloudAccount.isArchived, sortOrder: cloudAccount.sortOrder
            )
            try await localExpenseUseCase.importRemoteAccounts([mirror])
            _ = await prepareLocalWorkspace()
        }
        let occurredAt: Date?
        if let timestamp = draft.occurredAt {
            guard let parsed = ISO8601DateFormatter().date(from: timestamp),
                  NativeLocalDate.dateKey(parsed) == draft.dateKey else {
                throw LocalDataError.invalidRecord
            }
            occurredAt = parsed
        } else {
            occurredAt = nil
        }
        let saved = try await localExpenseUseCase.createIncome(LocalIncomeCommand(
            id: UUID(), accountID: accountID, amountText: draft.amountText, currency: "CNY",
            sourceName: draft.title, category: draft.category, incomeDate: draft.dateKey,
            occurredAt: occurredAt,
            note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
            createdAt: Date(), imageData: draft.imageData
        ))
        _ = await prepareLocalWorkspace()
        await refreshLocalMonthProjection(monthKey: String(saved.incomeDate.prefix(7)))
        manualRecordMessage = localWriteMessage("收入已记录（本机）")
        return true
    }

    private func createLocalDomainRecord(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?
    ) async throws -> Bool {
        guard let localRecordUseCase,
              LocalRecordValidation.supportedDomainKeys.contains(draft.domainKey) else {
            throw LocalDataError.invalidRecord
        }
        guard draft.validationMessage(domain: domain) == nil else {
            throw LocalDataError.invalidRecord
        }
        let payload = draft.universalPayload(domain: domain)
        let title = draft.resolvedTitle(domain: domain)
        let summary = draft.resolvedSummary(domain: domain)
        let record: LocalRecord
        var previousMonthKey: String?
        if let existingRawId = draft.existingRawId {
            guard let existingID = UUID(uuidString: existingRawId) else {
                throw LocalDataError.invalidIdentifier
            }
            guard let current = try await localRecordUseCase.record(id: existingID) else {
                throw LocalDataError.recordNotFound
            }
            previousMonthKey = String(current.businessDate.prefix(7))
            let updated = try await localRecordUseCase.update(LocalRecordUpdateCommand(
                id: existingID,
                expectedVersion: current.localVersion,
                title: title,
                summary: summary,
                payload: payload,
                recordDate: draft.dateKey,
                recordTime: draft.timeKey,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
                updatedAt: Date(),
                imageData: draft.imageData,
                removeImage: draft.removeImage
            ))
            record = updated.record
        } else {
            let created = try await localRecordUseCase.create(LocalRecordCommand(
                id: UUID(),
                domainKey: draft.domainKey,
                title: title,
                summary: summary,
                payload: payload,
                recordDate: draft.dateKey,
                recordTime: draft.timeKey,
                note: draft.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : draft.note,
                imageData: draft.imageData,
                createdAt: Date()
            ))
            record = created.record
        }
        let monthKey = String(record.recordDate.prefix(7))
        if let previousMonthKey, previousMonthKey != monthKey {
            await refreshLocalMonthProjection(monthKey: previousMonthKey)
        }
        await refreshLocalMonthProjection(monthKey: monthKey)
        if let existingRawId = draft.existingRawId {
            let oldReference = "local-data/\(existingRawId)"
            invalidateRecordExpressionPlanState(afterChanging: [oldReference])
            recordDetailCache.removeValue(forKey: NativeRecordReference(oldReference).canonicalValue)
            await loadRecordDetail(reference: "local-data/\(record.id.uuidString)", force: true)
        }
        manualRecordMessage = localWriteMessage(draft.existingRawId == nil ? "记录已保存（本机）" : "记录已更新（本机）")
        return true
    }

    private func createUnifiedManualRecord(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?
    ) async throws -> Bool {
        if draft.kind != .universal, let existingID = draft.existingRawId,
           let id = UUID(uuidString: existingID), let localExpenseUseCase {
            let oldDate: String
            if draft.kind == .expense {
                guard let current = try await localExpenseUseCase.expense(id: id) else { throw LocalDataError.recordNotFound }
                oldDate = current.transactionDate
                _ = try await localExpenseUseCase.update(LocalExpenseUpdateCommand(id: id,
                    expectedVersion: draft.localVersion ?? current.localVersion,
                    accountID: draft.accountId.flatMap(UUID.init(uuidString:)), amountText: draft.amountText,
                    currency: current.currency, merchantName: draft.title, platform: draft.platform,
                    category: draft.category, paymentMethod: draft.paymentMethod,
                    transactionDate: draft.dateKey, transactionTime: draft.timeKey, note: draft.note,
                    updatedAt: Date(), imageData: draft.imageData, removeImage: draft.removeImage))
            } else {
                guard let current = try await localExpenseUseCase.income(id: id) else { throw LocalDataError.recordNotFound }
                oldDate = current.incomeDate
                _ = try await localExpenseUseCase.updateIncome(LocalIncomeUpdate(id: id, profileID: current.profileID,
                    expectedVersion: draft.localVersion ?? current.localVersion,
                    accountID: draft.accountId.flatMap(UUID.init(uuidString:)),
                    amountMinor: try LocalExpenseMapper.amountMinor(draft.amountText), currency: current.currency,
                    sourceName: draft.title, category: draft.category, incomeDate: draft.dateKey,
                    occurredAt: draft.occurredAt.flatMap { ISO8601DateFormatter().date(from: $0) }, note: draft.note,
                    updatedAt: Date(), imageData: draft.imageData, removeImage: draft.removeImage))
            }
            _ = await prepareLocalWorkspace()
            await refreshLocalMonthProjection(monthKey: String(oldDate.prefix(7)))
            if String(oldDate.prefix(7)) != String(draft.dateKey.prefix(7)) {
                await refreshLocalMonthProjection(monthKey: String(draft.dateKey.prefix(7)))
            }
            let reference = "\(draft.kind == .expense ? "expense" : "income")/\(id.uuidString)"
            recordDetailCache.removeValue(forKey: NativeRecordReference(reference).canonicalValue)
            await loadRecordDetail(reference: reference, force: true)
            await retryLocalImageCleanups()
            manualRecordMessage = localWriteMessage("记录已更新（本机）")
            return true
        }
        if draft.kind == .universal, draft.domainKey == "wallet",
           draft.existingRawId == nil, localWalletSnapshotUseCase != nil {
            return try await createLocalWalletSnapshot(draft, domain: domain)
        }
        if draft.kind == .expense, localExpenseUseCase != nil {
            return try await createLocalExpense(draft)
        }
        if draft.kind == .income, localExpenseUseCase != nil {
            return try await createLocalIncome(draft, domain: domain)
        }
        if draft.kind == .universal,
           localRecordUseCase != nil,
           LocalRecordValidation.supportedDomainKeys.contains(draft.domainKey),
           await shouldCreateLocalDomainRecord(for: draft) {
            return try await createLocalDomainRecord(draft, domain: domain)
        }
        return try await createRemoteManualRecord(draft, domain: domain)
    }

    private func createLocalWalletSnapshot(
        _ draft: NativeManualRecordDraft,
        domain: NativeDomainDefinition?
    ) async throws -> Bool {
        guard let localWalletSnapshotUseCase, draft.existingRawId == nil,
              draft.validationMessage(domain: domain) == nil else {
            throw LocalDataError.invalidRecord
        }
        let amountMinor = try LocalExpenseMapper.amountMinor(draft.primaryValueText)
        let payload = draft.universalPayload(domain: domain)
        _ = try await localWalletSnapshotUseCase.create(LocalWalletSnapshotCommand(
            id: UUID(),
            title: draft.resolvedTitle(domain: domain),
            summary: draft.resolvedSummary(domain: domain),
            payload: payload,
            recordDate: draft.dateKey,
            recordTime: draft.timeKey,
            occurredAt: draft.occurredAt,
            balanceMinor: amountMinor,
            currency: "CNY",
            kind: draft.walletRecordKind == "liability_snapshot" ? .liability : .asset,
            imageData: draft.imageData,
            createdAt: Date()
        ))
        do {
            try await loadLocalWalletSnapshots()
        } catch {
            manualRecordMessage = "快照已保存在本机，但列表刷新失败：\(error.localizedDescription)"
            return true
        }
        manualRecordMessage = "钱包快照已保存（本机）"
        return true
    }

    private func shouldCreateLocalDomainRecord(for draft: NativeManualRecordDraft) async -> Bool {
        guard let localRecordUseCase else { return false }
        guard let existingRawId = draft.existingRawId else { return true }
        guard let existingID = UUID(uuidString: existingRawId) else { return false }
        return (try? await localRecordUseCase.record(id: existingID)) != nil
    }

    private func createRemoteManualRecord(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?) async throws -> Bool {
        let session = try await validSession()
        let reference = try await recordRepository.create(
            draft,
            domain: domain,
            userId: session.user.id,
            accessToken: session.accessToken
        )
        let savedReference = NativeRecordReference(reference).canonicalValue
        if let existingRawId = draft.existingRawId {
            let originalReference = NativeRecordReference(
                kind: "data",
                rawId: existingRawId
            ).canonicalValue
            invalidateRecordExpressionPlanState(afterChanging: [originalReference, savedReference])
        }
        if draft.kind == .expense {
            scheduleConfirmedExpenseVocabulary(
                platform: draft.platform,
                category: draft.category,
                paymentMethod: draft.paymentMethod,
                accountId: draft.accountId,
                userId: session.user.id,
                accessToken: session.accessToken
            )
        }
        await refreshAfterRecordWrite(affectedDateKeys: [draft.dateKey])
        if draft.kind != .universal || draft.domainKey == "wallet" {
            await loadAccounts()
        }
        if draft.existingRawId != nil {
            recordDetailCache.removeValue(forKey: savedReference)
            await loadRecordDetail(reference: savedReference, force: true)
        }
        manualRecordMessage = draft.existingRawId == nil ? "记录已保存" : "记录已更新"
        return true
    }

    private static func makeDefaultLocalStorage() throws -> AppDefaultLocalStorage {
        let database = try LocalDatabase()
        let imageStore = try LocalImageStore()
        let profileStore = LocalProfileStore(database: database)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let recordRepository = try LocalRecordRepository(database: database)
        let walletSnapshotRepository = try LocalWalletSnapshotRepository(database: database)
        let factReader = try LocalFactReader(database: database)
        return AppDefaultLocalStorage(
            expenseUseCase: LocalExpenseUseCase(profileStore: profileStore, repository: expenseRepository, imageStore: imageStore),
            recordUseCase: LocalRecordUseCase(
                profileStore: profileStore,
                repository: recordRepository,
                imageStore: imageStore
            ),
            walletSnapshotUseCase: LocalWalletSnapshotUseCase(
                profileStore: profileStore,
                repository: walletSnapshotRepository,
                imageStore: imageStore
            ),
            factReader: factReader,
            imageStore: imageStore,
            pendingFinancialRepository: LocalPendingFinancialRepository(database: database),
            financialBindingRepository: try LocalFinancialBindingRepository(database: database),
            historyMigrationCache: LocalHistoryMigrationCache(database: database, imageStore: imageStore),
            historyMigrationDiagnosticStore: try? LocalHistoryMigrationDiagnosticStore(),
            historyInventoryReader: LocalHistoryInventoryReader(database: database, imageStore: imageStore),
            historyUnresolvedRepository: LocalHistoryUnresolvedRepository(database: database)
        )
    }

    private static func defaultLocalExpenseUseCase() -> LocalExpenseUseCaseProtocol? {
        guard let database = try? LocalDatabase(),
              let repository = try? LocalExpenseRepository(database: database),
              let imageStore = try? LocalImageStore() else { return nil }
        return LocalExpenseUseCase(profileStore: LocalProfileStore(database: database), repository: repository, imageStore: imageStore)
    }

    private static func defaultLocalRecordUseCase() -> LocalRecordUseCaseProtocol? {
        guard let database = try? LocalDatabase(),
              let repository = try? LocalRecordRepository(database: database),
              let imageStore = try? LocalImageStore() else { return nil }
        return LocalRecordUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: repository,
            imageStore: imageStore
        )
    }

    private static func defaultLocalImageStore() -> LocalImageStore? {
        try? LocalImageStore()
    }

    private static func defaultLocalImageIntakeRepository() -> LocalImageIntakeRepository? {
        guard let database = try? LocalDatabase() else { return nil }
        return LocalImageIntakeRepository(database: database)
    }

    private static func defaultLocalRecordPortability() -> LocalRecordPortability? {
        guard let database = try? LocalDatabase(),
              let imageStore = try? LocalImageStore() else { return nil }
        return LocalRecordPortability(database: database, imageStore: imageStore)
    }

    private static func defaultLocalFactPortability() -> LocalFactPortability? {
        guard let database = try? LocalDatabase(),
              let imageStore = try? LocalImageStore() else { return nil }
        return LocalFactPortability(database: database, imageStore: imageStore)
    }

    private static func defaultLocalCompleteBackupPortability() -> LocalCompleteBackupPortability? {
        guard let database = try? LocalDatabase(),
              let imageStore = try? LocalImageStore() else { return nil }
        return LocalCompleteBackupPortability(database: database, imageStore: imageStore)
    }

    private static func defaultLocalBindingRepository() -> LocalBindingRepository? {
        guard let database = try? LocalDatabase() else { return nil }
        return LocalProfileStore(database: database)
    }

    private static func defaultLocalSyncRunner() -> LocalSyncRunner? {
        guard let database = try? LocalDatabase(),
              let repository = try? LocalExpenseRepository(database: database) else { return nil }
        let profileStore = LocalProfileStore(database: database)
        let transport = SupabaseSyncTransport(
            remoteClient: SupabaseRemoteClient(),
            accessToken: {
                try await SupabaseAuthService().currentSession().accessToken
            }
        )
        return LocalSyncCoordinator(
            stateStore: profileStore,
            repository: repository,
            portability: LocalExpensePortability(database: database),
            transport: transport
        )
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

/// 五域主场景的横滑域（IOS-V2-SHELL-001）。
enum AppDomain: String, CaseIterable, Identifiable {
    case expense
    case sleep
    case food
    case sport
    case reading

    var id: String { rawValue }

    static func pagerDomain(at x: CGFloat) -> AppDomain? {
        let width = JieziPrototypeLayout.page_dot_hit_width
        guard x.isFinite, width > 0 else { return nil }
        if x <= 0 { return allCases.first }
        if x >= CGFloat(allCases.count) * width { return allCases.last }
        return allCases[Int(x / width)]
    }

    var title: String {
        switch self {
        case .expense: return "记账"
        case .sleep: return "睡眠"
        case .food: return "饮食"
        case .sport: return "运动"
        case .reading: return "阅读"
        }
    }

    var systemImage: String {
        switch self {
        case .expense: return "creditcard"
        case .sleep: return "moon.zzz"
        case .food: return "fork.knife"
        case .sport: return "figure.run"
        case .reading: return "book"
        }
    }

    /// 新壳五域与 dashboard.domains 中旧域 key 的对应关系（用于空态判定与后续内容接线）。
    var legacyDomainKey: String {
        switch self {
        case .expense: return "expense"
        case .sleep, .food, .sport, .reading: return rawValue
        }
    }
}

/// 主场景之上的全屏覆盖层（IOS-V2-SHELL-004）；`.none` 表示无覆盖层、停留在五域横滑。
enum AppOverlay: String, CaseIterable, Identifiable {
    case none
    case inbox
    case records
    case insights
    case wallet
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return ""
        case .inbox: return "收件箱"
        case .records: return "记录"
        case .insights: return "观察"
        case .wallet: return "钱包"
        case .settings: return "设置"
        }
    }
}
