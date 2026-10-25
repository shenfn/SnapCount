import XCTest
@testable import SnapCount

final class LocalUserSettingsStoreTests: XCTestCase {
    func testLF01901OrdinaryPreferencesSurviveReopeningWithoutAccountOrConsent() throws {
        let suite = "LocalUserSettingsStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var settings = NativeUserSettings()
        settings.plan = "pro"
        settings.companionEnabled = false
        settings.companionPersona = "warm"
        settings.companionCustomNote = "合成偏好"
        settings.expressionImprovementEnabled = true
        settings.aiLogsEnabled = true
        LocalUserSettingsStore(defaults: defaults).save(settings)
        let restored = LocalUserSettingsStore(defaults: defaults).load()
        XCTAssertFalse(restored.companionEnabled)
        XCTAssertEqual(restored.companionPersona, "warm")
        XCTAssertEqual(restored.companionCustomNote, "合成偏好")
        XCTAssertEqual(restored.plan, "free")
        XCTAssertFalse(restored.expressionImprovementEnabled)
        XCTAssertFalse(restored.aiLogsEnabled)
        settings.companionMemoryEnabled = false
        settings.keepSourceImages = false
        LocalUserSettingsStore(defaults: defaults).saveExplicitConsent(settings, keys: ["companion_memory_enabled", "keep_source_images"])
        let consent = LocalUserSettingsStore(defaults: defaults).load()
        XCTAssertFalse(consent.companionMemoryEnabled)
        XCTAssertFalse(consent.keepSourceImages)
        XCTAssertFalse(consent.expressionImprovementEnabled, "an unrelated setting must not import consent")
    }
}
