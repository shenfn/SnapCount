export function normalizeAccountType(type) {
  const value = String(type || '').trim()
  if (['cash', 'wallet_balance', 'debit_card', 'credit_card', 'credit_line', 'other'].includes(value)) return value
  if (['wechat', 'alipay', 'balance'].includes(value)) return 'wallet_balance'
  if (['bank_card', 'bank', 'debit'].includes(value)) return 'debit_card'
  if (['huabei', 'jd_baitiao', 'douyin_monthly'].includes(value)) return 'credit_line'
  return 'other'
}

export function isLiabilityAccount(account) {
  return ['credit_card', 'credit_line'].includes(account?.type)
}

export function formatAccountCurrency(value) {
  const amount = Number(value || 0)
  return `¥${amount.toFixed(2)}`
}

export function mapAccountRow(row) {
  return {
    id: row.id,
    userId: row.user_id,
    name: row.name,
    type: normalizeAccountType(row.type),
    institution: row.institution || '',
    last4: row.last4 || '',
    currency: row.currency || 'CNY',
    initialBalance: Number(row.initial_balance || 0),
    currentBalance: Number(row.current_balance || 0),
    snapshotBalance: row.snapshot_balance == null ? null : Number(row.snapshot_balance),
    snapshotAt: row.snapshot_at || null,
    sourceRecordTable: row.source_record_table || '',
    sourceRecordId: row.source_record_id || '',
    billDay: row.bill_day == null ? null : Number(row.bill_day),
    paymentDueDay: row.payment_due_day == null ? null : Number(row.payment_due_day),
    autoDebitAccountId: row.auto_debit_account_id || null,
    autoConfirmRepayment: !!row.auto_confirm_repayment,
    gracePeriodDays: row.grace_period_days == null ? 0 : Number(row.grace_period_days),
    lastReconciledAt: row.last_reconciled_at || null,
    isDefaultExpense: !!row.is_default_expense,
    isDefaultIncome: !!row.is_default_income,
    isArchived: !!row.is_archived,
    sortOrder: Number(row.sort_order || 0),
    createdAt: row.created_at,
    updatedAt: row.updated_at,
  }
}

export function accountTitle(account) {
  if (!account) return '未知账户'
  if (account.last4) return `${account.name}（${account.last4}）`
  return account.name || account.institution || '未命名账户'
}

export function splitAccounts(accounts) {
  const active = (accounts || []).filter(account => !account.isArchived)
  return {
    assets: active.filter(account => !isLiabilityAccount(account)),
    liabilities: active.filter(isLiabilityAccount),
  }
}
