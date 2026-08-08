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
