import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({
  entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  write: false,
})
const url = 'data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64')
const { buildExpressionShadowPlan } = await import(url)

const repeatedApiMerchant = [
  { id: 'a', transaction_date: '2026-07-13', transaction_time: '10:00:00', amount: 10, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'b', transaction_date: '2026-07-13', transaction_time: '13:00:00', amount: 10, merchant_name: 'Example API Hub', status: 'done' },
  { id: 'c', transaction_date: '2026-07-13', transaction_time: '16:00:00', amount: 15, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'd', transaction_date: '2026-07-13', transaction_time: '19:07:00', amount: 12, merchant_name: 'Example API Hub', status: 'done' },
 ]

test('automatically plans a synthetic repeated merchant shadow sample', () => {
  const plan = buildExpressionShadowPlan({ transactions: repeatedApiMerchant, currentRecordId: 'd' })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.changes_user_output, false)
  assert.ok(plan.shared_modules.includes('deterministic-scoring'))
  assert.equal(plan.selected.length, 1)
  assert.equal(plan.selected[0].semantic_key, 'merchant_daily_count_total')
  assert.match(plan.selected[0].canonical_text, /4 笔/)
  assert.equal(plan.shortcut_plan.selected[0].selection_mode, 'threshold')
  assert.equal(plan.current_record.entity_id, 'merchant_unmapped_exampleapihub')
  assert.equal(plan.current_record.raw_merchant_name, 'Example API Hub')
  assert.equal(plan.current_record.merchant_observation.entity_first_seen, false)
  assert.equal(plan.current_record.merchant_observation.alias_first_seen, false)
  assert.deepEqual(
    plan.current_record.merchant_observation.observed_aliases.sort(),
    ['Example API Hub', 'ExampleAPIHub'].sort(),
  )
})

test('does not invent an insight from a single isolated expense', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{ id: 'only', transaction_date: '2026-07-13', amount: 14.98, merchant_name: '晚饭', status: 'done' }],
    currentRecordId: 'only',
  })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.selected.length, 0)
  assert.equal(plan.shortcut_plan.silent, true)
})

test('keeps category comparisons isolated and reflects pending coverage', () => {
  const currentFood = Array.from({ length: 13 }, (_, index) => ({
    id: `current-food-${index}`,
    transaction_date: index === 12 ? '2026-07-19' : `2026-07-${String(13 + (index % 6)).padStart(2, '0')}`,
    transaction_time: index === 12 ? '11:24:00' : '10:00:00',
    amount: 10,
    category: 'food',
    merchant_name: `Current Food ${index}`,
    status: 'done',
  }))
  const previousFood = Array.from({ length: 10 }, (_, index) => ({
    id: `previous-food-${index}`,
    transaction_date: `2026-07-${String(6 + (index % 6)).padStart(2, '0')}`,
    transaction_time: '10:00:00',
    amount: 10,
    category: 'food',
    merchant_name: `Previous Food ${index}`,
    status: 'done',
  }))
  const pendingFood = Array.from({ length: 12 }, (_, index) => ({
    id: `pending-food-${index}`,
    transaction_date: index < 7 ? '2026-07-17' : '2026-07-10',
    transaction_time: '10:00:00',
    amount: 20,
    category: 'food',
    merchant_name: index === 0 ? null : `Pending Food ${index}`,
    status: 'pending',
  }))
  const unrelated = [
    { id: 'rent', transaction_date: '2026-07-15', transaction_time: '19:42:00', amount: 1300, category: 'life', merchant_name: 'Housing', status: 'done' },
    { id: 'other-large', transaction_date: '2026-07-15', transaction_time: '18:30:00', amount: 900, category: 'other', merchant_name: 'Other', status: 'done' },
  ]

  const plan = buildExpressionShadowPlan({
    transactions: [...currentFood, ...previousFood, ...pendingFood, ...unrelated],
    currentRecordId: 'current-food-12',
  })
  const categoryComparison = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_category_week_to_date_vs_previous_week_same_period')

  assert.equal(categoryComparison.claim.structured_value.current_period.total, 130)
  assert.equal(categoryComparison.claim.structured_value.baseline_period.total, 100)
  assert.equal(categoryComparison.claim.structured_value.pending_review_count, 12)
  assert.equal(categoryComparison.quality.data_coverage, 0.66)
  assert.equal(categoryComparison.eligibility.surface_eligibility.shortcut_notification.eligible, false)
  assert.ok(categoryComparison.eligibility.surface_eligibility.shortcut_notification.blocked_reasons.includes('data_coverage_below_surface_threshold'))
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected[0].semantic_key, 'expense_category_week_to_date_vs_previous_week_same_period')
})
