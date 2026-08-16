function errorMessage(error) {
  return error?.message || String(error || '账户还款服务请求失败')
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

export function createAccountRepository({ client }) {
  if (typeof client?.rpc !== 'function') throw new Error('账户服务缺少 RPC 客户端')

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

  return { confirmRepayment, revokePayment }
}
