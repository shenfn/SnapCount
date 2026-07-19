import test from 'node:test'
import assert from 'node:assert/strict'
import { generateComparisonCandidates } from '../lib/comparison-candidates.mjs'

const merchant = { entity_id: 'merchant_qlhazycoder' }
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
    records, currentDayEvents: [event('1', 10), event('2', 15)], entityId: merchant.entity_id, localDate: '2026-07-12',
  })
  const daily = candidates.find(item => item.claim.semantic_key === 'merchant_daily_vs_active_day_median')
  assert.equal(daily.claim.structured_value.baseline.sample_days, 3)
  assert.equal(daily.claim.structured_value.baseline.count, 1)
  assert.equal(daily.claim.structured_value.baseline.total, 30)
  assert.equal(daily.claim.structured_value.current.total, 25)
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
})

test('does not create an active-day baseline from fewer than three days', () => {
  const candidates = generateComparisonCandidates({
    records: [record('a', '2026-07-01', 10), record('b', '2026-07-02', 20)],
    currentDayEvents: [event('today', 10)], entityId: merchant.entity_id, localDate: '2026-07-12',
  })
  assert.equal(candidates.some(item => item.dimension === 'personal_baseline'), false)
})
