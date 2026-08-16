import { mapAccountRow } from '../adapters/domain/accountAdapter.js'

function errorMessage(error) {
  return error?.message || String(error || '账户服务请求失败')
}

function accountWriteReason(error) {
  const message = errorMessage(error)
  if (/account_type_transition_blocked/i.test(message)) return 'account_type_transition_blocked'
  if (/invalid_auto_debit_account/i.test(message)) return 'invalid_auto_debit_account'
  if (/account_not_found|account not found|permission denied/i.test(message)) return 'account_not_found'
  return 'service_error'
}

export function mapAccountEntryRow(row = {}) {
  return {
    id: row.id,
    accountId: row.account_id,
    direction: row.direction,
    amount: Number(row.amount || 0),
    entryType: row.entry_type,
    sourceTable: row.source_table || '',
    sourceId: row.source_id || '',
    occurredAt: row.occurred_at,
    note: row.note || '',
    isVoided: !!row.is_voided,
    voidedReason: row.voided_reason || '',
    createdAt: row.created_at,
  }
}

export function mapLiabilityPaymentRow(row = {}) {
  return {
    id: row.id,
    accountId: row.account_id,
    statementId: row.statement_id || null,
    debitAccountId: row.debit_account_id || null,
    amount: Number(row.amount || 0),
    overpaymentAmount: Number(row.overpayment_amount || 0),
    paidAt: row.paid_at,
    source: row.source || 'manual',
    evidenceRecordId: row.evidence_record_id || null,
    status: row.status || 'confirmed',
    note: row.note || '',
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function firstRow(data) {
  return Array.isArray(data) ? data[0] : data
}

export function mapRepaymentCycleRow(row = {}) {
  return {
    id: row.id,
    userId: row.user_id,
    accountId: row.account_id,
    cycleMonth: row.cycle_month,
    statementStartDate: row.statement_start_date || null,
    statementEndDate: row.statement_end_date || null,
    dueDate: row.due_date || null,
    statementAmount: Number(row.statement_amount || 0),
    paidAmount: Number(row.paid_amount || 0),
    remainingAmount: Number(row.remaining_amount || 0),
    carriedOverAmount: Number(row.carried_over_amount || 0),
    originalStatementAmount: row.original_statement_amount == null ? null : Number(row.original_statement_amount),
    minPaymentAmount: row.min_payment_amount == null ? null : Number(row.min_payment_amount),
    refundAppliedAmount: Number(row.refund_applied_amount || 0),
    status: row.status || 'pending',
    autoDebitAccountId: row.auto_debit_account_id || null,
    autoConfirmRepayment: !!row.auto_confirm_repayment,
    source: row.source || 'system',
    evidenceRecordId: row.evidence_record_id || null,
    confidence: row.confidence == null ? null : Number(row.confidence),
    statementSourcePriority: Number(row.statement_source_priority || 0),
    note: row.note || '',
    confirmedAt: row.confirmed_at || null,
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

function failed(reason, error) {
  return { status: 'failed', reason, cycle: null, error: errorMessage(error) }
}

function readFailed(error) {
  return { status: 'failed', reason: 'service_error', rows: [], error: errorMessage(error) }
}

function readAccepted(rows, mapper) {
  return { status: 'accepted', reason: 'loaded', rows: (rows || []).map(mapper) }
}

function missingPaymentTable(error) {
  return error?.code === 'PGRST205'
    || /liability_payments|schema cache|Could not find the table/i.test(error?.message || '')
}

export function createAccountRepository({ client }) {
  if (typeof client?.rpc !== 'function') throw new Error('账户服务缺少 RPC 客户端')
  let paymentsAvailable = true

  async function listAccounts() {
    try {
      const { data, error } = await client.from('accounts')
        .select('*')
        .order('sort_order', { ascending: true })
        .order('created_at', { ascending: true })
      if (error) return readFailed(error)
      return readAccepted(data, mapAccountRow)
    } catch (error) {
      return readFailed(error)
    }
  }

  async function listAccountEntries({ accountId, limit = 50 } = {}) {
    try {
      const { data, error } = await client.from('account_entries')
        .select('*')
        .eq('account_id', accountId)
        .order('occurred_at', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error) return readFailed(error)
      return readAccepted(data, mapAccountEntryRow)
    } catch (error) {
      return readFailed(error)
    }
  }

  async function listAccountPayments({ accountId, limit = 30 } = {}) {
    if (!paymentsAvailable) {
      return { status: 'unavailable', reason: 'not_available', rows: [], error: '还款记录表尚不可用' }
    }
    try {
      const { data, error } = await client.from('liability_payments')
        .select('*')
        .eq('account_id', accountId)
        .order('paid_at', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error && missingPaymentTable(error)) {
        paymentsAvailable = false
        return { status: 'unavailable', reason: 'not_available', rows: [], error: errorMessage(error) }
      }
      if (error) return readFailed(error)
      return readAccepted(data, mapLiabilityPaymentRow)
    } catch (error) {
      return readFailed(error)
    }
  }

  async function listRepaymentCycles({ accountId, limit = 80 } = {}) {
    try {
      let query = client.from('account_repayment_cycles')
        .select('*')
      if (accountId) query = query.eq('account_id', accountId)
      const { data, error } = await query
        .order('due_date', { ascending: true, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(limit)
      if (error) return readFailed(error)
      return readAccepted(data, mapRepaymentCycleRow)
    } catch (error) {
      return readFailed(error)
    }
  }

  async function ensureRepaymentCycles({ cycleMonth } = {}) {
    try {
      const { error } = await client.rpc('ensure_liability_repayment_cycles', {
        p_cycle_month: cycleMonth,
      })
      if (error) return { status: 'failed', reason: 'service_error', error: errorMessage(error) }
      return { status: 'accepted', reason: 'ensured' }
    } catch (error) {
      return { status: 'failed', reason: 'service_error', error: errorMessage(error) }
    }
  }

  async function confirmRepayment(command = {}) {
    try {
      const { data, error } = await client.rpc('set_repayment_cycle_paid_amount', {
        p_cycle_id: command.cycleId,
        p_paid_amount: command.paidAmount,
        p_paid_at: command.paidAt || null,
        p_debit_account_id: command.debitAccountId || null,
        p_status: command.status || null,
        p_note: command.note || null,
      })
      if (error) return failed('service_error', error)
      const row = firstRow(data)
      if (!row?.id) return failed('invalid_response', '确认还款成功但未返回账单周期')
      return { status: 'accepted', reason: 'confirmed', cycle: mapRepaymentCycleRow(row) }
    } catch (error) {
      return failed('service_error', error)
    }
  }

  async function confirmStagingRepayment(command = {}) {
    try {
      const { data, error } = await client.rpc('confirm_staging_repayment', {
        p_staging_id: command.stagingId,
        p_cycle_id: command.cycleId,
        p_paid_amount: command.paidAmount,
        p_paid_at: command.paidAt || null,
        p_debit_account_id: command.debitAccountId || null,
        p_status: null,
        p_note: command.note || null,
      })
      if (error) return failed('service_error', error)
      const row = firstRow(data)
      if (!row?.id) return failed('invalid_response', '截图还款成功但未返回账单周期')
      return { status: 'accepted', reason: 'confirmed_from_screenshot', cycle: mapRepaymentCycleRow(row) }
    } catch (error) {
      return failed('service_error', error)
    }
  }

  async function revokePayment(command = {}) {
    try {
      const { data, error } = await client.rpc('revoke_liability_payment', {
        p_payment_id: command.paymentId,
        p_reason: command.reason || null,
      })
      if (error) return failed('service_error', error)
      const row = firstRow(data)
      return { status: 'accepted', reason: 'revoked', cycle: row?.id ? mapRepaymentCycleRow(row) : null }
    } catch (error) {
      return failed('service_error', error)
    }
  }

  async function saveAccount(command = {}) {
    try {
      const { data, error } = await client.rpc('save_account', {
        p_name: command.name,
        p_type: command.type,
        p_account_id: command.accountId || null,
        p_institution: command.institution || null,
        p_last4: command.last4 || null,
        p_initial_balance: command.initialBalance == null ? 0 : command.initialBalance,
        p_bill_day: command.billDay == null ? null : command.billDay,
        p_payment_due_day: command.paymentDueDay == null ? null : command.paymentDueDay,
        p_auto_debit_account_id: command.autoDebitAccountId || null,
        p_auto_confirm_repayment: !!command.autoConfirmRepayment,
        p_is_default_expense: !!command.isDefaultExpense,
        p_is_default_income: !!command.isDefaultIncome,
      })
      if (error) return { status: 'failed', reason: accountWriteReason(error), account: null, error: errorMessage(error) }
      const row = firstRow(data)
      if (!row?.id) return { status: 'failed', reason: 'invalid_response', account: null, error: '账户保存成功但未返回账户' }
      return { status: 'accepted', reason: 'saved', account: mapAccountRow(row) }
    } catch (error) {
      return { status: 'failed', reason: accountWriteReason(error), account: null, error: errorMessage(error) }
    }
  }

  async function setAccountArchived(command = {}) {
    try {
      const { data, error } = await client.rpc('set_account_archived', {
        p_account_id: command.accountId,
        p_archived: !!command.archived,
      })
      if (error) return { status: 'failed', reason: accountWriteReason(error), account: null, error: errorMessage(error) }
      const row = firstRow(data)
      if (!row?.id) return { status: 'failed', reason: 'invalid_response', account: null, error: '账户归档成功但未返回账户' }
      return { status: 'accepted', reason: command.archived ? 'archived' : 'restored', account: mapAccountRow(row) }
    } catch (error) {
      return { status: 'failed', reason: accountWriteReason(error), account: null, error: errorMessage(error) }
    }
  }

  return {
    listAccounts,
    listAccountEntries,
    listAccountPayments,
    listRepaymentCycles,
    ensureRepaymentCycles,
    confirmRepayment,
    confirmStagingRepayment,
    revokePayment,
    saveAccount,
    setAccountArchived,
  }
}
