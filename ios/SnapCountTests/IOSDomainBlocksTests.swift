import XCTest
@testable import SnapCount

final class IOSDomainBlocksTests: XCTestCase {
    func testIOSV2POLISH003F10MainSleepAndIndependentThirtyDayMedians() throws {
        var records: [NativeDayRecord] = []
        var details: [String: NativeRecordDetail] = [:]
        func add(_ id: String, day: String, minutes: Double, start: String? = nil, wake: String? = nil) {
            let item = record(id, date: day, domain: .sleep)
            var payload = ["sleep_minutes": AnyCodable(minutes)]
            if let start { payload["sleep_start_at"] = AnyCodable(start) }
            if let wake { payload["wake_at"] = AnyCodable(wake) }
            records.append(item)
            details[item.reference] = detail(item, payload)
        }
        for (index, day) in (24...30).enumerated() {
            let date = "2026-09-\(day)"
            add("main-\(day)", day: date, minutes: Double(420 + index * 30),
                start: index < 4 ? "2026-09-\(day - 1)T23:30:00+08:00" : "\(date)T00:30:00+08:00",
                wake: index == 0 ? nil : "\(date)T08:00:00+08:00")
            add("nap-\(day)", day: date, minutes: 20,
                start: "\(date)T13:00:00+08:00", wake: "\(date)T13:20:00+08:00")
        }
        add("boundary", day: "2026-09-01", minutes: 900)
        add("outside", day: "2026-08-31", minutes: 9999)
        add("today-main", day: "2026-10-01", minutes: 600)
        add("today-nap", day: "2026-10-01", minutes: 20)
        add("future", day: "2026-10-02", minutes: 9999)
        let groups = Dictionary(grouping: records, by: \.dateKey).map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value) }
        let result = NativeDomainScenePresentation.make(domain: .sleep, dateKey: "2026-10-01", weekGroups: groups,
            details: details, isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: "2026-10-02")
        let sleep = try XCTUnwrap(result.sleep)
        XCTAssertEqual(result.knownPrimaryTotal, 620, "当日总量保留午休")
        XCTAssertEqual(result.weeklyValues.last?.value, 600, "近七夜仅主要睡眠")
        XCTAssertEqual(sleep.mainRecord?.id, "today-main")
        XCTAssertEqual(sleep.duration.sampleCount, 8)
        XCTAssertEqual(sleep.duration.median, 525)
        XCTAssertEqual(sleep.bedtime.sampleCount, 7)
        XCTAssertEqual(sleep.bedtime.median, 1410)
        XCTAssertEqual(sleep.wake.sampleCount, 6, "不能用午休补齐主要睡眠缺失字段")
        XCTAssertNil(sleep.wake.median)
        XCTAssertEqual(NativeSleepBaseline([1410, 1470, 1410, 1470, 1410, 1470, 1410, 1470]).median, 1440)
        XCTAssertEqual(NativeSleepSummary.clockLabel(1440), "00:00")
        XCTAssertEqual(NativeSleepSummary.clockDifference(1470, baseline: 1410), 60)
        let a = record("tie-a", date: "2026-10-01", domain: .sleep)
        let b = record("tie-b", date: "2026-10-01", domain: .sleep)
        let tied = [a.reference: detail(a, ["sleep_minutes": AnyCodable(400)]),
                    b.reference: detail(b, ["sleep_minutes": AnyCodable(400)])]
        XCTAssertEqual(NativeSleepSummary.make(records: [b, a], details: tied, dateKey: "2026-10-01").mainRecord?.id, "tie-a")
        XCTAssertEqual(NativeSleepSummary.make(records: [a, b], details: tied, dateKey: "2026-10-01").mainRecord?.id, "tie-a")
        let missing = record("unknown-duration", date: "2026-10-01", domain: .sleep)
        XCTAssertNil(NativeSleepSummary.make(records: [a, missing], details: tied, dateKey: "2026-10-01").mainRecord,
                     "另有时长未知的睡眠时，不能把一条短记录冒充当日最长")
    }

    @MainActor
    func testIOSV2POLISH002AF02MonthPullCommitsOnlyAtReleasedHorizontalBoundary() {
        func release(_ month: String = "2024-03", leading: CGFloat = 0, trailing: CGFloat = 0,
                     x: CGFloat = 120, y: CGFloat = 0) -> String? {
            DomainDatePickerView.releasedBoundaryDate(
                monthKey: month, leadingPull: leading, trailingPull: trailing,
                translation: CGSize(width: x, height: y)
            )
        }
        XCTAssertNil(release(leading: 39))
        XCTAssertEqual(release(leading: 40), "2024-02-29")
        XCTAssertEqual(release("2026-01", leading: 70), "2025-12-31")
        XCTAssertEqual(release(trailing: 40, x: -120), "2024-04-01")
        XCTAssertNil(release(leading: 60, x: -120))
        XCTAssertNil(release(trailing: 39, x: -120))
        XCTAssertNil(release(leading: 60, y: 140))
        XCTAssertNil(release(leading: 60, x: 0))
        XCTAssertNil(release(leading: .nan))
        XCTAssertNil(release(leading: 60, x: .infinity))
        XCTAssertNil(release("invalid", leading: 60))
    }

    func testIOSV2POLISH004F03RemoteRefreshDoesNotHideReadableFormalRecords() {
        let meal = record("local-meal", date: "2026-10-05", domain: .food)
        let groups = [NativeDayRecordGroup(dateKey: meal.dateKey, records: [meal])]
        let details = [meal.reference: detail(meal, ["total_calorie_kcal": AnyCodable(450)])]

        for (loading, error) in [(true, nil as String?), (false, "网络不可用")] {
            let result = NativeDomainScenePresentation.make(
                domain: .food, dateKey: meal.dateKey, weekGroups: groups, details: details,
                isSignedIn: true, isLoading: loading, errorMessage: error, todayKey: meal.dateKey
            )
            XCTAssertEqual(result.records.map(\.reference), [meal.reference])
            XCTAssertEqual(result.knownPrimaryTotal, 450)
            XCTAssertNil(result.stateMessage, "本地正式事实可读时，远端刷新状态不能使页面进入整页加载/错误态")
            XCTAssertNotNil(result.refreshMessage, "读取未完成时仍须提示，不能把已知小计冒充完整总量")
        }
    }

    func testIOSV2POLISH004F03WithoutReadableRecordsLoadingAndFailureRemainExplicit() {
        let loading = NativeDomainScenePresentation.make(
            domain: .food, dateKey: "2026-10-05", weekGroups: [], details: [:],
            isSignedIn: true, isLoading: true, errorMessage: nil
        )
        XCTAssertEqual(loading.stateMessage, "正在读取本机与云端记录…")
        let failed = NativeDomainScenePresentation.make(
            domain: .food, dateKey: "2026-10-05", weekGroups: [], details: [:],
            isSignedIn: true, isLoading: false, errorMessage: "网络不可用"
        )
        XCTAssertEqual(failed.stateMessage, "记录读取失败：网络不可用")
    }

    func testIOSV2POLISH004FoodAverageIncludesExplicitZeroButNotMissingOrUnrecordedDays() throws {
        let zero = record("zero", date: "2026-10-05", domain: .food)
        let high = record("high", date: "2026-10-06", domain: .food)
        let missing = record("missing", date: "2026-10-08", domain: .food)
        let result = model(.food, date: "2026-10-08", records: [zero, high, missing], details: [
            zero.reference: detail(zero, ["total_calorie_kcal": AnyCodable(0)]),
            high.reference: detail(high, ["total_calorie_kcal": AnyCodable(800)])
        ])
        XCTAssertEqual(result.periodRecordCount, 3)
        XCTAssertEqual(result.validDayCount, 2)
        XCTAssertEqual(try XCTUnwrap(result.periodDailyAverage), 400, accuracy: 0.001)
        XCTAssertNil(result.periodTotal, "缺热量的一天不得以零计入完整累计")
        XCTAssertNil(result.highestMeal, "选中日没有可读取热量，不借用其他日最大一餐")
        let measuredDay = model(.food, date: "2026-10-06", records: [zero, high], details: [
            zero.reference: detail(zero, ["total_calorie_kcal": AnyCodable(0)]),
            high.reference: detail(high, ["total_calorie_kcal": AnyCodable(800)])
        ])
        XCTAssertEqual(measuredDay.highestMeal?.reference, high.reference)
    }

    func testIOSV2POLISH004FoodWeekIsNaturalWeekWhileSleepEndsOnSelectedDay() {
        XCTAssertEqual(NativeDomainScenePresentation.trendDateKeys(for: .food, dateKey: "2026-10-08"), [
            "2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09", "2026-10-10", "2026-10-11"
        ])
        XCTAssertEqual(NativeDomainScenePresentation.trendDateKeys(for: .sleep, dateKey: "2026-10-08").first, "2026-10-02")
    }

    func testIOSV2POLISH004SportAndReadingPeriodUseFormalRecordsInNaturalWeek() throws {
        for domain in [AppDomain.sport, .reading] {
            let key = domain == .sport ? "duration_minutes" : "reading_minutes"
            let prior = record("prior", date: "2026-10-04", domain: domain)
            let current = record("current", date: "2026-10-05", domain: domain)
            let next = record("next", date: "2026-10-06", domain: domain)
            let result = model(domain, records: [prior, current, next], details: [
                prior.reference: detail(prior, [key: AnyCodable(900)]),
                current.reference: detail(current, [key: AnyCodable(30), "sport_type": AnyCodable(" 散步 ")]),
                next.reference: detail(next, [key: AnyCodable(45)])
            ])
            XCTAssertEqual(result.periodRecordCount, 2)
            XCTAssertEqual(try XCTUnwrap(result.periodTotal), 75, accuracy: 0.001)
            if domain == .sport { XCTAssertEqual(result.periodTypes, ["散步", "类型未提供"]) }
        }
    }

    func testIOSV2POLISH003TimelineUsesEventTimeAndRetainsEqualTimeReferences() {
        let a = record("a", date: "2026-10-05", domain: .expense, time: "上传 11:00")
        let b = record("b", date: "2026-10-05", domain: .expense, time: "09:00")
        let upload = record("upload", date: "2026-10-05", domain: .expense, time: "上传 10:00")
        let invalid = record("bad", date: "2026-10-05", domain: .expense, time: "99:99")
        var actual = detail(a, [:])
        actual.occurredAt = "2026-10-05T01:00:00Z"
        let result = model(.expense, records: [b, upload, invalid, a], details: [a.reference: actual])
        XCTAssertEqual(result.timeline.map(\.minute), [540, 540])
        XCTAssertEqual(result.timeline.map(\.record.reference), [a.reference, b.reference])
        XCTAssertEqual(result.records.count, 4, "未知业务时间只退出时间线，正式记录仍可达")
    }

    func testIOSV2POLISH003ComparisonUsesPreviousDayAcrossMonthAndMissingAmountStaysUnknown() throws {
        let previous = record("previous", date: "2026-09-30", domain: .expense)
        let current = record("current", date: "2026-10-01", domain: .expense)
        let result = model(.expense, date: "2026-10-01", records: [previous, current], details: [:])
        XCTAssertEqual(try XCTUnwrap(result.previousExpenseTotal), 10, accuracy: 0.001)
        let missing = NativeDayRecord(id: "missing", reference: "expense/missing", dateKey: "2026-09-30",
            kind: .expense, domainKey: nil, title: "未填写", subtitle: "", value: "", timeLabel: nil, systemImage: "creditcard")
        XCTAssertNil(model(.expense, date: "2026-10-01", records: [missing, current], details: [:]).previousExpenseTotal)
    }

    func testIOSV2POLISH004SleepRangeCrossesMidnightAndNeverInfersRangeFromDuration() throws {
        let actual = record("actual", date: "2026-10-05", domain: .sleep)
        let durationOnly = record("duration", date: "2026-10-05", domain: .sleep)
        let reversed = record("reversed", date: "2026-10-05", domain: .sleep)
        let result = model(.sleep, records: [actual, durationOnly, reversed], details: [
            actual.reference: detail(actual, ["sleep_minutes": AnyCodable(480),
                "sleep_start_at": AnyCodable("2026-10-04T23:30:00+08:00"), "wake_at": AnyCodable("2026-10-05T07:30:00+08:00")]),
            durationOnly.reference: detail(durationOnly, ["sleep_minutes": AnyCodable(480)]),
            reversed.reference: detail(reversed, ["sleep_start_at": AnyCodable("2026-10-05T07:30:00+08:00"),
                "wake_at": AnyCodable("2026-10-04T23:30:00+08:00")])
        ])
        XCTAssertEqual(result.sleepRanges.map(\.id), [actual.reference])
        let interval = try XCTUnwrap(result.sleepRanges.first)
        XCTAssertEqual(interval.end.timeIntervalSince(interval.start), 8 * 3600, accuracy: 0.001)
    }

    private func record(_ id: String, date: String, domain: AppDomain, time: String? = nil) -> NativeDayRecord {
        NativeDayRecord(id: id, reference: "\(domain == .expense ? "expense" : "data")/\(id)", dateKey: date,
            kind: domain == .expense ? .expense : domain == .food ? .food : domain == .sleep ? .sleep : domain == .sport ? .sport : .reading,
            domainKey: domain.rawValue, title: id, subtitle: "", value: domain == .expense ? "¥10.00" : "",
            timeLabel: time, systemImage: "circle", status: "done")
    }

    private func detail(_ record: NativeDayRecord, _ payload: [String: AnyCodable]) -> NativeRecordDetail {
        NativeRecordDetail(id: record.reference, rawId: record.id, kind: "data", title: record.title,
            subtitle: "", value: "", detailRows: [], imageURL: nil, imageLoadError: false, imagePath: nil,
            imageHash: nil, amount: nil, merchantName: nil, platform: nil, category: nil, paymentMethod: nil,
            recordDate: record.dateKey, note: nil, companionMessage: nil, accountId: nil,
            systemImage: "circle", payload: payload, domainKey: record.domainKey)
    }

    private func model(_ domain: AppDomain, date: String = "2026-10-05", records: [NativeDayRecord],
        details: [String: NativeRecordDetail]) -> NativeDomainScenePresentation {
        NativeDomainScenePresentation.make(domain: domain, dateKey: date,
            weekGroups: Dictionary(grouping: records, by: \.dateKey).map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value) },
            details: details, isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: "2026-10-17")
    }
}
