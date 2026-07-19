import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var selectedTab: AppTab = .today
    @Published var isSignedIn = false
    @Published var currentUserId = ""
    @Published var currentUserEmail = ""
    @Published var lastShortcutMessage: String?
    @Published var isBootstrapping = true
    @Published var isSigningIn = false
    @Published var authMessage: String?
    @Published var authMessageIsError = false
    @Published var hasUploadToken = false
    @Published var dashboard = DashboardSnapshot()
    @Published var dashboardMessage: String?
    @Published var isLoadingDashboard = false
    @Published var isShowingCachedDashboard = false
    @Published var shortcutCredentialMessage: String?
    @Published var notificationPermissionMessage: String?
    @Published var notificationPermissionStatusText = "检查中"
    @Published var shortcutNotificationsEnabled = ShortcutFeedbackPreferences.notificationsEnabled
    @Published var shortcutResultCardEnabled = ShortcutFeedbackPreferences.resultCardEnabled
    @Published var todayPath = NavigationPath()
    @Published var inboxPath = NavigationPath()
    @Published var recordsPath = NavigationPath()
    @Published var selectedRecordDetail: NativeRecordDetail?
    @Published var recordDetailMessage: String?
    @Published var isSavingRecordDetail = false
    @Published var isDeletingRecordDetail = false
    @Published var recordFeedbackState: NativeAIFeedbackReviewState = .idle
    @Published var isCreatingManualRecord = false
    @Published var manualRecordMessage: String?
    @Published var recordMonthGroups: [String: [NativeDayRecordGroup]] = [:]
    @Published var recordMonthMessages: [String: String] = [:]
    @Published var loadingRecordMonthKey: String?
    @Published var accounts: [NativeAccount] = []
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
    @Published var settingsMessage: String?
    @Published var isLoadingSettings = false
    @Published var isSavingSettings = false
    @Published var isCleaningSourceImages = false
    @Published var isExportingData = false
    @Published var isDeletingAccount = false

    private let authService = SupabaseAuthService()
    private let dashboardRepository: DashboardRepositoryProtocol
    private let recordRepository: RecordRepositoryProtocol
    private let inboxRepository: InboxRepositoryProtocol
    private let domainRepository: DomainRepositoryProtocol
    private let snapshotStore: DashboardSnapshotStoreProtocol
    private let accountRepository: AccountRepositoryProtocol
    private let unboundRecordRepository: UnboundRecordRepositoryProtocol
    private let walletSnapshotRepository: WalletSnapshotRepositoryProtocol
    private let insightsRepository: InsightsRepositoryProtocol
    private let settingsRepository: SettingsRepositoryProtocol
    private let keychain = KeychainStore.shared
    private var hasAskedNotificationPermissionThisSession = false
    private var lastDashboardRefreshAt: Date?
    private var recordDetailCache: [String: NativeRecordDetail] = [:]
    private var recordMonthDetails: [String: [String: NativeRecordDetail]] = [:]
    private var activeRecordReference: String?
    private var prefetchingRecordReferences: Set<String> = []
    private var insightsLoadedAt: Date?
    private var dashboardRefreshGeneration = 0
    private var userStateGeneration = 0
    private var dashboardSupplementTask: Task<Void, Never>?

    init(
        dashboardRepository: DashboardRepositoryProtocol = DashboardRepository(),
        recordRepository: RecordRepositoryProtocol = RecordRepository(),
        inboxRepository: InboxRepositoryProtocol = InboxRepository(),
        domainRepository: DomainRepositoryProtocol = DomainRepository(),
        snapshotStore: DashboardSnapshotStoreProtocol = DashboardSnapshotStore(),
        accountRepository: AccountRepositoryProtocol = AccountRepository(),
        unboundRecordRepository: UnboundRecordRepositoryProtocol = UnboundRecordRepository(),
        walletSnapshotRepository: WalletSnapshotRepositoryProtocol = WalletSnapshotRepository(),
        insightsRepository: InsightsRepositoryProtocol = InsightsRepository(),
        settingsRepository: SettingsRepositoryProtocol = SettingsRepository()
    ) {
        self.dashboardRepository = dashboardRepository
        self.recordRepository = recordRepository
        self.inboxRepository = inboxRepository
        self.domainRepository = domainRepository
        self.snapshotStore = snapshotStore
        self.accountRepository = accountRepository
        self.unboundRecordRepository = unboundRecordRepository
        self.walletSnapshotRepository = walletSnapshotRepository
        self.insightsRepository = insightsRepository
        self.settingsRepository = settingsRepository
    }

    func bootstrap() {
        Task {
            await restoreAuthentication()
            isBootstrapping = false
            await refreshNotificationPermissionStatus()
        }
    }

    private func restoreAuthentication() async {
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
            try save(session: session)
            apply(session: session)
            restoreDashboardSnapshot(userId: session.user.id)
            hasUploadToken = (try keychain.string(for: KeychainKeys.uploadToken))?.isEmpty == false
            updateShortcutCredentialMessage()
            Task {
                await refreshDashboard()
                await requestShortcutNotificationPermissionIfNeeded()
            }
        } catch {
            if isInvalidRefreshSessionError(error) {
                invalidateSession(message: "登录状态已失效，请重新登录。")
            } else {
                authMessage = error.localizedDescription
                authMessageIsError = true
            }
        }
    }

    func signIn(email: String, password: String) async {
        guard !isSigningIn else { return }
        isSigningIn = true
        authMessage = nil
        authMessageIsError = false

        do {
            let session = try await authService.signIn(email: email, password: password)
            let uploadToken = try await authService.fetchUploadToken(
                userId: session.user.id,
                accessToken: session.accessToken
            )
            try save(session: session, uploadToken: uploadToken)
            apply(session: session)
            hasUploadToken = true
            authMessage = "已登录，快捷指令凭据已同步。"
            updateShortcutCredentialMessage()
            await refreshDashboard()
            await requestShortcutNotificationPermissionIfNeeded()
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
                await refreshDashboard()
                await requestShortcutNotificationPermissionIfNeeded()
            }
        } catch {
            authMessage = error.localizedDescription
            authMessageIsError = true
        }
    }

    func signOut() {
        let userId = try? requireSession().user.id
        Task {
            try? await authService.signOut()
            do {
                try keychain.remove(KeychainKeys.authSession)
                try keychain.remove(KeychainKeys.uploadToken)
            } catch {
                authMessage = error.localizedDescription
                authMessageIsError = true
            }
            if let userId { try? snapshotStore.remove(userId: userId) }
            invalidateSession(message: "")
            authMessage = nil
            authMessageIsError = false
            hasUploadToken = false
            shortcutCredentialMessage = nil
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

    func refreshDashboard() async {
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

        do {
            let (fetchedSnapshot, session) = try await fetchDashboardCoreWithValidSession()
            guard generation == dashboardRefreshGeneration else { return }
            let snapshot = preparedCoreSnapshot(fetchedSnapshot)
            publishDashboard(snapshot, userId: session.user.id)
            scheduleDashboardSupplement(snapshot, session: session, generation: generation)
        } catch {
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
            recordDetailCache[NativeRecordReference(detail.id).canonicalValue] = detail
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
            if let selectedId = self.selectedRecordDetail?.id,
               let selected = supplemented.recordDetails.values.first(where: {
                   NativeRecordReference($0.id).canonicalValue == NativeRecordReference(selectedId).canonicalValue
               }) {
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
        Task {
            await RemoteImageRepository.shared.prefetch(urls)
        }
    }

    func refreshDashboardIfStale(minInterval: TimeInterval = 3, force: Bool = false) async {
        guard isSignedIn else { return }
        if !force,
           let lastDashboardRefreshAt,
           Date().timeIntervalSince(lastDashboardRefreshAt) < minInterval {
            return
        }
        await refreshDashboard()
    }

    func recordGroups(monthKey: String) -> [NativeDayRecordGroup] {
        if monthKey == Self.currentMonthKey {
            return dashboard.dayRecordGroups
        }
        return recordMonthGroups[monthKey] ?? []
    }

    func loadRecordMonth(_ monthKey: String, force: Bool = false) async {
        guard monthKey != Self.currentMonthKey else {
            if force { await refreshDashboard() }
            return
        }
        guard force || recordMonthGroups[monthKey] == nil else { return }
        guard loadingRecordMonthKey != monthKey else { return }
        let generation = userStateGeneration
        loadingRecordMonthKey = monthKey
        recordMonthMessages.removeValue(forKey: monthKey)
        defer {
            if loadingRecordMonthKey == monthKey { loadingRecordMonthKey = nil }
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
                recordDetailCache[NativeRecordReference(reference).canonicalValue] = detail
            }
            recordMonthGroups[monthKey] = month.groups
        } catch {
            guard generation == userStateGeneration else { return }
            recordMonthMessages[monthKey] = error.localizedDescription
        }
    }

    func reportSnapshot(monthKey: String) -> DashboardSnapshot {
        if monthKey == Self.currentMonthKey { return dashboard }
        let groups = recordMonthGroups[monthKey] ?? []
        let details = recordMonthDetails[monthKey] ?? [:]
        let records = groups.flatMap(\.records).filter { $0.kind != .staging }
        var snapshot = DashboardSnapshot()
        snapshot.dayRecordGroups = groups
        snapshot.recordDetails = details
        snapshot.monthCount = records.count
        snapshot.monthExpense = details.values
            .filter { $0.kind == "expense" }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        snapshot.monthIncome = details.values
            .filter { $0.kind == "income" }
            .reduce(0) { $0 + ($1.amount ?? 0) }
        let definitions = dashboard.domains.isEmpty ? Self.fallbackDomains : dashboard.domains
        snapshot.domains = domainsWithUpdatedCounts(definitions, snapshot: snapshot)
        return snapshot
    }

    func loadAccounts() async {
        guard !isLoadingAccounts else { return }
        let generation = userStateGeneration
        isLoadingAccounts = true
        accountMessage = nil
        defer { isLoadingAccounts = false }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let loadedAccounts = try await accountRepository.fetchAccounts(accessToken: session.accessToken)
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            accounts = loadedAccounts
        } catch {
            guard generation == userStateGeneration else { return }
            accountMessage = error.localizedDescription
        }
    }

    func loadAccountDetail(_ account: NativeAccount) async {
        let generation = userStateGeneration
        selectedAccountDetail = nil
        selectedAccountSourceSnapshot = nil
        accountMessage = nil
        let session = try? await validSession()
        guard let session else { accountMessage = "登录状态已失效，请重新登录。"; return }
        guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
        if account.type.isLiability {
            try? await accountRepository.ensureRepaymentCycles(
                monthKey: Self.currentMonthKey,
                accessToken: session.accessToken
            )
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

    func confirmRepayment(
        cycle: NativeRepaymentCycle,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String
    ) async -> Bool {
        guard !isSubmittingRepayment else { return false }
        isSubmittingRepayment = true
        repaymentMessage = nil
        defer { isSubmittingRepayment = false }

        do {
            let session = try await validSession()
            _ = try await accountRepository.confirmRepayment(
                cycleId: cycle.id,
                paidAmount: paidAmount,
                debitAccountId: debitAccountId,
                status: status,
                note: note,
                accessToken: session.accessToken
            )
            await refreshAfterRepayment(accountId: cycle.accountId, session: session)
            repaymentMessage = debitAccountId == nil
                ? "已确认还款"
                : "已确认还款并记录扣款"
            return true
        } catch {
            repaymentMessage = error.localizedDescription
            return false
        }
    }

    func revokeLiabilityPayment(
        payment: NativeLiabilityPayment,
        accountId: String
    ) async -> Bool {
        guard !isSubmittingRepayment else { return false }
        isSubmittingRepayment = true
        repaymentMessage = nil
        defer { isSubmittingRepayment = false }

        do {
            let session = try await validSession()
            _ = try await accountRepository.revokePayment(
                paymentId: payment.id,
                accessToken: session.accessToken
            )
            await refreshAfterRepayment(accountId: accountId, session: session)
            repaymentMessage = "已撤销还款"
            return true
        } catch {
            repaymentMessage = error.localizedDescription
            return false
        }
    }

    func loadInboxRepaymentCandidates() async {
        let generation = userStateGeneration
        let stagingRecords = dashboard.stagingRecords
        guard !stagingRecords.isEmpty else {
            repaymentCandidates = [:]
            return
        }

        do {
            let session = try await validSession()
            try? await accountRepository.ensureRepaymentCycles(
                monthKey: Self.currentMonthKey,
                accessToken: session.accessToken
            )
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
        stagingRepaymentId = record.id
        inboxFinanceMessage = nil
        defer { stagingRepaymentId = nil }

        do {
            let session = try await validSession()
            try await inboxRepository.confirmStagingRepayment(
                id: record.id,
                cycleId: candidate.cycle.id,
                paidAmount: candidate.amount,
                debitAccountId: candidate.cycle.autoDebitAccountId ?? candidate.account.autoDebitAccountId,
                accessToken: session.accessToken
            )

            repaymentCandidates.removeValue(forKey: record.id)
            inboxPath = NavigationPath()
            await loadAccounts()
            await refreshDashboard()
            inboxFinanceMessage = "已根据截图确认还款"
            return true
        } catch {
            inboxFinanceMessage = error.localizedDescription
            return false
        }
    }

    private func refreshAfterRepayment(accountId: String, session: SupabaseAuthSession) async {
        await loadAccounts()
        if let account = accounts.first(where: { $0.id == accountId }) {
            selectedAccountDetail = await accountRepository.fetchDetail(
                account: account,
                accessToken: session.accessToken
            )
        }
        await refreshDashboard()
    }

    func saveAccount(_ draft: NativeAccountDraft) async -> Bool {
        guard !isSavingAccount else { return false }
        isSavingAccount = true
        accountMessage = nil
        defer { isSavingAccount = false }

        do {
            let session = try await validSession()
            accounts = try await accountRepository.save(
                draft,
                userId: session.user.id,
                accessToken: session.accessToken
            )
            if let accountId = draft.accountId,
               let account = accounts.first(where: { $0.id == accountId }) {
                selectedAccountDetail = await accountRepository.fetchDetail(
                    account: account,
                    accessToken: session.accessToken
                )
            }
            return true
        } catch {
            accountMessage = error.localizedDescription
            return false
        }
    }

    func setAccountArchived(_ account: NativeAccount, archived: Bool) async -> Bool {
        guard !isSavingAccount else { return false }
        isSavingAccount = true
        accountMessage = nil
        defer { isSavingAccount = false }

        do {
            let session = try await validSession()
            accounts = try await accountRepository.setArchived(
                accountId: account.id,
                archived: archived,
                accessToken: session.accessToken
            )
            if let updated = accounts.first(where: { $0.id == account.id }) {
                selectedAccountDetail = await accountRepository.fetchDetail(
                    account: updated,
                    accessToken: session.accessToken
                )
            }
            return true
        } catch {
            accountMessage = error.localizedDescription
            return false
        }
    }

    func loadUnboundRecords(monthKey: String) async {
        guard !isLoadingUnboundRecords else { return }
        let generation = userStateGeneration
        isLoadingUnboundRecords = true
        unboundRecordsMessage = nil
        defer { isLoadingUnboundRecords = false }

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

    func bindUnboundRecord(
        _ record: NativeUnboundRecord,
        accountId: String,
        monthKey: String
    ) async -> Bool {
        guard !isBindingUnboundRecords else { return false }
        isBindingUnboundRecords = true
        unboundBindingMessage = nil
        defer { isBindingUnboundRecords = false }

        do {
            let session = try await validSession()
            try await unboundRecordRepository.bind(
                record,
                accountId: accountId,
                accessToken: session.accessToken
            )
            unboundRecords.removeAll { $0.id == record.id && $0.kind == record.kind }
            await refreshAfterAccountBinding(monthKey: monthKey)
            unboundBindingMessage = "已补绑账户并生成流水"
            return true
        } catch {
            unboundBindingMessage = error.localizedDescription
            return false
        }
    }

    func batchBindUnboundRecords(
        _ candidates: [NativeUnboundBindingCandidate],
        monthKey: String
    ) async -> Bool {
        guard !isBindingUnboundRecords, !candidates.isEmpty else { return false }
        isBindingUnboundRecords = true
        unboundBindingMessage = nil
        defer { isBindingUnboundRecords = false }

        do {
            let session = try await validSession()
            var successCount = 0
            var failureCount = 0
            for candidate in candidates {
                do {
                    try await unboundRecordRepository.bind(
                        candidate.record,
                        accountId: candidate.recommendation.account.id,
                        accessToken: session.accessToken
                    )
                    successCount += 1
                } catch {
                    failureCount += 1
                }
            }
            await refreshAfterAccountBinding(monthKey: monthKey)
            unboundBindingMessage = failureCount == 0
                ? "已批量补绑 \(successCount) 条记录"
                : "已补绑 \(successCount) 条，\(failureCount) 条失败"
            return successCount > 0
        } catch {
            unboundBindingMessage = error.localizedDescription
            return false
        }
    }

    func loadWalletSnapshots() async {
        guard !isLoadingWalletSnapshots else { return }
        let generation = userStateGeneration
        isLoadingWalletSnapshots = true
        walletSnapshotMessage = nil
        defer { isLoadingWalletSnapshots = false }

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
        if !force,
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
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let snapshot = try await insightsRepository.fetchDailySummary(
                range: range,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            insightsSnapshot = snapshot
            insightsLoadedAt = Date()
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
        defer { isLoadingAIInsight = false }

        do {
            let session = try await validSession()
            let response = try await insightsRepository.generateAIInsight(
                range: range,
                force: force,
                question: question,
                accessToken: session.accessToken
            )
            guard insightsSnapshot?.range == range else { return false }
            aiInsight = response.insight.scoped(to: range)
            aiInsightIsCached = response.cached
            return true
        } catch {
            aiInsightMessage = error.localizedDescription
            return false
        }
    }

    func createAccountFromWalletSnapshot(_ snapshot: NativeWalletSnapshot) async -> Bool {
        guard walletSnapshotActionId == nil else { return false }
        walletSnapshotActionId = snapshot.id
        walletSnapshotMessage = nil
        defer { walletSnapshotActionId = nil }

        do {
            let session = try await validSession()
            let result = try await walletSnapshotRepository.createAccount(
                from: snapshot,
                userId: session.user.id,
                accessToken: session.accessToken
            )
            await refreshAfterWalletSnapshotLink()
            walletSnapshotMessage = result.warnings.isEmpty
                ? "已从快照创建账户"
                : result.warnings.joined(separator: "；")
            return true
        } catch {
            walletSnapshotMessage = error.localizedDescription
            return false
        }
    }

    func linkWalletSnapshot(
        _ snapshot: NativeWalletSnapshot,
        to account: NativeAccount
    ) async -> Bool {
        guard walletSnapshotActionId == nil else { return false }
        walletSnapshotActionId = snapshot.id
        walletSnapshotMessage = nil
        defer { walletSnapshotActionId = nil }

        do {
            let session = try await validSession()
            let result = try await walletSnapshotRepository.link(
                snapshot,
                to: account,
                userId: session.user.id,
                accessToken: session.accessToken
            )
            await refreshAfterWalletSnapshotLink()
            walletSnapshotMessage = result.warnings.isEmpty
                ? "已关联账户"
                : result.warnings.joined(separator: "；")
            return true
        } catch {
            walletSnapshotMessage = error.localizedDescription
            return false
        }
    }

    private func refreshAfterWalletSnapshotLink() async {
        await loadAccounts()
        await loadWalletSnapshots()
        await refreshDashboard()
    }

    func openUnboundRecord(_ record: NativeUnboundRecord) {
        selectedTab = .records
        recordsPath = NavigationPath([NativeRecordRoute(reference: record.reference)])
    }

    func openWalletSnapshot(_ snapshot: NativeWalletSnapshot) {
        selectedTab = .records
        let reference = "data/\(snapshot.id)"
        recordsPath = NavigationPath([NativeRecordRoute(reference: reference)])
        Task { await loadRecordDetail(reference: reference) }
    }

    private func refreshAfterAccountBinding(monthKey: String) async {
        await loadAccounts()
        await loadUnboundRecords(monthKey: monthKey)
        await refreshDashboard()
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
            recordDetailCache[reference] = detail
        } catch {
            return
        }
    }

    func openDayRecord(_ record: NativeDayRecord) {
        if record.reference.hasPrefix("staging-") {
            selectedTab = .inbox
            inboxPath = NavigationPath([NativeInboxRoute.staging(recordId: String(record.reference.dropFirst("staging-".count)))])
        } else {
            selectedTab = .records
            recordsPath = NavigationPath([NativeRecordRoute(reference: record.reference)])
        }
    }

    func openPendingExpense(_ pending: NativePendingExpense) {
        selectedTab = .inbox
        inboxPath = NavigationPath([NativeInboxRoute.record(reference: pending.reference)])
        Task { await loadRecordDetail(reference: pending.reference) }
    }

    func handleDeepLink(_ url: URL) {
        guard url.scheme == "jiezi" else { return }

        switch url.host {
        case "inbox":
            selectedTab = .inbox
        case "records", "record":
            selectedTab = .records
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .today
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    func handleShortcutNotificationRoute(_ route: String?) {
        let parts = (route ?? "")
            .split(separator: "/")
            .map(String.init)
        let target = parts.first
        let detailPath = parts.dropFirst().joined(separator: "/")

        switch target {
        case "inbox":
            selectedTab = .inbox
            if !detailPath.isEmpty {
                inboxPath = NavigationPath([NativeInboxRoute.staging(recordId: detailPath)])
            }
        case "records":
            selectedTab = .records
            if !detailPath.isEmpty {
                recordsPath = NavigationPath([NativeRecordRoute(reference: detailPath)])
            }
        case "settings":
            selectedTab = .settings
        default:
            selectedTab = .today
        }

        guard isSignedIn else { return }
        Task {
            await refreshDashboard()
        }
    }

    func discardStagingRecord(_ record: NativeStagingRecord) async {
        guard inboxActionRecordId == nil else { return }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在销毁截图…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        do {
            let session = try await validSession()
            try await inboxRepository.discard(id: record.id, accessToken: session.accessToken)
            inboxPath = NavigationPath()
            await refreshDashboard()
            inboxActionMessage = "已销毁这条待处理截图"
        } catch {
            inboxActionMessage = "销毁失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
        }
    }

    func retryStagingRecord(_ record: NativeStagingRecord) async {
        guard inboxActionRecordId == nil else { return }
        inboxActionRecordId = record.id
        inboxActionMessage = "正在重新识别…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        do {
            let session = try await validSession()
            let result = try await inboxRepository.retry(id: record.id, accessToken: session.accessToken)
            await refreshDashboard()
            let remainsInInbox = dashboard.stagingRecords.contains { $0.id == record.id }
            if !remainsInInbox {
                inboxPath = NavigationPath()
            }
            inboxActionMessage = remainsInInbox
                ? "重新识别完成，仍需确认或选择归档域"
                : "重新识别成功，记录已自动归档"
            if result.route.hasPrefix("inbox") {
                inboxActionMessage = "重新识别完成，仍需确认或选择归档域"
            }
        } catch {
            inboxActionMessage = "重新识别失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
        }
    }

    func archiveStagingRecord(_ record: NativeStagingRecord, domainKey: String) async {
        guard inboxActionRecordId == nil else { return }
        inboxActionRecordId = record.id
        let domainTitle = dashboard.domains.first(where: { $0.id == domainKey })?.shortName
            ?? InboxArchiveDomains.all.first(where: { $0.id == domainKey })?.title
            ?? domainKey
        inboxActionMessage = "正在归档到\(domainTitle)…"
        inboxActionMessageIsError = false
        defer { inboxActionRecordId = nil }
        do {
            let session = try await validSession()
            _ = try await inboxRepository.archive(
                record,
                domainKey: domainKey,
                accessToken: session.accessToken
            )
            inboxPath = NavigationPath()
            await refreshDashboard()
            inboxActionMessage = "已归档到\(domainTitle)"
        } catch {
            inboxActionMessage = "归档失败：\(error.localizedDescription)"
            inboxActionMessageIsError = true
        }
    }

    func resolveStagingImageURL(for record: NativeStagingRecord) async throws -> URL {
        guard let imagePath = record.imagePath, !imagePath.isEmpty else {
            throw SupabaseRemoteError.requestFailed("这条记录没有可查看的截图")
        }
        let session = try await validSession()
        return try await inboxRepository.resolveImageURL(path: imagePath, accessToken: session.accessToken)
    }

    func loadRecordDetail(reference: String, force: Bool = false) async {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        let generation = userStateGeneration
        activeRecordReference = canonicalReference
        recordDetailMessage = nil
        if selectedRecordDetail.map({ !NativeRecordReference($0.id).matchesReference(canonicalReference) }) ?? true {
            recordFeedbackState = .idle
        }
        if !force, let cached = recordDetailCache[canonicalReference] {
            selectedRecordDetail = cached
            if cached.imagePath == nil || cached.imageURL != nil || cached.imageLoadError {
                return
            }
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
            recordDetailCache[canonicalReference] = detail
            guard activeRecordReference == canonicalReference else { return }
            selectedRecordDetail = detail
        } catch {
            if activeRecordReference == canonicalReference {
                recordDetailMessage = error.localizedDescription
            }
        }
    }

    func recordDetail(matching reference: String) -> NativeRecordDetail? {
        let canonicalReference = NativeRecordReference(reference).canonicalValue
        guard let detail = selectedRecordDetail,
              NativeRecordReference(detail.id).canonicalValue == canonicalReference else { return nil }
        return detail
    }

    func saveRecordDetail(_ draft: NativeRecordEditDraft) async -> Bool {
        guard !isSavingRecordDetail else { return false }
        isSavingRecordDetail = true
        recordDetailMessage = nil
        defer { isSavingRecordDetail = false }

        do {
            let session = try await validSession()
            let reference = try await recordRepository.saveDetail(draft, accessToken: session.accessToken)
            let oldReference = NativeRecordReference(draft.reference).canonicalValue
            let savedReference = NativeRecordReference(reference).canonicalValue
            recordDetailCache.removeValue(forKey: oldReference)
            recordDetailCache.removeValue(forKey: savedReference)
            await refreshDashboard()
            await loadAccounts()
            recordDetailCache.removeValue(forKey: savedReference)
            await loadRecordDetail(reference: savedReference, force: true)
            return true
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
            let session = try await validSession()
            try await recordRepository.delete(reference: reference, accessToken: session.accessToken)
            recordDetailCache.removeValue(forKey: NativeRecordReference(reference).canonicalValue)
            activeRecordReference = nil
            selectedRecordDetail = nil
            recordsPath = NavigationPath()
            await loadAccounts()
            await refreshDashboard()
            return true
        } catch {
            recordDetailMessage = error.localizedDescription
            return false
        }
    }

    func confirmPendingRecord(_ draft: NativePendingResolutionDraft) async -> Bool {
        guard !isConfirmingPendingRecord else { return false }
        if let validationMessage = draft.validationMessage {
            pendingResolutionMessage = validationMessage
            return false
        }
        isConfirmingPendingRecord = true
        pendingResolutionMessage = "正在保存…"
        defer { isConfirmingPendingRecord = false }
        do {
            let session = try await validSession()
            try await inboxRepository.confirmPending(draft, accessToken: session.accessToken)
            recordDetailCache.removeValue(forKey: "expense/\(draft.pendingId)")
            selectedRecordDetail = nil
            await loadAccounts()
            await refreshDashboard()
            inboxPath = NavigationPath()
            pendingResolutionMessage = draft.kind == .income ? "收入已记录" : "支出已补全"
            return true
        } catch {
            pendingResolutionMessage = "保存失败：\(error.localizedDescription)"
            return false
        }
    }

    func submitRecordFeedback(choice: NativeAIFeedbackReviewChoice, freeText: String) async {
        if case .submitting = recordFeedbackState { return }
        guard let detail = selectedRecordDetail else { return }
        recordFeedbackState = .submitting
        do {
            let session = try await validSession()
            try await recordRepository.submitFeedback(
                recordId: detail.rawId,
                choice: choice,
                freeText: freeText,
                accessToken: session.accessToken
            )
            recordFeedbackState = .submitted
        } catch {
            recordFeedbackState = .failed(error.localizedDescription)
        }
    }

    func loadUserSettings() async {
        guard !isLoadingSettings else { return }
        let generation = userStateGeneration
        isLoadingSettings = true
        settingsMessage = nil
        defer { isLoadingSettings = false }
        do {
            let session = try await validSession()
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            let settings = try await settingsRepository.fetch(
                userId: session.user.id,
                accessToken: session.accessToken
            )
            guard isCurrentUserLoad(generation, userId: session.user.id) else { return }
            userSettings = settings
        } catch {
            guard generation == userStateGeneration else { return }
            settingsMessage = error.localizedDescription
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
            let session = try await validSession()
            return try await settingsRepository.export(request, accessToken: session.accessToken)
        } catch {
            settingsMessage = "导出失败：\(error.localizedDescription)"
            return nil
        }
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

    func requestShortcutNotificationPermissionIfNeeded() async {
        guard !hasAskedNotificationPermissionThisSession else { return }
        hasAskedNotificationPermissionThisSession = true

        let status = await ShortcutNotificationService.shared.authorizationStatus()
        guard status == .notDetermined else { return }
        await requestShortcutNotificationPermission()
    }

    func refreshNotificationPermissionStatus() async {
        notificationPermissionStatusText = await ShortcutNotificationService.shared.authorizationStatusText()
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
        currentUserEmail = session.user.email ?? ""
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
        try? keychain.remove(KeychainKeys.authSession)
        try? keychain.remove(KeychainKeys.uploadToken)
        isSignedIn = false
        currentUserId = ""
        currentUserEmail = ""
        hasUploadToken = false
        shortcutCredentialMessage = nil
        resetUserScopedState()
        Task { await RemoteImageRepository.shared.clear() }
        authMessage = message
        authMessageIsError = !message.isEmpty
    }

    func resetUserScopedState() {
        dashboardRefreshGeneration += 1
        userStateGeneration += 1
        dashboardSupplementTask?.cancel()
        dashboardSupplementTask = nil
        isLoadingDashboard = false
        dashboard = DashboardSnapshot()
        todayPath = NavigationPath()
        inboxPath = NavigationPath()
        recordsPath = NavigationPath()
        selectedRecordDetail = nil
        recordMonthGroups = [:]
        recordMonthDetails = [:]
        recordMonthMessages = [:]
        loadingRecordMonthKey = nil
        recordDetailCache.removeAll()
        activeRecordReference = nil
        prefetchingRecordReferences.removeAll()
        recordDetailMessage = nil
        isSavingRecordDetail = false
        isDeletingRecordDetail = false
        recordFeedbackState = .idle
        manualRecordMessage = nil
        accounts = []
        selectedAccountDetail = nil
        selectedAccountSourceSnapshot = nil
        accountMessage = nil
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
        isLoadingWalletSnapshots = false
        walletSnapshotActionId = nil
        walletSnapshotMessage = nil
        insightsSnapshot = nil
        isLoadingInsights = false
        insightsMessage = nil
        insightsLoadedAt = nil
        aiInsight = nil
        isLoadingAIInsight = false
        aiInsightMessage = nil
        aiInsightIsCached = false
        userSettings = NativeUserSettings()
        settingsMessage = nil
        isLoadingSettings = false
        isSavingSettings = false
        isCleaningSourceImages = false
        isExportingData = false
        isDeletingAccount = false
        dashboardMessage = nil
        isShowingCachedDashboard = false
        selectedTab = .today
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
        isCreatingManualRecord = true
        manualRecordMessage = nil
        defer { isCreatingManualRecord = false }

        do {
            let session = try await validSession()
            let reference = try await recordRepository.create(
                draft,
                domain: domain,
                userId: session.user.id,
                accessToken: session.accessToken
            )
            await refreshDashboard()
            if draft.kind != .universal || draft.domainKey == "wallet" {
                await loadAccounts()
            }
            if draft.existingRawId != nil {
                recordDetailCache.removeValue(forKey: reference)
                await loadRecordDetail(reference: reference, force: true)
            }
            manualRecordMessage = draft.existingRawId == nil ? "记录已保存" : "记录已更新"
            return true
        } catch {
            manualRecordMessage = error.localizedDescription
            return false
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

enum AppTab: String, CaseIterable, Identifiable {
    case today
    case inbox
    case records
    case insights
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "今日"
        case .inbox: return "收件箱"
        case .records: return "记录"
        case .insights: return "分析"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "sparkles"
        case .inbox: return "tray.full"
        case .records: return "list.bullet.rectangle"
        case .insights: return "chart.xyaxis.line"
        case .settings: return "gearshape"
        }
    }
}
