import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({ entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'], bundle: true, platform: 'node', format: 'esm', write: false })
const { buildExpressionShadowPlan, buildGenericExpressionShadowPlan } = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64'))

test('income planner recognizes fixed notification coverage and keeps richer plans for details', () => {
  const records = [
    { id: 'i1', occurred_at: '2026-07-01T12:00:00+08:00', amount: 1000, source_name: '项目款' },
    { id: 'i2', occurred_at: '2026-07-13T12:00:00+08:00', amount: 500, source_name: '项目款' },
  ]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'income', records, currentRecordId: 'i2' })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.domain_key, 'income')
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_month_total_count'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_source_month_pattern'))
  assert.equal(plan.shortcut_plan.silent, true)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('sleep planner creates a personal median comparison from history', () => {
  const records = [6, 7, 7.5, 8, 5.5, 6.5, 7, 8.5].map((hours, index) => ({
    id: 's' + index, occurred_at: `2026-07-${String(index + 1).padStart(2, '0')}T08:00:00+08:00`, payload: { sleep_hours: hours },
  }))
  records.push({ id: 'current', occurred_at: '2026-07-13T08:00:00+08:00', payload: { sleep_hours: 5 } })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records, currentRecordId: 'current' })
  const comparison = plan.candidates.find(item => item.claim.semantic_key === 'sleep_vs_personal_median')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.sample_count, 8)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('food planner reads the production total_calorie_kcal field', () => {
  const records = [{
    id: 'food-current',
    occurred_at: '2026-07-14T19:00:00+08:00',
    payload: { total_calorie_kcal: 638, meal_type: 'dinner' },
  }]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records, currentRecordId: 'food-current' })
  const fact = plan.candidates.find(item => item.claim.semantic_key === 'food_current_metric')
  assert.ok(fact)
  assert.equal(fact.claim.structured_value.value, 638)
  assert.equal(fact.claim.structured_value.unit, '千卡')
})

test('expense planner normalizes legacy category aliases without changing raw records', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{
      id: 'expense-current', transaction_date: '2026-07-14', transaction_time: '18:00:00',
      amount: 30, merchant_name: '社区药房', category: '医疗', status: 'done',
    }],
    currentRecordId: 'expense-current',
  })
  assert.equal(plan.current_record.category, 'health')
})
