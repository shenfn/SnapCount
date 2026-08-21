import Foundation

protocol AccountRepositoryProtocol {
    func fetchAccounts(accessToken:String) async throws -> [NativeAccount]
    func fetchDetail(account:NativeAccount, accessToken:String) async -> NativeAccountDetail
    func fetchOpenRepaymentCycles(accessToken: String) async throws -> [NativeRepaymentCycle]
    func save(_ draft: NativeAccountDraft, userId: String, accessToken: String) async throws -> [NativeAccount]
    func setArchived(accountId: String, archived: Bool, accessToken: String) async throws -> [NativeAccount]
    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws
    func confirmRepayment(
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle
    func revokePayment(paymentId: String, accessToken: String) async throws -> NativeRepaymentCycle?
}

protocol AccountManagementRepositoryProtocol {
    func saveAccount(
        _ command: AccountManagementSaveCommand,
        accessToken: String
    ) async throws -> NativeAccount
    func setAccountArchived(
        accountId: String,
        archived: Bool,
        accessToken: String
    ) async throws -> NativeAccount
}

final class AccountRepository: AccountRepositoryProtocol, AccountManagementRepositoryProtocol, AccountReadPreparationRepositoryProtocol {
    private let remoteClient:SupabaseRemoteClientProtocol
    init(remoteClient:SupabaseRemoteClientProtocol=SupabaseRemoteClient()){self.remoteClient=remoteClient}

    func fetchAccounts(accessToken:String) async throws -> [NativeAccount] {
        let rows=try await remoteClient.get([AccountRow].self,path:"rest/v1/accounts",queryItems:[URLQueryItem(name:"select",value:"*"),URLQueryItem(name:"order",value:"sort_order.asc,created_at.asc")],accessToken:accessToken)
        return rows.compactMap(\.native)
    }

    func fetchDetail(account:NativeAccount, accessToken:String) async -> NativeAccountDetail {
        async let entriesResult = section { try await self.fetchEntries(account.id, accessToken:accessToken) }
        async let cyclesResult = section { try await self.fetchCycles(account.id, accessToken:accessToken) }
        async let paymentsResult = section { try await self.fetchPayments(account.id, accessToken:accessToken) }
        let (entries, cycles, payments) = await (entriesResult, cyclesResult, paymentsResult)
        var errors: [NativeAccountDetailSection: String] = [:]
        if let error = entries.error { errors[.entries] = error }
        if let error = cycles.error { errors[.repaymentCycles] = error }
        if let error = payments.error { errors[.payments] = error }
        return NativeAccountDetail(
            account: account,
            entries: entries.value ?? [],
            repaymentCycles: cycles.value ?? [],
            payments: payments.value ?? [],
            loadErrors: errors
        )
    }

    func fetchOpenRepaymentCycles(accessToken: String) async throws -> [NativeRepaymentCycle] {
        let statuses = [
            NativeRepaymentStatus.pending,
            .dueToday,
            .overdueUnconfirmed,
            .partialPaid,
            .minimumPaid,
            .carriedOver
        ].map(\.rawValue).joined(separator: ",")
        let rows = try await remoteClient.get(
            [RepaymentCycleRow].self,
            path: "rest/v1/account_repayment_cycles",
            queryItems: [
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "status", value: "in.(\(statuses))"),
                URLQueryItem(name: "order", value: "due_date.asc.nullslast,created_at.desc")
            ],
            accessToken: accessToken
        )
        return rows.compactMap(\.native)
    }

    func save(_ draft: NativeAccountDraft, userId: String, accessToken: String) async throws -> [NativeAccount] {
        guard let initialBalance = Double(draft.initialBalanceText.isEmpty ? "0" : draft.initialBalanceText) else {
            throw SupabaseRemoteError.requestFailed("初始余额必须是数字")
        }
        let command = AccountManagementSaveCommand(
            accountId: draft.accountId,
            name: draft.name,
            type: draft.type,
            institution: draft.institution,
            last4: draft.last4,
            initialBalance: initialBalance,
            billDay: Int(draft.billDayText),
            paymentDueDay: Int(draft.paymentDueDayText),
            autoDebitAccountId: draft.autoDebitAccountId,
            autoConfirmRepayment: draft.autoConfirmRepayment,
            isDefaultExpense: draft.isDefaultExpense,
            isDefaultIncome: draft.isDefaultIncome
        )
        _ = try await saveAccount(command, accessToken: accessToken)
        return try await fetchAccounts(accessToken: accessToken)
    }

    func setArchived(accountId: String, archived: Bool, accessToken: String) async throws -> [NativeAccount] {
        _ = try await setAccountArchived(
            accountId: accountId,
            archived: archived,
            accessToken: accessToken
        )
        return try await fetchAccounts(accessToken: accessToken)
    }

    func saveAccount(
        _ command: AccountManagementSaveCommand,
        accessToken: String
    ) async throws -> NativeAccount {
        guard command.validationMessage == nil else {
            throw SupabaseRemoteError.requestFailed(command.validationMessage ?? "invalid_account_data")
        }
        do {
            let row = try await remoteClient.rpc(
                AccountRow.self,
                name: "save_account",
                body: [
                    "p_name": AnyCodable(command.name.trimmingCharacters(in: .whitespacesAndNewlines)),
                    "p_type": AnyCodable(command.type.rawValue),
                    "p_account_id": AnyCodable(nullableString(command.accountId)),
                    "p_institution": AnyCodable(nullableString(command.institution)),
                    "p_last4": AnyCodable(nullableString(command.last4)),
                    "p_initial_balance": AnyCodable(command.initialBalance),
                    "p_bill_day": AnyCodable(nullableInt(command.billDay)),
                    "p_payment_due_day": AnyCodable(nullableInt(command.paymentDueDay)),
                    "p_auto_debit_account_id": AnyCodable(nullableString(command.autoDebitAccountId)),
                    "p_auto_confirm_repayment": AnyCodable(command.type.isLiability && command.autoConfirmRepayment),
                    "p_is_default_expense": AnyCodable(command.isDefaultExpense),
                    "p_is_default_income": AnyCodable(command.isDefaultIncome)
                ],
                accessToken: accessToken
            )
            guard let account = row.native else {
                throw SupabaseRemoteError.requestFailed("invalid_response")
            }
            return account
        } catch is DecodingError {
            throw SupabaseRemoteError.requestFailed("invalid_response")
        }
    }

    func setAccountArchived(
        accountId: String,
        archived: Bool,
        accessToken: String
    ) async throws -> NativeAccount {
        do {
            let row = try await remoteClient.rpc(
                AccountRow.self,
                name: "set_account_archived",
                body: [
                    "p_account_id": AnyCodable(accountId),
                    "p_archived": AnyCodable(archived)
                ],
                accessToken: accessToken
            )
            guard let account = row.native else {
                throw SupabaseRemoteError.requestFailed("invalid_response")
            }
            return account
        } catch is DecodingError {
            throw SupabaseRemoteError.requestFailed("invalid_response")
        }
    }

    func ensureRepaymentCycles(monthKey: String, accessToken: String) async throws {
        _ = try await remoteClient.rpc(
            [RepaymentCycleRow].self,
            name: "ensure_liability_repayment_cycles",
            body: ["p_cycle_month": AnyCodable(monthKey)],
            accessToken: accessToken
        )
    }

    func confirmRepayment(
        cycleId: String,
        paidAmount: Double,
        debitAccountId: String?,
        status: NativeRepaymentStatus,
        note: String,
        accessToken: String
    ) async throws -> NativeRepaymentCycle {
        guard paidAmount > 0 else {
            throw SupabaseRemoteError.requestFailed("请输入有效的还款金额")
        }
        let row = try await remoteClient.rpc(
            RepaymentCycleRow.self,
            name: "set_repayment_cycle_paid_amount",
            body: [
                "p_cycle_id": AnyCodable(cycleId),
                "p_paid_amount": AnyCodable(paidAmount),
                "p_paid_at": AnyCodable(ISO8601DateFormatter().string(from: Date())),
                "p_debit_account_id": AnyCodable(nullableString(debitAccountId)),
                "p_status": AnyCodable(status.rawValue),
                "p_note": AnyCodable(note)
            ],
            accessToken: accessToken
        )
        guard let cycle = row.native else {
            throw SupabaseRemoteError.requestFailed("服务端返回了无法识别的还款状态")
        }
        return cycle
    }

    func revokePayment(paymentId: String, accessToken: String) async throws -> NativeRepaymentCycle? {
        let row = try await remoteClient.rpc(
            RepaymentCycleRow?.self,
            name: "revoke_liability_payment",
            body: [
                "p_payment_id": AnyCodable(paymentId),
                "p_reason": AnyCodable("用户撤销还款")
            ],
            accessToken: accessToken
        )
        return row?.native
    }

    private func nullableString(_ value: String?) -> Any {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return NSNull() }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func nullableInt(_ value: String) -> Any {
        guard let value = Int(value) else { return NSNull() }
        return value
    }

    private func nullableInt(_ value: Int?) -> Any {
        value ?? NSNull()
    }

    private func fetchEntries(_ accountId:String,accessToken:String) async throws -> [NativeAccountEntry] {
        let rows = try await remoteClient.get([AccountEntryRow].self,path:"rest/v1/account_entries",queryItems:[URLQueryItem(name:"select",value:"*"),URLQueryItem(name:"account_id",value:"eq.\(accountId)"),URLQueryItem(name:"order",value:"occurred_at.desc,created_at.desc"),URLQueryItem(name:"limit",value:"50")],accessToken:accessToken)
        return rows.map(\.native)
    }
    private func fetchCycles(_ accountId:String,accessToken:String) async throws -> [NativeRepaymentCycle] {
        let rows = try await remoteClient.get([RepaymentCycleRow].self,path:"rest/v1/account_repayment_cycles",queryItems:[URLQueryItem(name:"select",value:"*"),URLQueryItem(name:"account_id",value:"eq.\(accountId)"),URLQueryItem(name:"order",value:"due_date.desc.nullslast,created_at.desc"),URLQueryItem(name:"limit",value:"24")],accessToken:accessToken)
        return rows.compactMap(\.native)
    }
    private func fetchPayments(_ accountId:String,accessToken:String) async throws -> [NativeLiabilityPayment] {
        let rows = try await remoteClient.get([LiabilityPaymentRow].self,path:"rest/v1/liability_payments",queryItems:[URLQueryItem(name:"select",value:"*"),URLQueryItem(name:"account_id",value:"eq.\(accountId)"),URLQueryItem(name:"order",value:"paid_at.desc,created_at.desc"),URLQueryItem(name:"limit",value:"30")],accessToken:accessToken)
        return rows.map(\.native)
    }

    private func section<Value>(_ operation: () async throws -> Value) async -> AccountDetailSectionResult<Value> {
        do {
            return AccountDetailSectionResult(value: try await operation(), error: nil)
        } catch {
            return AccountDetailSectionResult(value: nil, error: error.localizedDescription)
        }
    }
}

private struct AccountDetailSectionResult<Value> {
    let value: Value?
    let error: String?
}

private struct AccountRow:Decodable {
    let id:String,name:String,type:String,institution:String?,last4:String?,currency:String?,initialBalance:Double?,currentBalance:Double?,snapshotBalance:Double?,snapshotAt:String?,sourceRecordTable:String?,sourceRecordId:String?,billDay:Int?,paymentDueDay:Int?,autoDebitAccountId:String?,autoConfirmRepayment:Bool?,gracePeriodDays:Int?,lastReconciledAt:String?,isDefaultExpense:Bool?,isDefaultIncome:Bool?,isArchived:Bool?,sortOrder:Int?
    enum CodingKeys:String,CodingKey{case id,name,type,institution,last4,currency;case initialBalance="initial_balance",currentBalance="current_balance",snapshotBalance="snapshot_balance",snapshotAt="snapshot_at",sourceRecordTable="source_record_table",sourceRecordId="source_record_id",billDay="bill_day",paymentDueDay="payment_due_day",autoDebitAccountId="auto_debit_account_id",autoConfirmRepayment="auto_confirm_repayment",gracePeriodDays="grace_period_days",lastReconciledAt="last_reconciled_at",isDefaultExpense="is_default_expense",isDefaultIncome="is_default_income",isArchived="is_archived",sortOrder="sort_order"}
    var native:NativeAccount?{let type=NativeAccountType.normalized(type);return NativeAccount(id:id,name:name,type:type,institution:institution ?? "",last4:last4 ?? "",currency:currency ?? "CNY",initialBalance:initialBalance ?? 0,currentBalance:currentBalance ?? 0,snapshotBalance:snapshotBalance,snapshotAt:snapshotAt,sourceRecordTable:sourceRecordTable ?? "",sourceRecordId:sourceRecordId ?? "",billDay:billDay,paymentDueDay:paymentDueDay,autoDebitAccountId:autoDebitAccountId,autoConfirmRepayment:autoConfirmRepayment ?? false,gracePeriodDays:gracePeriodDays ?? 0,lastReconciledAt:lastReconciledAt,isDefaultExpense:isDefaultExpense ?? false,isDefaultIncome:isDefaultIncome ?? false,isArchived:isArchived ?? false,sortOrder:sortOrder ?? 0)}
}
private struct AccountEntryRow:Decodable {let id:String,accountId:String,direction:String,entryType:String,sourceTable:String?,sourceId:String?,occurredAt:String,note:String?,voidedReason:String?;let amount:Double;let isVoided:Bool?;enum CodingKeys:String,CodingKey{case id,direction,amount,note;case accountId="account_id",entryType="entry_type",sourceTable="source_table",sourceId="source_id",occurredAt="occurred_at",isVoided="is_voided",voidedReason="voided_reason"};var native:NativeAccountEntry{NativeAccountEntry(id:id,accountId:accountId,direction:direction,amount:amount,entryType:entryType,sourceTable:sourceTable ?? "",sourceId:sourceId ?? "",occurredAt:occurredAt,note:note ?? "",isVoided:isVoided ?? false,voidedReason:voidedReason ?? "")}}
struct RepaymentCycleRow:Decodable {let id:String,accountId:String,cycleMonth:String,statementStartDate:String?,statementEndDate:String?,dueDate:String?,status:String,autoDebitAccountId:String?,source:String?,evidenceRecordId:String?,note:String?,confirmedAt:String?;let statementAmount:Double?,paidAmount:Double?,remainingAmount:Double?,carriedOverAmount:Double?,originalStatementAmount:Double?,minPaymentAmount:Double?,refundAppliedAmount:Double?,confidence:Double?;let autoConfirmRepayment:Bool?;enum CodingKeys:String,CodingKey{case id,status,source,note,confidence;case accountId="account_id",cycleMonth="cycle_month",statementStartDate="statement_start_date",statementEndDate="statement_end_date",dueDate="due_date",statementAmount="statement_amount",paidAmount="paid_amount",remainingAmount="remaining_amount",carriedOverAmount="carried_over_amount",originalStatementAmount="original_statement_amount",minPaymentAmount="min_payment_amount",refundAppliedAmount="refund_applied_amount",autoDebitAccountId="auto_debit_account_id",autoConfirmRepayment="auto_confirm_repayment",evidenceRecordId="evidence_record_id",confirmedAt="confirmed_at"};var native:NativeRepaymentCycle?{guard let status=NativeRepaymentStatus(rawValue:status)else{return nil};return NativeRepaymentCycle(id:id,accountId:accountId,cycleMonth:cycleMonth,statementStartDate:statementStartDate,statementEndDate:statementEndDate,dueDate:dueDate,statementAmount:statementAmount ?? 0,paidAmount:paidAmount ?? 0,remainingAmount:remainingAmount ?? 0,carriedOverAmount:carriedOverAmount ?? 0,originalStatementAmount:originalStatementAmount,minPaymentAmount:minPaymentAmount,refundAppliedAmount:refundAppliedAmount ?? 0,status:status,autoDebitAccountId:autoDebitAccountId,autoConfirmRepayment:autoConfirmRepayment ?? false,source:source ?? "system",evidenceRecordId:evidenceRecordId,confidence:confidence,note:note ?? "",confirmedAt:confirmedAt)}}
private struct LiabilityPaymentRow:Decodable {let id:String,accountId:String,statementId:String?,debitAccountId:String?,paidAt:String,source:String?,evidenceRecordId:String?,status:String?,note:String?;let amount:Double?,overpaymentAmount:Double?;enum CodingKeys:String,CodingKey{case id,amount,source,status,note;case accountId="account_id",statementId="statement_id",debitAccountId="debit_account_id",overpaymentAmount="overpayment_amount",paidAt="paid_at",evidenceRecordId="evidence_record_id"};var native:NativeLiabilityPayment{NativeLiabilityPayment(id:id,accountId:accountId,statementId:statementId,debitAccountId:debitAccountId,amount:amount ?? 0,overpaymentAmount:overpaymentAmount ?? 0,paidAt:paidAt,source:source ?? "manual",evidenceRecordId:evidenceRecordId,status:status ?? "confirmed",note:note ?? "")}}
