import XCTest
@testable import SnapCount

final class GenericImportCSVTests: XCTestCase {
    func testIMP001ParsesChineseHeadersQuotedCommaAndNegativeIncome() {
        let csv = "日期,金额,收支,商户,分类,支付方式,备注\n2026/11/01,\"1,234.50\",支出,\"咖啡,店\",餐饮,微信,\"带\n换行\"\n2026-11-02,-88.00,收入,退款,其他,,"
        let result = GenericImportCSVParser().parse(Data(csv.utf8))
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.records.count, 2)
        XCTAssertEqual(result.records[0].amountMinor, 123450)
        XCTAssertEqual(result.records[0].merchant, "咖啡,店")
        XCTAssertEqual(result.records[0].note, "带\n换行")
        XCTAssertEqual(result.records[1].kind, .income)
        XCTAssertEqual(result.records[1].amountMinor, 8800)
    }

    func testIMP001KeepsUnknownColumnsAndReportsRowFieldErrors() {
        let csv = "date,amount,merchant,external_status\n2026-11-03,12.3,Shop,settled\nwrong,nope,Other,pending"
        let result = GenericImportCSVParser().parse(Data(csv.utf8))
        XCTAssertEqual(result.records.count, 1)
        XCTAssertEqual(result.records[0].rawFields["external_status"], "settled")
        XCTAssertEqual(result.errors, [GenericImportCSVError(row: 3, field: "日期", reason: "日期格式无效")])
    }
}
