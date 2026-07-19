import test from 'node:test'
import assert from 'node:assert/strict'
import { buildExpenseFactContract } from '../lib/expense-fact-contract.mjs'

test('assigns a confirmed category record to its own comparison cohort', () => {
  const contract = buildExpenseFactContract({ status: 'done', category: 'food' })
  assert.equal(contract.fact_status, 'confirmed')
  assert.equal(contract.expense_total_scope, 'include')
  assert.equal(contract.comparison_cohort, 'expense.category.food')
  assert.equal(contract.intervention_scope, 'observe_only')
})

test('keeps pending records out of totals while retaining their provisional cohort', () => {
  const contract = buildExpenseFactContract({ status: 'pending', category: 'food' })
  assert.equal(contract.fact_status, 'pending_review')
  assert.equal(contract.expense_total_scope, 'exclude_pending_review')
  assert.equal(contract.comparison_scope, 'pending_review')
  assert.equal(contract.comparison_cohort, 'expense.category.food')
})

test('treats user-confirmed rent as fixed expense rather than discretionary spending', () => {
  const contract = buildExpenseFactContract({ status: 'done', category: 'life', business_kind: 'housing_rent' })
  assert.equal(contract.cashflow_scope, 'include')
  assert.equal(contract.expense_total_scope, 'include')
  assert.equal(contract.fixed_expense_scope, 'include')
  assert.equal(contract.discretionary_scope, 'exclude')
  assert.equal(contract.intervention_scope, 'exclude')
  assert.equal(contract.comparison_cohort, 'expense.fixed.housing')
})

test('keeps liability repayments in cashflow but outside expense totals', () => {
  const contract = buildExpenseFactContract({ status: 'done', category: 'other', business_kind: 'liability_repayment' })
  assert.equal(contract.cashflow_scope, 'include')
  assert.equal(contract.expense_total_scope, 'exclude_non_expense_cashflow')
  assert.equal(contract.intervention_scope, 'exclude')
  assert.equal(contract.comparison_cohort, 'cashflow.liability_repayment')
})
