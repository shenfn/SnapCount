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

function withCanonicalOccurrence(row) {
  if (!row.transaction_date || !row.transaction_time) return row
  return {
    ...row,
    occurred_at: `${row.transaction_date}T${row.transaction_time}+08:00`,
  }
}

const repeatedApiMerchant = [
  { id: 'a', transaction_date: '2026-07-13', transaction_time: '10:00:00', amount: 10, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'b', transaction_date: '2026-07-13', transaction_time: '13:00:00', amount: 10, merchant_name: 'Example API Hub', status: 'done' },
  { id: 'c', transaction_date: '2026-07-13', transaction_time: '16:00:00', amount: 15, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'd', transaction_date: '2026-07-13', transaction_time: '19:07:00', amount: 12, merchant_name: 'Example API Hub', status: 'done' },
].map(withCanonicalOccurrence)

test('automatically plans a synthetic repeated merchant shadow sample', () => {
  const plan = buildExpressionShadowPlan({ transactions: repeatedApiMerchant, currentRecordId: 'd' })
  assert.equal(plan.status, 'auto_planned')
  assert.ok(plan.render_plans?.record_detail)
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

test('uses first occurrence as the insight for a single isolated expense', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{ id: 'only', transaction_date: '2026-07-13', amount: 14.98, merchant_name: '晚饭', status: 'done' }],
    currentRecordId: 'only',
  })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.selected.length, 0)
  assert.equal(plan.shortcut_plan.silent, true)
  assert.equal(plan.current_record.merchant_observation.entity_first_seen, true)
  assert.equal(plan.current_record.merchant_observation.alias_first_seen, true)
  assert.equal(plan.plan_summary.record_detail.selected[0].semantic_key, 'expense_merchant_first_occurrence')
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected[0].semantic_key, 'expense_merchant_first_occurrence')
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected[0].selection_mode, 'threshold')
  assert.equal(plan.plan_summary.record_detail.selected[0].selection_mode, 'threshold')
  assert.equal(plan.plan_summary.weekly_report.selected.length, 0)
})

test('a prior pending record prevents a false first-occurrence claim', () => {
  const plan = buildExpressionShadowPlan({
    currentRecordId: 'current-after-pending',
    transactions: [
      {
        id: 'prior-pending', type: 'expense', transaction_date: '2026-08-06',
        transaction_time: '12:00:00', created_at: '2026-08-06T12:01:00+08:00',
        amount: 6.28, merchant_name: '示例茶饮', category: null,
        platform: '外卖', payment_method: '微信支付', status: 'pending',
      },
      {
        id: 'current-after-pending', type: 'expense', transaction_date: '2026-08-07',
        transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00',
        amount: 6.01, merchant_name: '示例茶饮', category: 'food',
        platform: '外卖', payment_method: '微信支付', status: 'done',
      },
    ],
  })

  assert.equal(plan.current_record.merchant_observation.entity_first_seen, false)
  assert.equal(
    plan.candidates.some(candidate => candidate.claim?.semantic_key === 'expense_merchant_first_occurrence'),
    false,
  )
})

test('a later event already known to Jiezi prevents a backfill from being called first', () => {
  const plan = buildExpressionShadowPlan({
    currentRecordId: 'backfilled-current',
    transactions: [{
      id: 'known-later-event', type: 'expense', transaction_date: '2026-08-07', transaction_time: '12:00:00',
      created_at: '2026-08-07T12:01:00+08:00', amount: 8, merchant_name: '示例茶饮', category: 'food', status: 'done',
    }, {
      id: 'backfilled-current', type: 'expense', transaction_date: '2026-08-01', transaction_time: '08:00:00',
      created_at: '2026-08-08T08:01:00+08:00', amount: 6.28, merchant_name: '示例茶饮', category: 'food', status: 'done',
    }],
  })

  assert.equal(plan.current_record.merchant_observation.entity_first_seen, false)
  assert.equal(plan.candidates.some(candidate => candidate.claim?.semantic_key === 'expense_merchant_first_occurrence'), false)
})

test('retains a near-identical personal baseline for shadow analysis without selecting it for users', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'baseline-a', transaction_date: '2026-07-22', transaction_time: '08:00:00', amount: 100, merchant_name: 'Near Baseline Shop', status: 'done' },
      { id: 'baseline-b', transaction_date: '2026-07-23', transaction_time: '08:00:00', amount: 101, merchant_name: 'Near Baseline Shop', status: 'done' },
      { id: 'baseline-c', transaction_date: '2026-07-24', transaction_time: '08:00:00', amount: 99, merchant_name: 'Near Baseline Shop', status: 'done' },
      { id: 'current', transaction_date: '2026-07-25', transaction_time: '08:30:00', amount: 103.27, merchant_name: 'Near Baseline Shop', status: 'done' },
    ],
    currentRecordId: 'current',
  })
  const baseline = plan.candidates.find(candidate => candidate.claim.semantic_key === 'merchant_daily_vs_active_day_median')

  assert.ok(baseline)
  assert.equal(plan.planner_version, 'expression-shadow-auto-v0.6')
  assert.equal(baseline.claim.structured_value.delta.count, 0)
  assert.equal(baseline.claim.structured_value.delta.total_percent, 3.27)
  assert.equal(baseline.eligibility.eligible, true)
  assert.equal(baseline.eligibility.materiality.passes, false)
  assert.ok(baseline.eligibility.surface_eligibility.record_detail.blocked_reasons.includes('difference_below_materiality_threshold'))
  assert.equal(baseline.scoring.surfaces.record_detail.score, null)
  assert.equal(plan.plan_summary.record_detail.selected.some(item => item.semantic_key === 'merchant_daily_vs_active_day_median'), false)
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected.some(item => item.semantic_key === 'merchant_daily_vs_active_day_median'), false)
  assert.ok(plan.plan_summary.record_detail.selected.length > 0)
})

test('keeps a pending expense out of aggregates while exposing its verified record context', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      {
        id: 'previous-week', type: 'expense', transaction_date: '2026-07-18', transaction_time: '10:00:00',
        amount: 40, merchant_name: '示例记录', category: 'life', status: 'done',
      },
      {
        id: 'confirmed-morning', type: 'expense', transaction_date: '2026-07-25', transaction_time: '09:00:00',
        amount: 10, merchant_name: '示例记录', category: 'life', status: 'done',
      },
      {
        id: 'confirmed-noon', type: 'expense', transaction_date: '2026-07-25', transaction_time: '12:00:00',
        amount: 20, merchant_name: '示例记录', category: 'life', status: 'done',
      },
      {
        id: 'pending-current', type: 'expense', transaction_date: '2026-07-25', transaction_time: '20:16:00',
        amount: 32, merchant_name: '示例记录', category: 'life', status: 'pending',
      },
    ],
    currentRecordId: 'pending-current',
  })
  const context = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_current_record_context')

  assert.equal(plan.status, 'auto_planned')
  assert.ok(context)
  assert.equal(context.claim.structured_value.fact_status, 'pending_review')
  assert.match(context.claim.canonical_text, /分类仍待确认/)
  assert.equal(context.evidence[0].ledger_status, 'pending_review')
  assert.deepEqual(plan.candidates.map(candidate => candidate.claim.semantic_key), ['expense_current_record_context'])
  assert.equal(plan.shortcut_plan.silent, true)
  assert.equal(plan.plan_summary.record_detail.selected[0].semantic_key, 'expense_current_record_context')
})

test('does not expose the noon proxy when an expense has only a transaction date', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{
      id: 'date-only', type: 'expense', transaction_date: '2026-07-25', transaction_time: null,
      amount: 32, merchant_name: '示例记录', category: 'life', status: 'done',
    }],
    currentRecordId: 'date-only',
  })
  const context = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_current_record_context')

  assert.ok(context)
  assert.equal(context.claim.structured_value.time_precision, 'date_only')
  assert.doesNotMatch(context.claim.canonical_text, /12:00/)
})

test('current-day facts do not read same-day transactions after the current record', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'past', transaction_date: '2026-07-23', transaction_time: '08:00:00', amount: 10, merchant_name: 'Causal Shop', status: 'done' },
      { id: 'current', transaction_date: '2026-07-23', transaction_time: '10:00:00', amount: 20, merchant_name: 'Causal Shop', status: 'done' },
      { id: 'future', transaction_date: '2026-07-23', transaction_time: '18:00:00', amount: 30, merchant_name: 'Causal Shop', status: 'done' },
    ].map(withCanonicalOccurrence),
    currentRecordId: 'current',
  })
  const daily = plan.candidates.find(candidate => candidate.claim.semantic_key === 'merchant_daily_count_total')
  const recurrence = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap')
  assert.equal(daily.claim.structured_value.count, 2)
  assert.equal(daily.claim.structured_value.total_amount, 30)
  assert.equal(recurrence.claim.structured_value.elapsed_minutes, 120)
  assert.equal(recurrence.evidence.length, 2)
  assert.ok(recurrence.numbers.some(number => number.meaning === 'same_record_name_elapsed_minutes'))
  assert.equal(plan.candidates.some(candidate => candidate.claim.semantic_key === 'merchant_daily_activity_span'), false)
})

test('does not use a same-name income transaction as previous expense', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'previous-expense', type: 'expense', transaction_date: '2026-07-10', transaction_time: '08:00:00', amount: 10, merchant_name: 'Mixed Type Name', status: 'done' },
      { id: 'recent-income', type: 'income', transaction_date: '2026-07-11', transaction_time: '08:00:00', amount: 20, merchant_name: 'Mixed Type Name', status: 'done' },
      { id: 'current-expense', type: 'expense', transaction_date: '2026-07-12', transaction_time: '08:00:00', amount: 30, merchant_name: 'Mixed Type Name', status: 'done' },
    ].map(withCanonicalOccurrence),
    currentRecordId: 'current-expense',
  })
  const recurrence = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap')
  assert.equal(recurrence.claim.structured_value.previous_record_id, 'previous-expense')
  assert.equal(recurrence.claim.structured_value.elapsed_minutes, 2880)
})

test('selects a same-name interval for the AI card and detail without interrupting the user', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'previous', transaction_date: '2026-06-15', transaction_time: '08:10:00', created_at: '2026-06-15T00:11:00Z', amount: 12, merchant_name: 'Named Record', status: 'done' },
      { id: 'current', transaction_date: '2026-07-12', transaction_time: '17:47:00', created_at: '2026-07-12T09:48:00Z', amount: 18, merchant_name: 'Named Record', status: 'done' },
    ].map(withCanonicalOccurrence),
    currentRecordId: 'current',
  })
  const recurrence = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap')
  assert.equal(recurrence.claim.structured_value.previous_record_id, 'previous')
  assert.deepEqual(recurrence.claim.structured_value.elapsed_duration, {
    days: 27, hours: 9, minutes: 37, display_text: '27 天 9 小时 37 分钟',
  })
  assert.equal(recurrence.eligibility.surface_eligibility.shortcut_notification.eligible, false)
  assert.equal(recurrence.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, true)
  assert.equal(recurrence.eligibility.surface_eligibility.record_detail.eligible, true)
  assert.equal(recurrence.eligibility.surface_eligibility.weekly_report.eligible, false)
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected[0].semantic_key, 'expense_record_name_previous_gap')
  assert.equal(plan.plan_summary.record_detail.selected[0].semantic_key, 'expense_record_name_previous_gap')
})

test('same-day date-only records stay in totals without inventing a recurrence interval', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'proxy-a', transaction_date: '2026-07-23', created_at: '2026-07-23T08:00:00Z', amount: 10, merchant_name: 'Proxy Shop', status: 'done' },
      { id: 'proxy-b', transaction_date: '2026-07-23', created_at: '2026-07-23T09:00:00Z', amount: 20, merchant_name: 'Proxy Shop', status: 'done' },
    ],
    currentRecordId: 'proxy-b',
  })
  const daily = plan.candidates.find(candidate => candidate.claim.semantic_key === 'merchant_daily_count_total')
  assert.equal(daily.claim.structured_value.count, 2)
  assert.equal(daily.claim.structured_value.total_amount, 30)
  assert.equal(plan.candidates.some(candidate => candidate.claim.semantic_key === 'merchant_daily_activity_span'), false)
  assert.equal(plan.candidates.some(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap'), false)
})

test('legacy transaction_time alone never restores minute precision', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'legacy-a', transaction_date: '2026-07-22', transaction_time: '23:46:00', amount: 10, merchant_name: 'Legacy Time Shop', status: 'done' },
      { id: 'legacy-b', transaction_date: '2026-07-23', transaction_time: '06:41:00', amount: 20, merchant_name: 'Legacy Time Shop', status: 'done' },
    ],
    currentRecordId: 'legacy-b',
  })

  const recurrence = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap')
  assert.ok(recurrence)
  assert.equal(recurrence.claim.structured_value.elapsed_minutes, null)
  assert.deepEqual(recurrence.claim.structured_value.elapsed_duration, {
    days: 1, hours: null, minutes: null, display_text: '1 天',
  })
})

test('same-time records remain in daily totals without inventing a positive recurrence interval', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'same-a', transaction_date: '2026-07-23', transaction_time: '10:00:00', created_at: '2026-07-23T10:01:00Z', amount: 10, merchant_name: 'Same Time Shop', status: 'done' },
      { id: 'same-b', transaction_date: '2026-07-23', transaction_time: '10:00:00', created_at: '2026-07-23T10:02:00Z', amount: 20, merchant_name: 'Same Time Shop', status: 'done' },
    ],
    currentRecordId: 'same-b',
  })
  const daily = plan.candidates.find(candidate => candidate.claim.semantic_key === 'merchant_daily_count_total')
  assert.equal(daily.claim.structured_value.count, 2)
  assert.equal(daily.claim.structured_value.total_amount, 30)
  assert.equal(plan.candidates.some(candidate => candidate.claim.semantic_key === 'merchant_daily_activity_span'), false)
  assert.equal(plan.candidates.some(candidate => candidate.claim.semantic_key === 'expense_record_name_previous_gap'), false)
})

test('category comparison keeps invalid historical amounts visible in coverage', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'baseline', transaction_date: '2026-07-16', transaction_time: '09:00:00', created_at: '2026-07-16T01:01:00Z', amount: 10, merchant_name: 'Baseline Shop', category: 'life', status: 'done' },
      { id: 'invalid', transaction_date: '2026-07-23', transaction_time: '08:00:00', created_at: '2026-07-23T00:01:00Z', amount: null, merchant_name: 'Invalid Shop', category: 'life', status: 'done' },
      { id: 'current-valid', transaction_date: '2026-07-23', transaction_time: '10:00:00', created_at: '2026-07-23T02:01:00Z', amount: 20, merchant_name: 'Current Shop', category: 'life', status: 'done' },
    ],
    currentRecordId: 'current-valid',
  })
  const comparison = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_category_week_to_date_vs_previous_week_same_period')
  assert.equal(comparison.claim.structured_value.current_period.count, 1)
  assert.equal(comparison.claim.structured_value.data_status.invalid_amount_count, 1)
  assert.equal(comparison.quality.data_coverage, 0.67)
})

test('category comparison excludes same-day proxy records created after the current record', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [
      { id: 'baseline-proxy', transaction_date: '2026-07-16', created_at: '2026-07-16T01:00:00Z', amount: 10, merchant_name: 'Baseline Proxy', category: 'life', status: 'done' },
      { id: 'known-before', transaction_date: '2026-07-23', created_at: '2026-07-23T01:00:00Z', amount: 10, merchant_name: 'Known Before', category: 'life', status: 'done' },
      { id: 'proxy-current', transaction_date: '2026-07-23', created_at: '2026-07-23T02:00:00Z', amount: 20, merchant_name: 'Proxy Current', category: 'life', status: 'done' },
      { id: 'known-after', transaction_date: '2026-07-23', created_at: '2026-07-23T03:00:00Z', amount: 30, merchant_name: 'Known After', category: 'life', status: 'done' },
    ],
    currentRecordId: 'proxy-current',
  })
  const comparison = plan.candidates.find(candidate => candidate.claim.semantic_key === 'expense_category_week_to_date_vs_previous_week_same_period')
  assert.equal(comparison.claim.structured_value.current_period.count, 2)
  assert.equal(comparison.claim.structured_value.current_period.total, 30)
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
  assert.equal(categoryComparison.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
  assert.equal(categoryComparison.eligibility.surface_eligibility.record_detail.eligible, false)
  assert.equal(plan.plan_summary.pwa_pending_ai_card.selected.some(item => item.semantic_key === 'expense_category_week_to_date_vs_previous_week_same_period'), false)
  assert.equal(plan.plan_summary.record_detail.selected.some(item => item.semantic_key === 'expense_category_week_to_date_vs_previous_week_same_period'), false)
})
