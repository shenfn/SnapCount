import XCTest
@testable import SnapCount

final class NativeTimePresentationTests: XCTestCase {
    func testManualDraftWithoutTimeKeepsOccurrenceUnknown() {
        var draft = NativeManualRecordDraft(kind: .expense)
        draft.includesTime = false

        XCTAssertNil(draft.occurredAt)
    }

    func testUTCDateTimeRendersInShanghaiTimeZone() {
        XCTAssertEqual(
            NativeLocalDate.dateTimeLabel("2026-08-07T22:41:00Z"),
            "2026-08-08 06:41"
        )
    }

    func testFinanceOccurrenceUsesCanonicalInstantBeforeLegacyFields() {
        XCTAssertEqual(
            NativeLocalDate.financeDateKey(
                occurredAt: "2026-08-07T22:41:00Z",
                legacyDate: "2026-08-07"
            ),
            "2026-08-08"
        )
        XCTAssertEqual(
            NativeLocalDate.financeTimeKey(occurredAt: "2026-08-07T22:41:00Z"),
            "06:41"
        )
    }

    func testDateOnlyFinanceRecordDoesNotInventAnInstant() {
        XCTAssertNil(
            NativeLocalDate.financeOccurredAt(
                dateKey: "2026-08-08",
                timeKey: nil
            )
        )
        XCTAssertEqual(
            NativeLocalDate.financeDateKey(
                occurredAt: nil,
                legacyDate: "2026-08-08"
            ),
            "2026-08-08"
        )
        XCTAssertNil(NativeLocalDate.financeTimeKey(occurredAt: nil))
    }

    func testStagingDatePrefersExtractedBusinessDateBeforeUploadDate() {
        XCTAssertEqual(
            NativeDataService.stagingDateKey(
                occurredAt: nil,
                extracted: ["record_date": AnyCodable("2026-08-08")],
                createdAt: "2026-08-09T00:00:00Z"
            ),
            "2026-08-08"
        )
        XCTAssertEqual(
            NativeDataService.stagingDateKey(
                occurredAt: "2026-08-10T00:00:00Z",
                extracted: ["record_date": AnyCodable("2026-08-08")],
                createdAt: "2026-08-09T00:00:00Z"
            ),
            "2026-08-10"
        )
    }

    func testStagingDateUsesUploadDateWithoutInventingDateWhenSourcesAreMissing() {
        XCTAssertEqual(
            NativeDataService.stagingDateKey(
                occurredAt: nil,
                extracted: nil,
                createdAt: "2026-08-08T22:00:00Z"
            ),
            "2026-08-09"
        )
        XCTAssertEqual(
            NativeDataService.stagingDateKey(
                occurredAt: "not-a-timestamp",
                extracted: nil,
                createdAt: "2026-08-08T22:00:00Z"
            ),
            "2026-08-09"
        )
        XCTAssertNil(
            NativeDataService.stagingDateKey(
                occurredAt: nil,
                extracted: nil,
                createdAt: nil
            )
        )
    }

    func testInboxTodayScopeUsesStagingFallbackDate() {
        let staging = NativeStagingRecord(
            id: "staging-1",
            dateKey: "2026-08-09",
            title: "待确认截图",
            summary: "待处理",
            status: "pending_review",
            statusLabel: "待确认",
            recordTypeLabel: "截图识别",
            createdAtLabel: "2026-08-09 06:00",
            occurredAtLabel: nil,
            confidencePercent: nil,
            lastErrorMessage: nil,
            retryCount: 0,
            systemImage: "tray",
            imagePath: nil,
            imageURL: nil,
            imageLoadError: false,
            recordType: "expense",
            domainKey: "expense",
            domainName: "消费",
            extracted: [:],
            companionMessage: nil,
            targetRecordId: nil,
            imageHash: nil
        )
        guard let item = NativeInboxPresentation.items(pendingExpenses: [], stagingRecords: [staging]).first else {
            return XCTFail("staging item should be present")
        }
        XCTAssertEqual(
            NativeInboxPresentation.filtered([item], scope: .today, filter: .all, today: "2026-08-09").count,
            1
        )
    }

    func testEditDraftTreatsEmptyDateAsMissing() {
        let detail = makeExpenseDetail(
            recordDate: "",
            transactionTime: "",
            createdAt: "2026-08-08T22:00:00Z",
            occurredAt: nil
        )

        XCTAssertEqual(NativeRecordEditDraft(detail: detail).recordDate, "2026-08-09")
    }

    func testShanghaiWallTimeBuildsTheExpectedInstant() {
        XCTAssertEqual(
            NativeLocalDate.financeOccurredAt(
                dateKey: "2026-08-08",
                timeKey: "06:41:00"
            ),
            "2026-08-07T22:41:00Z"
        )
    }

    func testRecordDetailPrefersOccurredAtAndKeepsUploadTime() throws {
        let detail = makeExpenseDetail(
            recordDate: "2026-08-08",
            transactionTime: "02:41",
            createdAt: "2026-08-07T22:42:00Z",
            occurredAt: "2026-08-07T22:41:00Z"
        )

        let rows = NativeRecordDetailPresentationAdapter.basicRows(
            for: detail,
            accountName: nil
        )

        XCTAssertEqual(rows.first(where: { $0.label == "发生时间" })?.value, "2026-08-08 06:41")
        XCTAssertEqual(rows.first(where: { $0.label == "上传时间" })?.value, "2026-08-08 06:42")
        XCTAssertLessThan(
            try XCTUnwrap(rows.firstIndex(where: { $0.label == "发生时间" })),
            try XCTUnwrap(rows.firstIndex(where: { $0.label == "上传时间" }))
        )
    }

    func testLegacyFinanceRecordDoesNotInventOccurrenceTime() {
        let detail = makeExpenseDetail(
            recordDate: "2026-08-08",
            transactionTime: "06:41:00",
            createdAt: "2026-08-07T22:42:00Z",
            occurredAt: nil
        )

        let rows = NativeRecordDetailPresentationAdapter.basicRows(
            for: detail,
            accountName: nil
        )

        XCTAssertNil(rows.first(where: { $0.label == "发生时间" }))
        XCTAssertEqual(rows.first(where: { $0.label == "上传时间" })?.value, "2026-08-08 06:42")
    }

    private func makeExpenseDetail(
        recordDate: String,
        transactionTime: String,
        createdAt: String,
        occurredAt: String?
    ) -> NativeRecordDetail {
        NativeRecordDetail(
            id: "expense/record-1",
            rawId: "record-1",
            kind: "expense",
            title: "早餐",
            subtitle: recordDate,
            value: "¥9.18",
            detailRows: [],
            imageURL: nil,
            imageLoadError: false,
            imagePath: nil,
            imageHash: nil,
            amount: 9.18,
            merchantName: "沙县小吃",
            platform: nil,
            category: "food",
            paymentMethod: nil,
            recordDate: recordDate,
            note: nil,
            companionMessage: nil,
            accountId: nil,
            systemImage: "creditcard",
            payload: nil,
            createdAt: createdAt,
            occurredAt: occurredAt,
            transactionTime: transactionTime,
            domainKey: "expense"
        )
    }
}
