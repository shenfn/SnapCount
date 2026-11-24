import SwiftUI

/// 统一手动录入入口：无论是否登录、无论从哪个域进入，一律走同一套五域原位录入体验。
struct UnifiedManualRecordEntry: View {
    @EnvironmentObject private var appState: AppState
    let domain: AppDomain

    init(domain: AppDomain = .expense) {
        self.domain = domain
    }

    var body: some View {
        Group {
            if domain == .expense {
                ManualRecordSheet(kind: .expense, domainKey: "expense")
            } else {
                ManualRecordSheet(kind: .universal, domainKey: domain.rawValue)
            }
        }
    }
}
