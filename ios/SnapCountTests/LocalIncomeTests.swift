import Foundation
import XCTest
@testable import SnapCount

@MainActor
final class LocalIncomeTests: XCTestCase {
    func testLOCALP1LF032AmountParserRejectsSubMinorPrecision() {
        XCTAssertThrowsError(try LocalIncomeMoney.amountMinor("1.005", currency: "CNY"))
        XCTAssertEqual(try? LocalIncomeMoney.amountMinor("1.01", currency: "CNY"), 101)
    }

    func testLOCALP1LF032CreatesIncomeWithExactMinorUnitsAndBoundEntry() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let profile = try expenseRepository.createProfile(id: UUID(), createdAt: fixedDate)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "工资卡",
            kind: "debit_card",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: fixedDate
        ))
        let incomeRepository = try LocalIncomeRepository(database: database)
        let useCase = LocalIncomeUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: incomeRepository
        )

        let outcome = try await useCase.create(LocalIncomeCommand(
            id: UUID(),
            accountID: account.id,
            amountText: "12.34",
            currency: "CNY",
            incomeCategory: "salary",
            sourceName: "公司",
            incomeDate: "2026-09-27",
            incomeTime: "09:30",
            note: "月薪",
            createdAt: fixedDate
        ))

        XCTAssertEqual(outcome.income.amountMinor, 1_234)
        XCTAssertEqual(outcome.income.accountID, account.id)
        XCTAssertEqual(try incomeRepository.income(id: outcome.income.id)?.incomeCategory, "salary")
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).count, 1)
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).first?.direction, "in")
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).first?.entryKind, "income")
        XCTAssertEqual(
            try expenseRepository.pendingOutboxOperations().map(\.aggregateKind),
            ["account"]
        )
    }

    func testLOCALP1LF032IncomeUpdateAndDeleteReplaceAndVoidEntry() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let expenseRepository = try LocalExpenseRepository(database: database)
        let profile = try expenseRepository.createProfile(id: UUID(), createdAt: fixedDate)
        let account = try expenseRepository.createAccount(LocalAccountDraft(
            id: UUID(),
            profileID: profile.id,
            name: "现金",
            kind: "cash",
            currency: "CNY",
            openingBalanceMinor: 0,
            createdAt: fixedDate
        ))
        let incomeRepository = try LocalIncomeRepository(database: database)
        let useCase = LocalIncomeUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: incomeRepository
        )
        let created = try await useCase.create(LocalIncomeCommand(
            id: UUID(),
            accountID: account.id,
            amountText: "10.00",
            currency: "CNY",
            incomeCategory: "bonus",
            sourceName: "奖励",
            incomeDate: "2026-09-27",
            incomeTime: nil,
            note: nil,
            createdAt: fixedDate
        ))

        let updated = try await useCase.update(LocalIncomeUpdateCommand(
            id: created.income.id,
            expectedVersion: created.income.localVersion,
            accountID: account.id,
            amountText: "20.01",
            currency: "CNY",
            incomeCategory: "salary",
            sourceName: "补发工资",
            incomeDate: "2026-09-28",
            incomeTime: "10:00",
            note: nil,
            updatedAt: fixedDate.addingTimeInterval(60)
        ))
        XCTAssertEqual(updated.income.amountMinor, 2_001)
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).filter { $0.voidedAt == nil }.count, 1)
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).reduce(0) { $0 + ($1.voidedAt == nil ? $1.amountMinor : 0) }, 2_001)

        let deleted = try await useCase.delete(LocalIncomeDeleteCommand(
            id: updated.income.id,
            expectedVersion: updated.income.localVersion,
            deletedAt: fixedDate.addingTimeInterval(120)
        ))
        XCTAssertNotNil(deleted.tombstone.deletedAt)
        XCTAssertEqual(try expenseRepository.accountEntries(accountID: account.id).filter { $0.voidedAt == nil }.count, 0)
        XCTAssertNil(try incomeRepository.income(id: updated.income.id))
    }

    func testLOCALP1LF032FactReaderAndExportExposeIncomeAsIncomeReference() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let useCase = LocalIncomeUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalIncomeRepository(database: database)
        )
        let created = try await useCase.create(LocalIncomeCommand(
            id: UUID(),
            accountID: nil,
            amountText: "8.88",
            currency: "CNY",
            incomeCategory: "reimbursement",
            sourceName: "报销",
            incomeDate: "2026-09-27",
            incomeTime: nil,
            note: nil,
            createdAt: fixedDate
        ))

        let month = try LocalFactReader(database: database).month(
            profileID: profile.id,
            monthKey: "2026-09"
        )
        let incomeFact = try XCTUnwrap(month.facts.first { $0.domainKey == "income" })
        XCTAssertEqual(incomeFact.reference, "income/\(created.income.id.uuidString)")
        let incomeRow = try XCTUnwrap(
            LocalFactReadModel.groups(from: month, including: [.record])
                .flatMap(\.records)
                .first { $0.reference == incomeFact.reference }
        )
        XCTAssertEqual(incomeRow.kind, .income)
        XCTAssertEqual(incomeRow.value, "+¥8.88")
        let detail = try XCTUnwrap(LocalFactReadModel.details(from: month)[incomeFact.reference])
        XCTAssertEqual(detail.kind, "income")
        XCTAssertEqual(detail.amount ?? 0, 8.88, accuracy: 0.001)

        var request = NativeDataExportRequest()
        request.range = .all
        request.format = .json
        request.includeFullPayload = true
        let archiveData = try LocalFactPortability(database: database).exportArchive(
            request: request,
            exportedAt: fixedDate
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(LocalFactArchive.self, from: archiveData)
        XCTAssertEqual(archive.schemaVersion, 2)
        XCTAssertEqual(archive.facts.map(\.reference), [incomeFact.reference])
        XCTAssertTrue(archive.facts[0].payloadJSON.contains("amount_minor"))
    }

    func testLOCALP1LF032SignedOutDashboardAggregatesLocalIncome() async throws {
        let databaseURL = temporaryDatabaseURL()
        defer { removeDatabase(at: databaseURL) }

        let database = try LocalDatabase(databaseURL: databaseURL)
        let profile = try LocalProfileStore(database: database).activeProfile()
        let monthKey = String(NativeLocalDate.dateKey(Date()).prefix(7))
        let incomeDate = "\(monthKey)-01"
        let useCase = LocalIncomeUseCase(
            profileStore: LocalProfileStore(database: database),
            repository: try LocalIncomeRepository(database: database)
        )
        let created = try await useCase.create(LocalIncomeCommand(
            id: UUID(),
            accountID: nil,
            amountText: "5.50",
            currency: "CNY",
            incomeCategory: "other",
            sourceName: "退款",
            incomeDate: incomeDate,
            incomeTime: nil,
            note: nil,
            createdAt: fixedDate
        ))

        let state = AppState(
            localIncomeUseCase: useCase,
            localFactReader: try LocalFactReader(database: database),
            localFactPortability: LocalFactPortability(database: database)
        )
        state.isSignedIn = false
        await state.loadRecordMonth(monthKey, force: true)

        XCTAssertEqual(state.dashboard.monthIncome, 5.50, accuracy: 0.001)
        XCTAssertEqual(state.dashboard.dailySummaries.first(where: { $0.dateKey == incomeDate })?.income ?? 0, 5.50, accuracy: 0.001)
        XCTAssertEqual(state.recordGroups(monthKey: monthKey).flatMap(\.records).filter { $0.kind == .income }.count, 1)
        await state.loadRecordDetail(reference: "income/\(created.income.id.uuidString)", force: true)
        XCTAssertEqual(state.selectedRecordDetail?.kind, "income")
        XCTAssertEqual(profile.id, try LocalFactReader(database: database).activeProfileID())
    }

    private var fixedDate: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("jiezi-local-income-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("jiezi.sqlite")
    }

    private func removeDatabase(at url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: url)
    }
}
