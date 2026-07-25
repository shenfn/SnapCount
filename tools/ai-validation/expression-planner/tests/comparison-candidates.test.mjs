import test from 'node:test'
import assert from 'node:assert/strict'
import { generateCategoryComparisonCandidates, generateComparisonCandidates } from '../lib/comparison-candidates.mjs'
import { buildExpenseFactContract } from '../lib/expense-fact-contract.mjs'

const merchant = { entity_id: 'merchant_fixture_alpha' }
function record(id, date, amount) {
  return { id, transaction_date: date, occurred_at: `${date}T12:00:00+08:00`, amount, merchant }
}
function event(id, amount) {
  return {
    event_id: id, source_type: 'ai_recognition_log', ledger_status: 'confirmed_transaction',
    count_in_facts: true, amount, event_at: `2026-07-12T12:00:00+08:00`, known_at: `2026-07-12T12:01:00+08:00`, merchant,
  }
}

test('compares current day with historical active-day medians', () => {
  const records = [
    record('a', '2026-06-22', 10),
    record('b', '2026-06-23', 20), record('c', '2026-06-23', 10),
    record('d', '2026-06-24', 30),
  ]
  const candidates = generateComparisonCandidates({
    records, currentDayEvents: [event('1', 10), event('2', 15)], entityId: merchant.entity_id, localDate: '2026-07-12', currentRecordId: 'record-2',
  })
  const daily = candidates.find(item => item.claim.semantic_key === 'merchant_daily_vs_active_day_median')
  assert.equal(daily.claim.structured_value.baseline.sample_days, 3)
  assert.equal(daily.claim.structured_value.baseline.count, 1)
  assert.equal(daily.claim.structured_value.baseline.total, 30)
  assert.equal(daily.claim.structured_value.current.total, 25)
  assert.match(daily.candidate_id, /:record-2$/)
  assert.equal(daily.selection_hints.exposure_key, 'expense:merchant:merchant_fixture_alpha:daily_active_median:2026-07-12')
})

test('compares week-to-date with the same elapsed period last week', () => {
  const records = [
    record('previous-mon', '2026-06-29', 10),
    record('previous-wed', '2026-07-01', 20),
    record('outside-previous-period', '2026-07-05', 100),
    record('current-mon', '2026-07-06', 15),
  ]
  const candidates = generateComparisonCandidates({
    records, currentDayEvents: [event('today', 10)], entityId: merchant.entity_id, localDate: '2026-07-08',
  })
  const weekly = candidates.find(item => item.claim.semantic_key === 'merchant_week_to_date_vs_previous_week_same_period')
  assert.deepEqual(weekly.claim.structured_value.current_period, {
    start: '2026-07-06', end: '2026-07-08', count: 2, total: 25,
  })
  assert.deepEqual(weekly.claim.structured_value.baseline_period, {
    start: '2026-06-29', end: '2026-07-01', count: 2, total: 30,
  })
  assert.match(weekly.candidate_id, /:2026-07-08:(?:2026-07-08|today)$/)
  assert.equal(weekly.selection_hints.exposure_key, 'expense:merchant:merchant_fixture_alpha:week_to_date:2026-07-06')
  assert.equal(weekly.selection_hints.delivery_scope, 'period_summary')
  assert.equal(weekly.selection_hints.cadence_scope, 'calendar_week:2026-07-06')
  assert.deepEqual(weekly.selection_hints.allowed_surfaces, ['weekly_report'])
  assert.equal(weekly.selection_hints.max_exposure_count.record_detail, undefined)
  assert.equal(weekly.selection_hints.max_exposure_count.weekly_report, 1)
})

test('does not create an active-day baseline from fewer than three days', () => {
  const candidates = generateComparisonCandidates({
    records: [record('a', '2026-07-01', 10), record('b', '2026-07-02', 20)],
    currentDayEvents: [event('today', 10)], entityId: merchant.entity_id, localDate: '2026-07-12',
  })
  assert.equal(candidates.some(item => item.dimension === 'personal_baseline'), false)
})

function categoryRecord(id, occurredAt, amount, category, status = 'done', businessKind = null) {
  return {
    id,
    transaction_date: occurredAt.slice(0, 10),
    occurred_at: occurredAt,
    amount,
    category,
    fact_contract: buildExpenseFactContract({ status, category, business_kind: businessKind }),
  }
}

test('compares a category with the previous week at the same time without unrelated expenses', () => {
  const records = [
    categoryRecord('current-a', '2026-07-13T12:00:00+08:00', 10, 'food'),
    categoryRecord('current-b', '2026-07-18T18:00:00+08:00', 10, 'food'),
    categoryRecord('current', '2026-07-19T11:24:00+08:00', 15, 'food'),
    categoryRecord('current-rent', '2026-07-15T19:42:00+08:00', 1300, 'life', 'done', 'housing_rent'),
    categoryRecord('previous-a', '2026-07-06T12:00:00+08:00', 15, 'food'),
    categoryRecord('previous-b', '2026-07-12T10:00:00+08:00', 15, 'food'),
    categoryRecord('previous-after-cutoff', '2026-07-12T18:00:00+08:00', 100, 'food'),
    categoryRecord('pending-current', '2026-07-17T12:00:00+08:00', 20, 'food', 'pending'),
    categoryRecord('pending-previous', '2026-07-10T12:00:00+08:00', 20, 'food', 'pending'),
  ]
  const candidates = generateCategoryComparisonCandidates({ records, currentRecord: records[2] })
  const categoryComparison = candidates[0]

  assert.equal(categoryComparison.claim.semantic_key, 'expense_category_week_to_date_vs_previous_week_same_period')
  assert.equal(categoryComparison.claim.structured_value.comparison_cohort, 'expense.category.food')
  assert.deepEqual(categoryComparison.claim.structured_value.current_period, {
    start: '2026-07-13', end_at: '2026-07-19T11:24:00+08:00', count: 3, total: 35, average: 11.67,
  })
  assert.equal(categoryComparison.claim.structured_value.baseline_period.count, 2)
  assert.equal(categoryComparison.claim.structured_value.baseline_period.total, 30)
  assert.equal(categoryComparison.claim.structured_value.driver, 'record_frequency')
  assert.deepEqual(categoryComparison.claim.structured_value.directions, {
    total: 'increase', count: 'increase', average: 'decrease',
  })
  assert.equal(categoryComparison.claim.structured_value.change_pattern, 'count_up_average_down_total_up')
  assert.match(categoryComparison.candidate_id, /:current$/)
  assert.equal(categoryComparison.selection_hints.diversity_groups.weekly_report, 'expense_week_to_date_comparison')
  assert.equal(categoryComparison.selection_hints.delivery_scope, 'period_summary')
  assert.equal(categoryComparison.selection_hints.cadence_scope, 'calendar_week:2026-07-13')
  assert.deepEqual(categoryComparison.selection_hints.allowed_surfaces, ['weekly_report'])
  assert.equal(categoryComparison.selection_hints.max_exposure_count.pwa_pending_ai_card, undefined)
  assert.equal(categoryComparison.selection_hints.period_owner, true)
  assert.equal(categoryComparison.claim.structured_value.decomposition.dominant_effect, 'record_frequency')
  assert.equal(categoryComparison.claim.structured_value.decomposition.offsetting, true)
  assert.equal(categoryComparison.claim.structured_value.pending_review_count, 2)
  assert.equal(categoryComparison.quality.data_coverage, 0.71)
  assert.doesNotMatch(categoryComparison.claim.canonical_text, /1300/)
})

test('keeps total, count, and average directions consistent when frequency rises but total falls', () => {
  const currentAmounts = [10, 10, 10, 10, 10, 10, 10, 10]
  const baselineAmounts = [15, 15, 15, 15, 15, 15, 15]
  const current = currentAmounts.map((amount, index) => categoryRecord(
    `current-${index}`,
    `2026-07-23T${String(8 + Math.floor(index / 2)).padStart(2, '0')}:${index === 7 ? '06' : '00'}:00+08:00`,
    amount,
    'life',
  ))
  current[7].occurred_at = '2026-07-23T12:34:00+08:00'
  const baseline = baselineAmounts.map((amount, index) => categoryRecord(
    `baseline-${index}`,
    `2026-07-16T${String(8 + Math.floor(index / 2)).padStart(2, '0')}:00:00+08:00`,
    amount,
    'life',
  ))
  const comparison = generateCategoryComparisonCandidates({ records: [...baseline, ...current], currentRecord: current[7] })[0]
  const value = comparison.claim.structured_value

  assert.deepEqual(value.directions, { total: 'decrease', count: 'increase', average: 'decrease' })
  assert.equal(value.change_pattern, 'count_up_average_down_total_down')
  assert.equal(value.driver, 'average_amount')
  assert.deepEqual(value.metrics.total, {
    current: 80, baseline: 105, delta: -25, delta_percent: -23.81, direction: 'decrease',
  })
  assert.deepEqual(value.metrics.count, {
    current: 8, baseline: 7, delta: 1, delta_percent: 14.29, direction: 'increase',
  })
  assert.deepEqual(value.metrics.average, {
    current: 10, baseline: 15, delta: -5, delta_percent: -33.33, direction: 'decrease',
  })
  assert.deepEqual(value.decomposition, {
    method: 'symmetric_count_average_v1',
    frequency_effect_amount: 12.5,
    average_effect_amount: -37.5,
    net_delta: -25,
    dominant_effect: 'average_amount',
    offsetting: true,
  })
  assert.equal(value.comparison_window.time_zone, 'Asia/Shanghai')
  assert.equal(value.baseline_period.end_at, '2026-07-16T12:34:00+08:00')
  assert.match(comparison.claim.canonical_text, /本周截至 7 月 23 日 12:34/)
  assert.match(comparison.claim.canonical_text, /合计少 25 元，笔数多 1 笔，单笔均价低 5 元/)
  assert.doesNotMatch(comparison.claim.canonical_text, /总额增加|主要来自|导致/)
})

test('category aggregation rejects null and blank amounts but keeps zero', () => {
  const records = [
    categoryRecord('current-null', '2026-07-23T08:00:00+08:00', null, 'life'),
    categoryRecord('current-blank', '2026-07-23T09:00:00+08:00', '  ', 'life'),
    categoryRecord('current-zero', '2026-07-23T10:00:00+08:00', 0, 'life'),
    categoryRecord('current-ten', '2026-07-23T11:00:00+08:00', '10', 'life'),
    categoryRecord('baseline-a', '2026-07-16T09:00:00+08:00', 5, 'life'),
    categoryRecord('baseline-b', '2026-07-16T10:00:00+08:00', 5, 'life'),
  ]
  const comparison = generateCategoryComparisonCandidates({ records, currentRecord: records[3] })[0]
  assert.equal(comparison.claim.structured_value.current_period.count, 2)
  assert.equal(comparison.claim.structured_value.current_period.total, 10)
  assert.equal(comparison.claim.structured_value.data_status.invalid_amount_count, 2)
  assert.equal(comparison.quality.data_coverage, 0.67)
})
