import XCTest
import UIKit
@testable import SnapCount

final class SnapCountTests: XCTestCase {
    func testLocalDateKeyUsesShanghaiCalendarDay() {
        XCTAssertEqual(NativeLocalDate.dateKey("2026-07-17T16:30:00Z"), "2026-07-18")
        XCTAssertEqual(NativeLocalDate.dateKey("2026-07-18T00:30:00+08:00"), "2026-07-18")
        XCTAssertEqual(NativeLocalDate.dateKey("2026-07-18"), "2026-07-18")
        XCTAssertEqual(NativeLocalDate.timeKey("2026-07-17T16:30:00Z"), "00:30")
    }

    func testAppTabsHaveTitles() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testInboxCategoriesKeepActionOrderAndHideEmptyGroups() {
        let pending = NativePendingExpense(
            id: "pending-1",
            title: "待补全账单",
            amount: 70.89,
            dateKey: "2026-07-25",
            reference: "pending/pending-1"
        )
        let item = NativeInboxItem(
            id: "pending-pending-1",
            kind: .pendingExpense,
            dateKey: pending.dateKey,
            title: pending.title,
            subtitle: "¥70.89",
            status: "pending",
            statusLabel: "待补全",
            systemImage: "creditcard",
            pendingExpense: pending,
            stagingRecord: nil
        )

        let categories = NativeInboxPresentation.categories(from: [item])

        XCTAssertEqual(categories.map(\.filter), [.pendingExpense])
        XCTAssertEqual(categories.first?.count, 1)
        XCTAssertEqual(categories.first?.title, "待补全账单")
    }

    func testOnboardingProgressIsVersionedAndUserScoped() throws {
        let suiteName = "SnapCountTests.Onboarding.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = OnboardingProgressStore(defaults: defaults)

        XCTAssertTrue(store.shouldPresent(for: "user-a"))
        XCTAssertTrue(store.shouldPresent(for: "user-b"))

        store.mark(.completed, for: "user-a")

        XCTAssertFalse(store.shouldPresent(for: "user-a"))
        XCTAssertEqual(store.completion(for: "user-a"), .completed)
        XCTAssertTrue(store.shouldPresent(for: "user-b"))
        XCTAssertTrue(store.shouldPresent(for: "user-a", version: OnboardingProgressStore.currentVersion + 1))

        store.mark(.skipped, for: "user-b")
        XCTAssertEqual(store.completion(for: "user-b"), .skipped)
    }

    @MainActor
    func testResetUserScopedStateClearsNavigationAndDetails() {
        let state = AppState()
        state.selectedTab = .records
        state.dashboard = DashboardSnapshot(todayCount: 3)
        state.todayPath.append(NativeDayDetailRoute(dateKey: "2026-07-17", kind: .all))
        state.inboxPath.append(NativeInboxRoute.staging(recordId: "staging-1"))
        state.recordsPath.append(NativeRecordRoute(reference: "expense/record-1"))
        state.recordExpressionPlanExposureState = .failed
        state.selectedRecordDetail = NativeRecordDetail(
            id: "expense/record-1", rawId: "record-1", kind: "expense",
            title: "早餐", subtitle: "2026-07-17", value: "¥12.00", detailRows: [],
            imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: 12, merchantName: "早餐", platform: "微信", category: "food",
            paymentMethod: "微信支付", recordDate: "2026-07-17", note: nil,
            companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil
        )
        state.financeVocabulary = [
            NativeFinanceVocabularyEntry(
                id: "platform-1",
                kind: .platform,
                displayName: "盒马",
                primaryCategory: nil,
                linkedAccountId: nil,
                source: "user_confirmed",
                status: "active",
                usageCount: 2,
                lastUsedAt: "2026-07-21T12:00:00Z"
            )
        ]

        state.resetUserScopedState()

        XCTAssertEqual(state.selectedTab, .today)
        XCTAssertEqual(state.dashboard.todayCount, 0)
        XCTAssertTrue(state.todayPath.isEmpty)
        XCTAssertEqual(state.inboxPath.count, 0)
        XCTAssertEqual(state.recordsPath.count, 0)
        XCTAssertNil(state.selectedRecordDetail)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
        XCTAssertTrue(state.accounts.isEmpty)
        XCTAssertTrue(state.financeVocabulary.isEmpty)
    }

    @MainActor
    func testOpeningInboxCategorySwitchesTabAndCreatesOneRoute() {
        let state = AppState()

        state.openInbox(filter: .failed)

        XCTAssertEqual(state.selectedTab, .inbox)
        XCTAssertEqual(state.inboxPath.count, 1)
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

    func testMonthKeyShiftHandlesYearBoundary() {
        XCTAssertEqual(NativeMonthKey.shifted("2026-01", by: -1), "2025-12")
        XCTAssertEqual(NativeMonthKey.shifted("2025-12", by: 1), "2026-01")
        XCTAssertEqual(NativeMonthKey.title("2026-07"), "2026年7月")
        XCTAssertNil(NativeMonthKey.shifted("2026-13", by: 1))
    }

    func testDashboardPartialFailurePreservesFailedSectionOnly() {
        let oldExpense = NativeDayRecord(
            id: "expense-old", reference: "expense/old", dateKey: "2026-07-17",
            kind: .expense, domainKey: "expense", title: "旧消费", subtitle: "",
            value: "¥10.00", timeLabel: "08:00", systemImage: "creditcard"
        )
        let oldIncome = NativeDayRecord(
            id: "income-old", reference: "income/old", dateKey: "2026-07-17",
            kind: .income, domainKey: "income", title: "旧收入", subtitle: "",
            value: "+¥20.00", timeLabel: nil, systemImage: "arrow.down.circle"
        )
        var previous = DashboardSnapshot(monthExpense: 10, monthIncome: 20)
        previous.dayRecordGroups = [NativeDayRecordGroup(dateKey: "2026-07-17", records: [oldExpense, oldIncome])]
        previous.dailySummaries = [NativeDailySummary(dateKey: "2026-07-17", expense: 10, income: 20, pendingCount: 0, recordCount: 2)]

        let newIncome = NativeDayRecord(
            id: "income-new", reference: "income/new", dateKey: "2026-07-17",
            kind: .income, domainKey: "income", title: "新收入", subtitle: "",
            value: "+¥30.00", timeLabel: nil, systemImage: "arrow.down.circle"
        )
        var partial = DashboardSnapshot(monthIncome: 30)
        partial.dayRecordGroups = [NativeDayRecordGroup(dateKey: "2026-07-17", records: [newIncome])]
        partial.dailySummaries = [NativeDailySummary(dateKey: "2026-07-17", expense: 0, income: 30, pendingCount: 0, recordCount: 1)]
        partial.unavailableSections = [.expense]

        let merged = partial.mergingUnavailableSections(from: previous)

        XCTAssertEqual(merged.monthExpense, 10)
        XCTAssertEqual(merged.monthIncome, 30)
        XCTAssertEqual(Set(merged.dayRecordGroups.flatMap(\.records).map(\.id)), ["expense-old", "income-new"])
        XCTAssertEqual(merged.dailySummaries.first?.expense, 10)
        XCTAssertEqual(merged.dailySummaries.first?.income, 30)
    }

    func testDashboardPendingHistoryFailurePreservesOnlyOlderPendingRecords() {
        let currentMonth = String(NativeLocalDate.dateKey(Date()).prefix(7))
        let currentDate = "\(currentMonth)-15"
        let olderDate = NativeMonthKey.shifted(currentMonth, by: -1).map { "\($0)-20" }
            ?? "2026-06-20"
        let currentPending = NativePendingExpense(
            id: "current-new", title: "本月待补全", amount: 12, dateKey: currentDate,
            reference: "expense/current-new", occurredAtLabel: "\(currentDate) 12:00"
        )
        let staleCurrentPending = NativePendingExpense(
            id: "current-stale", title: "已处理的旧缓存", amount: 18, dateKey: currentDate,
            reference: "expense/current-stale", occurredAtLabel: "\(currentDate) 08:00"
        )
        let olderPending = NativePendingExpense(
            id: "older", title: "跨月待补全", amount: 20, dateKey: olderDate,
            reference: "expense/older", occurredAtLabel: "\(olderDate) 09:00"
        )
        var previous = DashboardSnapshot(monthExpense: 80)
        previous.pendingExpenses = [staleCurrentPending, olderPending]
        var partial = DashboardSnapshot(monthExpense: 100)
        partial.pendingExpenses = [currentPending]
        partial.unavailableSections = [.pendingExpense]

        let merged = partial.mergingUnavailableSections(from: previous)

        XCTAssertEqual(merged.monthExpense, 100)
        XCTAssertEqual(merged.pendingExpenses.map(\.id), ["current-new", "older"])
        XCTAssertEqual(merged.pendingCount, 2)
    }

    func testDashboardKeepsFreshPendingWhenMonthlyExpenseQueryFails() {
        let previousPending = NativePendingExpense(
            id: "previous",
            title: "旧待补全",
            amount: 10,
            dateKey: "2026-07-20",
            reference: "expense/previous"
        )
        let freshPending = NativePendingExpense(
            id: "fresh",
            title: "新待补全",
            amount: 20,
            dateKey: "2026-07-26",
            reference: "expense/fresh"
        )
        var previous = DashboardSnapshot(monthExpense: 80, todayExpense: 8)
        previous.pendingExpenses = [previousPending]
        var partial = DashboardSnapshot(monthExpense: 0, todayExpense: 0)
        partial.pendingExpenses = [freshPending]
        partial.unavailableSections = [.expense]

        let merged = partial.mergingUnavailableSections(from: previous)

        XCTAssertEqual(merged.monthExpense, 80)
        XCTAssertEqual(merged.todayExpense, 8)
        XCTAssertEqual(merged.pendingExpenses.map(\.id), ["fresh"])
        XCTAssertEqual(merged.pendingCount, 1)
    }

    func testDashboardPagedQueriesEndWithUniqueIDTieBreaker() {
        XCTAssertTrue(
            NativeDashboardQueryOrder.pagedQueries.allSatisfy { $0.hasSuffix(",id.desc") }
        )
    }

    func testFinanceRangeFilterUsesPostgRESTOrGrouping() {
        let financeFilter = NativeDataService.financeRangeFilter(
            occurredAtColumn: "occurred_at",
            legacyDateColumn: "transaction_date",
            fallbackStart: "2026-08-01",
            fallbackEnd: "2026-08-31",
            startTimestamp: "2026-07-31T16:00:00Z",
            endTimestamp: "2026-08-31T15:59:59Z"
        )

        XCTAssertEqual(
            financeFilter,
            "(and(occurred_at.gte.2026-07-31T16:00:00Z,occurred_at.lte.2026-08-31T15:59:59Z),and(occurred_at.is.null,transaction_date.gte.2026-08-01,transaction_date.lte.2026-08-31))"
        )
        XCTAssertTrue(financeFilter.hasPrefix("(and("))
        XCTAssertTrue(financeFilter.hasSuffix("))"))

        let universalFilter = NativeDataService.financeRangeFilter(
            occurredAtColumn: "occurred_at",
            legacyDateColumn: "created_at",
            fallbackStart: "2026-07-31T16:00:00Z",
            fallbackEnd: "2026-08-31T15:59:59Z",
            startTimestamp: "2026-07-31T16:00:00Z",
            endTimestamp: "2026-08-31T15:59:59Z"
        )

        XCTAssertEqual(
            universalFilter,
            "(and(occurred_at.gte.2026-07-31T16:00:00Z,occurred_at.lte.2026-08-31T15:59:59Z),and(occurred_at.is.null,created_at.gte.2026-07-31T16:00:00Z,created_at.lte.2026-08-31T15:59:59Z))"
        )
    }

    func testCameraUploadUsesSmallerPhotoPreset() throws {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1_800, height: 1_200))
        let source = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 1_800, height: 1_200))
        }

        let data = try ImageUploadPreprocessor.cameraJPEGData(from: source)
        let compressed = try XCTUnwrap(UIImage(data: data))
        let compressedPixels = try XCTUnwrap(compressed.cgImage)

        XCTAssertLessThanOrEqual(max(compressedPixels.width, compressedPixels.height), 960)
        XCTAssertLessThan(data.count, 900_000)
    }

    func testRecordRepositoryProtocolSupportsStubInjection() async throws {
        let repository: RecordRepositoryProtocol = RecordRepositoryStub()
        try await repository.delete(reference: "expense:record-1", accessToken: "test-token")
        let expressionPlanLookup = try await repository.getRecordExpressionPlan(
            reference: "sleep/record-1",
            accessToken: "test-token"
        )
        XCTAssertEqual(expressionPlanLookup, .unavailable(reason: "no_selected_candidate"))
        try await repository.submitFeedback(
            recordId: "record-1",
            choice: .notHelpful,
            freeText: "",
            exposureEventId: "exposure-1",
            accessToken: "test-token"
        )
    }

    func testRecordReferenceCanonicalizesLegacyAliases() {
        XCTAssertEqual(NativeRecordReference("tx-record-1").canonicalValue, "expense/record-1")
        XCTAssertEqual(NativeRecordReference("income-record-2").canonicalValue, "income/record-2")
        XCTAssertEqual(NativeRecordReference("data-record-3").canonicalValue, "data/record-3")
        XCTAssertEqual(NativeRecordReference("expense/record-1").canonicalValue, "expense/record-1")
    }

    @MainActor
    func testRecordDetailOnlyMatchesCurrentRouteIdentity() {
        let state = AppState()
        state.selectedRecordDetail = NativeRecordDetail(
            id: "expense/record-1", rawId: "record-1", kind: "expense",
            title: "早餐", subtitle: "2026-07-17", value: "¥12.00", detailRows: [],
            imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: 12, merchantName: "早餐", platform: "微信", category: "food",
            paymentMethod: "微信支付", recordDate: "2026-07-17", note: nil,
            companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil
        )

        XCTAssertNotNil(state.recordDetail(matching: "tx-record-1"))
        XCTAssertNil(state.recordDetail(matching: "expense/record-2"))
    }

    func testRecordEditDraftPreservesPWAExpenseMetadata() {
        let detail = NativeRecordDetail(
            id: "expense/record-1", rawId: "record-1", kind: "expense",
            title: "高铁票", subtitle: "2026-07-17", value: "¥420.00", detailRows: [],
            imageURL: nil, imageLoadError: false, imagePath: "user/ticket.jpg", imageHash: "hash-1",
            amount: 420, merchantName: "铁路 12306", platform: "铁路 12306", category: "transport",
            paymentMethod: "银行卡", recordDate: "2026-07-17", note: "出差",
            companionMessage: "已记录行程", accountId: "card-1", systemImage: "creditcard", payload: nil,
            transactionTime: "08:25:00", source: "manual", isLargeTransport: true, transportType: "高铁"
        )

        let draft = NativeRecordEditDraft(detail: detail)

        XCTAssertEqual(draft.transactionTime, "08:25:00")
        XCTAssertEqual(draft.source, "manual")
        XCTAssertTrue(draft.isLargeTransport)
        XCTAssertEqual(draft.transportType, "高铁")
        XCTAssertEqual(draft.imagePath, "user/ticket.jpg")
        XCTAssertEqual(draft.imageHash, "hash-1")
        XCTAssertEqual(draft.companionMessage, "已记录行程")
    }

    func testAIFeedbackParsesPWAFields() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "icon": AnyCodable("✨"),
            "badge": AnyCodable("今天很稳"),
            "band": AnyCodable("positive"),
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("记录已经落下。"),
            "utility_line": AnyCodable("继续保持当前节奏。"),
            "detail_reason": AnyCodable("金额和分类完整。"),
            "exposure_event_id": AnyCodable("exposure-1"),
            "timing_signal": AnyCodable(["label": AnyCodable("晚间记录")])
        ]))

        XCTAssertEqual(feedback.exposureEventId, "exposure-1")
        XCTAssertEqual(feedback.candidateId, "candidate-1")
        XCTAssertTrue(feedback.isReviewable)
        XCTAssertTrue(feedback.isAcknowledgedPlannerFeedback)
        XCTAssertTrue(
            NativeAIFeedbackReviewPresentation.shouldShowSection(
                reviewable: feedback.isReviewable,
                requiresExposureAcknowledgement: feedback.requiresExposureAcknowledgement
            )
        )
        XCTAssertEqual(feedback.badge, "今天很稳")
        XCTAssertEqual(feedback.bandLabel, "正向")
        XCTAssertEqual(feedback.timingLabel, "晚间记录")
    }

    func testPlannerPreviewIsNotReviewableBeforeExposureAcknowledgement() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("本周餐饮支出较上周同期下降。")
        ]))

        XCTAssertNil(feedback.exposureEventId)
        XCTAssertTrue(feedback.requiresExposureAcknowledgement)
        XCTAssertFalse(feedback.isReviewable)
        XCTAssertFalse(feedback.isAcknowledgedPlannerFeedback)
        XCTAssertTrue(
            NativeAIFeedbackReviewPresentation.shouldShowSection(
                reviewable: feedback.isReviewable,
                requiresExposureAcknowledgement: feedback.requiresExposureAcknowledgement
            )
        )
    }

    func testLegacyFeedbackRemainsReviewableWithoutExposureEvent() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "emotion_line": AnyCodable("这条旧反馈仍可按记录点评。")
        ]))

        XCTAssertNil(feedback.exposureEventId)
        XCTAssertTrue(feedback.isReviewable)
        XCTAssertTrue(
            NativeAIFeedbackReviewPresentation.shouldShowSection(
                reviewable: feedback.isReviewable,
                requiresExposureAcknowledgement: feedback.requiresExposureAcknowledgement
            )
        )
        XCTAssertFalse(
            NativeAIFeedbackReviewPresentation.shouldShowSection(
                reviewable: false,
                requiresExposureAcknowledgement: feedback.requiresExposureAcknowledgement
            )
        )
    }

    func testFeedbackRequestBodyIncludesOnlyUsableExposureEventId() {
        let boundBody = RecordRepository.feedbackRequestBody(
            recordId: "record-1",
            choice: .helpful,
            freeText: "这个角度很好",
            exposureEventId: " exposure-1 "
        )

        XCTAssertEqual(boundBody["record_id"]?.stringValue, "record-1")
        XCTAssertEqual(boundBody["primary_choice"]?.stringValue, "helpful")
        XCTAssertEqual(boundBody["exposure_event_id"]?.stringValue, "exposure-1")

        let unboundBody = RecordRepository.feedbackRequestBody(
            recordId: "record-2",
            choice: .notHelpful,
            freeText: "",
            exposureEventId: "  "
        )

        XCTAssertNil(unboundBody["exposure_event_id"])
    }

    func testExpressionPlanDeliveryRequestBodiesUseTwoPhaseActions() {
        let previewBody = RecordRepository.expressionPlanPreviewRequestBody(reference: "data/record-1")
        XCTAssertEqual(previewBody["action"]?.stringValue, "get_record_expression_plan")
        XCTAssertEqual(previewBody["record_id"]?.stringValue, "record-1")
        XCTAssertEqual(previewBody["record_kind"]?.stringValue, "data")
        XCTAssertNil(previewBody["plan_token"])

        let sleepPreviewBody = RecordRepository.expressionPlanPreviewRequestBody(reference: "sleep/record-2")
        XCTAssertEqual(sleepPreviewBody["record_id"]?.stringValue, "record-2")
        XCTAssertEqual(sleepPreviewBody["record_kind"]?.stringValue, "data")

        let acknowledgementBody = RecordRepository.expressionPlanAcknowledgementRequestBody(
            recordId: "record-1",
            planToken: "plan-1",
            candidateId: "candidate-1"
        )
        XCTAssertEqual(acknowledgementBody["action"]?.stringValue, "ack_record_expression_plan")
        XCTAssertEqual(acknowledgementBody["record_id"]?.stringValue, "record-1")
        XCTAssertEqual(acknowledgementBody["plan_token"]?.stringValue, "plan-1")
        XCTAssertEqual(acknowledgementBody["candidate_id"]?.stringValue, "candidate-1")
    }

    @MainActor
    func testExpressionPlanRetryWaitsForExplicitAcknowledgement() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("距离上一次同名记录已经过去 2 天。")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("距离上一次同名记录已经过去 2 天。"),
            "exposure_event_id": AnyCodable("exposure-1")
        ]))
        let expected = NativeRecordExpressionPlan(
            planToken: "plan-1",
            candidateId: "candidate-1",
            feedback: previewFeedback
        )
        let repository = RecordRepositoryStub(
            expressionPlanLookups: [.pending, .pending, .available(expected)],
            acknowledgedFeedback: acknowledgedFeedback
        )
        var observedDelays: [UInt64] = []

        let resolved = await NativeRecordExpressionPlanRetryPolicy.resolve(
            fetch: {
                try await repository.getRecordExpressionPlan(
                    reference: "expense/record-1",
                    accessToken: "test-token"
                )
            },
            shouldContinue: { true },
            sleep: { observedDelays.append($0) }
        )

        XCTAssertEqual(resolved, expected)
        XCTAssertNotEqual(previewFeedback.renderIdentity, acknowledgedFeedback.renderIdentity)
        XCTAssertEqual(observedDelays, Array(NativeRecordExpressionPlanRetryPolicy.delaysNanoseconds.prefix(2)))
        XCTAssertLessThanOrEqual(
            NativeRecordExpressionPlanRetryPolicy.delaysNanoseconds.reduce(0, +),
            6_000_000_000
        )
        XCTAssertEqual(repository.acknowledgementCount, 0)
        let resolvedPlan = try XCTUnwrap(resolved)
        let acknowledged = try await repository.acknowledgeRecordExpressionPlan(
            recordId: "record-1",
            planToken: resolvedPlan.planToken,
            candidateId: resolvedPlan.candidateId,
            accessToken: "test-token"
        )
        XCTAssertEqual(acknowledged.exposureEventId, "exposure-1")
        XCTAssertEqual(repository.acknowledgementCount, 1)
    }

    @MainActor
    func testExpressionPlanCardVisibilityStateIsExplicitAndReversible() {
        let state = AppState()
        let feedbackIdentity = "expression_planner:candidate-1:preview:当前候选"

        XCTAssertFalse(state.isRecordExpressionPlanCardVisible(reference: "expense/record-1"))
        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "tx-record-1",
            feedbackIdentity: feedbackIdentity
        )
        XCTAssertTrue(state.isRecordExpressionPlanCardVisible(reference: "expense/record-1"))
        XCTAssertTrue(state.isRecordExpressionPlanCardVisible(
            reference: "expense/record-1",
            feedbackIdentity: feedbackIdentity
        ))
        state.setRecordExpressionPlanCardVisible(false, reference: "expense/record-1")
        XCTAssertFalse(state.isRecordExpressionPlanCardVisible(reference: "tx-record-1"))
    }

    func testAIFeedbackCardVisibilityRequiresOnePercentOfCardArea() {
        let cardFrame = CGRect(x: 0, y: 0, width: 100, height: 100)
        let exactlyOnePercent = CGRect(x: 99, y: 0, width: 100, height: 100)
        let lessThanOnePercent = CGRect(x: 99.1, y: 0, width: 100, height: 100)
        let outsideViewport = CGRect(x: 100, y: 0, width: 100, height: 100)

        XCTAssertEqual(
            NativeAIFeedbackCardVisibility.visibleRatio(
                cardFrame: cardFrame,
                viewportFrame: exactlyOnePercent
            ),
            0.01,
            accuracy: 0.000_001
        )
        XCTAssertTrue(
            NativeAIFeedbackCardVisibility.isVisible(
                cardFrame: cardFrame,
                viewportFrame: exactlyOnePercent
            )
        )
        XCTAssertFalse(
            NativeAIFeedbackCardVisibility.isVisible(
                cardFrame: cardFrame,
                viewportFrame: lessThanOnePercent
            )
        )
        XCTAssertFalse(
            NativeAIFeedbackCardVisibility.isVisible(
                cardFrame: cardFrame,
                viewportFrame: outsideViewport
            )
        )
        XCTAssertFalse(
            NativeAIFeedbackCardVisibility.isVisible(
                cardFrame: .zero,
                viewportFrame: cardFrame
            )
        )
    }

    func testSubmittedAIFeedbackCanReopenRevisionFormForSameExposure() {
        XCTAssertEqual(NativeAIFeedbackReviewChoice.allCases.count, 9)
        XCTAssertEqual(
            NativeAIFeedbackReviewPresentation.resolve(
                reviewState: .submitted,
                isRevisingSubmittedReview: false
            ),
            .submitted
        )
        XCTAssertEqual(
            NativeAIFeedbackReviewPresentation.resolve(
                reviewState: .submitted,
                isRevisingSubmittedReview: true
            ),
            .form(isRevision: true)
        )
        XCTAssertEqual(
            NativeAIFeedbackReviewPresentation.resolve(
                reviewState: .failed("temporary failure"),
                isRevisingSubmittedReview: true
            ),
            .form(isRevision: true)
        )

        let original = RecordRepository.feedbackRequestBody(
            recordId: "record-1",
            choice: .helpful,
            freeText: "这个角度很好",
            exposureEventId: "exposure-1"
        )
        let revision = RecordRepository.feedbackRequestBody(
            recordId: "record-1",
            choice: .repetitive,
            freeText: "最近出现得太多",
            exposureEventId: "exposure-1"
        )

        XCTAssertEqual(
            original["exposure_event_id"]?.stringValue,
            revision["exposure_event_id"]?.stringValue
        )
        XCTAssertNotEqual(
            original["primary_choice"]?.stringValue,
            revision["primary_choice"]?.stringValue
        )
    }

    func testAcknowledgedPlannerFeedbackWinsOverPendingAndRemoteFeedback() throws {
        let remoteFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("legacy_voice"),
            "emotion_line": AnyCodable("远端旧反馈")
        ]))
        let pendingFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-new"),
            "emotion_line": AnyCodable("新的待确认候选")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-stable"),
            "emotion_line": AnyCodable("当前可点评候选"),
            "exposure_event_id": AnyCodable("exposure-stable")
        ]))

        XCTAssertTrue(
            NativeRecordExpressionFeedbackPolicy.hasAcknowledgedPlannerFeedback([
                remoteFeedback,
                acknowledgedFeedback
            ])
        )
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToPreserve(
                existing: [remoteFeedback, acknowledgedFeedback],
                pending: pendingFeedback
            ),
            acknowledgedFeedback
        )
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToPreserve(
                existing: [remoteFeedback],
                pending: pendingFeedback
            ),
            pendingFeedback
        )
    }

    func testPlannerPreviewUsesIndependentFeedbackSlotInsteadOfLegacyFeedback() throws {
        let companionFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "badge": AnyCodable("金额偏高"),
            "emotion_line": AnyCodable("这笔比你平时的同类消费高一些。"),
            "detail_reason": AnyCodable("结合当前金额和历史消费判断。")
        ]))
        let contextPreview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:expense:record-context:record-1"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "dimension": AnyCodable("record_context"),
            "emotion_line": AnyCodable("记录于今天 09:43。"),
            "detail_reason": AnyCodable("基于当前记录计算。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: companionFeedback,
                preview: contextPreview
            ),
            contextPreview
        )
    }

    func testLegacyFeedbackIsHiddenWhenRecordHasCompanionMessage() throws {
        let companionFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("这笔金额值得留意。")
        ]))
        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "支付宝的 6.8 元支出已归档，平静收尾。",
                feedback: companionFeedback
            )
        )
    }

    func testPlannerCurrentRecordFallbackIsHiddenAfterCompanionMessage() throws {
        let plannerFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:expense:record-context:record-1"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "emotion_line": AnyCodable("7/28 19:15 已记录一笔 6.8 元支出。")
        ]))

        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "支付宝的 6.8 元支出已归档，平静收尾。",
                feedback: plannerFeedback
            )
        )
    }

    func testAuthoritativeFeedbackCardIsNotHiddenByLegacyClientHeuristics() throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-card"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "claim_fingerprint": AnyCodable("fnv1a64:current-record"),
            "dimension": AnyCodable("current_fact"),
            "presentation_target": AnyCodable("feedback_card"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:card-text"),
            "emotion_line": AnyCodable("本次记录发生在今天 09:43。")
        ]))
        let legacyCoverage = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("这笔已经记下。"),
            "expression_coverage": AnyCodable([
                "coverage_version": "expression-coverage-v1",
                "expressed_semantic_key": "expense_current_record_context",
                "source_surface": "record_detail",
                "planner_version": "expression-shadow-auto-v0.6",
                "packet_fingerprint": "fnv1a32:legacy",
                "claim_fingerprint": "fnv1a64:current-record"
            ])
        ]))

        XCTAssertTrue(feedback.hasExplicitPresentationTarget)
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: legacyCoverage,
                preview: feedback,
                companionMessage: "这笔已经记下。"
            ),
            feedback
        )
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "这笔已经记下。",
                feedback: feedback,
                companionFeedback: legacyCoverage
            ),
            feedback
        )
        let acknowledged = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-card"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "claim_fingerprint": AnyCodable("fnv1a64:current-record"),
            "dimension": AnyCodable("current_fact"),
            "presentation_target": AnyCodable("feedback_card"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:card-text"),
            "emotion_line": AnyCodable("本次记录发生在今天 09:43。"),
            "exposure_event_id": AnyCodable("exposure-card")
        ]))
        let rewrittenAcknowledgement = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-card"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "claim_fingerprint": AnyCodable("fnv1a64:current-record"),
            "dimension": AnyCodable("current_fact"),
            "presentation_target": AnyCodable("feedback_card"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:rewritten-card"),
            "emotion_line": AnyCodable("确认时被改写的卡片文案。"),
            "exposure_event_id": AnyCodable("exposure-card")
        ]))
        XCTAssertTrue(feedback.hasSameDeliveryIdentity(as: acknowledged))
        XCTAssertFalse(feedback.hasSameDeliveryIdentity(as: rewrittenAcknowledgement))
    }

    func testCompanionTargetUsesVisibleMessageForExposureWithoutRenderingDuplicateBody() throws {
        let message = "这周第 4 次点沙县，熟悉的味道又出现了。"
        let existing = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable(message)
        ]))
        let preview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "semantic_key": AnyCodable("merchant_weekly_repeat"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable(message)
        ]))
        let acknowledged = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "semantic_key": AnyCodable("merchant_weekly_repeat"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable(message),
            "exposure_event_id": AnyCodable("exposure-voice")
        ]))

        XCTAssertTrue(preview.isCompanionMessageDelivery)
        XCTAssertTrue(preview.matchesVisibleCompanionMessage(message))
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: existing,
                preview: preview,
                companionMessage: message
            ),
            preview
        )
        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: message,
                feedback: preview
            )
        )
        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.companionFeedbackToReview(
                companionMessage: message,
                feedback: preview
            ),
            preview
        )
        XCTAssertTrue(preview.hasSameDeliveryIdentity(as: acknowledged))
        XCTAssertTrue(acknowledged.isReviewable)
    }

    func testCompanionTargetRejectsVisibleTextAndFingerprintDrift() throws {
        let preview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable("本周第 4 次记录沙县。")
        ]))
        let wrongFingerprint = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:different-text"),
            "emotion_line": AnyCodable("本周第 4 次记录沙县。"),
            "exposure_event_id": AnyCodable("exposure-voice")
        ]))

        XCTAssertFalse(preview.matchesVisibleCompanionMessage("本周第 11 次记录沙县。"))
        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.companionFeedbackToReview(
                companionMessage: "本周第 11 次记录沙县。",
                feedback: preview
            )
        )
        XCTAssertFalse(preview.hasSameDeliveryIdentity(as: wrongFingerprint))
    }

    func testPlannerRicherAngleStillRendersAfterCompanionMessage() throws {
        let plannerFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("comparison:merchant:daily-active-median:record-1"),
            "semantic_key": AnyCodable("merchant_daily_vs_active_day_median"),
            "dimension": AnyCodable("personal_baseline"),
            "emotion_line": AnyCodable("今天的消费低于你的活跃日中位数。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "支付宝的 6.8 元支出已归档，平静收尾。",
                feedback: plannerFeedback
            ),
            plannerFeedback
        )
    }

    func testPlannerAngleCoveredByVoiceProvenanceDoesNotReplaceOrRenderBesideCompanion() throws {
        let companionFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("第一次记下青禾茶饮，像是碰上了小惊喜。"),
            "expression_coverage": AnyCodable([
                "coverage_version": "expression-coverage-v1",
                "expressed_semantic_key": " Expense_Merchant_First_Occurrence ",
                "expressed_semantic_keys": ["expense_merchant_first_occurrence"],
                "source_surface": "record_detail",
                "planner_version": "expression-shadow-auto-v0.6",
                "packet_fingerprint": "fnv1a32:test",
                "claim_fingerprint": "fnv1a64:first-occurrence"
            ])
        ]))
        let plannerFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:expense:merchant-first-occurrence:record-1"),
            "semantic_key": AnyCodable("expense_merchant_first_occurrence"),
            "claim_fingerprint": AnyCodable("fnv1a64:first-occurrence"),
            "dimension": AnyCodable("first_occurrence"),
            "emotion_line": AnyCodable("第一次记录「青禾茶饮」")
        ]))

        XCTAssertEqual(
            companionFeedback.expressionCoverageSemanticKeys,
            ["expense_merchant_first_occurrence"]
        )
        let selected = NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
            existing: companionFeedback,
            preview: plannerFeedback,
            companionMessage: "第一次记下青禾茶饮，像是碰上了小惊喜。"
        )
        XCTAssertEqual(selected, companionFeedback)
        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "第一次记下青禾茶饮，像是碰上了小惊喜。",
                feedback: selected
            )
        )
    }

    func testExpressionCoverageDecodesFromRealJSONAndNormalizesKeys() throws {
        let json = #"""
        {
          "source": "hybrid",
          "emotion_line": "第一次记下青禾茶饮。",
          "expression_coverage": {
            "coverage_version": "expression-coverage-v1",
            "expressed_semantic_key": " Expense_Merchant_First_Occurrence ",
            "expressed_semantic_keys": [
              "expense_merchant_first_occurrence",
              " merchant_daily_count_total ",
              "",
              42
            ],
            "source_surface": "record_detail",
            "planner_version": "expression-shadow-auto-v0.6",
            "packet_fingerprint": "fnv1a32:test",
            "claim_fingerprint": "fnv1a64:first-occurrence"
          }
        }
        """#
        let payload = try JSONDecoder().decode(
            [String: AnyCodable].self,
            from: Data(json.utf8)
        )
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: payload))

        XCTAssertEqual(
            feedback.expressionCoverageSemanticKeys,
            ["expense_merchant_first_occurrence", "merchant_daily_count_total"]
        )
        XCTAssertEqual(feedback.expressionCoverageClaimFingerprint, "fnv1a64:first-occurrence")
    }

    func testEditedClaimFingerprintFailsOpenForSameSemanticKey() throws {
        let existing = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("第一次记下旧商户。"),
            "expression_coverage": AnyCodable([
                "coverage_version": "expression-coverage-v1",
                "expressed_semantic_key": "expense_merchant_first_occurrence",
                "expressed_semantic_keys": ["expense_merchant_first_occurrence"],
                "source_surface": "record_detail",
                "planner_version": "expression-shadow-auto-v0.6",
                "packet_fingerprint": "fnv1a32:before-edit",
                "claim_fingerprint": "fnv1a64:before-edit"
            ])
        ]))
        let preview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "semantic_key": AnyCodable("expense_merchant_first_occurrence"),
            "claim_fingerprint": AnyCodable("fnv1a64:after-edit"),
            "emotion_line": AnyCodable("第一次记录「新商户」")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: existing,
                preview: preview,
                companionMessage: "第一次记下旧商户。"
            ),
            preview
        )
    }

    func testCurrentRecordPreviewIsDiscardedWhenCompanionAlreadyOwnsThatSlot() throws {
        let preview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:expense:record-context:record-1"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "emotion_line": AnyCodable("已记录一笔 6.8 元支出。")
        ]))

        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: nil,
                preview: preview,
                companionMessage: "支付宝的 6.8 元支出已归档。"
            )
        )
    }

    func testPlannerObjectContextStillRendersAfterCompanionMessage() throws {
        let plannerFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:food:context:record-1"),
            "semantic_key": AnyCodable("food_record_context"),
            "dimension": AnyCodable("record_context"),
            "emotion_line": AnyCodable("这顿早餐记录了全麦面包。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "早餐已经记下。",
                feedback: plannerFeedback
            ),
            plannerFeedback
        )
    }

    func testPlannerCurrentMetricIsHiddenAfterCompanionMessage() throws {
        let plannerFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:sleep:record-1"),
            "semantic_key": AnyCodable("sleep_current_metric"),
            "dimension": AnyCodable("current_fact"),
            "emotion_line": AnyCodable("本次睡眠为 7.18 小时。")
        ]))

        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: "昨晚的睡眠已经收好。",
                feedback: plannerFeedback
            )
        )
    }

    func testLegacyFeedbackRendersWithoutCompanionMessage() throws {
        let legacyFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("legacy_voice"),
            "emotion_line": AnyCodable("已记录这笔支出。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: nil,
                feedback: legacyFeedback
            ),
            legacyFeedback
        )
    }

    func testPlannerPreviewStillDisplaysWhenRecordHasNoFeedback() throws {
        let contextPreview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("fact:expense:record-context:record-1"),
            "semantic_key": AnyCodable("expense_current_record_context"),
            "dimension": AnyCodable("record_context"),
            "emotion_line": AnyCodable("记录于今天 09:43。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: nil,
                preview: contextPreview
            ),
            contextPreview
        )
    }

    func testIncompletePlannerInsightStillUsesPlannerFeedbackSlot() throws {
        let companionFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("这笔金额值得留意。"),
            "detail_reason": AnyCodable("金额明显高于同类记录。")
        ]))
        let incompleteComparison = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("comparison:merchant:daily-active-median:record-1"),
            "semantic_key": AnyCodable("merchant_daily_vs_active_day_median"),
            "dimension": AnyCodable("personal_baseline"),
            "emotion_line": AnyCodable("今天共 1 笔、4 元。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: companionFeedback,
                preview: incompleteComparison
            ),
            incompleteComparison
        )
    }

    func testCompletePlannerInsightUsesPlannerFeedbackSlot() throws {
        let companionFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable("这笔金额值得留意。"),
            "detail_reason": AnyCodable("金额偏高。")
        ]))
        let comparison = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("comparison:merchant:daily-active-median:record-1"),
            "semantic_key": AnyCodable("merchant_daily_vs_active_day_median"),
            "dimension": AnyCodable("personal_baseline"),
            "emotion_line": AnyCodable("今天共 1 笔、4 元，低于你的活跃日中位数。"),
            "detail_reason": AnyCodable("基于 8 个历史活跃日计算。")
        ]))

        XCTAssertEqual(
            NativeRecordExpressionFeedbackPolicy.feedbackToDisplay(
                existing: companionFeedback,
                preview: comparison
            ),
            comparison
        )
    }

    func testExposurePresentationDoesNotShowProgressBeforeAcknowledgementStarts() {
        XCTAssertEqual(
            NativeAIFeedbackExposurePresentation.resolve(exposureState: .idle),
            .start
        )
        XCTAssertEqual(
            NativeAIFeedbackExposurePresentation.resolve(exposureState: .acknowledging),
            .acknowledging
        )
        XCTAssertEqual(
            NativeAIFeedbackExposurePresentation.resolve(exposureState: .failed),
            .retry
        )
    }

    @MainActor
    func testCompanionTargetAcknowledgesWhenCompanionContainerBecomesVisible() async throws {
        let companionMessage = "这周第 4 次点沙县，熟悉的味道又出现了。"
        let legacyFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("hybrid"),
            "emotion_line": AnyCodable(companionMessage)
        ]))
        let companionPreview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "semantic_key": AnyCodable("merchant_weekly_repeat"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable(companionMessage)
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "semantic_key": AnyCodable("merchant_weekly_repeat"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable(companionMessage),
            "exposure_event_id": AnyCodable("exposure-voice")
        ]))
        let repository = RecordRepositoryStub(
            details: [expressionRecordDetail(
                feedback: legacyFeedback,
                companionMessage: companionMessage
            )],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-voice",
                candidateId: "candidate-voice",
                feedback: companionPreview
            ))],
            acknowledgedFeedback: acknowledgedFeedback
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        XCTAssertEqual(state.selectedRecordDetail?.companionMessage, companionMessage)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, companionPreview)
        XCTAssertNil(
            NativeRecordExpressionFeedbackPolicy.feedbackToRender(
                companionMessage: companionMessage,
                feedback: state.selectedRecordDetail?.aiFeedback
            )
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")
        XCTAssertEqual(repository.acknowledgementCount, 0)
        XCTAssertFalse(companionPreview.isReviewable)
        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-1",
            feedbackIdentity: companionPreview.renderIdentity
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(state.selectedRecordDetail?.companionMessage, companionMessage)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)
        XCTAssertEqual(repository.acknowledgementCount, 1)
        XCTAssertTrue(state.selectedRecordDetail?.aiFeedback?.isReviewable == true)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testCompanionTargetRejectsAcknowledgementWithDifferentRenderedFingerprint() async throws {
        let message = "这周第 4 次点沙县，熟悉的味道又出现了。"
        let preview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:voice-text"),
            "emotion_line": AnyCodable(message)
        ]))
        let mismatchedAcknowledgement = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-voice"),
            "claim_fingerprint": AnyCodable("fnv1a64:merchant-repeat"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:other-text"),
            "emotion_line": AnyCodable(message),
            "exposure_event_id": AnyCodable("exposure-wrong")
        ]))
        let repository = RecordRepositoryStub(
            details: [expressionRecordDetail(companionMessage: message)],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-voice",
                candidateId: "candidate-voice",
                feedback: preview
            ))],
            acknowledgedFeedback: mismatchedAcknowledgement
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-1",
            feedbackIdentity: preview.renderIdentity
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(repository.acknowledgementCount, 1)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, preview)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .failed)
    }

    @MainActor
    func testCompanionRefreshDropsStalePendingAndLoadsPlanForNewVisibleText() async throws {
        let oldMessage = "本周第 4 次记录沙县。"
        let newMessage = "本周第 5 次记录沙县。"
        let oldPreview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-old"),
            "claim_fingerprint": AnyCodable("fnv1a64:old-claim"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:old-text"),
            "emotion_line": AnyCodable(oldMessage)
        ]))
        let newPreview = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-new"),
            "claim_fingerprint": AnyCodable("fnv1a64:new-claim"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:new-text"),
            "emotion_line": AnyCodable(newMessage)
        ]))
        let acknowledged = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-new"),
            "claim_fingerprint": AnyCodable("fnv1a64:new-claim"),
            "presentation_target": AnyCodable("companion_message"),
            "rendered_text_fingerprint": AnyCodable("fnv1a64:new-text"),
            "emotion_line": AnyCodable(newMessage),
            "exposure_event_id": AnyCodable("exposure-new")
        ]))
        let repository = RecordRepositoryStub(
            details: [
                expressionRecordDetail(companionMessage: oldMessage),
                expressionRecordDetail(companionMessage: newMessage)
            ],
            expressionPlanLookups: [
                .available(NativeRecordExpressionPlan(
                    planToken: "plan-old",
                    candidateId: "candidate-old",
                    feedback: oldPreview
                )),
                .available(NativeRecordExpressionPlan(
                    planToken: "plan-new",
                    candidateId: "candidate-new",
                    feedback: newPreview
                ))
            ],
            acknowledgedFeedback: acknowledged
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, oldPreview)

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        XCTAssertEqual(repository.expressionPlanLookupCount, 2)
        XCTAssertEqual(state.selectedRecordDetail?.companionMessage, newMessage)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, newPreview)

        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-1",
            feedbackIdentity: oldPreview.renderIdentity
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")
        XCTAssertEqual(repository.acknowledgementCount, 0)

        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-1",
            feedbackIdentity: newPreview.renderIdentity
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")
        XCTAssertEqual(repository.acknowledgementCount, 1)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledged)
    }

    @MainActor
    func testExpressionPlanAcknowledgementFailureKeepsPreviewAndCanRetry() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("记录于今天 09:43。")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("记录于今天 09:43。"),
            "exposure_event_id": AnyCodable("exposure-1")
        ]))
        let repository = RecordRepositoryStub(
            details: [expressionRecordDetail()],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-1",
                candidateId: "candidate-1",
                feedback: previewFeedback
            ))],
            acknowledgedFeedback: acknowledgedFeedback,
            acknowledgementFailuresRemaining: 4
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession },
            expressionPlanAcknowledgementSleep: { _ in }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        state.setRecordExpressionPlanCardVisible(true, reference: "expense/record-1")
        XCTAssertTrue(state.isRecordExpressionPlanCardVisible(
            reference: "expense/record-1",
            feedbackIdentity: previewFeedback.renderIdentity
        ))
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(repository.acknowledgementCount, 4)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, previewFeedback)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .failed)
        XCTAssertTrue(state.selectedRecordDetail?.aiFeedback?.requiresExposureAcknowledgement == true)

        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(repository.acknowledgementCount, 5)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
        XCTAssertTrue(state.selectedRecordDetail?.aiFeedback?.isReviewable == true)
    }

    @MainActor
    func testExpressionPlanAcknowledgementContinuesAfterCardLeavesViewport() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("记录于今天 09:43。")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("记录于今天 09:43。"),
            "exposure_event_id": AnyCodable("exposure-1")
        ]))
        let repository = RecordRepositoryStub(
            details: [expressionRecordDetail()],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-1",
                candidateId: "candidate-1",
                feedback: previewFeedback
            ))],
            acknowledgedFeedback: acknowledgedFeedback,
            acknowledgementFailuresRemaining: 1
        )
        var stateReference: AppState?
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession },
            expressionPlanAcknowledgementSleep: { _ in
                await MainActor.run {
                    stateReference?.setRecordExpressionPlanCardVisible(
                        false,
                        reference: "expense/record-1"
                    )
                }
            }
        )
        stateReference = state

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        state.setRecordExpressionPlanCardVisible(true, reference: "expense/record-1")
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(repository.acknowledgementCount, 2)
        XCTAssertFalse(state.isRecordExpressionPlanCardVisible(reference: "expense/record-1"))
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testAcknowledgedPlannerFeedbackSurvivesRemoteRefreshUntilRecordChanges() async throws {
        let legacyFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("legacy_voice"),
            "emotion_line": AnyCodable("远端旧反馈")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-stable"),
            "emotion_line": AnyCodable("当前可点评候选"),
            "exposure_event_id": AnyCodable("exposure-stable")
        ]))
        let repository = RecordRepositoryStub(details: [
            expressionRecordDetail(feedback: acknowledgedFeedback),
            expressionRecordDetail(feedback: legacyFeedback)
        ])
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        await state.loadRecordDetail(reference: "expense/record-1", force: true)

        XCTAssertEqual(repository.expressionPlanLookupCount, 0)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)

        state.invalidateRecordExpressionPlanState(afterChanging: ["expense/record-1"])

        XCTAssertNil(state.selectedRecordDetail)
        XCTAssertNil(state.recordDetail(matching: "expense/record-1"))
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testExpressionPlanAcknowledgementRequiresVisibleCandidateIdentity() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-current"),
            "emotion_line": AnyCodable("当前候选")
        ]))
        let repository = RecordRepositoryStub(
            details: [expressionRecordDetail()],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-current",
                candidateId: "candidate-current",
                feedback: previewFeedback
            ))]
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "expense/record-1", force: true)
        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-1",
            feedbackIdentity: "expression_planner:candidate-old:preview:旧候选"
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-1")

        XCTAssertEqual(repository.acknowledgementCount, 0)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, previewFeedback)
    }

    @MainActor
    func testStaleAcknowledgementCannotOverwriteAnotherRecord() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-a"),
            "emotion_line": AnyCodable("A 的待确认候选")
        ]))
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-a"),
            "emotion_line": AnyCodable("A 的待确认候选"),
            "exposure_event_id": AnyCodable("exposure-a")
        ]))
        var stateReference: AppState?
        let repository = RecordRepositoryStub(
            details: [
                expressionRecordDetail(id: "record-a"),
                expressionRecordDetail(id: "record-b")
            ],
            expressionPlanLookups: [
                .available(NativeRecordExpressionPlan(
                    planToken: "plan-a",
                    candidateId: "candidate-a",
                    feedback: previewFeedback
                )),
                .unavailable(reason: "no_selected_candidate")
            ],
            acknowledgedFeedback: acknowledgedFeedback,
            onAcknowledgementStarted: {
                await stateReference?.loadRecordDetail(
                    reference: "expense/record-b",
                    force: true
                )
            }
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )
        stateReference = state

        await state.loadRecordDetail(reference: "expense/record-a", force: true)
        state.setRecordExpressionPlanCardVisible(
            true,
            reference: "expense/record-a",
            feedbackIdentity: previewFeedback.renderIdentity
        )
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-a")

        XCTAssertEqual(repository.acknowledgementCount, 1)
        XCTAssertEqual(state.selectedRecordDetail?.id, "expense/record-b")
        XCTAssertNil(state.selectedRecordDetail?.aiFeedback)
        XCTAssertNotEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testSwitchingRecordsInvalidatesOldPendingExpressionPlan() async throws {
        let previewFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-a"),
            "emotion_line": AnyCodable("A 的待确认候选")
        ]))
        let repository = RecordRepositoryStub(
            details: [
                expressionRecordDetail(id: "record-a"),
                expressionRecordDetail(id: "record-b")
            ],
            expressionPlanLookups: [
                .available(NativeRecordExpressionPlan(
                    planToken: "plan-a",
                    candidateId: "candidate-a",
                    feedback: previewFeedback
                )),
                .unavailable(reason: "no_selected_candidate")
            ]
        )
        let state = AppState(
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession },
            expressionPlanAcknowledgementSleep: { _ in }
        )

        await state.loadRecordDetail(reference: "expense/record-a", force: true)
        await state.loadRecordDetail(reference: "expense/record-b", force: true)
        state.setRecordExpressionPlanCardVisible(true, reference: "expense/record-a")
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "expense/record-a")

        XCTAssertEqual(repository.acknowledgementCount, 0)
        XCTAssertEqual(state.selectedRecordDetail?.id, "expense/record-b")
        XCTAssertNil(state.selectedRecordDetail?.aiFeedback)
    }

    @MainActor
    func testEditingUniversalRecordDoesNotRestorePreEditPlannerFeedback() async throws {
        let acknowledgedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-before-edit"),
            "emotion_line": AnyCodable("编辑前的可点评候选"),
            "exposure_event_id": AnyCodable("exposure-before-edit")
        ]))
        let refreshedFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-after-edit"),
            "emotion_line": AnyCodable("编辑后重新计算的候选")
        ]))
        let readingPayload = [
            "reading_minutes": AnyCodable(25),
            "book_name": AnyCodable("测试书名")
        ]
        let repository = RecordRepositoryStub(
            details: [
                expressionRecordDetail(
                    referencePrefix: "data",
                    kind: "data",
                    category: "reading",
                    domainKey: "reading",
                    payload: readingPayload,
                    feedback: acknowledgedFeedback
                ),
                expressionRecordDetail(
                    referencePrefix: "data",
                    kind: "data",
                    category: "reading",
                    domainKey: "reading",
                    payload: readingPayload
                )
            ],
            expressionPlanLookups: [.available(NativeRecordExpressionPlan(
                planToken: "plan-after-edit",
                candidateId: "candidate-after-edit",
                feedback: refreshedFeedback
            ))],
            createReference: "data/record-1"
        )
        let state = AppState(
            dashboardRepository: DashboardRepositoryStub(snapshot: DashboardSnapshot()),
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "data/record-1", force: true)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)

        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "reading")
        draft.existingRawId = "record-1"
        let saved = await state.createManualRecord(draft, domain: nil)

        XCTAssertTrue(saved)
        XCTAssertEqual(repository.createCount, 1)
        XCTAssertEqual(repository.expressionPlanLookupCount, 1)
        XCTAssertEqual(state.selectedRecordDetail?.id, "data/record-1")
        XCTAssertEqual(state.recordDetail(matching: "data-record-1")?.aiFeedback, refreshedFeedback)
        XCTAssertNotEqual(state.selectedRecordDetail?.aiFeedback, acknowledgedFeedback)
        XCTAssertTrue(state.selectedRecordDetail?.aiFeedback?.requiresExposureAcknowledgement == true)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testEditingUniversalRecordDiscardsPreEditPendingExpressionPlan() async throws {
        let pendingFeedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-before-edit"),
            "emotion_line": AnyCodable("编辑前尚未确认的候选")
        ]))
        let readingDetail = expressionRecordDetail(
            referencePrefix: "data",
            kind: "data",
            category: "reading",
            domainKey: "reading",
            payload: ["reading_minutes": AnyCodable(25)]
        )
        let repository = RecordRepositoryStub(
            details: [readingDetail, readingDetail],
            expressionPlanLookups: [
                .available(NativeRecordExpressionPlan(
                    planToken: "plan-before-edit",
                    candidateId: "candidate-before-edit",
                    feedback: pendingFeedback
                )),
                .unavailable(reason: "no_selected_candidate")
            ],
            createReference: "data/record-1"
        )
        let state = AppState(
            dashboardRepository: DashboardRepositoryStub(snapshot: DashboardSnapshot()),
            recordRepository: repository,
            sessionProvider: { _ in Self.expressionTestSession }
        )

        await state.loadRecordDetail(reference: "data/record-1", force: true)
        XCTAssertEqual(state.selectedRecordDetail?.aiFeedback, pendingFeedback)

        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "reading")
        draft.existingRawId = "record-1"
        let saved = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(saved)

        state.setRecordExpressionPlanCardVisible(true, reference: "data/record-1")
        await state.acknowledgeRecordExpressionPlanIfVisible(reference: "data/record-1")

        XCTAssertEqual(repository.expressionPlanLookupCount, 2)
        XCTAssertEqual(repository.acknowledgementCount, 0)
        XCTAssertNil(state.selectedRecordDetail?.aiFeedback)
        XCTAssertEqual(state.recordExpressionPlanExposureState, .idle)
    }

    @MainActor
    func testExpressionPlanRetryStopsWhenDetailIsNoLongerActive() async {
        var isActive = true
        var fetchCount = 0

        let resolved = await NativeRecordExpressionPlanRetryPolicy.resolve(
            fetch: {
                fetchCount += 1
                return .pending
            },
            shouldContinue: { isActive },
            sleep: { _ in isActive = false }
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(fetchCount, 1)
    }

    @MainActor
    func testExpressionPlanAcknowledgementRetriesTransientFailuresWithinBound() async throws {
        let feedback = try XCTUnwrap(NativeAIFeedback(payload: [
            "source": AnyCodable("expression_planner"),
            "candidate_id": AnyCodable("candidate-1"),
            "emotion_line": AnyCodable("距离上一次同名记录已经过去 2 天。"),
            "exposure_event_id": AnyCodable("exposure-1")
        ]))
        var attemptCount = 0
        var observedDelays: [UInt64] = []

        let resolved = await NativeRecordExpressionPlanAcknowledgementRetryPolicy.resolve(
            acknowledge: {
                attemptCount += 1
                if attemptCount < 3 {
                    throw SupabaseRemoteError.requestFailed("temporary failure")
                }
                return feedback
            },
            shouldContinue: { true },
            sleep: { observedDelays.append($0) }
        )

        XCTAssertEqual(resolved, feedback)
        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(
            observedDelays,
            Array(NativeRecordExpressionPlanAcknowledgementRetryPolicy.delaysNanoseconds.prefix(2))
        )
    }

    @MainActor
    func testExpressionPlanAcknowledgementStopsRetryingWhenDeliveryContextIsNoLongerActive() async {
        var isActive = true
        var attemptCount = 0
        var observedDelays: [UInt64] = []

        let resolved = await NativeRecordExpressionPlanAcknowledgementRetryPolicy.resolve(
            acknowledge: {
                attemptCount += 1
                throw SupabaseRemoteError.requestFailed("temporary failure")
            },
            shouldContinue: { isActive },
            sleep: { delay in
                observedDelays.append(delay)
                isActive = false
            }
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(observedDelays, [
            NativeRecordExpressionPlanAcknowledgementRetryPolicy.delaysNanoseconds[0]
        ])
    }

    @MainActor
    func testExpressionPlanAcknowledgementRetryHasAHardAttemptLimit() async {
        var attemptCount = 0
        var observedDelays: [UInt64] = []

        let resolved = await NativeRecordExpressionPlanAcknowledgementRetryPolicy.resolve(
            acknowledge: {
                attemptCount += 1
                throw SupabaseRemoteError.requestFailed("temporary failure")
            },
            shouldContinue: { true },
            sleep: { observedDelays.append($0) }
        )

        XCTAssertNil(resolved)
        XCTAssertEqual(
            attemptCount,
            NativeRecordExpressionPlanAcknowledgementRetryPolicy.delaysNanoseconds.count + 1
        )
        XCTAssertEqual(
            observedDelays,
            NativeRecordExpressionPlanAcknowledgementRetryPolicy.delaysNanoseconds
        )
    }

    func testRecordDetailPresentationUsesDomainSpecificFields() throws {
        let detail = NativeRecordDetail(
            id: "data/food-1", rawId: "food-1", kind: "data", title: "午餐", subtitle: "2026-07-16",
            value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: nil, merchantName: nil, platform: nil, category: "food", paymentMethod: nil,
            recordDate: "2026-07-16", note: "清淡午餐", companionMessage: nil, accountId: nil,
            systemImage: "fork.knife", payload: [
                "meal_type": AnyCodable("lunch"),
                "total_calorie_kcal": AnyCodable(520),
                "dishes": AnyCodable([["name": "米饭", "calorie_kcal": 220, "estimated_grams": 150]])
            ], domainKey: "food", source: "staging", domainVersion: "1.0"
        )

        let rows = NativeRecordDetailPresentationAdapter.extractedRows(for: detail)
        XCTAssertEqual(rows.first(where: { $0.label == "餐次" })?.value, "午餐")
        XCTAssertEqual(rows.first(where: { $0.label == "总热量" })?.value, "520 千卡（估算）")
        XCTAssertEqual(rows.first(where: { $0.label == "来源类型" })?.value, "中转站归档")
        let dish = try XCTUnwrap(NativeRecordDetailPresentationAdapter.foodDishes(for: detail).first)
        XCTAssertEqual(dish.name, "米饭")
        XCTAssertEqual(dish.calories, 220)
        XCTAssertEqual(dish.estimatedGrams, 150)
    }

    func testRecordDetailUsesCurrentPWAReadingAndSportFields() {
        let reading = NativeRecordDetail(
            id: "data/reading-1", rawId: "reading-1", kind: "data", title: "原则", subtitle: "2026-07-17",
            value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: nil, merchantName: nil, platform: nil, category: "reading", paymentMethod: nil,
            recordDate: "2026-07-17", note: nil, companionMessage: nil, accountId: nil,
            systemImage: "book", payload: ["reading_minutes": AnyCodable(45), "pages": AnyCodable(18)],
            domainKey: "reading"
        )
        let sport = NativeRecordDetail(
            id: "data/sport-1", rawId: "sport-1", kind: "data", title: "骑行", subtitle: "2026-07-17",
            value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: nil, merchantName: nil, platform: nil, category: "sport", paymentMethod: nil,
            recordDate: "2026-07-17", note: nil, companionMessage: nil, accountId: nil,
            systemImage: "figure.run", payload: ["duration_minutes": AnyCodable(30), "calories": AnyCodable(260)],
            domainKey: "sport"
        )

        let readingRows = NativeRecordDetailPresentationAdapter.extractedRows(for: reading)
        let sportRows = NativeRecordDetailPresentationAdapter.extractedRows(for: sport)
        XCTAssertEqual(readingRows.first(where: { $0.label == "阅读时长" })?.value, "45 分钟")
        XCTAssertEqual(readingRows.first(where: { $0.label == "阅读页数" })?.value, "18 页")
        XCTAssertEqual(sportRows.first(where: { $0.label == "消耗热量" })?.value, "260 千卡")
    }

    func testRecordDetailReusesPWAAccountRecommendation() throws {
        let account = NativeAccount(
            id: "wechat-1", name: "微信零钱", type: .walletBalance, institution: "微信", last4: "", currency: "CNY",
            initialBalance: 100, currentBalance: 80, snapshotBalance: nil, snapshotAt: nil,
            sourceRecordTable: "", sourceRecordId: "", billDay: nil, paymentDueDay: nil,
            autoDebitAccountId: nil, autoConfirmRepayment: false, gracePeriodDays: 0,
            lastReconciledAt: nil, isDefaultExpense: true, isDefaultIncome: false,
            isArchived: false, sortOrder: 0
        )
        let detail = NativeRecordDetail(
            id: "tx-1", rawId: "1", kind: "expense", title: "早餐", subtitle: "2026-07-16",
            value: "¥12.00", detailRows: [], imageURL: nil, imageLoadError: false,
            imagePath: nil, imageHash: nil, amount: 12, merchantName: "早餐", platform: "微信",
            category: "food", paymentMethod: "微信支付", recordDate: "2026-07-16",
            note: nil, companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil
        )

        let binding = try XCTUnwrap(
            NativeRecordDetailPresentationAdapter.accountBinding(for: detail, accounts: [account])
        )

        XCTAssertEqual(binding.status, .recommended)
        XCTAssertEqual(binding.recommendedAccount?.id, account.id)
    }

    func testManualExpensePreservesPWAValidationAndCategoryKeys() {
        var draft = NativeManualRecordDraft()
        draft.amountText = "28.50"
        draft.category = "food"
        XCTAssertNil(draft.validationMessage(domain: nil))
        XCTAssertEqual(draft.amount, 28.5)
        XCTAssertEqual(NativeManualRecordDraft.expenseCategories.map(\.id), ["food", "shopping", "transport", "entertainment", "life", "health", "education", "other"])
    }

    func testFinanceVocabularyKeepsDynamicValuesAndStablePrimaryCategories() {
        let vocabulary = [
            NativeFinanceVocabularyEntry(
                id: "payment-1",
                kind: .payment,
                displayName: "Apple Pay",
                primaryCategory: nil,
                linkedAccountId: nil,
                source: "user_confirmed",
                status: "active",
                usageCount: 3,
                lastUsedAt: "2026-07-21T12:00:00Z"
            )
        ]

        let payments = NativeFinanceOptionCatalog.options(
            kind: .payment,
            currentValue: "云闪付",
            vocabulary: vocabulary
        )

        XCTAssertEqual(payments.first?.id, "云闪付")
        XCTAssertTrue(payments.contains { $0.id == "Apple Pay" && $0.isFrequent })
        XCTAssertEqual(NativeFinanceOptionCatalog.categoryCode(for: "交通"), "transport")
        XCTAssertNil(NativeFinanceOptionCatalog.categoryCode(for: "咖啡"))
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

    func testManualWalletSnapshotPreservesPWAPayloadContract() {
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "wallet")
        draft.primaryValueText = "4620"
        draft.dimension = "支付宝花呗"
        draft.walletRecordKind = "liability_snapshot"
        draft.walletAccountType = "credit_line"
        draft.walletDueDate = "2026-07-20"
        draft.walletBillDay = "20"

        let payload = draft.universalPayload(domain: nil)

        XCTAssertEqual(payload.double("snapshot_balance"), 4620)
        XCTAssertEqual(payload.string("account_name"), "支付宝花呗")
        XCTAssertEqual(payload.string("record_kind"), "liability_snapshot")
        XCTAssertEqual(payload.string("account_snapshot_kind"), "liability")
        XCTAssertEqual(payload.string("account_type"), "credit_line")
        XCTAssertEqual(payload.string("due_date"), "2026-07-20")
        XCTAssertEqual(payload.double("bill_day"), 20)
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

    func testStagingReviewDraftAppliesReadingFieldsWithoutDroppingAIMetadata() {
        let record = NativeStagingRecord(
            id: "staging-reading",
            dateKey: "2026-07-22",
            title: "补上阅读时长",
            summary: "补完后会计入阅读趋势",
            status: "pending_review",
            statusLabel: "待确认",
            recordTypeLabel: "阅读截图",
            createdAtLabel: "2026-07-22 11:06",
            occurredAtLabel: "2026-07-22 11:06",
            confidencePercent: 84,
            lastErrorMessage: nil,
            retryCount: 0,
            systemImage: "book",
            imagePath: nil,
            imageURL: nil,
            imageLoadError: false,
            recordType: "reading",
            domainKey: "reading",
            domainName: "阅读",
            extracted: [
                "book_name": AnyCodable("虚无元素"),
                "ai_feedback": AnyCodable(["emotion_line": "这页内容值得留下"])
            ],
            companionMessage: "这页内容值得留下",
            targetRecordId: nil,
            imageHash: "hash"
        )

        var draft = NativeManualRecordDraft(stagingRecord: record, domainKey: "reading")
        XCTAssertEqual(draft.dimension, "虚无元素")
        XCTAssertTrue(draft.primaryValueText.isEmpty)
        draft.primaryValueText = "25"

        let adjusted = record.applyingArchiveDraft(draft, domain: nil)

        XCTAssertEqual(adjusted.extracted.double("reading_minutes"), 25)
        XCTAssertEqual(adjusted.extracted.string("book_name"), "虚无元素")
        XCTAssertNotNil(adjusted.extracted["ai_feedback"])
        XCTAssertEqual(adjusted.companionMessage, "这页内容值得留下")
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
        let definition = NativeDomainDefinition(
            id: "sport", name: "运动记录", description: "", icon: "🏃", isSystem: true,
            schema: [
                "facts": AnyCodable([["key": "duration_minutes", "label": "运动时长", "unit": "分钟"]]),
                "dimensions": AnyCodable([["key": "sport_type", "label": "运动类型"]])
            ],
            display: ["primary_fact": AnyCodable("duration_minutes"), "primary_dimension": AnyCodable("sport_type")],
            recordCount: 1
        )
        let reference = "data/1"
        let record = NativeDayRecord(id: "sport-1", reference: reference, dateKey: "2026-07-12", kind: .sport, domainKey: "sport", title: "骑行", subtitle: "30 分钟", value: "", timeLabel: nil, systemImage: "figure.run")
        var dashboard = DashboardSnapshot()
        dashboard.dayRecordGroups = [NativeDayRecordGroup(dateKey: "2026-07-12", records: [record])]
        dashboard.recordDetails[reference] = NativeRecordDetail(
            id: reference, rawId: "1", kind: "data", title: "骑行", subtitle: "2026-07-12",
            value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
            amount: nil, merchantName: nil, platform: nil, category: "sport", paymentMethod: nil,
            recordDate: "2026-07-12", note: nil, companionMessage: nil, accountId: nil,
            systemImage: "figure.run", payload: ["duration_minutes": AnyCodable(60), "sport_type": AnyCodable("骑行")],
            domainKey: "sport"
        )
        let presentation = NativeDomainPresentationAdapter.presentation(for: definition, dashboard: dashboard)
        XCTAssertEqual(presentation.recentRecords.map(\.reference), [reference])
        XCTAssertEqual(presentation.metrics.first?.label, "本月总运动时长")
        XCTAssertEqual(presentation.metrics.first?.value, "1 小时 0 分钟")
        XCTAssertEqual(presentation.distribution.first?.name, "骑行")
        XCTAssertEqual(presentation.recentRecords.first?.value, "1 小时 0 分钟")
    }

    func testUnifiedInboxItemDistinguishesPendingExpenseAndStaging() {
        let pending = NativePendingExpense(id: "tx-1", title: "待补全消费", amount: 20, dateKey: "2026-07-12", reference: "tx-1")
        let item = NativeInboxItem(id: "pending-tx-1", kind: .pendingExpense, dateKey: pending.dateKey, title: pending.title, subtitle: "¥20.00", status: "pending", statusLabel: "待补全", systemImage: "clock", pendingExpense: pending, stagingRecord: nil)
        XCTAssertEqual(item.kind, .pendingExpense)
        XCTAssertNil(item.stagingRecord)
    }

    func testInboxTodayScopeUsesOccurrenceInsteadOfUploadFallback() {
        let unknownOccurrence = NativeStagingRecord(
            id: "unknown", dateKey: "2026-07-26", title: "待分类", summary: "发生时间未知",
            status: "routing_failed", statusLabel: "待分类", recordTypeLabel: "截图",
            createdAtLabel: "2026-07-26 09:30", occurredAtLabel: nil, confidencePercent: nil,
            lastErrorMessage: nil, retryCount: 0, systemImage: "tray", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "uncertain", domainKey: nil,
            domainName: nil, extracted: [:], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )
        let oldOccurrence = NativeStagingRecord(
            id: "old", dateKey: "2026-07-25", title: "待确认", summary: "昨天发生、今天上传",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "截图",
            createdAtLabel: "2026-07-26 10:00", occurredAtLabel: "2026-07-25 22:30", confidencePercent: 80,
            lastErrorMessage: nil, retryCount: 0, systemImage: "tray", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "uncertain", domainKey: nil,
            domainName: nil, extracted: [:], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )
        let todayOccurrence = NativeStagingRecord(
            id: "today", dateKey: "2026-07-26", title: "待确认", summary: "今天发生",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "截图",
            createdAtLabel: "2026-07-26 11:00", occurredAtLabel: "2026-07-26 08:00", confidencePercent: 80,
            lastErrorMessage: nil, retryCount: 0, systemImage: "tray", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "uncertain", domainKey: nil,
            domainName: nil, extracted: [:], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )

        let allItems = NativeInboxPresentation.items(
            pendingExpenses: [],
            stagingRecords: [unknownOccurrence, oldOccurrence, todayOccurrence]
        )
        let todayItems = NativeInboxPresentation.filtered(
            allItems,
            scope: .today,
            filter: .all,
            today: "2026-07-26"
        )

        XCTAssertEqual(todayItems.map(\.id), ["staging-today"])
        XCTAssertEqual(allItems.count, 3)
    }

    func testInboxMixedQueueSortsByOccurrenceAcrossKinds() {
        let pending = NativePendingExpense(
            id: "bill", title: "待补全账单", amount: 18,
            dateKey: "2026-07-26", reference: "expense/bill",
            occurredAtLabel: "2026-07-26 09:30", createdAtLabel: "2026-07-26 09:31"
        )
        let staging = NativeStagingRecord(
            id: "review", dateKey: "2026-07-26", title: "待确认", summary: "稍早发生",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "截图",
            createdAtLabel: "2026-07-26 10:00", occurredAtLabel: "2026-07-26 09:00", confidencePercent: 80,
            lastErrorMessage: nil, retryCount: 0, systemImage: "tray", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "uncertain", domainKey: nil,
            domainName: nil, extracted: [:], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )

        let items = NativeInboxPresentation.items(
            pendingExpenses: [pending],
            stagingRecords: [staging]
        )

        XCTAssertEqual(items.map(\.id), ["pending-bill", "staging-review"])
    }

    func testInboxNextSelectionKeepsAdjacentPosition() {
        let ids = ["first", "middle", "last"]

        XCTAssertEqual(
            NativeInboxPresentation.nextSelection(afterRemoving: "middle", from: ids),
            "last"
        )
        XCTAssertEqual(
            NativeInboxPresentation.nextSelection(afterRemoving: "last", from: ids),
            "middle"
        )
        XCTAssertNil(
            NativeInboxPresentation.nextSelection(afterRemoving: "only", from: ["only"])
        )
    }

    func testAtomicArchiveBodyUsesStagingIdentityAndDomain() {
        let record = NativeStagingRecord(
            id: "staging-1", dateKey: "2026-07-16", title: "骑行记录", summary: "骑行 30 分钟",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "运动",
            createdAtLabel: "2026-07-16", occurredAtLabel: "2026-07-16", confidencePercent: 92,
            lastErrorMessage: nil, retryCount: 0, systemImage: "figure.run", imagePath: "user/ride.jpg",
            imageURL: nil, imageLoadError: false, recordType: "sport", domainKey: "sport",
            domainName: "运动", extracted: ["duration_minutes": AnyCodable(30)], companionMessage: nil,
            targetRecordId: nil, imageHash: "hash-1"
        )

        let body = NativeDataService.stagingArchiveRPCBody(
            record: record,
            domainKey: "sport",
            payload: record.extracted,
            occurredAt: "2026-07-16T08:00:00+08:00"
        )

        XCTAssertEqual(body.string("p_staging_id"), record.id)
        XCTAssertEqual(body.string("p_domain_key"), "sport")
        XCTAssertEqual(body.string("p_record_date"), "2026-07-16")
        XCTAssertNil(body["user_id"])
    }

    func testStagingPresentationHidesInternalTimeContext() {
        let record = NativeStagingRecord(
            id: "staging-1", dateKey: "2026-07-16", title: "骑行记录", summary: "骑行 30 分钟",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "运动",
            createdAtLabel: "2026-07-16", occurredAtLabel: "2026-07-16", confidencePercent: 92,
            lastErrorMessage: nil, retryCount: 0, systemImage: "figure.run", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "sport", domainKey: "sport",
            domainName: "运动", extracted: [
                "duration_minutes": AnyCodable(30),
                "time_context": AnyCodable(["reference_time": "2026-07-16T03:07:21Z"])
            ], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )

        let fields = NativeStagingDetailPresentation.fields(for: record)

        XCTAssertEqual(fields.map(\.label), ["时长"])
        XCTAssertEqual(fields.first?.value, "30 分钟")
    }

    func testStagingPresentationSupportsPWALegacyDomainFields() {
        let record = NativeStagingRecord(
            id: "staging-2", dateKey: "2026-07-16", title: "阅读记录", summary: "阅读",
            status: "pending_review", statusLabel: "待确认", recordTypeLabel: "阅读",
            createdAtLabel: "2026-07-16", occurredAtLabel: nil, confidencePercent: 90,
            lastErrorMessage: nil, retryCount: 0, systemImage: "book", imagePath: nil,
            imageURL: nil, imageLoadError: false, recordType: "reading", domainKey: "reading",
            domainName: "阅读", extracted: [
                "reading_minutes": AnyCodable(45),
                "pages_read": AnyCodable(20)
            ], companionMessage: nil, targetRecordId: nil, imageHash: nil
        )

        let fields = NativeStagingDetailPresentation.fields(for: record)

        XCTAssertEqual(fields.first(where: { $0.label == "阅读时长" })?.value, "45 分钟")
        XCTAssertEqual(fields.first(where: { $0.label == "阅读页数" })?.value, "20 页")
    }

    func testStagingErrorSummaryHidesProviderStack() {
        let message = "All vision providers failed -> qwen timed out after 20000ms | moonshot token limit"
        XCTAssertEqual(
            NativeStagingDetailPresentation.errorSummary(message),
            "识别内容超过模型处理上限，请重新识别。"
        )
    }

    func testPossibleDuplicateStagingUsesReviewCopy() {
        let copy = NativeStagingDetailPresentation.actionCopy(
            domainKey: "expense",
            status: "pending_review",
            summary: "疑似与已有记录重复",
            errorMessage: "图片和已有记录相似，请确认是否为同一笔",
            extracted: ["review_reason": AnyCodable("possible_duplicate")]
        )

        XCTAssertEqual(copy?.title, "这笔可能已经记过")
        XCTAssertEqual(copy?.summary, "对照图片或文字事实，确认是新记录再收下。")
    }

    func testNativeSettingsDefaultsMatchPWAVisionRoutes() {
        let settings = NativeUserSettings()

        XCTAssertEqual(settings.screenshotVisionPrimary, "auto")
        XCTAssertEqual(settings.photoVisionPrimary, "qwen")
        XCTAssertEqual(settings.qwenScreenshotModel, "qwen3.6-flash")
        XCTAssertEqual(settings.qwenPhotoModel, "qwen3.6-flash")
        XCTAssertFalse(settings.qwenScreenshotThinking)
        XCTAssertFalse(settings.qwenPhotoThinking)
        XCTAssertEqual(Set(NativeSettingsOptions.visionProviders.map(\.id)), Set(["auto", "qwen"]))
        XCTAssertEqual(Set(NativeSettingsOptions.insightProviders.map(\.id)), Set(["auto", "qwen"]))
        XCTAssertEqual(NativeSettingsOptions.normalizedQwenModel("custom-model"), "qwen3.6-flash")
    }

    func testSettingsRepositoryProtocolSupportsStubInjection() async throws {
        let repository: SettingsRepositoryProtocol = SettingsRepositoryStub()

        let settings = try await repository.fetch(userId: "user-1", accessToken: "test-token")

        XCTAssertEqual(settings.companionPersona, "warm")
        XCTAssertEqual(settings.qwenPhotoModel, "qwen3.6-flash")
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
        let record = NativeDayRecord(
            id: "expense-1", reference: "expense/1", dateKey: "2026-07-23", kind: .expense,
            domainKey: "expense", title: "早餐", subtitle: "", value: "¥20", timeLabel: nil,
            systemImage: "creditcard", transactionType: "expense", status: "done"
        )
        let snapshot = DashboardSnapshot(
            todayCount: 2,
            pendingCount: 1,
            dayRecordGroups: [NativeDayRecordGroup(dateKey: "2026-07-23", records: [record])]
        )
        try store.save(snapshot, userId: "user-a")
        let restored = try store.load(userId: "user-a")?.dashboardSnapshot
        XCTAssertEqual(restored?.todayCount, 2)
        XCTAssertEqual(restored?.dayRecordGroups.first?.records.first?.transactionType, "expense")
        XCTAssertEqual(restored?.dayRecordGroups.first?.records.first?.status, "done")
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

    func testFinanceChartScaleKeepsNormalAmountsLinear() {
        let rows = [
            makeInsightDay(date: "2026-07-14", expense: 30, income: 0, sleep: 0, food: 0),
            makeInsightDay(date: "2026-07-15", expense: 40, income: 0, sleep: 0, food: 0),
            makeInsightDay(date: "2026-07-16", expense: 80, income: 0, sleep: 0, food: 0)
        ]

        let scale = NativeFinanceChartScale(rows: rows)

        XCTAssertFalse(scale.isCompressed)
        XCTAssertEqual(scale.plottedAmount(80), 80)
        XCTAssertGreaterThanOrEqual(scale.limit, 80)
    }

    func testFinanceChartScaleCompressesOutliersWithoutChangingRegularAmounts() {
        let rows = [
            makeInsightDay(date: "2026-07-14", expense: 30, income: 0, sleep: 0, food: 0),
            makeInsightDay(date: "2026-07-15", expense: 40, income: 0, sleep: 0, food: 0),
            makeInsightDay(date: "2026-07-16", expense: 50, income: 0, sleep: 0, food: 0),
            makeInsightDay(date: "2026-07-17", expense: 1_000, income: 5_000, sleep: 0, food: 0)
        ]

        let scale = NativeFinanceChartScale(rows: rows)

        XCTAssertTrue(scale.isCompressed)
        XCTAssertEqual(scale.compressedCount, 2)
        XCTAssertEqual(scale.plottedAmount(50), 50)
        XCTAssertEqual(scale.plottedAmount(1_000), scale.limit)
        XCTAssertEqual(scale.plottedAmount(5_000), scale.limit)
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
            dayExpense: 30,
            dayIncome: 100
        )
        XCTAssertEqual(summary.availableCash, 800)
        XCTAssertEqual(summary.liabilityTotal, 320)
        XCTAssertEqual(summary.netWorthEstimate, 480)
        XCTAssertEqual(summary.dayIncome - summary.dayExpense, 70)
    }

    func testHomeInsightDefaultsShowThreeFinanceAndDomainCards() {
        XCTAssertEqual(NativeHomeInsightPreferences.financeDefaults.filter(\.isEnabled).count, 3)
        XCTAssertEqual(NativeHomeInsightPreferences.domainDefaults.filter(\.isEnabled).count, 3)
        XCTAssertEqual(
            NativeHomeInsightPreferences.domainDefaults.filter(\.isEnabled).map(\.key),
            [.sleepRecovery, .foodEnergy, .sleepSpending]
        )
        XCTAssertEqual(NativeHomeInsightPreferences.maximumEnabledCards, 3)
    }

    func testHomeInsightCardsDeclareUsefulDestinations() {
        XCTAssertEqual(NativeHomeFinanceCardKey.cashSafety.destination, .accounts)
        XCTAssertEqual(NativeHomeFinanceCardKey.spendingRhythm.destination, .records)
        XCTAssertEqual(NativeHomeFinanceCardKey.expenseStructure.destination, .expenseDomain)
        XCTAssertEqual(NativeHomeFinanceCardKey.repaymentPlan.destination, .nearestLiability)
        XCTAssertEqual(NativeHomeDomainCardKey.sleepRecovery.destination, .domain("sleep"))
        XCTAssertEqual(NativeHomeDomainCardKey.foodEnergy.destination, .domain("food"))
        XCTAssertEqual(NativeHomeDomainCardKey.sleepSpending.destination, .allDomains)
        XCTAssertEqual(NativeHomeDomainCardKey.dailyBalance.destination, .selectedDay)
    }

    func testHomeInsightPreferencesRestoreMissingCardsAndRemoveDuplicates() {
        let configuration = [
            NativeHomeFinanceCardConfiguration(key: .cashSafety, isEnabled: true, order: 2),
            NativeHomeFinanceCardConfiguration(key: .cashSafety, isEnabled: false, order: 3),
            NativeHomeFinanceCardConfiguration(key: .accountMix, isEnabled: true, order: 1)
        ]

        let normalized = NativeHomeInsightPreferences.normalizedFinance(configuration)

        XCTAssertEqual(normalized.map(\.key), [.accountMix, .cashSafety, .spendingRhythm, .expenseStructure, .repaymentPlan])
        XCTAssertEqual(normalized.filter(\.isEnabled).count, 3)
        XCTAssertEqual(normalized.map(\.order), [0, 1, 2, 3, 4])
    }

    func testHomeInsightPreferencesNeverEnableMoreThanThreeCards() {
        var configuration = NativeHomeInsightPreferences.financeDefaults.map {
            NativeHomeFinanceCardConfiguration(key: $0.key, isEnabled: false, order: $0.order)
        }
        configuration = NativeHomeInsightPreferences.updatingFinance(configuration, key: .cashSafety, isEnabled: true)
        configuration = NativeHomeInsightPreferences.updatingFinance(configuration, key: .spendingRhythm, isEnabled: true)
        configuration = NativeHomeInsightPreferences.updatingFinance(configuration, key: .expenseStructure, isEnabled: true)
        configuration = NativeHomeInsightPreferences.updatingFinance(configuration, key: .repaymentPlan, isEnabled: true)

        XCTAssertEqual(configuration.filter(\.isEnabled).map(\.key), [.cashSafety, .spendingRhythm, .expenseStructure])
    }

    func testHomeInsightAnalyticsFillsMissingDaysWithoutChangingRecordedTotals() {
        let records = [
            NativeDayRecord(
                id: "expense-1", reference: "expense/1", dateKey: "2026-07-23", kind: .expense,
                domainKey: "expense", title: "早餐", subtitle: "", value: "¥12", timeLabel: nil, systemImage: "creditcard"
            ),
            NativeDayRecord(
                id: "expense-2", reference: "expense/2", dateKey: "2026-07-25", kind: .expense,
                domainKey: "expense", title: "晚餐", subtitle: "", value: "¥30", timeLabel: nil, systemImage: "creditcard"
            )
        ]
        let snapshot = DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: "2026-07-23", records: [records[0]]),
            NativeDayRecordGroup(dateKey: "2026-07-25", records: [records[1]])
        ])

        let summaries = NativeHomeInsightAnalytics.recentDailySummaries(
            from: snapshot,
            endingAt: "2026-07-25"
        )

        XCTAssertEqual(summaries.count, 7)
        XCTAssertEqual(summaries.first?.dateKey, "2026-07-19")
        XCTAssertEqual(summaries[4].expense, 12)
        XCTAssertEqual(summaries[6].expense, 30)
        XCTAssertEqual(summaries.filter { $0.expense > 0 }.count, 2)
    }

    func testHomeInsightDailySummariesShowNewestRecordedDayFirst() {
        let olderRecord = NativeDayRecord(
            id: "expense-old", reference: "expense/old", dateKey: "2026-07-01", kind: .expense,
            domainKey: "expense", title: "早餐", subtitle: "", value: "¥12", timeLabel: nil,
            systemImage: "creditcard"
        )
        let newerRecord = NativeDayRecord(
            id: "expense-new", reference: "expense/new", dateKey: "2026-07-25", kind: .expense,
            domainKey: "expense", title: "晚餐", subtitle: "", value: "¥30", timeLabel: nil,
            systemImage: "creditcard"
        )
        let snapshot = DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: "2026-07-01", records: [olderRecord]),
            NativeDayRecordGroup(dateKey: "2026-07-25", records: [newerRecord])
        ])

        XCTAssertEqual(
            NativeHomeInsightAnalytics.dailySummaries(from: snapshot).map(\.dateKey),
            ["2026-07-25", "2026-07-01"]
        )
    }

    func testHomeInsightDailySummaryFallbackShowsNewestDayFirst() {
        let snapshot = DashboardSnapshot(dailySummaries: [
            NativeDailySummary(dateKey: "2026-07-01", expense: 12, income: 0, pendingCount: 0, recordCount: 1),
            NativeDailySummary(dateKey: "2026-07-25", expense: 30, income: 0, pendingCount: 0, recordCount: 1)
        ])

        XCTAssertEqual(
            NativeHomeInsightAnalytics.dailySummaries(from: snapshot).map(\.dateKey),
            ["2026-07-25", "2026-07-01"]
        )
    }

    func testHomeInsightRecentWindowIncludesPreviousMonthAndExcludesPendingExpense() {
        let juneSnapshot = DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: "2026-06-30", records: [
                NativeDayRecord(
                    id: "expense-june", reference: "expense/june", dateKey: "2026-06-30", kind: .expense,
                    domainKey: "expense", title: "晚餐", subtitle: "", value: "¥40", timeLabel: nil,
                    systemImage: "creditcard", transactionType: "expense", status: "done"
                )
            ])
        ])
        let julySnapshot = DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: "2026-07-01", records: [
                NativeDayRecord(
                    id: "expense-pending", reference: "expense/pending", dateKey: "2026-07-01", kind: .expense,
                    domainKey: "expense", title: "待补全", subtitle: "", value: "¥999", timeLabel: nil,
                    systemImage: "clock", transactionType: "expense", status: "pending"
                )
            ]),
            NativeDayRecordGroup(dateKey: "2026-07-02", records: [
                NativeDayRecord(
                    id: "expense-july", reference: "expense/july", dateKey: "2026-07-02", kind: .expense,
                    domainKey: "expense", title: "早餐", subtitle: "", value: "¥20", timeLabel: nil,
                    systemImage: "creditcard", transactionType: "expense", status: "done"
                )
            ])
        ])

        let combined = NativeHomeInsightAnalytics.combining([julySnapshot, juneSnapshot])
        let summaries = NativeHomeInsightAnalytics.recentDailySummaries(
            from: combined,
            endingAt: "2026-07-02"
        )

        XCTAssertEqual(
            NativeHomeInsightAnalytics.monthKeysForRecentWindow(endingAt: "2026-07-02"),
            ["2026-07", "2026-06"]
        )
        XCTAssertEqual(summaries.count, 7)
        XCTAssertEqual(summaries.reduce(0) { $0 + $1.expense }, 60)
        XCTAssertEqual(summaries.first(where: { $0.dateKey == "2026-07-01" })?.pendingCount, 1)
    }

    func testHomeInsightFinancialAggregatesExcludePendingExpenses() {
        let confirmed = NativeDayRecord(
            id: "expense-done", reference: "expense/done", dateKey: "2026-07-23", kind: .expense,
            domainKey: "expense", title: "早餐", subtitle: "", value: "¥20", timeLabel: nil,
            systemImage: "creditcard", transactionType: "expense", status: "done"
        )
        let pending = NativeDayRecord(
            id: "expense-pending", reference: "expense/pending", dateKey: "2026-07-23", kind: .expense,
            domainKey: "expense", title: "待补全", subtitle: "", value: "¥900", timeLabel: nil,
            systemImage: "clock", transactionType: "expense", status: "pending"
        )
        let legacyIncome = NativeDayRecord(
            id: "legacy-income", reference: "expense/legacy-income", dateKey: "2026-07-23", kind: .expense,
            domainKey: "expense", title: "旧收入", subtitle: "", value: "¥500", timeLabel: nil,
            systemImage: "creditcard", transactionType: "income", status: "done"
        )
        let sleep = NativeDayRecord(
            id: "sleep-1", reference: "data/sleep-1", dateKey: "2026-07-23", kind: .sleep,
            domainKey: "sleep", title: "睡眠", subtitle: "", value: "", timeLabel: nil,
            systemImage: "moon"
        )
        let snapshot = DashboardSnapshot(dayRecordGroups: [
            NativeDayRecordGroup(dateKey: "2026-07-23", records: [confirmed, pending, legacyIncome, sleep])
        ])

        XCTAssertEqual(NativeHomeInsightAnalytics.dailySummary(on: "2026-07-23", from: snapshot).expense, 20)
        XCTAssertEqual(NativeHomeInsightAnalytics.dailySummary(on: "2026-07-23", from: snapshot).pendingCount, 1)
        XCTAssertEqual(NativeHomeInsightAnalytics.confirmedExpenseTotal(from: snapshot), 20)
        XCTAssertEqual(NativeHomeInsightAnalytics.expenseBreakdown(from: snapshot).first?.amount, 20)
        XCTAssertFalse(NativeHomeInsightAnalytics.hasHydratedExpenseDetails(in: snapshot))
        XCTAssertEqual(NativeHomeInsightAnalytics.sleepSpendingObservation(from: snapshot).sleepDayAverage, 20)
        XCTAssertFalse(NativeHomeInsightAnalytics.hasHydratedDetails(for: "sleep", in: snapshot))
        XCTAssertEqual(NativeHomeDomainCardKey.dailyBalance.title, "当天生活")
    }

    func testHomeInsightDomainMetricsRequireARealMetricField() {
        let sleep = NativeDayRecord(
            id: "sleep-1", reference: "data/sleep-1", dateKey: "2026-07-23", kind: .sleep,
            domainKey: "sleep", title: "睡眠", subtitle: "", value: "", timeLabel: nil,
            systemImage: "moon"
        )

        func detail(payload: [String: AnyCodable]) -> NativeRecordDetail {
            NativeRecordDetail(
                id: "data/sleep-1", rawId: "sleep-1", kind: "data", title: "睡眠", subtitle: "2026-07-23",
                value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
                amount: nil, merchantName: nil, platform: nil, category: "sleep", paymentMethod: nil,
                recordDate: "2026-07-23", note: nil, companionMessage: nil, accountId: nil,
                systemImage: "moon", payload: payload, domainKey: "sleep"
            )
        }

        let groups = [NativeDayRecordGroup(dateKey: "2026-07-23", records: [sleep])]
        let metadataOnly = DashboardSnapshot(
            dayRecordGroups: groups,
            recordDetails: ["data/sleep-1": detail(payload: ["ai_feedback": AnyCodable(["choice": "good"])])]
        )
        let hydrated = DashboardSnapshot(
            dayRecordGroups: groups,
            recordDetails: ["data/sleep-1": detail(payload: ["sleep_minutes": AnyCodable(480)])]
        )

        XCTAssertFalse(NativeHomeInsightAnalytics.hasHydratedDetails(for: "sleep", in: metadataOnly))
        XCTAssertTrue(NativeHomeInsightAnalytics.hasHydratedDetails(for: "sleep", in: hydrated))
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

    func testAccountDetailKeepsSectionErrorsSeparateFromEmptyData() {
        let account = NativeAccount(
            id: "wallet", name: "微信零钱", type: .walletBalance, institution: "微信", last4: "",
            currency: "CNY", initialBalance: 0, currentBalance: 0, snapshotBalance: nil,
            snapshotAt: nil, sourceRecordTable: "", sourceRecordId: "", billDay: nil,
            paymentDueDay: nil, autoDebitAccountId: nil, autoConfirmRepayment: false,
            gracePeriodDays: 0, lastReconciledAt: nil, isDefaultExpense: false,
            isDefaultIncome: false, isArchived: false, sortOrder: 0
        )
        let detail = NativeAccountDetail(
            account: account,
            entries: [],
            repaymentCycles: [],
            payments: [],
            loadErrors: [.entries: "网络不可用"]
        )

        XCTAssertEqual(detail.loadError(for: .entries), "网络不可用")
        XCTAssertNil(detail.loadError(for: .payments))
    }

    func testImageCleanupResultDistinguishesCompleteAndPending() {
        let complete = NativeImageCleanupResult(
            status: "ok", deleted: 3, queued: 3, failed: 0, deadLetter: 0,
            remaining: 0, skippedExternal: 1, total: 4
        )
        let pending = NativeImageCleanupResult(
            status: "pending", deleted: 2, queued: 3, failed: 1, deadLetter: 0,
            remaining: 1, skippedExternal: 0, total: 3
        )

        XCTAssertTrue(complete.isComplete)
        XCTAssertFalse(pending.isComplete)
        XCTAssertEqual(complete.displayMessage, "已删除 3 张云端原图，跳过 1 个外部链接")
        XCTAssertEqual(pending.displayMessage, "已删除 2 张云端原图，剩余 1 张将在后台重试")
        XCTAssertEqual(
            NativeImageCleanupResult(
                status: "ok", deleted: 0, queued: 0, failed: 0, deadLetter: 0,
                remaining: 0, skippedExternal: 0, total: 0
            ).displayMessage,
            "没有需要清理的云端原图"
        )

        let accountCleanup = NativeAccountDeletionCleanupResult(
            total: 4, queued: 4, processed: 3, failed: 1,
            deadLetter: 0, skippedExternal: 0, remaining: 1
        )
        let deletion = NativeAccountDeletionResult(
            status: "deletion_pending", message: nil, cleanup: accountCleanup
        )
        XCTAssertTrue(deletion.isPending)
        XCTAssertEqual(
            deletion.displayMessage,
            "账户删除已提交；已删除 3 张云端原图，剩余 1 张将在后台清理，完成后自动删除账户"
        )
    }

    @MainActor
    func testRegistrationRequiresBothConsentSteps() async {
        let state = AppState()
        await state.signUp(
            email: "new-user@example.com",
            password: "123456",
            acceptedTerms: false,
            acceptedSensitiveData: false
        )
        XCTAssertEqual(state.authMessage, "请先阅读并同意服务协议与隐私政策")
        XCTAssertTrue(state.authMessageIsError)
        XCTAssertFalse(state.isSigningIn)

        await state.signUp(
            email: "new-user@example.com",
            password: "123456",
            acceptedTerms: true,
            acceptedSensitiveData: false
        )
        XCTAssertEqual(state.authMessage, "请确认同意处理主动提交的敏感数据及跨境存储说明")
        XCTAssertFalse(state.isSigningIn)
    }

    func testRegistrationConsentUsesCurrentLegalVersions() {
        let consent = NativeRegistrationConsent.current(at: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(consent.termsVersion, "2026-07-19")
        XCTAssertEqual(consent.privacyVersion, "2026-07-22")
        XCTAssertEqual(consent.legalAcceptedAt, consent.sensitiveDataAcceptedAt)
    }

    private static let expressionTestSession = SupabaseAuthSession(
        accessToken: "test-token",
        refreshToken: nil,
        expiresIn: nil,
        expiresAt: nil,
        tokenType: "bearer",
        user: SupabaseUser(id: "user-1", email: "test@example.com")
    )

    private func expressionRecordDetail(
        id: String = "record-1",
        referencePrefix: String = "expense",
        kind: String = "expense",
        category: String? = "other",
        domainKey: String? = nil,
        payload: [String: AnyCodable]? = nil,
        feedback: NativeAIFeedback? = nil,
        companionMessage: String? = nil
    ) -> NativeRecordDetail {
        NativeRecordDetail(
            id: "\(referencePrefix)/\(id)",
            rawId: id,
            kind: kind,
            title: "测试记录",
            subtitle: "2026-07-25",
            value: "¥6.80",
            detailRows: [],
            imageURL: nil,
            imageLoadError: false,
            imagePath: nil,
            imageHash: nil,
            amount: 6.8,
            merchantName: "测试商户",
            platform: "支付宝",
            category: category,
            paymentMethod: "花呗",
            recordDate: "2026-07-25",
            note: nil,
            companionMessage: companionMessage,
            accountId: nil,
            systemImage: "creditcard",
            payload: payload,
            domainKey: domainKey,
            aiFeedback: feedback
        )
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


private final class RecordRepositoryStub: RecordRepositoryProtocol {
    private var details: [NativeRecordDetail]
    private var expressionPlanLookups: [NativeRecordExpressionPlanLookup]
    private let acknowledgedFeedback: NativeAIFeedback?
    private let createReference: String
    private let onAcknowledgementStarted: (@MainActor () async -> Void)?
    private var acknowledgementFailuresRemaining: Int
    private(set) var expressionPlanLookupCount = 0
    private(set) var acknowledgementCount = 0
    private(set) var createCount = 0

    init(
        details: [NativeRecordDetail] = [],
        expressionPlanLookups: [NativeRecordExpressionPlanLookup] = [.unavailable(reason: "no_selected_candidate")],
        acknowledgedFeedback: NativeAIFeedback? = nil,
        createReference: String = "expense/record-1",
        acknowledgementFailuresRemaining: Int = 0,
        onAcknowledgementStarted: (@MainActor () async -> Void)? = nil
    ) {
        self.details = details
        self.expressionPlanLookups = expressionPlanLookups
        self.acknowledgedFeedback = acknowledgedFeedback
        self.createReference = createReference
        self.acknowledgementFailuresRemaining = acknowledgementFailuresRemaining
        self.onAcknowledgementStarted = onAcknowledgementStarted
    }

    func fetchMonth(monthKey: String, accessToken: String) async throws -> NativeRecordMonthSnapshot {
        NativeRecordMonthSnapshot(groups: [], details: [:])
    }

    func fetchDetail(reference: String, accessToken: String) async throws -> NativeRecordDetail {
        guard !details.isEmpty else {
            throw SupabaseRemoteError.requestFailed("unused")
        }
        return details.removeFirst()
    }

    func hydrateDetailImage(_ detail: NativeRecordDetail, accessToken: String) async throws -> NativeRecordDetail {
        detail
    }

    func getRecordExpressionPlan(reference: String, accessToken: String) async throws -> NativeRecordExpressionPlanLookup {
        expressionPlanLookupCount += 1
        return expressionPlanLookups.isEmpty
            ? .unavailable(reason: "no_selected_candidate")
            : expressionPlanLookups.removeFirst()
    }

    func acknowledgeRecordExpressionPlan(
        recordId: String,
        planToken: String,
        candidateId: String,
        accessToken: String
    ) async throws -> NativeAIFeedback {
        acknowledgementCount += 1
        if let onAcknowledgementStarted {
            await onAcknowledgementStarted()
        }
        if acknowledgementFailuresRemaining > 0 {
            acknowledgementFailuresRemaining -= 1
            throw SupabaseRemoteError.requestFailed("temporary failure")
        }
        guard let acknowledgedFeedback else {
            throw SupabaseRemoteError.requestFailed("unused")
        }
        return acknowledgedFeedback
    }

    func saveDetail(_ draft: NativeRecordEditDraft, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func create(_ draft: NativeManualRecordDraft, domain: NativeDomainDefinition?, userId: String, accessToken: String) async throws -> String {
        createCount += 1
        return createReference
    }

    func delete(reference: String, accessToken: String) async throws {}

    func submitFeedback(
        recordId: String,
        choice: NativeAIFeedbackReviewChoice,
        freeText: String,
        exposureEventId: String?,
        accessToken: String
    ) async throws {}
}

private struct InboxRepositoryStub: InboxRepositoryProtocol {
    func discard(id: String, accessToken: String) async throws {}

    func retry(id: String, accessToken: String) async throws -> ShortcutUploadResult {
        ShortcutUploadResult(displayText: "已重新识别")
    }

    func archive(_ record: NativeStagingRecord, domainKey: String, accessToken: String) async throws -> String {
        "expense:record-1"
    }

    func confirmStagingRepayment(
        id: String,
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        accessToken: String
    ) async throws {}

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

private struct SettingsRepositoryStub: SettingsRepositoryProtocol {
    func fetch(userId: String, accessToken: String) async throws -> NativeUserSettings {
        var settings = NativeUserSettings()
        settings.companionPersona = "warm"
        return settings
    }

    func update(userId: String, values: [String: AnyCodable], accessToken: String) async throws {}

    func export(_ request: NativeDataExportRequest, accessToken: String) async throws -> NativeExportedFile {
        NativeExportedFile(url: URL(fileURLWithPath: "/tmp/jiezi.csv"))
    }

    func cleanupSourceImages(accessToken: String) async throws -> NativeImageCleanupResult {
        NativeImageCleanupResult(
            status: "ok",
            deleted: 0,
            queued: 0,
            failed: 0,
            deadLetter: 0,
            remaining: 0,
            skippedExternal: 0,
            total: 0
        )
    }

    func deleteAccount(accessToken: String) async throws -> NativeAccountDeletionResult {
        NativeAccountDeletionResult(status: "deleted", message: nil, cleanup: nil)
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
