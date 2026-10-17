import SwiftUI

/// 域页展示模型（IOS-V2-SHELL-005）：空态判定与记账 hero 口径抽成纯函数，便于特征测试。
///
/// 口径（拍板 1b / 2026-10-17 确认单）：
/// - 记账域空态 = 本月收支均为零（monthExpense == 0 && monthIncome == 0）；
/// - 其余四域空态 = 当月正式记录中对应域的数量为零，不使用可能陈旧的领域定义计数；
/// - 记账 hero 永远显示收支两行，空态时不显示 hero。
struct NativeDomainPageModel {
    let showsFinanceHero: Bool
    let showsContentEmptyState: Bool
    let monthExpense: Double
    let monthIncome: Double
    let domainRecordCount: Int

    static func make(domain: AppDomain, dashboard: DashboardSnapshot) -> Self {
        let records = NativeRecordQuery(monthKey: NativeMonthKey.current())
            .groups(from: dashboard.dayRecordGroups)
            .flatMap(\.records)
        let domainRecordCount = records.filter {
            ($0.domainKey ?? $0.kind.rawValue) == domain.legacyDomainKey
        }.count
        let financeEmpty = dashboard.monthExpense == 0 && dashboard.monthIncome == 0
        switch domain {
        case .expense:
            return .init(
                showsFinanceHero: !financeEmpty,
                showsContentEmptyState: financeEmpty,
                monthExpense: dashboard.monthExpense,
                monthIncome: dashboard.monthIncome,
                domainRecordCount: dashboard.monthCount
            )
        case .sleep, .food, .sport, .reading:
            return .init(
                showsFinanceHero: false,
                showsContentEmptyState: domainRecordCount == 0,
                monthExpense: dashboard.monthExpense,
                monthIncome: dashboard.monthIncome,
                domainRecordCount: domainRecordCount
            )
        }
    }
}

/// 五域骨架的域页（IOS-V2-SHELL-001/005）：
/// 记账域 hero 为本月收支两行（支出主值 + 收入次值）；其余四域骨架期只有本月记录数概要，
/// 记录列表为下一阶段域页内容工程（见《五域骨架Shell规格说明》已知边界）。
struct NativeDomainPageView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var themeManager: JieziThemeManager
    let domain: AppDomain
    @State private var showManualRecordSheet = false

    private var model: NativeDomainPageModel {
        NativeDomainPageModel.make(domain: domain, dashboard: appState.dashboard)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: JieziSpacing.lg) {
                Text(domain.title)
                    .font(JieziType.display)
                    .foregroundStyle(themeManager.palette.ink)

                if domain == .expense, model.showsFinanceHero {
                    financeHero
                } else if domain != .expense, !model.showsContentEmptyState {
                    domainSummary
                }

                if model.showsContentEmptyState {
                    JieziEmptyState(
                        systemImage: domain.systemImage,
                        title: "还没有\(domain.title)记录",
                        message: "通过快捷指令截图识别，或点下方按钮手动记录。",
                        actionTitle: "记一笔",
                        action: { showManualRecordSheet = true }
                    )
                } else if domain != .expense {
                    // ponytail: 骨架期占位，上限 = 域页内容工程（观察行/时间线）上线后移除。
                    domainPlaceholder
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, JieziSpacing.lg)
            .padding(.top, 68)
            .padding(.bottom, 104)
        }
        .sheet(isPresented: $showManualRecordSheet) {
            manualRecordSheet
        }
    }

    // MARK: - 记账 hero（收支两行，拍板 1b）

    private var financeHero: some View {
        JieziCard {
            VStack(alignment: .leading, spacing: JieziSpacing.sm) {
                Text("本月收支")
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(themeManager.palette.ink)

                HStack(alignment: .firstTextBaseline, spacing: JieziSpacing.xl) {
                    VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                        Text("支出")
                            .font(JieziFont.caption)
                            .foregroundStyle(themeManager.palette.muted)
                        Text("¥\(String(format: "%.2f", model.monthExpense))")
                            .font(JieziType.moneyHero.monospacedDigit())
                            .foregroundStyle(themeManager.palette.ink)
                    }
                    VStack(alignment: .leading, spacing: JieziSpacing.xxs) {
                        Text("收入")
                            .font(JieziFont.caption)
                            .foregroundStyle(themeManager.palette.muted)
                        Text("¥\(String(format: "%.2f", model.monthIncome))")
                            .font(JieziType.moneyCard.monospacedDigit())
                            .foregroundStyle(themeManager.palette.brand)
                    }
                }
            }
        }
    }

    // MARK: - 非记账域概要与占位

    private var domainSummary: some View {
        JieziCard {
            HStack {
                Text("本月记录")
                    .font(JieziType.sectionTitle)
                    .foregroundStyle(themeManager.palette.ink)
                Spacer()
                Text("\(model.domainRecordCount) 条")
                    .font(JieziType.moneyCard.monospacedDigit())
                    .foregroundStyle(themeManager.palette.brand)
            }
        }
    }

    private var domainPlaceholder: some View {
        JieziCard {
            VStack(alignment: .leading, spacing: JieziSpacing.xs) {
                Text("记录明细即将上线")
                    .font(JieziFont.body)
                    .foregroundStyle(themeManager.palette.ink)
                Text("本域本月共 \(model.domainRecordCount) 条记录，明细列表在后续版本中开放。")
                    .font(JieziFont.caption)
                    .foregroundStyle(themeManager.palette.muted)
            }
        }
    }

    // MARK: - 记一笔入口（SHELL-005）

    @ViewBuilder
    private var manualRecordSheet: some View {
        if domain == .expense {
            UnifiedManualRecordEntry()
        } else {
            ManualRecordSheet(kind: .universal, domainKey: domain.rawValue)
        }
    }
}
