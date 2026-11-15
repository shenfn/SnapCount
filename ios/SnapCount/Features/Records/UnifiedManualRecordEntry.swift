import SwiftUI

/// A single entry point that keeps the shell unified while each data capability
/// uses its current persistence-backed form until LOCAL-003B completes the merge.
struct UnifiedManualRecordEntry: View {
    @EnvironmentObject private var appState: AppState
    let domain: AppDomain
    @State private var workspaceReady = false
    @State private var draftAccountID: UUID?

    init(domain: AppDomain = .expense) {
        self.domain = domain
    }

    var body: some View {
        Group {
            if domain != .expense {
                ManualRecordSheet(kind: .universal, domainKey: domain.rawValue)
            } else if appState.isSignedIn {
                ManualRecordSheet()
            } else if !workspaceReady {
                ProgressView("正在准备本机数据…")
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else if appState.localAccounts.isEmpty {
                LocalAccountPreparationView { account in
                    draftAccountID = account.id
                }
            } else {
                LocalExpenseEntryView(
                    accounts: appState.localAccounts,
                    initialAccountID: draftAccountID
                )
            }
        }
        .task {
            if domain == .expense, !appState.isSignedIn {
                _ = await appState.prepareLocalWorkspace()
            }
            workspaceReady = true
        }
    }
}
