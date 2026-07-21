import test from 'node:test'
import assert from 'node:assert/strict'
import { generateFactCandidates } from '../lib/fact-candidates.mjs'

const events = [
  ['1', 10, '2026-07-12T12:46:00+08:00'],
  ['2', 10, '2026-07-12T17:36:00+08:00'],
  ['3', 10, '2026-07-12T20:18:00+08:00'],
  ['4', 15, '2026-07-12T23:17:00+08:00'],
].map(([event_id, amount, event_at]) => ({
  event_id,
  source_type: 'ai_recognition_log',
  ledger_status: 'confirmed_transaction',
  count_in_facts: true,
  amount,
  event_at,
  known_at: event_at,
  event_time_source: 'occurred_at',
  event_time_confidence: 0.95,
  merchant: { entity_id: 'merchant_example_api_hub', canonical_name: 'Example API Hub' },
}))

test('generates auditable daily facts from four events', () => {
  const candidates = generateFactCandidates(events, {
    entityId: 'merchant_example_api_hub', localDate: '2026-07-12', timeZone: 'Asia/Shanghai',
  })
  assert.equal(candidates.length, 3)
  assert.deepEqual(candidates[0].claim.structured_value, {
    entity_id: 'merchant_example_api_hub', date: '2026-07-12', count: 4, total_amount: 45,
  })
  assert.equal(candidates[1].claim.structured_value.max_amount, 15)
  assert.equal(candidates[2].claim.structured_value.span_minutes, 631)
})

test('filters UTC events by the requested local date', () => {
  const utcEvent = {
    ...events[0],
    event_id: 'utc-cross-day',
    event_at: '2026-07-11T16:30:00Z',
    known_at: '2026-07-11T16:30:00Z',
  }
  const candidates = generateFactCandidates([utcEvent], {
    entityId: 'merchant_example_api_hub', localDate: '2026-07-12', timeZone: 'Asia/Shanghai',
  })
  assert.equal(candidates[0].claim.structured_value.count, 1)
})
