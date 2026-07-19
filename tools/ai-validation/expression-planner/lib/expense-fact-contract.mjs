const PENDING_STATUSES = new Set(['pending', 'pending_review'])

function normalizedText(value) {
  return value === null || value === undefined ? '' : String(value).trim().toLowerCase()
}

export function buildExpenseFactContract(record = {}) {
  const status = normalizedText(record.status)
  const category = normalizedText(record.category) || null
  const businessKind = normalizedText(record.business_kind ?? record.confirmed_business_kind) || null
  const pending = PENDING_STATUSES.has(status)

  if (pending) {
    return {
      contract_version: 'expense-fact-contract-v0.1',
      fact_status: 'pending_review',
      cashflow_scope: 'exclude_pending_review',
      expense_total_scope: 'exclude_pending_review',
      discretionary_scope: 'pending_review',
      fixed_expense_scope: 'pending_review',
      intervention_scope: 'blocked_pending_context',
      comparison_scope: 'pending_review',
      comparison_cohort: category ? `expense.category.${category}` : null,
      classification_source: category ? 'provisional_transaction_category' : 'missing',
    }
  }

  if (businessKind === 'liability_repayment') {
    return {
      contract_version: 'expense-fact-contract-v0.1',
      fact_status: 'confirmed',
      cashflow_scope: 'include',
      expense_total_scope: 'exclude_non_expense_cashflow',
      discretionary_scope: 'exclude',
      fixed_expense_scope: 'exclude',
      intervention_scope: 'exclude',
      comparison_scope: 'include',
      comparison_cohort: 'cashflow.liability_repayment',
      classification_source: 'confirmed_business_kind',
    }
  }

  if (businessKind === 'housing_rent') {
    return {
      contract_version: 'expense-fact-contract-v0.1',
      fact_status: 'confirmed',
      cashflow_scope: 'include',
      expense_total_scope: 'include',
      discretionary_scope: 'exclude',
      fixed_expense_scope: 'include',
      intervention_scope: 'exclude',
      comparison_scope: 'include',
      comparison_cohort: 'expense.fixed.housing',
      classification_source: 'confirmed_business_kind',
    }
  }

  return {
    contract_version: 'expense-fact-contract-v0.1',
    fact_status: 'confirmed',
    cashflow_scope: 'include',
    expense_total_scope: 'include',
    discretionary_scope: 'unknown',
    fixed_expense_scope: 'unknown',
    intervention_scope: category && category !== 'other' ? 'observe_only' : 'blocked_pending_context',
    comparison_scope: category ? 'include' : 'pending_review',
    comparison_cohort: category ? `expense.category.${category}` : null,
    classification_source: category ? 'transaction_category' : 'missing',
  }
}
