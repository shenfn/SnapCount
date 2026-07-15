import XCTest
@testable import SnapCount

final class SnapCountTests: XCTestCase {
    func testAppTabsHaveTitles() {
        XCTAssertEqual(AppTab.allCases.count, 5)
        XCTAssertTrue(AppTab.allCases.allSatisfy { !$0.title.isEmpty })
    }

    func testDashboardRepositoryProtocolSupportsStubInjection() async throws {
        let expected = DashboardSnapshot(todayCount: 3)
        let repository = DashboardRepositoryStub(snapshot: expected)

        let snapshot = try await repository.fetchDashboard(accessToken: "test-token")

        XCTAssertEqual(snapshot.todayCount, 3)
    }

    func testRecordRepositoryProtocolSupportsStubInjection() async throws {
        let repository: RecordRepositoryProtocol = RecordRepositoryStub()
        try await repository.delete(reference: "expense:record-1", accessToken: "test-token")
    }

    func testInboxRepositoryProtocolSupportsStubInjection() async throws {
        let repository = InboxRepositoryStub()
        let result = try await repository.retry(id: "staging-1", accessToken: "test-token")
        XCTAssertFalse(result.displayText.isEmpty)
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
        let presentation = NativeDomainPresentationAdapter.presentation(for: definition, groups: [NativeDayRecordGroup(dateKey: "2026-07-12", records: [record])])
        XCTAssertEqual(presentation.recentRecords.map(\.reference), ["data-1"])
        XCTAssertEqual(presentation.metrics.first?.value, "1 条")
    }

    func testUnifiedInboxItemDistinguishesPendingExpenseAndStaging() {
        let pending = NativePendingExpense(id: "tx-1", title: "待补全消费", amount: 20, dateKey: "2026-07-12", reference: "tx-1")
        let item = NativeInboxItem(id: "pending-tx-1", kind: .pendingExpense, dateKey: pending.dateKey, title: pending.title, subtitle: "¥20.00", status: "pending", statusLabel: "待补全", systemImage: "clock", pendingExpense: pending, stagingRecord: nil)
        XCTAssertEqual(item.kind, .pendingExpense)
        XCTAssertNil(item.stagingRecord)
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

    func fetchDashboard(accessToken: String) async throws -> DashboardSnapshot {
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

    func delete(reference: String, accessToken: String) async throws {}
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
