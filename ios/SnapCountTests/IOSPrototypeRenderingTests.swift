import XCTest
import SwiftUI
import UIKit
import CoreText
@testable import SnapCount

/// 合成事实的原生渲染证据，只证明能生成图片，不代替视觉、手势或真机性能验收。
@MainActor
final class IOSPrototypeRenderingTests: XCTestCase {
    /// LF-034/LF-036/LF-037: real local writes feed the actual pages.
    /// Captures prove native rendering of synthetic facts, not device gestures.
    func testLF034FinancialScenesUseCommittedLocalFactsAndOriginalImages() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("local-scenes-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("scene.sqlite"))
        let profiles = LocalProfileStore(database: database)
        let profile = try profiles.activeProfile()
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images"))
        let repository = try LocalExpenseRepository(database: database)
        let account = try repository.createAccount(LocalAccountDraft(id: UUID(), profileID: profile.id,
            name: "合成现金", kind: "cash", currency: "CNY", openingBalanceMinor: 10_000, createdAt: Date()))
        let pending = LocalPendingFinancialRepository(database: database)
        let state = AppState(localExpenseUseCase: LocalExpenseUseCase(profileStore: profiles, repository: repository, imageStore: images),
            localRecordUseCase: LocalRecordUseCase(profileStore: profiles, repository: try LocalRecordRepository(database: database), imageStore: images),
            localFactReader: try LocalFactReader(database: database), localImageStore: images,
            localPendingFinancialRepository: pending, localFinancialBindingRepository: try LocalFinancialBindingRepository(database: database),
            localBindingRepository: profiles,
            sessionProvider: { _ in XCTFail("本机场景不能请求云会话"); throw SupabaseRemoteError.missingSession })
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
            UIColor.systemOrange.setFill(); context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
            ("合成午餐 ¥20" as NSString).draw(at: CGPoint(x: 20, y: 60), withAttributes: [.foregroundColor: UIColor.black])
        }
        var draft = NativeManualRecordDraft(kind: .expense)
        draft.accountId = account.id.uuidString; draft.amountText = "20"; draft.title = "合成午餐"
        draft.platform = "线下"; draft.category = "food"; draft.paymentMethod = "现金"
        draft.imageData = try XCTUnwrap(sample.jpegData(compressionQuality: 0.8))
        let created = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(created)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 8000)
        await state.loadAccounts()
        try await capture(NavigationStack { AccountsView() }.environmentObject(state), name: "local-cash100-expense20-balance80", height: 844)
        let record = try XCTUnwrap(state.recordGroups(monthKey: NativeMonthKey.current()).flatMap(\.records).first)
        await state.loadRecordDetail(reference: record.reference, force: true)
        let detail = try XCTUnwrap(state.selectedRecordDetail)
        XCTAssertNotNil(detail.imageURL)
        try await capture(NavigationStack { RecordDetailView(reference: record.reference) }.environmentObject(state)
            .environmentObject(JieziThemeManager.shared), name: "local-expense-original-detail", height: 1000)
        try await capture(ManualRecordSheet(editing: detail).environmentObject(state)
            .environmentObject(JieziThemeManager.shared), name: "local-expense-edit-original", height: 1000)
        var edit = NativeManualRecordDraft(detail: detail)
        edit.amountText = "30"
        let edited = await state.createManualRecord(edit, domain: nil)
        XCTAssertTrue(edited)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 7000)
        let deleted = await state.deleteRecord(reference: record.reference)
        XCTAssertTrue(deleted)
        XCTAssertEqual(try repository.accountBalanceMinor(accountID: account.id), 10000)
        await state.loadAccounts()
        try await capture(NavigationStack { AccountsView() }.environmentObject(state), name: "local-delete-restores-balance100", height: 844)
    }

    func testIOSV2POLISH003P1ExportTimelineWithCoincidentFallbackAndUnknownTimes() async throws {
        let date = "2026-10-17"
        let records = ["早餐", "咖啡", "补录", "未填时间"].enumerated().map { index, title in
            NativeDayRecord(id: "timeline-\(index)", reference: "expense/timeline-\(index)", dateKey: date,
                kind: .expense, domainKey: nil, title: title, subtitle: "", value: "¥12.00",
                timeLabel: index < 2 ? "09:00" : nil, systemImage: "creditcard", status: "done")
        }
        let detail = NativeRecordDetail(id: records[2].reference, rawId: records[2].id, kind: "expense",
            title: records[2].title, subtitle: "", value: "¥12.00", detailRows: [], imageURL: nil,
            imageLoadError: false, imagePath: nil, imageHash: nil, amount: 12, merchantName: "示例店",
            platform: nil, category: nil, paymentMethod: nil, recordDate: date, note: nil,
            companionMessage: nil, accountId: nil, systemImage: "creditcard", payload: nil,
            createdAt: "2026-10-18T02:30:00Z")
        let details = [detail.id: detail]
        let model = NativeDomainScenePresentation.make(domain: .expense, dateKey: date,
            weekGroups: [NativeDayRecordGroup(dateKey: date, records: records)], details: details,
            isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: date)
        XCTAssertEqual(model.records.count, 4)
        XCTAssertEqual(model.timeline.count, 3)
        let state = try makeIsolatedState()
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = ZStack {
                DomainSceneView(domain: .expense)
                NativeDomainPageContent(domain: .expense, weekDates: model.weeklyValues.map(\.dateKey),
                    details: details, loadingWindow: false, model: model)
            }.environmentObject(state).environment(\.dynamicTypeSize, size)
            try await capture(view, name: "timeline-fallback-\(size)", height: 1050)
        }
    }

    /// The display face is the system serif design instead of a bundled
    /// Noto Serif SC payload (~25 MB). `CTFontGetGlyphsForCharacters` never
    /// consults the cascade list, so it reports "no glyph" for CJK even when
    /// the rendered line is complete. Shape a real line and check the glyphs.
    func testIOSV2POLISH011SystemAndNumericFontsCoverRepresentativeText() throws {
        let display = UIFont.systemFont(ofSize: 24, weight: .bold)
        let numeric = try XCTUnwrap(UIFont(name: JieziFontFamily.numeric, size: 44))
        for (font, text) in [(display, "芥子阅读记录收入书名"), (numeric, "0123456789¥.")] {
            let line = CTLineCreateWithAttributedString(
                NSAttributedString(string: text, attributes: [.font: font])
            )
            let runs = CTLineGetGlyphRuns(line) as! [CTRun]
            var glyphs: [CGGlyph] = []
            for run in runs {
                let count = CTRunGetGlyphCount(run)
                var buffer = [CGGlyph](repeating: 0, count: count)
                CTRunGetGlyphs(run, CFRange(location: 0, length: count), &buffer)
                glyphs.append(contentsOf: buffer)
            }
            XCTAssertEqual(glyphs.count, text.utf16.count, "\(font.fontName) dropped characters in \(text)")
            XCTAssertFalse(glyphs.contains(0), "\(font.fontName) is missing a glyph for part of \(text)")
        }
    }

    func testIOSV2POLISH004ExportFiveDomainContentAtNormalAndAccessibleType() async throws {
        let sizes: [DynamicTypeSize] = [.large, .accessibility3]
        for domain in AppDomain.allCases {
            for size in sizes {
                let date = "2026-10-17"
                let record = NativeDayRecord(
                    id: "fixture-\(domain.rawValue)", reference: "fixture/\(domain.rawValue)",
                    dateKey: date, kind: NativeDayRecordKind(rawValue: domain.rawValue)!,
                    domainKey: domain.rawValue, title: domain == .expense ? "瑞幸咖啡（软件园店）" : domain.title,
                    subtitle: domain == .expense ? "工作日午间 · 餐饮" : "", value: domain == .expense ? "¥42.00" : "",
                    timeLabel: "12:30", systemImage: domain.systemImage, status: "done"
                )
                let detail = NativeRecordDetail(
                    id: record.reference, rawId: record.id, kind: domain == .expense ? "expense" : "data",
                    title: record.title, subtitle: record.subtitle, value: record.value,
                    detailRows: domain == .expense ? [
                        NativeDetailRow(label: "消费分类", value: "餐饮美食"),
                        NativeDetailRow(label: "支付方式", value: "微信支付"),
                        NativeDetailRow(label: "记录来源", value: "截图识别")
                    ] : [], imageURL: nil,
                    imageLoadError: false, imagePath: nil, imageHash: nil,
                    amount: domain == .expense ? 42 : nil, merchantName: domain == .expense ? record.title : nil,
                    platform: domain == .expense ? "微信" : nil,
                    category: domain == .expense ? "餐饮" : nil,
                    paymentMethod: domain == .expense ? "微信支付" : nil, recordDate: date,
                    note: domain == .expense ? "午休路过，少糖拿铁" : nil,
                    companionMessage: nil, accountId: nil, systemImage: domain.systemImage,
                    payload: [
                        "sleep_minutes": AnyCodable(480),
                        "sleep_start_at": AnyCodable("2026-10-16T23:30:00+08:00"),
                        "wake_at": AnyCodable("2026-10-17T07:30:00+08:00"),
                        "total_calorie_kcal": AnyCodable(780), "meal_type": AnyCodable("lunch"),
                        "duration_minutes": AnyCodable(30), "sport_type": AnyCodable("骑行"),
                        "reading_minutes": AnyCodable(32), "pages": AnyCodable(18),
                        "book_name": AnyCodable("示例书目：一段需要在大字体下完整显示的长书名")
                    ], domainKey: domain.rawValue
                )
                let details = [record.reference: detail]
                let groups = [NativeDayRecordGroup(dateKey: date, records: [record])]
                let model = NativeDomainScenePresentation.make(
                    domain: domain, dateKey: date, weekGroups: groups, details: details,
                    isSignedIn: false, isLoading: false, errorMessage: nil, todayKey: date
                )
                let state = try makeIsolatedState()
                state.selectedDateKey = date
                state.selectedDomain = domain
                let view = ZStack(alignment: .topTrailing) {
                    DomainSceneView(domain: domain)
                    if !size.isAccessibilitySize {
                        DomainCatView(domain: domain)
                            .padding(.trailing, JieziPrototypeLayout.metric_inset)
                    }
                    NativeDomainPageContent(
                        domain: domain, weekDates: model.weeklyValues.map(\.dateKey),
                        details: details, loadingWindow: false, model: model
                    )
                }
                .environmentObject(state)
                .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "content-\(domain.rawValue)-\(size)")
                if domain == .expense || domain == .sleep || domain == .sport {
                    let drill = NativeDomainPageContent(domain: domain, weekDates: model.weeklyValues.map(\.dateKey),
                        details: details, loadingWindow: false, model: model, isDrillDown: true)
                        .environmentObject(state).environment(\.dynamicTypeSize, size)
                    try await capture(drill, name: "drill-\(domain.rawValue)-\(size)", height: 1000)
                }
            }
        }
    }

    /// Promotional source captures: a whole synthetic day across all five domains.
    /// The fixtures are deliberately richer than a single-record smoke test so
    /// App Store artwork can show the product's cross-domain context honestly.
    func testPROMOExportRichCrossDomainSourceCaptures() async throws {
        let date = "2026-10-17"
        var records: [NativeDayRecord] = []
        var details: [String: NativeRecordDetail] = [:]

        func add(_ record: NativeDayRecord, detail: NativeRecordDetail) {
            records.append(record)
            details[record.reference] = detail
        }

        func expense(
            _ id: String, _ title: String, _ amount: Double, _ time: String,
            category: String, payment: String, note: String,
            companion: String? = nil, feedback: [String: AnyCodable]? = nil,
            dateKey: String = date
        ) {
            let reference = "expense/promo-\(id)"
            let record = NativeDayRecord(
                id: "promo-\(id)", reference: reference, dateKey: dateKey,
                kind: .expense, domainKey: "expense", title: title,
                subtitle: "\(category) · \(payment)", value: String(format: "¥%.2f", amount),
                timeLabel: time, systemImage: "creditcard", transactionType: "expense",
                status: "done", amount: amount
            )
            let detail = NativeRecordDetail(
                id: reference, rawId: record.id, kind: "expense", title: title,
                subtitle: record.subtitle, value: record.value,
                detailRows: [
                    NativeDetailRow(label: "消费分类", value: category),
                    NativeDetailRow(label: "支付方式", value: payment),
                    NativeDetailRow(label: "交易时间", value: time),
                    NativeDetailRow(label: "备注", value: note)
                ], imageURL: nil, imageLoadError: false, imagePath: nil, imageHash: nil,
                amount: amount, merchantName: title, platform: payment,
                category: category, paymentMethod: payment, recordDate: dateKey,
                note: note, companionMessage: companion, accountId: nil,
                systemImage: "creditcard", payload: nil, transactionTime: time,
                domainKey: "expense", source: "shortcut-screenshot", status: "done",
                aiFeedback: feedback.flatMap(NativeAIFeedback.init(payload:))
            )
            add(record, detail: detail)
        }

        let companion = "早上用咖啡把自己叫醒，中午按时吃饭，晚上也把花销收得住。今天的节奏，比昨天更像你想要的样子。"
        let companionFeedback: [String: AnyCodable] = [
            "icon": AnyCodable("sparkles"), "badge": AnyCodable("今天的节奏"),
            "band": AnyCodable("positive"), "source": AnyCodable("hosted"),
            "emotion_line": AnyCodable(companion),
            "utility_line": AnyCodable("把睡眠、饮食、运动和消费放在一起看，才看得见这一天的起伏。"),
            "detail_reason": AnyCodable("依据：7 笔消费、3 餐饮食、1 次骑行和昨夜 7 小时 45 分睡眠。"),
            "presentation_target": AnyCodable("companion_message"),
            "claim_fingerprint": AnyCodable("promo-cross-domain-20261017"),
            "rendered_text_fingerprint": AnyCodable("promo-companion-v1")
        ]

        expense("breakfast", "全家便利店（软件园店）", 18.50, "07:35", category: "早餐", payment: "微信支付", note: "豆浆和饭团")
        expense("coffee", "瑞幸咖啡（软件园店）", 22.00, "09:10", category: "咖啡", payment: "微信支付", note: "生椰拿铁", companion: companion, feedback: companionFeedback)
        expense("lunch", "园区食堂", 36.00, "12:20", category: "午餐", payment: "支付宝", note: "番茄牛腩饭")
        expense("snack", "喜茶（万象城店）", 14.00, "15:45", category: "下午茶", payment: "微信支付", note: "无糖茶饮")
        expense("grocery", "盒马鲜生（滨江店）", 86.00, "18:30", category: "日常采购", payment: "银行卡", note: "蔬菜和酸奶")
        expense("takeaway", "美团外卖 · 暖锅小馆", 42.00, "20:15", category: "晚餐", payment: "微信支付", note: "晚饭补充")
        expense("transit", "杭州地铁", 6.00, "22:10", category: "交通", payment: "支付宝", note: "回家")

        func universal(
            _ id: String, domain: String, title: String, subtitle: String,
            time: String, image: String, payload: [String: AnyCodable],
            foodImage: String? = nil,
            dateKey: String = date
        ) {
            let reference = "data/promo-\(id)"
            let kind = NativeDayRecordKind(rawValue: domain)!
            let foodImageURL: URL? = foodImage.flatMap { name in
                let projectRoot = URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                let url = projectRoot
                    .appendingPathComponent("docs/app-store-assets/food-photos", isDirectory: true)
                    .appendingPathComponent(name)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    XCTFail("缺少宣传用餐食图片：\(url.path)")
                    return nil
                }
                return url
            }
            let record = NativeDayRecord(
                id: "promo-\(id)", reference: reference, dateKey: dateKey,
                kind: kind, domainKey: domain, title: title, subtitle: subtitle,
                value: "", timeLabel: time, systemImage: image, status: "done"
            )
            let detail = NativeRecordDetail(
                id: reference, rawId: record.id, kind: "data", title: title,
                subtitle: subtitle, value: "", detailRows: [], imageURL: foodImageURL,
                imageLoadError: false, imagePath: foodImage.map { "records/promo-\($0)" }, imageHash: nil, amount: nil,
                merchantName: nil, platform: nil, category: nil, paymentMethod: nil,
                recordDate: dateKey, note: payload.string("note"),
                companionMessage: nil, accountId: nil, systemImage: image,
                payload: payload, transactionTime: time, domainKey: domain,
                source: "shortcut", status: "done"
            )
            add(record, detail: detail)
        }

        universal("breakfast-meal", domain: "food", title: "早餐", subtitle: "早餐 · 估算", time: "07:50", image: "fork.knife", payload: [
            "meal_type": AnyCodable("breakfast"), "total_calorie_kcal": AnyCodable(420),
            "dishes": AnyCodable([["name": "鸡蛋", "calorie_kcal": 90], ["name": "全麦面包", "calorie_kcal": 180], ["name": "无糖豆浆", "calorie_kcal": 150]]),
            "note": AnyCodable("吃得简单，上午精神比较稳")
        ], foodImage: "breakfast.jpg")
        universal("lunch-meal", domain: "food", title: "番茄牛腩饭", subtitle: "午餐 · 估算", time: "12:25", image: "fork.knife", payload: [
            "meal_type": AnyCodable("lunch"), "total_calorie_kcal": AnyCodable(680),
            "dishes": AnyCodable([["name": "番茄牛腩", "calorie_kcal": 360], ["name": "米饭", "calorie_kcal": 260], ["name": "青菜", "calorie_kcal": 60]]),
            "note": AnyCodable("午餐按时完成")
        ], foodImage: "tomato-beef-rice.jpg")
        universal("dinner-meal", domain: "food", title: "蔬菜鸡肉沙拉", subtitle: "晚餐 · 估算", time: "19:40", image: "fork.knife", payload: [
            "meal_type": AnyCodable("dinner"), "total_calorie_kcal": AnyCodable(560),
            "dishes": AnyCodable([["name": "鸡胸肉", "calorie_kcal": 260], ["name": "生菜", "calorie_kcal": 80], ["name": "玉米", "calorie_kcal": 120], ["name": "酸奶", "calorie_kcal": 100]]),
            "note": AnyCodable("晚上没有继续加餐")
        ], foodImage: "chicken-salad.jpg")
        universal("night-sleep", domain: "sleep", title: "主要睡眠", subtitle: "睡眠 · 7 小时 45 分钟", time: "07:25", image: "moon.zzz", payload: [
            "sleep_minutes": AnyCodable(465),
            "sleep_start_at": AnyCodable("2026-10-16T23:40:00+08:00"),
            "wake_at": AnyCodable("2026-10-17T07:25:00+08:00"),
            "sleep_quality": AnyCodable("稳")
        ])
        universal("morning-ride", domain: "sport", title: "骑行", subtitle: "运动类型 · 骑行", time: "08:05", image: "figure.run", payload: [
            "duration_minutes": AnyCodable(30), "sport_type": AnyCodable("骑行"), "note": AnyCodable("通勤路上")
        ])
        universal("evening-walk", domain: "sport", title: "散步", subtitle: "运动类型 · 散步", time: "21:10", image: "figure.walk", payload: [
            "duration_minutes": AnyCodable(22), "sport_type": AnyCodable("散步"), "note": AnyCodable("饭后走了一会儿")
        ])
        universal("reading", domain: "reading", title: "《掌控习惯》", subtitle: "阅读 · 32 分钟", time: "22:35", image: "book", payload: [
            "reading_minutes": AnyCodable(32), "pages": AnyCodable(18), "book_name": AnyCodable("《掌控习惯》"), "note": AnyCodable("睡前读了两节")
        ])

        // Add a small, synthetic seven-day history so the trend cards have shape.
        for offset in -6 ... -1 {
            guard let day = NativeLocalDate.shiftedDateKey(date, byDays: offset) else { continue }
            let amount = Double(32 + abs(offset) * 11)
            expense("history-\(offset)", "日常便利店", amount, "18:00", category: "日常", payment: "微信支付", note: "合成历史记录", dateKey: day)
            universal("food-history-\(offset)", domain: "food", title: "家常餐食", subtitle: "晚餐 · 估算", time: "19:00", image: "fork.knife", payload: [
                "meal_type": AnyCodable("dinner"), "total_calorie_kcal": AnyCodable(520 + abs(offset) * 18)
            ], dateKey: day)
            universal("sport-history-\(offset)", domain: "sport", title: "散步", subtitle: "运动类型 · 散步", time: "20:00", image: "figure.walk", payload: [
                "duration_minutes": AnyCodable(18 + abs(offset) * 2), "sport_type": AnyCodable("散步")
            ], dateKey: day)
        }

        let groups = Dictionary(grouping: records, by: \.dateKey)
            .map { NativeDayRecordGroup(dateKey: $0.key, records: $0.value) }
        let state = try makeIsolatedState()
        state.selectedDateKey = date
        state.selectedDomain = .expense

        for domain in [AppDomain.expense, .food, .sleep, .sport, .reading] {
            let model = NativeDomainScenePresentation.make(
                domain: domain, dateKey: date, weekGroups: groups, details: details,
                isSignedIn: true, isLoading: false, errorMessage: nil, todayKey: date
            )
            let view = ZStack(alignment: .topTrailing) {
                DomainSceneView(domain: domain)
                DomainCatView(domain: domain).padding(.trailing, JieziPrototypeLayout.metric_inset)
                NativeDomainPageContent(
                    domain: domain, weekDates: model.weeklyValues.map(\.dateKey),
                    details: details, loadingWindow: false, model: model
                )
            }
            .environmentObject(state)
            .environment(\.dynamicTypeSize, .large)
            try await capture(view, name: "promo-rich-\(domain.rawValue)", height: 1250)
        }

        let companionReference = "expense/promo-coffee"
        let companionDetail = try XCTUnwrap(details[companionReference])
        let detailView = PromoCompanionSourceView(detail: companionDetail)
            .environmentObject(state)
            .environmentObject(JieziThemeManager.shared)
            .environment(\.dynamicTypeSize, .large)
        try await capture(detailView, name: "promo-rich-ai-companion", height: 1250)
    }

    func testIOSV2POLISH001ExportEmptyShellAtNormalAndAccessibleType() async throws {
        let sizes: [DynamicTypeSize] = [.large, .accessibility3]
        for domain in AppDomain.allCases {
            for size in sizes {
            let state = try makeIsolatedState()
            state.selectedDateKey = "2026-10-17"
            state.selectedDomain = domain
            await state.loadRecordDateWindow(around: state.selectedDateKey)
            let view = MainShellView()
                .environmentObject(state)
                .environmentObject(JieziThemeManager.shared)
                .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "shell-empty-\(domain.rawValue)-\(size)", height: 844)
        }
        }
    }

    func testIOSV2POLISH002ExportSixRowCalendarInMediumHeight() async throws {
        let sizes: [DynamicTypeSize] = [.large, .accessibility3]
        for size in sizes {
            let state = try makeIsolatedState()
            await state.loadRecordMonth("2026-08")
            let view = DomainCalendarSheet(initialDateKey: "2026-08-17")
                .environmentObject(state)
                .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "calendar-six-rows-\(size)", height: 422)
        }
    }

    func testIOSV2POLISH002F02ExportMonthDateStripBoundaries() async throws {
        for dateKey in ["2024-03-01", "2024-03-31"] {
            for size in [DynamicTypeSize.large, .accessibility3] {
                let state = try makeIsolatedState()
                state.selectedDateKey = dateKey
                let view = VStack(alignment: .leading, spacing: 16) {
                    Text("日期选择 · \(dateKey)").font(JieziFont.body)
                    DomainDatePickerView(showsCalendar: .constant(false))
                    Spacer()
                }
                .padding(20)
                .background(JieziTheme.pageBackground)
                .environmentObject(state)
                .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "date-strip-\(dateKey)-\(size)", height: 300)
            }
        }
    }

    func testIOSV2POLISH007ExportOnboardingSteps() async throws {
        let sizes: [DynamicTypeSize] = [.large, .accessibility3]
        for size in sizes {
            for step in OnboardingStep.allCases {
                let view = OnboardingFlowView(initialStep: step)
                    .environmentObject(try makeIsolatedState())
                    .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "onboarding-\(step)-\(size)", height: 844)
            }
            let binding = NavigationStack { ShortcutBindingView() }
                .environment(\.dynamicTypeSize, size)
            try await capture(binding, name: "shortcut-binding-\(size)", height: 844)
        }
    }

    func testIOSV2POLISH004F03ExportReadableFoodDuringRemoteFailure() async throws {
        let date = "2026-10-17"
        let meal = NativeDayRecord(
            id: "refresh-meal", reference: "data/refresh-meal", dateKey: date, kind: .food,
            domainKey: "food", title: "合成午餐", subtitle: "午餐 · 估算", value: "",
            timeLabel: "12:30", systemImage: "fork.knife", status: "done"
        )
        let detail = NativeRecordDetail(
            id: meal.reference, rawId: meal.id, kind: "data", title: meal.title,
            subtitle: meal.subtitle, value: "", detailRows: [], imageURL: nil,
            imageLoadError: false, imagePath: nil, imageHash: nil, amount: nil,
            merchantName: nil, platform: nil, category: nil, paymentMethod: nil,
            recordDate: date, note: nil, companionMessage: nil, accountId: nil,
            systemImage: meal.systemImage, payload: ["total_calorie_kcal": AnyCodable(450)], domainKey: "food"
        )
        let model = NativeDomainScenePresentation.make(
            domain: .food, dateKey: date,
            weekGroups: [NativeDayRecordGroup(dateKey: date, records: [meal])],
            details: [meal.reference: detail], isSignedIn: true, isLoading: false,
            errorMessage: "网络不可用", todayKey: date
        )
        for size in [DynamicTypeSize.large, .accessibility3] {
            let state = try makeIsolatedState()
            state.selectedDateKey = date
            state.selectedDomain = .food
            let view = ZStack(alignment: .topTrailing) {
                DomainSceneView(domain: .food)
                if !size.isAccessibilitySize {
                    DomainCatView(domain: .food)
                        .padding(.trailing, JieziPrototypeLayout.metric_inset)
                }
                NativeDomainPageContent(
                    domain: .food, weekDates: model.weeklyValues.map(\.dateKey),
                    details: [meal.reference: detail], loadingWindow: false, model: model
                )
            }
            .environmentObject(state)
            .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "content-food-refresh-failure-\(size)")
        }
    }

    func testIOSV2POLISH004F14ExportEnergyReferenceBoundaryStates() async throws {
        let date = "2026-10-17"
        let meal = NativeDayRecord(
            id: "energy-meal", reference: "data/energy-meal", dateKey: date, kind: .food,
            domainKey: "food", title: "合成餐食", subtitle: "午餐 · 估算", value: "",
            timeLabel: "12:30", systemImage: "fork.knife", status: "done"
        )
        let cases: [(String, Double?)] = [("zero", 0), ("above-reference", 3_200), ("not-estimated", nil)]
        for (name, energy) in cases {
            let payload: [String: AnyCodable] = energy.map { ["total_calorie_kcal": AnyCodable($0)] } ?? [:]
            let detail = NativeRecordDetail(
                id: meal.reference, rawId: meal.id, kind: "data", title: meal.title,
                subtitle: meal.subtitle, value: "", detailRows: [], imageURL: nil,
                imageLoadError: false, imagePath: nil, imageHash: nil, amount: nil,
                merchantName: nil, platform: nil, category: nil, paymentMethod: nil,
                recordDate: date, note: nil, companionMessage: nil, accountId: nil,
                systemImage: meal.systemImage, payload: payload, domainKey: "food"
            )
            let model = NativeDomainScenePresentation.make(
                domain: .food, dateKey: date,
                weekGroups: [NativeDayRecordGroup(dateKey: date, records: [meal])],
                details: [meal.reference: detail], isSignedIn: false, isLoading: false,
                errorMessage: nil, todayKey: date
            )
            for size in [DynamicTypeSize.large, .accessibility3] {
                let state = try makeIsolatedState()
                state.selectedDateKey = date
                state.selectedDomain = .food
                let view = ZStack {
                    DomainSceneView(domain: .food)
                    NativeDomainPageContent(
                        domain: .food, weekDates: model.weeklyValues.map(\.dateKey),
                        details: [meal.reference: detail], loadingWindow: false, model: model
                    )
                }
                .environmentObject(state)
                .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "food-energy-\(name)-\(size)", height: 1_100)
            }
        }
    }

    func testIOSV2POLISH010ExportReachableOverlayRoots() async throws {
        for size in [DynamicTypeSize.large, .accessibility3] {
            let pages: [(String, AnyView)] = [
                ("records", AnyView(RecordsView(initialMonthKey: "2026-10"))),
                ("inbox", AnyView(InboxView())),
                ("accounts", AnyView(AccountsView())),
                ("unbound", AnyView(UnboundRecordsView())),
                ("domains", AnyView(DomainsView())),
                ("day", AnyView(DayDetailView(route: NativeDayDetailRoute(dateKey: "2026-10-17", kind: .all)))),
                ("insights", AnyView(InsightsView())),
                ("settings", AnyView(SettingsView())),
                ("vision-settings", AnyView(VisionSettingsView())),
                ("companion-settings", AnyView(CompanionSettingsView())),
                ("insight-settings", AnyView(InsightSettingsView())),
                ("privacy-settings", AnyView(PrivacySettingsView())),
                ("export", AnyView(DataExportView())),
                ("new-account", AnyView(AccountEditSheet(draft: NativeAccountDraft()))),
                ("login", AnyView(LoginView())),
                ("privacy-document", AnyView(LegalDocumentView(kind: .privacy))),
                ("terms-document", AnyView(LegalDocumentView(kind: .terms))),
                ("shortcuts", AnyView(ShortcutSetupView()))
            ]
            for (name, page) in pages {
                let view = NavigationStack { page }
                    .environmentObject(try makeIsolatedState())
                    .environmentObject(JieziThemeManager.shared)
                    .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "overlay-\(name)-\(size)", height: 844)
            }
        }
    }

    func testIOSV2POLISH006ExportInboxStatusStages() async throws {
        for status in ["pending_review", "unassigned", "ai_error", "schema_failed", "duplicate"] {
            let record = NativeStagingRecord(
                id: "fixture-\(status)", dateKey: "2026-10-17", title: "示例候选 · \(status)",
                summary: "这是一条需要保留事实并完成后续处理的合成候选记录。", status: status,
                statusLabel: status, recordTypeLabel: "阅读", createdAtLabel: "2026-10-17 12:35",
                occurredAtLabel: "2026-10-17 12:30", confidencePercent: 80, lastErrorMessage: nil,
                retryCount: 0, systemImage: "book", imagePath: nil, imageURL: nil, imageLoadError: false,
                recordType: "reading", domainKey: "reading", domainName: "阅读",
                extracted: ["book_name": AnyCodable("合成书名"), "reading_minutes": AnyCodable(30)],
                companionMessage: nil, targetRecordId: nil, imageHash: nil
            )
            let items = NativeInboxPresentation.items(pendingExpenses: [], stagingRecords: [record])
            for size in [DynamicTypeSize.large, .accessibility3] {
                let view = InboxVerdictStageView(items: items, selection: .constant(items.first?.id), domains: [])
                    .environmentObject(try makeIsolatedState())
                    .environment(\.dynamicTypeSize, size)
                try await capture(view, name: "inbox-stage-\(status)-\(size)", height: 844)
            }
        }
    }

    func testIOSV2POLISH002ExportDomainAwareSignedOutEntry() async throws {
        for domain in AppDomain.allCases {
            let state = try makeIsolatedState()
            state.selectedDateKey = "2025-01-01"
            state.selectedDomain = domain
            let view = UnifiedManualRecordEntry(domain: domain)
                .environmentObject(state)
                .environment(\.dynamicTypeSize, .large)
            try await capture(view, name: "entry-signed-out-\(domain.rawValue)", height: 844)
        }
    }

    func testIOSV2POLISH010ExportPersistedLocalRecordDetailAndEditor() async throws {
        let state = try makeIsolatedState()
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "reading")
        draft.primaryValueText = "32"
        draft.dimension = "一段需要完整展示的合成书名"
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-17T12:30:00+08:00"))
        let saved = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(saved)
        await state.loadRecordMonth("2026-10", force: true)
        let reference = try XCTUnwrap(state.recordGroups(monthKey: "2026-10").flatMap(\.records).first?.reference)
        await state.loadRecordDetail(reference: reference)
        let detail = try XCTUnwrap(state.selectedRecordDetail)
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = NavigationStack { RecordDetailView(reference: reference) }
                .environmentObject(state)
                .environmentObject(JieziThemeManager.shared)
                .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "local-record-detail-\(size)", height: 844)
            let editor = ManualRecordSheet(editing: detail)
                .environmentObject(state)
                .environmentObject(JieziThemeManager.shared)
                .environment(\.dynamicTypeSize, size)
            try await capture(editor, name: "local-record-editor-\(size)", height: 844)
        }
    }

    private func makeIsolatedState() throws -> AppState {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("jiezi-capture-\(UUID().uuidString)", isDirectory: true)
        let database = try LocalDatabase(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
        let profiles = try LocalProfileStore(database: database)
        let images = try LocalImageStore(rootDirectory: directory.appendingPathComponent("images", isDirectory: true))
        _ = try profiles.activeProfile()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profiles, repository: try LocalExpenseRepository(database: database)),
            localRecordUseCase: LocalRecordUseCase(profileStore: profiles, repository: try LocalRecordRepository(database: database), imageStore: images),
            localFactReader: try LocalFactReader(database: database),
            localImageStore: images,
            localBindingRepository: profiles,
            sessionProvider: { _ in throw NSError(domain: "synthetic-capture-no-session", code: 1) }
        )
    }

    func testIOSV2POLISH004F13LocalPhotoThumbnailAndViewer() async throws {
        let state = try makeIsolatedState()
        state.resetUserScopedState()
        state.selectedDateKey = "2026-10-17"
        state.selectedDomain = .food
        let sample = UIGraphicsImageRenderer(size: CGSize(width: 240, height: 160)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 240, height: 160))
            UIColor.white.setFill()
            UIBezierPath(ovalIn: CGRect(x: 55, y: 15, width: 130, height: 130)).fill()
        }
        var draft = NativeManualRecordDraft(kind: .universal, domainKey: "food")
        draft.title = "合成照片测试餐食"
        draft.primaryValueText = "610"
        draft.dimension = "午餐"
        draft.date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-17T12:30:00+08:00"))
        draft.imageData = try XCTUnwrap(sample.jpegData(compressionQuality: 0.8))
        let saved = await state.createManualRecord(draft, domain: nil)
        XCTAssertTrue(saved)
        let record = try XCTUnwrap(state.recordGroups(monthKey: "2026-10").flatMap(\.records).first)
        let resolved = await state.thumbnailImageURL(for: record)
        let url = try XCTUnwrap(resolved)
        XCTAssertTrue(url.isFileURL)
        XCTAssertNil(state.selectedRecordDetail, "缩略图不能抢占详情/Planner的活跃记录")
        for size in [DynamicTypeSize.large, .accessibility3] {
            let view = MainShellView().environmentObject(state).environmentObject(JieziThemeManager.shared)
                .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "food-photo-local-\(size)", height: 1000)
        }
        try await capture(RecordPhotoViewer(url: url), name: "food-photo-viewer", height: 844)
    }

    private func capture<V: View>(_ view: V, name: String, height: CGFloat = 720) async throws {
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: "zh_CN")))
        host.overrideUserInterfaceStyle = .light
        let bounds = CGRect(x: 0, y: 0, width: 390, height: height)
        let window = UIWindow(frame: bounds)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.frame = bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        // 等待 SwiftUI 提交首帧布局，不用此延时模拟任何业务成功。
        try await Task.sleep(for: .milliseconds(100))
        let image = UIGraphicsImageRenderer(bounds: bounds).image { _ in
            XCTAssertTrue(host.view.drawHierarchy(in: bounds, afterScreenUpdates: true))
        }
        XCTAssertGreaterThan(try XCTUnwrap(image.pngData()).count, 1_000)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// The detail source capture keeps the production AI card and typography while
/// avoiding a network read. It is used only for synthetic promotional artwork.
private struct PromoCompanionSourceView: View {
    let detail: NativeRecordDetail

    var body: some View {
        ZStack {
            JieziTheme.pageBackground.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("记录详情")
                        .font(.largeTitle.bold())
                        .padding(.top, 18)

                    HStack(spacing: 12) {
                        Image(systemName: detail.systemImage)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(JieziTheme.brand)
                            .frame(width: 40, height: 40)
                            .background(JieziTheme.brand.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 4) {
                            Text(detail.title).font(.headline)
                            Text(detail.subtitle).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(detail.value).font(.headline.monospacedDigit())
                    }
                    .padding(16)
                    .jieziPrototypePanel()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("基本信息").font(.headline).padding(.bottom, 12)
                        ForEach(detail.detailRows) { row in
                            HStack(alignment: .top, spacing: 16) {
                                Text(row.label).foregroundStyle(.secondary)
                                Spacer()
                                Text(row.value).multilineTextAlignment(.trailing)
                            }
                            .font(.subheadline)
                            .padding(.vertical, 11)
                            Divider()
                        }
                    }
                    .padding(16)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))

                    if let message = detail.companionMessage,
                       let feedback = detail.voiceAiFeedback {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "quote.bubble.fill")
                                .foregroundStyle(JieziTheme.brand)
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 8) {
                                    Text("AI 陪伴").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                                    Text(feedback.badge)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(JieziTheme.brand)
                                }
                                Text(message)
                                    .font(.subheadline)
                                    .fixedSize(horizontal: false, vertical: true)
                                NativeAIFeedbackSupportingContent(
                                    feedback: feedback, primaryMessage: message, compact: true
                                )
                            }
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(JieziTheme.brand.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))

                        NativeAIFeedbackCard(
                            feedback: feedback,
                            compact: true,
                            primaryMessage: message,
                            reviewable: false,
                            reviewState: .idle,
                            exposureState: .idle
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI 摘要").font(.headline)
                        Text("把一条记录放回这一天里，睡眠、饮食、运动和消费就不再是孤立的数字。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .background(.white.opacity(0.68), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
        }
    }
}
