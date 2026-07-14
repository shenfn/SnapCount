import Foundation

enum NativeAccountType: String, Codable, CaseIterable {
    case cash, walletBalance = "wallet_balance", debitCard = "debit_card", creditCard = "credit_card", creditLine = "credit_line", other
    var isLiability: Bool { self == .creditCard || self == .creditLine }
    var title: String { switch self { case .cash:return "现金";case .walletBalance:return "钱包余额";case .debitCard:return "储蓄卡";case .creditCard:return "信用卡";case .creditLine:return "信用额度";case .other:return "其他" } }
    var systemImage: String { isLiability ? "creditcard.fill" : "wallet.pass.fill" }

    static func normalized(_ value: String) -> NativeAccountType {
        if let type = NativeAccountType(rawValue: value) { return type }
        switch value {
        case "wechat", "alipay", "balance": return .walletBalance
        case "bank_card", "bank", "debit": return .debitCard
        case "huabei", "jd_baitiao", "douyin_monthly": return .creditLine
        default: return .other
        }
    }
}

enum NativeRepaymentStatus: String, Codable, CaseIterable {
    case draftEstimated = "draft_estimated"
    case pending
    case dueToday = "due_today"
    case overdueUnconfirmed = "overdue_unconfirmed"
    case partialPaid = "partial_paid"
    case minimumPaid = "minimum_paid"
    case paid
    case ignored
    case carriedOver = "carried_over"
    case historicalUnconfirmed = "historical_unconfirmed"
    case reconciled
    case replaced
    case reopened

    var title: String {
        switch self {
        case .draftEstimated: return "系统估算"
        case .pending: return "待还"
        case .dueToday: return "今日到期"
        case .overdueUnconfirmed: return "逾期未确认"
        case .partialPaid: return "部分已还"
        case .minimumPaid: return "已还最低"
        case .paid: return "已还清"
        case .ignored: return "已忽略"
        case .carriedOver: return "已结转"
        case .historicalUnconfirmed: return "历史待确认"
        case .reconciled: return "已对账"
        case .replaced: return "已被替代"
        case .reopened: return "重新估算中"
        }
    }

    var allowsManualRepayment: Bool {
        [.pending, .dueToday, .overdueUnconfirmed, .partialPaid, .carriedOver].contains(self)
    }
}

struct NativeAccount: Identifiable {
    let id:String;let name:String;let type:NativeAccountType;let institution:String;let last4:String;let currency:String
    let initialBalance:Double;let currentBalance:Double;let snapshotBalance:Double?;let snapshotAt:String?
    let sourceRecordTable:String;let sourceRecordId:String;let billDay:Int?;let paymentDueDay:Int?;let autoDebitAccountId:String?
    let autoConfirmRepayment:Bool;let gracePeriodDays:Int;let lastReconciledAt:String?;let isDefaultExpense:Bool;let isDefaultIncome:Bool;let isArchived:Bool;let sortOrder:Int
    var title:String { last4.isEmpty ? name : "\(name)（\(last4)）" }
}

struct NativeAccountEntry: Identifiable { let id:String;let accountId:String;let direction:String;let amount:Double;let entryType:String;let sourceTable:String;let sourceId:String;let occurredAt:String;let note:String;let isVoided:Bool;let voidedReason:String }
struct NativeRepaymentCycle: Identifiable { let id:String;let accountId:String;let cycleMonth:String;let statementStartDate:String?;let statementEndDate:String?;let dueDate:String?;let statementAmount:Double;let paidAmount:Double;let remainingAmount:Double;let carriedOverAmount:Double;let originalStatementAmount:Double?;let minPaymentAmount:Double?;let refundAppliedAmount:Double;let status:NativeRepaymentStatus;let autoDebitAccountId:String?;let autoConfirmRepayment:Bool;let source:String;let evidenceRecordId:String?;let confidence:Double?;let note:String;let confirmedAt:String? }
struct NativeLiabilityPayment: Identifiable { let id:String;let accountId:String;let statementId:String?;let debitAccountId:String?;let amount:Double;let overpaymentAmount:Double;let paidAt:String;let source:String;let evidenceRecordId:String?;let status:String;let note:String }
struct NativeAccountDetail { let account:NativeAccount;let entries:[NativeAccountEntry];let repaymentCycles:[NativeRepaymentCycle];let payments:[NativeLiabilityPayment] }

enum NativeRepaymentCalculator {
    static func status(
        paidAmount: Double,
        remainingAmount: Double,
        minimumPaymentAmount: Double?
    ) -> NativeRepaymentStatus {
        if paidAmount >= remainingAmount { return .paid }
        if let minimumPaymentAmount, paidAmount >= minimumPaymentAmount { return .minimumPaid }
        return .partialPaid
    }

    static func overpayment(paidAmount: Double, currentBalance: Double) -> Double {
        max(paidAmount - currentBalance, 0)
    }
}

struct NativeAccountDraft: Identifiable, Equatable {
    let accountId: String?
    var name: String
    var type: NativeAccountType
    var institution: String
    var last4: String
    var initialBalanceText: String
    var billDayText: String
    var paymentDueDayText: String
    var autoDebitAccountId: String?
    var autoConfirmRepayment: Bool
    var isDefaultExpense: Bool
    var isDefaultIncome: Bool
    var isArchived: Bool

    var id: String { accountId ?? "new-account" }
    var isCreating: Bool { accountId == nil }

    init(account: NativeAccount? = nil) {
        accountId = account?.id
        name = account?.name ?? ""
        type = account?.type ?? .walletBalance
        institution = account?.institution ?? ""
        last4 = account?.last4 ?? ""
        initialBalanceText = account.map { String(format: "%.2f", $0.initialBalance) } ?? ""
        billDayText = account?.billDay.map(String.init) ?? ""
        paymentDueDayText = account?.paymentDueDay.map(String.init) ?? ""
        autoDebitAccountId = account?.autoDebitAccountId
        autoConfirmRepayment = account?.autoConfirmRepayment ?? false
        isDefaultExpense = account?.isDefaultExpense ?? false
        isDefaultIncome = account?.isDefaultIncome ?? false
        isArchived = account?.isArchived ?? false
    }

    var validationMessage: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedName.isEmpty { return "请输入账户名称" }
        if trimmedName.count > 30 { return "账户名称最多 30 个字" }
        if !last4.isEmpty && last4.range(of: #"^\d{4}$"#, options: .regularExpression) == nil {
            return "尾号必须是 4 位数字"
        }
        if isCreating, !initialBalanceText.isEmpty, Double(initialBalanceText) == nil {
            return "初始余额必须是数字"
        }
        if type.isLiability {
            if let message = dayValidationMessage(billDayText, label: "账单日") { return message }
            if let message = dayValidationMessage(paymentDueDayText, label: "还款日") { return message }
        }
        return nil
    }

    private func dayValidationMessage(_ text: String, label: String) -> String? {
        guard !text.isEmpty else { return nil }
        guard let day = Int(text), (1...31).contains(day) else {
            return "\(label)必须是 1-31 之间的整数"
        }
        return nil
    }
}
