import XCTest
import SwiftUI
import UIKit
import CoreText
@testable import SnapCount

/// 合成事实的原生渲染证据，只证明能生成图片，不代替视觉、手势或真机性能验收。
@MainActor
final class IOSPrototypeRenderingTests: XCTestCase {
    func testIOSV2POLISH011RegisteredFontsResolveAndCoverRepresentativeText() throws {
        let serif = try XCTUnwrap(UIFont(name: JieziFontFamily.serif, size: 24))
        let numeric = try XCTUnwrap(UIFont(name: JieziFontFamily.numeric, size: 44))
        for (font, text) in [(serif, "芥子阅读记录收入书名"), (numeric, "0123456789¥.")] {
            let characters = Array(text.utf16)
            var glyphs = Array<CGGlyph>(repeating: 0, count: characters.count)
            let coreFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
            XCTAssertTrue(CTFontGetGlyphsForCharacters(coreFont, characters, &glyphs, characters.count))
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
                    domainKey: domain.rawValue, title: domain == .expense ? "示例咖啡店" : domain.title,
                    subtitle: "", value: domain == .expense ? "¥42.00" : "",
                    timeLabel: "12:30", systemImage: domain.systemImage, status: "done"
                )
                let detail = NativeRecordDetail(
                    id: record.reference, rawId: record.id, kind: domain == .expense ? "expense" : "data",
                    title: record.title, subtitle: "", value: record.value, detailRows: [], imageURL: nil,
                    imageLoadError: false, imagePath: nil, imageHash: nil,
                    amount: domain == .expense ? 42 : nil, merchantName: domain == .expense ? record.title : nil,
                    platform: nil, category: nil, paymentMethod: nil, recordDate: date, note: nil,
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
            }
        }
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

    func testIOSV2POLISH007ExportAllFiveOnboardingSteps() async throws {
        let sizes: [DynamicTypeSize] = [.large, .accessibility3]
        for size in sizes {
            for step in OnboardingStep.allCases {
            let view = OnboardingFlowView(initialStep: step)
                .environmentObject(try makeIsolatedState())
                .environment(\.dynamicTypeSize, size)
            try await capture(view, name: "onboarding-\(step)-\(size)", height: 844)
            }
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
            let view = ZStack {
                DomainSceneView(domain: .food)
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
        _ = try profiles.activeProfile()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return AppState(
            localExpenseUseCase: LocalExpenseUseCase(profileStore: profiles, repository: try LocalExpenseRepository(database: database)),
            localRecordUseCase: LocalRecordUseCase(profileStore: profiles, repository: try LocalRecordRepository(database: database)),
            localFactReader: try LocalFactReader(database: database),
            localBindingRepository: profiles,
            sessionProvider: { _ in throw NSError(domain: "synthetic-capture-no-session", code: 1) }
        )
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
