import SwiftUI

struct AccountsView: View {
    @EnvironmentObject private var appState: AppState
    private var activeAccounts:[NativeAccount]{appState.accounts.filter{!$0.isArchived}}
    private var assetAccounts:[NativeAccount]{activeAccounts.filter{!$0.type.isLiability}}
    private var liabilityAccounts:[NativeAccount]{activeAccounts.filter{$0.type.isLiability}}
    var body: some View {
        ZStack { JieziTheme.pageBackground.ignoresSafeArea(); List {
            if appState.isLoadingAccounts && appState.accounts.isEmpty { ProgressView("正在加载账户…").frame(maxWidth:.infinity) }
            if let message=appState.accountMessage,appState.accounts.isEmpty { Button("加载失败，点此重试：\(message)"){Task{await appState.loadAccounts()}}.foregroundStyle(JieziTheme.coral) }
            if !assetAccounts.isEmpty { Section("资产账户") { ForEach(assetAccounts){account in NavigationLink(value:account.id){AccountRowView(account:account)}} } }
            if !liabilityAccounts.isEmpty { Section("负债与待还") { ForEach(liabilityAccounts){account in NavigationLink(value:account.id){AccountRowView(account:account)}} } }
            let archived=appState.accounts.filter(\.isArchived);if !archived.isEmpty { Section("已归档") { ForEach(archived){AccountRowView(account:$0).foregroundStyle(.secondary)} } }
            if !appState.isLoadingAccounts && appState.accounts.isEmpty && appState.accountMessage == nil { ContentUnavailableView("暂无账户",systemImage:"wallet.pass",description:Text("PWA 中已有的账户会显示在这里。")) }
        }.scrollContentBackground(.hidden).refreshable{await appState.loadAccounts()} }
        .navigationTitle("账户与钱包")
        .navigationDestination(for:String.self){id in if let account=appState.accounts.first(where:{$0.id==id}){AccountDetailView(account:account)} }
        .task{if appState.accounts.isEmpty{await appState.loadAccounts()}}
    }
}
private struct AccountRowView:View{let account:NativeAccount;var body:some View{HStack(spacing:12){Image(systemName:account.type.systemImage).foregroundStyle(account.type.isLiability ? JieziTheme.coral:JieziTheme.brand).frame(width:34,height:34).background(.thinMaterial,in:RoundedRectangle(cornerRadius:10));VStack(alignment:.leading){Text(account.title).font(.subheadline.weight(.semibold));Text(account.type.title + (account.institution.isEmpty ? "":" · \(account.institution)")).font(.caption).foregroundStyle(.secondary)};Spacer();Text(String(format:"¥%.2f",account.currentBalance)).font(.subheadline.monospacedDigit())}}}

private struct AccountDetailView:View{
    @EnvironmentObject private var appState:AppState;let account:NativeAccount
    var detail:NativeAccountDetail?{appState.selectedAccountDetail?.account.id==account.id ? appState.selectedAccountDetail:nil}
    var body:some View{ZStack{JieziTheme.pageBackground.ignoresSafeArea();List{
        Section{VStack(alignment:.leading,spacing:8){Text(account.type.isLiability ? "当前待还":"当前余额").font(.caption).foregroundStyle(.secondary);Text(String(format:"¥%.2f",account.currentBalance)).font(.largeTitle.bold().monospacedDigit());Text(account.type.title + (account.institution.isEmpty ? "":" · \(account.institution)")).foregroundStyle(.secondary)}}
        if account.type.isLiability { Section("还款设置"){LabeledContent("账单日",value:account.billDay.map{"每月\($0)日"} ?? "未设置");LabeledContent("还款日",value:account.paymentDueDay.map{"每月\($0)日"} ?? "未设置");LabeledContent("自动确认",value:account.autoConfirmRepayment ? "已开启":"需手动确认")} }
        if let cycles=detail?.repaymentCycles,!cycles.isEmpty { Section("还款计划"){ForEach(cycles){cycle in VStack(alignment:.leading,spacing:4){HStack{Text(cycle.cycleMonth).font(.subheadline.weight(.semibold));Spacer();Text(cycle.status.title).font(.caption).foregroundStyle(.secondary)};Text("应还 ¥\(cycle.statementAmount.formatted(.number.precision(.fractionLength(2)))) · 剩余 ¥\(cycle.remainingAmount.formatted(.number.precision(.fractionLength(2))))").font(.caption).foregroundStyle(.secondary)}}} }
        if let detail { Section("账户概览"){LabeledContent("初始余额",value:String(format:"¥%.2f",account.initialBalance));LabeledContent("有效流水",value:"\(detail.entries.filter{!$0.isVoided}.count) 条");LabeledContent("有效净额",value:String(format:"%+.2f",detail.entries.filter{!$0.isVoided}.reduce(0){$0 + ($1.direction == "in" ? $1.amount : -$1.amount)}))} }
        if let entries=detail?.entries,!entries.isEmpty { Section("账户流水"){ForEach(entries){entry in HStack{VStack(alignment:.leading){Text(entry.note.isEmpty ? entry.entryType:entry.note).font(.subheadline);Text(entry.occurredAt).font(.caption2).foregroundStyle(.secondary)};Spacer();Text((entry.direction=="in" ? "+":"-")+String(format:"¥%.2f",entry.amount)).foregroundStyle(entry.isVoided ? .secondary:(entry.direction=="in" ? JieziTheme.mint:JieziTheme.coral)).strikethrough(entry.isVoided)}}} }
        if let payments=detail?.payments,!payments.isEmpty { Section("还款记录"){ForEach(payments){payment in HStack{VStack(alignment:.leading){Text(payment.status == "voided" ? "已撤销还款":"已确认还款").font(.subheadline);Text(payment.paidAt + (payment.note.isEmpty ? "":" · \(payment.note)")).font(.caption2).foregroundStyle(.secondary)};Spacer();Text(String(format:"¥%.2f",payment.amount)).strikethrough(payment.status == "voided").foregroundStyle(payment.status == "voided" ? .secondary:JieziTheme.brand)}}} }
        if detail == nil { ProgressView("正在加载账户详情…").frame(maxWidth:.infinity) }
    }.scrollContentBackground(.hidden)}.navigationTitle(account.title).task{await appState.loadAccountDetail(account)}}
}
