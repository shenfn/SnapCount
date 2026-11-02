import XCTest
import UIKit
@testable import SnapCount

final class LocalFinancialDuplicateRuleTests: XCTestCase {
    private let baseDate = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - 感知指纹

    func testPerceptualHashIsStableForSameImage() throws {
        let data = makeImageData(width: 200, height: 400, color: .systemBlue)
        let first = try XCTUnwrap(LocalPerceptualHash.compute(from: data))
        let second = try XCTUnwrap(LocalPerceptualHash.compute(from: data))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 16)
    }

    func testPerceptualHashDiffersForDifferentImages() throws {
        let solid = try XCTUnwrap(LocalPerceptualHash.compute(
            from: makeImageData(width: 200, height: 400, color: .white)
        ))
        let split = try XCTUnwrap(LocalPerceptualHash.compute(
            from: makeSplitImageData(width: 200, height: 400)
        ))
        XCTAssertNotEqual(solid, split)
        XCTAssertGreaterThan(try XCTUnwrap(LocalPerceptualHash.hammingDistance(solid, split)), 5)
    }

    func testPerceptualHashReturnsNilForUndecodableData() {
        XCTAssertNil(LocalPerceptualHash.compute(from: Data([0x00, 0x01, 0x02])))
    }

    func testHammingDistanceRejectsMismatchedInput() {
        XCTAssertNil(LocalPerceptualHash.hammingDistance(nil, "ffff"))
        XCTAssertNil(LocalPerceptualHash.hammingDistance("ffff", "ff"))
        XCTAssertNil(LocalPerceptualHash.hammingDistance("zzzz", "ffff"))
        XCTAssertEqual(LocalPerceptualHash.hammingDistance("0000000000000000", "0000000000000001"), 1)
        XCTAssertEqual(LocalPerceptualHash.hammingDistance("ffffffffffffffff", "0000000000000000"), 64)
    }

    // MARK: - 判定

    func testIdenticalFactsMatchAsDuplicate() {
        let current = facts()
        let match = LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(hash: current.perceptualHash)]
        )
        XCTAssertEqual(match?.distance, 0)
    }

    func testDistanceAtThresholdMatchesAndBeyondDoesNot() {
        // 阈值 5 位；第 6 位不同就不再视为同一张图。
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(hash: "0000000000000000"),
            candidates: [candidate(hash: "000000000000001f")]
        ))
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(hash: "0000000000000000"),
            candidates: [candidate(hash: "000000000000003f")]
        ))
    }

    func testAmountDifferenceWithinOneCentMatches() {
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(amount: 2500),
            candidates: [candidate(amount: 2501)]
        ))
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(amount: 2500),
            candidates: [candidate(amount: 2502)]
        ))
    }

    func testFallsBackToPlatformAndPaymentWhenMerchantMissing() {
        let current = facts(merchant: nil, platform: "支付宝", payment: "余额宝")
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(merchant: nil, platform: "支付宝", payment: "余额宝")]
        ))
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(merchant: nil, platform: "支付宝", payment: "花呗")]
        ))
    }

    func testDifferentMerchantDoesNotMatchEvenWhenPlatformMatches() {
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(merchant: "星巴克", platform: "支付宝", payment: "余额宝"),
            candidates: [candidate(merchant: "瑞幸咖啡", platform: "支付宝", payment: "余额宝")]
        ))
    }

    func testTimeWindowIsTenMinutes() {
        let current = facts(occurredAt: baseDate)
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(occurredAt: baseDate.addingTimeInterval(9 * 60))]
        ))
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(occurredAt: baseDate.addingTimeInterval(11 * 60))]
        ))
    }

    func testFallsBackToSameDateWhenTimeMissing() {
        let current = facts(occurredAt: nil, date: "2026-11-02")
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(occurredAt: nil, date: "2026-11-02")]
        ))
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(occurredAt: nil, date: "2026-11-01")]
        ))
    }

    func testGenericIncomeNamesMatchEachOther() {
        let current = facts(type: "income", merchant: "截图识别收入")
        XCTAssertNotNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [candidate(type: "income", merchant: "收入记录")]
        ))
    }

    func testRecordTypeMustMatch() {
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(type: "expense"),
            candidates: [candidate(type: "income")]
        ))
    }

    func testClosestCandidateWins() {
        let current = facts(hash: "0000000000000000")
        let match = LocalFinancialDuplicateRule.findLikelyDuplicate(
            current,
            candidates: [
                candidate(id: UUID(), hash: "0000000000000007", referenceTable: "expense"),
                candidate(id: UUID(), hash: "0000000000000001", referenceTable: "expense")
            ]
        )
        XCTAssertEqual(match?.distance, 1)
    }

    func testMissingPerceptualHashNeverMatches() {
        XCTAssertNil(LocalFinancialDuplicateRule.findLikelyDuplicate(
            facts(hash: nil),
            candidates: [candidate(hash: "0000000000000000")]
        ))
    }

    // MARK: - 业务层判重（第二道，3 分钟）

    func testBusinessDuplicateWithinThreeMinutes() {
        XCTAssertNotNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(occurredAt: baseDate),
            candidates: [candidate(occurredAt: baseDate.addingTimeInterval(2 * 60))],
            now: baseDate
        ))
    }

    func testBusinessDuplicateBeyondThreeMinutes() {
        XCTAssertNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(occurredAt: baseDate),
            candidates: [candidate(occurredAt: baseDate.addingTimeInterval(4 * 60))],
            now: baseDate
        ))
    }

    func testBusinessDuplicateRequiresSamePaymentMethod() {
        XCTAssertNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(payment: "余额宝", occurredAt: baseDate),
            candidates: [candidate(payment: "花呗", occurredAt: baseDate)],
            now: baseDate
        ))
    }

    func testBusinessDuplicateSkippedWithoutPaymentMethod() {
        XCTAssertNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(payment: nil, occurredAt: baseDate),
            candidates: [candidate(payment: nil, occurredAt: baseDate)],
            now: baseDate
        ))
    }

    func testBusinessDuplicateOnlyAppliesToExpense() {
        XCTAssertNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(type: "income", occurredAt: baseDate),
            candidates: [candidate(type: "expense", occurredAt: baseDate)],
            now: baseDate
        ))
    }

    func testBusinessDuplicateFallsBackToCreationTime() {
        XCTAssertNotNil(LocalFinancialDuplicateRule.findBusinessDuplicate(
            facts(occurredAt: nil),
            candidates: [candidate(occurredAt: nil)],
            now: baseDate
        ))
    }

    // MARK: - 夹具

    private func facts(
        type: String = "expense",
        amount: Int64 = 2500,
        merchant: String? = "星巴克",
        platform: String? = "支付宝",
        payment: String? = "余额宝",
        occurredAt: Date? = nil,
        date: String? = "2026-11-02",
        hash: String? = "ffffffffffffffff"
    ) -> LocalFinancialDuplicateFacts {
        LocalFinancialDuplicateFacts(
            recordType: type,
            amountMinor: amount,
            merchantOrSource: merchant,
            platform: platform,
            paymentMethod: payment,
            occurredAt: occurredAt,
            occurredDate: date,
            perceptualHash: hash
        )
    }

    private func candidate(
        id: UUID = UUID(),
        type: String = "expense",
        amount: Int64 = 2500,
        merchant: String? = "星巴克",
        platform: String? = "支付宝",
        payment: String? = "余额宝",
        occurredAt: Date? = nil,
        date: String? = "2026-11-02",
        hash: String? = "ffffffffffffffff",
        referenceTable: String = "expense"
    ) -> LocalFinancialDuplicateCandidate {
        LocalFinancialDuplicateCandidate(
            id: id,
            facts: facts(
                type: type,
                amount: amount,
                merchant: merchant,
                platform: platform,
                payment: payment,
                occurredAt: occurredAt,
                date: date,
                hash: hash
            ),
            referenceTable: referenceTable,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
    }

    private func makeImageData(width: CGFloat, height: CGFloat, color: UIColor) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.pngData { context in
            color.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// 上半黑下半白：让 8×8 采样点明显分两组，避免与纯色图撞哈希。
    private func makeSplitImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        return renderer.pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height / 2))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: height / 2, width: width, height: height / 2))
        }
    }
}
