import Foundation

enum NativeAccountType: String, Codable, CaseIterable {
    case cash, walletBalance = "wallet_balance", debitCard = "debit_card", creditCard = "credit_card", creditLine = "credit_line", other
    var isLiability: Bool { self == .creditCard || self == .creditLine }
    var title: String { switch self { case .cash:return "现金";case .walletBalance:return "钱包余额";case .debitCard:return "储蓄卡";case .creditCard:return "信用卡";case .creditLine:return "信用额度";case .other:return "其他" } }
    var systemImage: String { isLiability ? "creditcard.fill" : "wallet.pass.fill" }
}

enum NativeRepaymentStatus: String, Codable, CaseIterable {
    case pending, dueToday = "due_today", overdueUnconfirmed = "overdue_unconfirmed", partialPaid = "partial_paid", minimumPaid = "minimum_paid", paid, ignored, carriedOver = "carried_over", historicalUnconfirmed = "historical_unconfirmed"
    var title: String { switch self { case .pending:return "待还";case .dueToday:return "今日到期";case .overdueUnconfirmed:return "逾期未确认";case .partialPaid:return "部分已还";case .minimumPaid:return "已还最低";case .paid:return "已还清";case .ignored:return "已忽略";case .carriedOver:return "已结转";case .historicalUnconfirmed:return "历史待确认" } }
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
