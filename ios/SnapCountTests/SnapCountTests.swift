import XCTest
import UIKit
@testable import SnapCount

final class SnapCountTests: XCTestCase {
    func testAppTabsHaveTitles() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testDashboardRepositoryProtocolSupportsStubInjection() async throws {
        let expected = DashboardSnapshot(todayCount: 3)
        let repository = DashboardRepositoryStub(snapshot: expected)

        let snapshot = try await repository.fetchDashboardCore(accessToken: "test-token")

        XCTAssertEqual(snapshot.todayCount, 3)
    }

    func testDashboardImageHydrationPreservesCoreData() {
        let imageURL = URL(string: "https://example.com/receipt.jpg")!
        let detail = NativeRecordDetail(
            id: "tx-1", rawId: "1", kind: "expense", title: "早餐", subtitle: "2026-07-15",
            value: "¥12.00", detailRows: [], imageURL: nil, imageLoadError: false,
            imagePath: "user/receipt.jpg", imageHash: nil, amount: 12, merchantName: "早餐",
            platform: nil, category: "food", paymentMethod: nil, recordDate: "2026-07-15",
            note: nil, companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil
        )
        var core = DashboardSnapshot(todayCount: 1)
        core.recordDetails[detail.id] = detail

        let hydrated = core.applyingSignedImageURLs(["user/receipt.jpg": imageURL])

        XCTAssertEqual(hydrated.todayCount, 1)
        XCTAssertEqual(hydrated.recordDetails[detail.id]?.title, "早餐")
        XCTAssertEqual(hydrated.recordDetails[detail.id]?.imageURL, imageURL)
        XCTAssertEqual(hydrated.recordDetails[detail.id]?.imageLoadError, false)
        XCTAssertNil(core.recordDetails[detail.id]?.imageURL)
    }

    func testDashboardCanReuseImagesWithoutMarkingNewPathsAsFailed() {
        let detail = NativeRecordDetail(
            id: "tx-1", rawId: "1", kind: "expense", title: "早餐", subtitle: "2026-07-15",
            value: "¥12.00", detailRows: [], imageURL: nil, imageLoadError: false,
            imagePath: "user/new.jpg", imageHash: nil, amount: 12, merchantName: "早餐",
            platform: nil, category: "food", paymentMethod: nil, recordDate: "2026-07-15",
            note: nil, companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil
        )
        var core = DashboardSnapshot()
        core.recordDetails[detail.id] = detail

        let reused = core.applyingSignedImageURLs([:], markMissingAsFailure: false)

        XCTAssertNil(reused.recordDetails[detail.id]?.imageURL)
        XCTAssertEqual(reused.recordDetails[detail.id]?.imageLoadError, false)
    }

    func testCameraUploadUsesSmallerPhotoPreset() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_800, height: 1_200))
        let source = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_800, height: 1_200))
        }

        let data = try ImageUploadPreprocessor.cameraJPEGData(from: source)
        let compressed = try XCTUnwrap(UIImage(data: data))

        XCTAssertLessThanOrEqual(max(compressed.size.width, compressed.size.height), 960.5)
        XCTAssertLessThan(data.count, 900_000)
    }

    func testRecordRepositoryProtocolSupportsStubInjection() async throws {
        let repository: RecordRepositoryProtocol = RecordRepositoryStub()
        try await repository.delete(reference: "expense:record-1", accessToken: "test-token")
        try await repository.submitFeedback(recordId: "record-1", choice: .notHelpful, freeText: "", accessToken: "test-token")
    }

    func testAIFeedbackParsesPWAFields() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "icon": AnyCodable("✨"),
            "badge": AnyCodable("今天很稳"),
            "band": AnyCodable("positive"),
            "emotion_line": AnyCodable("记录已经落下。"),
            "utility_line": AnyCodable("继续保持当前节奏。"),
            "detail_reason": AnyCodable("金额和分类完整。"),
            "timing_signal": AnyCodable(["label": AnyCodable("晚间记录")])
        ]))

        XCTAssertEqual(feedback.badge, "今天很稳")
        XCTAssertEqual(feedback.bandLabel, "正向")
        XCTAssertEqual(feedback.timingLabel, "晚间记录")
    }

    func testRecordDetailPresentationUsesDomainSpecificFields() {
        let detail = NativeRecordDetail(
            id: "data/food-1", rawId: "food-1", kind: "data", title: "午餐", subtitle: "2026-07-16",
            value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: nil, merchantName: nil, platform: nil, category: "food", paymentMethod: nil,
            recordDate: "2026-07-16", note: "清淡午餐", companionMessage: nil, accountId: nil,
            systemImage: "fork.knife", payload: [
                "meal_type": AnyCodable("lunch"),
                "total_calories": AnyCodable(520),
                "dishes": AnyCodable([["name": "米饭", "calories": 220]])
            ], domainKey: "food"
        )

        let rows = NativeRecordDetailPresentationAdapter.extractedRows(for: detail)
        XCTAssertEqual(rows.first(where: { $0.label == "餐次" })?.value, "午餐")
        XCTAssertEqual(NativeRecordDetailPresentationAdapter.foodDishes(for: detail).first?.name, "米饭")
    }

    func testManualExpensePreservesPWAValidationAndCategoryKeys() {
        var draft = NativeManualRecordDraft()
        draft.amountText = "28.50"
        draft.category = "food"
        XCTAssertNil(draft.validationMessage(domain: nil))
        XCTAssertEqual(draft.amount, 28.5)
        XCTAssertEqual(NativeManualRecordDraft.expenseCategories.map(\.id), ["food", "shopping", "transport", "entertainment", "life", "health", "education", "other"])
    }

    func testManualUniversalPayloadUsesPWADomainKeys() {
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "sport")
        draft.primaryValueText = "45"
        draft.dimension = "骑行"
        let payload = draft.universalPayload(domain: nil)
        XCTAssertEqual(payload.double("duration_minutes"), 45)
        XCTAssertEqual(payload.string("sport_type"), "骑行")
        XCTAssertEqual(payload.string("source_app"), "manual")
    }

    func testManualUniversalEditPreservesUnknownPayloadFields() {
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "sport")
        draft.existingRawId = "record-1"
        draft.originalPayload = ["distance_km": AnyCodable(12.5)]
        draft.primaryValueText = "60"
        draft.dimension = "骑行"
        let payload = draft.universalPayload(domain: nil)
        XCTAssertEqual(payload.double("distance_km"), 12.5)
        XCTAssertEqual(payload.double("duration_minutes"), 60)
    }

    func testInboxRepositoryProtocolSupportsStubInjection() async throws {
        let repository = InboxRepositoryStub()
        let result = try await repository.retry(id: "staging-1", accessToken: "test-token")
        XCTAssertFalse(result.displayText.isEmpty)
    }

    func testPendingResolutionRequiresPWAExpenseFields() {
        let detail = NativeRecordDetail(
            id: "tx-1", rawId: "1", kind: "expense", title: "待补全", subtitle: "2026-07-16",
            value: "¥12.00", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil,
            imageHash: nil, amount: 12, merchantName: nil, platform: nil, category: nil,
            paymentMethod: nil, recordDate: "2026-07-16", note: nil, companionMessage: nil,
            accountId: nil, systemImage: "clock", payload: nil
        )
        var draft = NativePendingResolutionDraft(detail: detail)
        XCTAssertEqual(draft.validationMessage, "请选择消费渠道")
        draft.platform = "微信"
        draft.category = "food"
        draft.paymentMethod = "微信支付"
        XCTAssertNil(draft.validationMessage)
    }

    func testInboxArchiveDomainsPreservePWAContract() {
        XCTAssertEqual(
            InboxArchiveDomains.all.map(\.id),
            ["expense", "income", "sport", "sleep", "reading", "food", "wallet"]
        )
        XCTAssertEqual(
            InboxArchiveDomains.all.map(\.systemImage),
            ["creditcard", "arrow.down.circle", "figure.run", "moon", "book", "fork.knife", "wallet.pass"]
        )
    }

    func testDayRecordGroupFiltersByPWAKinds() {
        let records = [
            NativeDayRecord(id: "expense-1", reference: "tx-1", dateKey: "2026-07-12", kind: .expense, domainKey: "expense", title: "早餐", subtitle: "微信 · 餐饮", value: "¥12.00", timeLabel: "08:00", systemImage: "creditcard"),
            NativeDayRecord(id: "sport-1", reference: "data-1", dateKey: "2026-07-12", kind: .sport, domainKey: "sport", title: "骑行", subtitle: "30 分钟", value: "", timeLabel: "07:00", systemImage: "figure.run")
        ]
        let group = NativeDayRecordGroup(dateKey: "2026-07-12", records: records)

        XCTAssertEqual(group.records(for: .expense).map(\.reference), ["tx-1"])
        XCTAssertEqual(group.records(for: .sport).map(\.reference), ["data-1"])
        XCTAssertEqual(group.availableKinds, [.all, .expense, .sport])
    }

    func testDayRecordKindsPreservePWADomainKeys() {
        XCTAssertEqual(
            NativeDayRecordKind.allCases.map(\.rawValue),
            ["all", "expense", "income", "sport", "sleep", "food", "reading", "wallet", "staging"]
        )
    }

    func testRecordQueryFiltersMonthKindAndPendingItems() {
        let groups = [
            NativeDayRecordGroup(dateKey: "2026-07-12", records: [
                NativeDayRecord(id: "expense-1", reference: "tx-1", dateKey: "2026-07-12", kind: .expense, domainKey: "expense", title: "午餐", subtitle: "餐饮", value: "¥20.00", timeLabel: nil, systemImage: "creditcard"),
                NativeDayRecord(id: "staging-1", reference: "staging-1", dateKey: "2026-07-12", kind: .staging, domainKey: nil, title: "待处理", subtitle: "", value: "", timeLabel: nil, systemImage: "tray")
            ]),
            NativeDayRecordGroup(dateKey: "2026-06-30", records: [
                NativeDayRecord(id: "expense-2", reference: "tx-2", dateKey: "2026-06-30", kind: .expense, domainKey: "expense", title: "晚餐", subtitle: "餐饮", value: "¥30.00", timeLabel: nil, systemImage: "creditcard")
            ])
        ]

        let result = NativeRecordQuery(monthKey: "2026-07", kind: .expense).groups(from: groups)
        XCTAssertEqual(result.map(\.dateKey), ["2026-07-12"])
        XCTAssertEqual(result.flatMap(\.records).map(\.reference), ["tx-1"])
    }

    func testDomainRepositoryProtocolSupportsStubInjection() async throws {
        let repository: DomainRepositoryProtocol = DomainRepositoryStub()
        let domains = try await repository.fetchDefinitions(accessToken: "test-token")
        XCTAssertEqual(domains.map(\.id), ["sport"])
    }

    func testDomainPresentationUsesUniversalDomainRecords() {
        let definition = NativeDomainDefinition(id: "sport", name: "运动记录", description: "", icon: "🏃", isSystem: true, schema: [:], display: [:], recordCount: 1)
        let record = NativeDayRecord(id: "sport-1", reference: "data-1", dateKey: "2026-07-12", kind: .sport, domainKey: "sport", title: "骑行", subtitle: "30 分钟", value: "", timeLabel: nil, systemImage: "figure.run")
        var dashboard = DashboardSnapshot()
        dashboard.dayRecordGroups = [NativeDayRecordGroup(dateKey: "2026-07-12", records: [record])]
        let presentation = NativeDomainPresentationAdapter.presentation(for: definition, dashboard: dashboard)
        XCTAssertEqual(presentation.recentRecords.map(\.reference), ["data-1"])
        XCTAssertEqual(presentation.metrics.first?.value, "1")
    }

    func testUnifiedInboxItemDistinguishesPendingExpenseAndStaging() {
        let pending = NativePendingExpense(id: "tx-1", title: "待补全消费", amount: 20, dateKey: "2026-07-12", reference: "tx-1")
        let item = NativeInboxItem(id: "pending-tx-1", kind: .pendingExpense, dateKey: pending.dateKey, title: pending.title, subtitle: "¥20.00", status: "pending", statusLabel: "待补全", systemImage: "clock", pendingExpense: pending, stagingRecord: nil)
        XCTAssertEqual(item.kind, .pendingExpense)
        XCTAssertNil(item.stagingRecord)
    }

    func testInboxRoutesKeepStagingAndPendingRecordsDistinct() {
        XCTAssertNotEqual(
            NativeInboxRoute.staging(recordId: "same-id"),
            NativeInboxRoute.record(reference: "same-id")
        )
    }


    func testDashboardSnapshotStoreIsolatesUsers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = DashboardSnapshotStore(directory: directory)
        let snapshot = DashboardSnapshot(todayCount: 2, pendingCount: 1)
        try store.save(snapshot, userId: "user-a")
        XCTAssertEqual(try store.load(userId: "user-a")?.dashboardSnapshot.todayCount, 2)
        XCTAssertNil(try store.load(userId: "user-b"))
        try? FileManager.default.removeItem(at: directory)
    }

    func testFinancialContractPreservesPWAKeys() {
        XCTAssertEqual(NativeAccountType.allCases.map(\.rawValue), ["cash", "wallet_balance", "debit_card", "credit_card", "credit_line", "other"])
        XCTAssertEqual(
            NativeRepaymentStatus.allCases.map(\.rawValue),
            ["draft_estimated", "pending", "due_today", "overdue_unconfirmed", "partial_paid", "minimum_paid", "paid", "ignored", "carried_over", "historical_unconfirmed", "reconciled", "replaced", "reopened"]
        )
    }

    func testRepaymentCalculatorMatchesPWAStatusRules() {
        XCTAssertEqual(
            NativeRepaymentCalculator.status(paidAmount: 100, remainingAmount: 100, minimumPaymentAmount: 20),
            .paid
        )
        XCTAssertEqual(
            NativeRepaymentCalculator.status(paidAmount: 20, remainingAmount: 100, minimumPaymentAmount: 20),
            .minimumPaid
        )
        XCTAssertEqual(
            NativeRepaymentCalculator.status(paidAmount: 10, remainingAmount: 100, minimumPaymentAmount: 20),
            .partialPaid
        )
    }

    func testRepaymentOverpaymentUsesCurrentLiabilityBalance() {
        XCTAssertEqual(NativeRepaymentCalculator.overpayment(paidAmount: 120, currentBalance: 100), 20)
    }

    func testRepaymentCandidateMatchesPWAAmountAndAccountRules() {
        let account = makeLiabilityAccount(id: "credit-1", name: "支付宝花呗")
        let cycle = makeRepaymentCycle(accountId: account.id, amount: 320, dueDate: "2026-07-15")
        let record = NativeStagingRecord(
            id: "staging-1", dateKey: "2026-07-14", title: "花呗已还清", summary: "支付宝花呗还款",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "钱包快照",
            createdAtLabel: "2026-07-14", occurredAtLabel: "2026-07-14", confidencePercent: 95,
            lastErrorMessage: nil, retryCount: 0, systemImage: "wallet.pass", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "wallet_snapshot", domainKey: "wallet",
            domainName: "钱包", extracted: [
                "payload_jsonb": AnyCodable([
                    "record_kind": "liability_snapshot",
                    "account_snapshot_kind": "liability",
                    "status": "paid",
                    "account_name": "支付宝花呗",
                    "snapshot_balance": 320.0
                ])
            ], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )

        let candidate = NativeRepaymentCandidateEngine.candidate(
            for: record,
            accounts: [account],
            cycles: [cycle]
        )

        XCTAssertEqual(candidate?.account.id, account.id)
        XCTAssertEqual(candidate?.amount, 320)
        XCTAssertTrue((candidate?.score ?? 0) >= 0.9)
    }

    func testWalletSnapshotDerivesPWAAccountAndCycleFields() {
        let snapshot = NativeWalletSnapshot(
            id: "wallet-1",
            title: "花呗账单",
            summary: "本月待还",
            occurredAt: "2026-07-14T10:00:00Z",
            createdAt: "2026-07-14T10:01:00Z",
            payload: [
                "record_kind": AnyCodable("liability_snapshot"),
                "account_name": AnyCodable("支付宝花呗"),
                "account_type": AnyCodable("huabei"),
                "snapshot_balance": AnyCodable(520.0),
                "due_date": AnyCodable("2026-07-20"),
                "bill_day": AnyCodable(2),
                "confidence": AnyCodable(0.93)
            ],
            imagePath: "receipts/wallet-1.jpg",
            imageHash: "hash",
            linkedAccountId: nil,
            kind: .liability,
            balance: 520,
            snapshotAt: "2026-07-14T10:00:00Z"
        )

        XCTAssertEqual(snapshot.accountType, .creditLine)
        XCTAssertEqual(snapshot.cycleMonth, "2026-07")
        XCTAssertEqual(snapshot.paymentDueDay, 20)
        XCTAssertEqual(snapshot.billDay, 2)
        XCTAssertEqual(snapshot.confidence, 0.93)
    }

    func testInsightMaturityPreservesPWAThresholds() {
        XCTAssertEqual(NativeMaturityStage.resolve(days: 0).key, .seed)
        XCTAssertEqual(NativeMaturityStage.resolve(days: 3).key, .sprout)
        XCTAssertEqual(NativeMaturityStage.resolve(days: 7).key, .growing)
        XCTAssertEqual(NativeMaturityStage.resolve(days: 14).key, .mature)
        XCTAssertEqual(NativeMaturityStage.resolve(days: 30).key, .rich)
    }

    func testInsightSnapshotAggregatesDailyDomainSummary() {
        let rows = [
            makeInsightDay(date: "2026-07-14", expense: 30, income: 100, sleep: 480, food: 1200),
            makeInsightDay(date: "2026-07-15", expense: 20, income: 0, sleep: 420, food: 900)
        ]
        let snapshot = NativeInsightSnapshot(range: .fourteen, rows: rows)

        XCTAssertEqual(snapshot.activeDays, 2)
        XCTAssertEqual(snapshot.expenseTotal, 50)
        XCTAssertEqual(snapshot.incomeTotal, 100)
        XCTAssertEqual(snapshot.netBalance, 50)
        XCTAssertEqual(snapshot.averageSleepHours, 7.5)
        XCTAssertEqual(snapshot.foodCalories, 2100)
    }

    func testAIInsightPayloadParsesStructuredLists() {
        let payload = NativeAIInsightPayload([
            "headline": AnyCodable("近两周收支稳定"),
            "observations": AnyCodable(["消费集中在周末", "睡眠逐步改善"]),
            "action_plan": AnyCodable(["设置每日预算"]),
            "route": AnyCodable(["mode_label": "现金流分析"])
        ])

        XCTAssertEqual(payload.headline, "近两周收支稳定")
        XCTAssertEqual(payload.observations.count, 2)
        XCTAssertEqual(payload.actionPlan, ["设置每日预算"])
        XCTAssertEqual(payload.modeLabel, "现金流分析")
    }

    func testHomeWidgetPreferencesRestoreMissingPWAKeys() {
        let configuration = [
            NativeHomeWidgetConfiguration(key: .today, isEnabled: false, order: 8),
            NativeHomeWidgetConfiguration(key: .finance, isEnabled: true, order: 1)
        ]
        let normalized = NativeHomeWidgetPreferences.normalized(configuration)
        XCTAssertEqual(normalized.map(\.key), [.finance, .today, .pending, .domains, .daily])
        XCTAssertEqual(normalized.first(where: { $0.key == .today })?.isEnabled, false)
        XCTAssertEqual(normalized.map(\.order), [0, 1, 2, 3, 4])
    }

    func testHomeFinanceUsesRealAccountBalances() {
        let cash = NativeAccount(
            id: "cash", name: "零钱", type: .walletBalance, institution: "", last4: "", currency: "CNY",
            initialBalance: 0, currentBalance: 800, snapshotBalance: nil, snapshotAt: nil,
            sourceRecordTable: "", sourceRecordId: "", billDay: nil, paymentDueDay: nil,
            autoDebitAccountId: nil, autoConfirmRepayment: false, gracePeriodDays: 0,
            lastReconciledAt: nil, isDefaultExpense: true, isDefaultIncome: false,
            isArchived: false, sortOrder: 0
        )
        let liability = makeLiabilityAccount(id: "credit", name: "花呗")
        let summary = NativeHomeFinanceSummary.make(
            accounts: [cash, liability],
            dashboard: DashboardSnapshot(todayExpense: 30, todayIncome: 100)
        )
        XCTAssertEqual(summary.availableCash, 800)
        XCTAssertEqual(summary.liabilityTotal, 320)
        XCTAssertEqual(summary.netWorthEstimate, 480)
        XCTAssertEqual(summary.todayIncome - summary.todayExpense, 70)
    }

    func testAccountTypeNormalizationMatchesPWAAdapter() {
        XCTAssertEqual(NativeAccountType.normalized("wechat"), .walletBalance)
        XCTAssertEqual(NativeAccountType.normalized("bank_card"), .debitCard)
        XCTAssertEqual(NativeAccountType.normalized("huabei"), .creditLine)
        XCTAssertEqual(NativeAccountType.normalized("unknown"), .other)
    }

    func testAccountDraftRejectsInvalidLiabilityDays() {
        var draft = NativeAccountDraft()
        draft.name = "信用账户"
        draft.type = .creditCard
        draft.billDayText = "32"
        XCTAssertEqual(draft.validationMessage, "账单日必须是 1-31 之间的整数")
    }

    func testAccountRecommendationMatchesPWAExpenseRules() {
        let account = NativeAccount(
            id: "wechat", name: "微信零钱", type: .walletBalance, institution: "微信", last4: "",
            currency: "CNY", initialBalance: 0, currentBalance: 100, snapshotBalance: nil,
            snapshotAt: nil, sourceRecordTable: "", sourceRecordId: "", billDay: nil,
            paymentDueDay: nil, autoDebitAccountId: nil, autoConfirmRepayment: false,
            gracePeriodDays: 0, lastReconciledAt: nil, isDefaultExpense: false,
            isDefaultIncome: false, isArchived: false, sortOrder: 0
        )
        let record = NativeUnboundRecord(
            id: "tx-1", kind: .expense, title: "早餐", amount: 12, date: "2026-07-14",
            time: nil, platform: "微信", category: "餐饮", paymentMethod: "微信支付",
            note: nil, source: nil, imagePath: nil, imageHash: nil, companionMessage: nil
        )
        XCTAssertEqual(
            NativeAccountRecommendationEngine.recommendation(for: record, accounts: [account])?.account.id,
            "wechat"
        )
    }

    func testArchivedAccountIsNeverRecommended() {
        let account = NativeAccount(
            id: "default", name: "默认卡", type: .debitCard, institution: "", last4: "",
            currency: "CNY", initialBalance: 0, currentBalance: 0, snapshotBalance: nil,
            snapshotAt: nil, sourceRecordTable: "", sourceRecordId: "", billDay: nil,
            paymentDueDay: nil, autoDebitAccountId: nil, autoConfirmRepayment: false,
            gracePeriodDays: 0, lastReconciledAt: nil, isDefaultExpense: true,
            isDefaultIncome: false, isArchived: true, sortOrder: 0
        )
        let record = NativeUnboundRecord(
            id: "tx-1", kind: .expense, title: "支出", amount: 10, date: "2026-07-14",
            time: nil, platform: nil, category: nil, paymentMethod: nil,
            note: nil, source: nil, imagePath: nil, imageHash: nil, companionMessage: nil
        )
        XCTAssertNil(NativeAccountRecommendationEngine.recommendation(for: record, accounts: [account]))
    }

}

private struct DashboardRepositoryStub: DashboardRepositoryProtocol {
    let snapshot: DashboardSnapshot

    func fetchDashboardCore(accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }

    func hydrateDashboardImages(_ snapshot: DashboardSnapshot, accessToken: String) async throws -> DashboardSnapshot {
        snapshot
    }
}


private struct RecordRepositoryStub: RecordRepositoryProtocol {
    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        throw SupabaseRemoteError.requestFailed("unused")
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func delete(reference: String, accessToken: String) async throws {}

    func submitFeedback(recordId: String, choice: NativeAIFeedbackReviewChoice, freeText: String, accessToken: String) async throws {}
}

private struct InboxRepositoryStub: InboxRepositoryProtocol {
    func discard(id: String, accessToken: String) async throws {}

    func retry(id: String, accessToken: String) async throws -> ShortcutUploadResult {
        ShortcutUploadResult(displayText: "已重新识别")
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func resolveRepayment(id: String, cycleId: String, accessToken: String) async throws {}

    func resolveImageURL(path: String, accessToken: String) async throws -> URL {
        URL(string: "https://example.com/receipt.jpg")!
    }

    func confirmPending(_ draft: NativePendingResolutionDraft, accessToken: String) async throws {}
}


private struct DomainRepositoryStub: DomainRepositoryProtocol {
    func fetchDefinitions(accessToken: String) async throws -> [NativeDomainDefinition] {
        [NativeDomainDefinition(id: "sport", name: "运动记录", description: "", icon: "🏃", isSystem: true, schema: [:], display: [:], recordCount: 0)]
    }
}

private func makeLiabilityAccount(id: String, name: String) -> NativeAccount {
    NativeAccount(
        id: id, name: name, type: .creditLine, institution: "支付宝", last4: "", currency: "CNY",
        initialBalance: 320, currentBalance: 320, snapshotBalance: nil, snapshotAt: nil,
        sourceRecordTable: "", sourceRecordId: "", billDay: 1, paymentDueDay: 15,
        autoDebitAccountId: nil, autoConfirmRepayment: false, gracePeriodDays: 0,
        lastReconciledAt: nil, isDefaultExpense: false, isDefaultIncome: false,
        isArchived: false, sortOrder: 0
    )
}

private func makeRepaymentCycle(accountId: String, amount: Double, dueDate: String) -> NativeRepaymentCycle {
    NativeRepaymentCycle(
        id: "cycle-1", accountId: accountId, cycleMonth: "2026-07", statementStartDate: nil,
        statementEndDate: nil, dueDate: dueDate, statementAmount: amount, paidAmount: 0,
        remainingAmount: amount, carriedOverAmount: 0, originalStatementAmount: amount,
        minPaymentAmount: 30, refundAppliedAmount: 0, status: .pending,
        autoDebitAccountId: nil, autoConfirmRepayment: false, source: "screenshot",
        evidenceRecordId: nil, confidence: 0.95, note: "", confirmedAt: nil
    )
}

private func makeInsightDay(
    date: String,
    expense: Double,
    income: Double,
    sleep: Double,
    food: Double
) -> NativeDailyDomainSummary {
    NativeDailyDomainSummary(
        date: date, expenseTotal: expense, expenseCount: expense > 0 ? 1 : 0,
        incomeTotal: income, incomeCount: income > 0 ? 1 : 0,
        sleepMinutes: sleep, sleepScoreAverage: nil, sleepCount: sleep > 0 ? 1 : 0,
        sportMinutes: 0, sportCount: 0, readingMinutes: 0, readingCount: 0,
        foodCalories: food, foodMeals: food > 0 ? 1 : 0, hasAnyData: true
    )
}
