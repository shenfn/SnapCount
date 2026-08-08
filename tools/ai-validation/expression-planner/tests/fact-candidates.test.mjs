import test from 'node:test'
import assert from 'node:assert/strict'
import {
  generateCurrentExpenseRecordCandidate,
  generateFactCandidates,
  generateMerchantFirstOccurrenceCandidate,
} from '../lib/fact-candidates.mjs'

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
  assert.equal(candidates.length, 2)
  assert.deepEqual(candidates[0].claim.structured_value, {
    entity_id: 'merchant_example_api_hub', date: '2026-07-12', count: 4, total_amount: 45,
  })
  assert.equal(candidates[1].claim.structured_value.max_amount, 15)
  assert.equal(candidates.some(item => item.claim.semantic_key === 'merchant_daily_activity_span'), false)
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

test('ignores missing and invalid amounts while preserving an explicit zero', () => {
  const candidates = generateFactCandidates([
    { ...events[0], event_id: 'null', amount: null },
    { ...events[0], event_id: 'blank', amount: '  ' },
    { ...events[0], event_id: 'invalid', amount: 'not-a-number' },
    { ...events[0], event_id: 'zero', amount: 0 },
    { ...events[0], event_id: 'ten', amount: '10' },
  ], {
    entityId: 'merchant_example_api_hub', localDate: '2026-07-12', timeZone: 'Asia/Shanghai',
  })
  assert.deepEqual(candidates[0].claim.structured_value, {
    entity_id: 'merchant_example_api_hub', date: '2026-07-12', count: 2, total_amount: 10,
  })
})

test('creates a provisional current-record fact without using it in aggregates', () => {
  const [current] = generateCurrentExpenseRecordCandidate({
    event_id: 'transaction:pending-current',
    target_id: 'pending-current',
    source_type: 'transaction',
    ledger_status: 'pending_review',
    count_in_facts: false,
    amount: 32,
    event_at: '2026-07-25T20:16:00+08:00',
    event_time_precision: 'second',
    category: null,
    merchant: { canonical_name: '示例记录' },
    fact_contract: { fact_status: 'pending_review', comparison_scope: 'pending_review' },
  })

  assert.equal(current.claim.semantic_key, 'expense_current_record_context')
  assert.equal(current.claim.structured_value.fact_status, 'pending_review')
  assert.equal(current.claim.structured_value.category_needs_review, true)
  assert.match(current.claim.canonical_text, /32 元支出/)
  assert.match(current.claim.canonical_text, /分类仍待确认/)
  assert.deepEqual(current.selection_hints.allowed_surfaces, ['pwa_pending_ai_card', 'record_detail'])
  assert.equal(current.evidence[0].ledger_status, 'pending_review')
})

test('does not mark a confirmed categorized expense as awaiting category review', () => {
  const [current] = generateCurrentExpenseRecordCandidate({
    event_id: 'transaction:confirmed-current',
    target_id: 'confirmed-current',
    source_type: 'transaction',
    ledger_status: 'confirmed_transaction',
    count_in_facts: true,
    amount: 32,
    event_at: '2026-07-25T20:16:00+08:00',
    event_time_precision: 'second',
    category: 'life',
    merchant: { canonical_name: '示例记录' },
    fact_contract: { fact_status: 'confirmed', comparison_scope: 'include' },
  })

  assert.equal(current.claim.structured_value.category_needs_review, false)
  assert.doesNotMatch(current.claim.canonical_text, /分类仍待确认/)
})

test('generates a stable first-occurrence candidate for a new merchant entity', () => {
  const [first] = generateMerchantFirstOccurrenceCandidate({
    event_id: 'transaction:first-merchant',
    target_id: 'first-merchant',
    amount: 6.28,
    event_at: '2026-08-05T10:20:00+08:00',
    merchant: {
      entity_id: 'merchant_example',
      canonical_name: '示例茶饮',
      raw_name: '示例茶饮',
      normalized_key: '示例茶饮',
    },
  }, {
    entity_id: 'merchant_example',
    canonical_name: '示例茶饮',
    raw_name: '示例茶饮',
    normalized_key: '示例茶饮',
    entity_first_seen: true,
    alias_first_seen: true,
  })

  assert.equal(first.claim.semantic_key, 'expense_merchant_first_occurrence')
  assert.equal(first.dimension, 'first_occurrence')
  assert.equal(first.claim.structured_value.first_seen_kind, 'entity')
  assert.match(first.claim.canonical_text, /第一次记录/)
  assert.deepEqual(first.selection_hints.allowed_surfaces, ['pwa_pending_ai_card', 'record_detail'])
  assert.equal(first.selection_hints.exposure_key, 'expense:merchant:entity:merchant_example:first-occurrence')
  assert.equal(first.selection_hints.dedupe_key, first.selection_hints.exposure_key)
  assert.deepEqual(first.numbers, [
    { value: 1, meaning: 'first_occurrence_count', role: 'count', derivation: 'merchant_observation.entity_first_seen' },
    { value: 6.28, meaning: 'current_record_amount', role: 'measure', derivation: 'source_event.amount' },
  ])
})

test('does not turn a new alias of an existing merchant into a first-occurrence insight', () => {
  const candidates = generateMerchantFirstOccurrenceCandidate({
    event_id: 'transaction:first-alias',
    target_id: 'first-alias',
    amount: 12,
    event_at: '2026-08-05T10:20:00+08:00',
    merchant: {
      entity_id: 'merchant_example',
      canonical_name: '示例茶饮',
      raw_name: '示例茶饮（外卖）',
      normalized_key: '示例茶饮外卖',
    },
  }, {
    entity_id: 'merchant_example',
    canonical_name: '示例茶饮',
    raw_name: '示例茶饮（外卖）',
    normalized_key: '示例茶饮外卖',
    entity_first_seen: false,
    alias_first_seen: true,
  })

  assert.deepEqual(candidates, [])
})

test('does not generate a first-occurrence candidate without a first-seen observation', () => {
  assert.deepEqual(generateMerchantFirstOccurrenceCandidate({
    event_id: 'transaction:known-merchant', amount: 12,
    merchant: { entity_id: 'merchant_example', canonical_name: '示例茶饮' },
  }, {
    entity_id: 'merchant_example', canonical_name: '示例茶饮',
    entity_first_seen: false, alias_first_seen: false,
  }), [])
})
