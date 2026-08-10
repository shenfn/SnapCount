import test from 'node:test'
import assert from 'node:assert/strict'
import { generateCrossRecordRelationshipCandidates } from '../lib/cross-record-relationships.mjs'

function expense(id, occurredAt, item) {
  return {
    id,
    domain_key: 'expense',
    occurred_at: occurredAt,
    created_at: occurredAt,
    merchant_name: '外卖平台',
    title: item ? `外卖 ${item}` : '外卖订单',
    payload: { items: item ? [{ name: item }] : [] },
    source_type: 'transaction',
  }
}

function food(id, occurredAt, item) {
  return {
    id,
    domain_key: 'food',
    occurred_at: occurredAt,
    created_at: occurredAt,
    title: item,
    payload: { dishes: [{ name: item }] },
    source_type: 'data_record',
  }
}

test('EXP-007 creates an uncertain cross-domain candidate when object and event order agree', () => {
  const current = food('food-1', '2026-08-09T18:20:00+08:00', '饺子')
  const candidates = generateCrossRecordRelationshipCandidates({
    currentRecord: current,
    relatedRecords: [expense('order-1', '2026-08-09T17:42:00+08:00', '饺子')],
    timeZone: 'Asia/Shanghai',
  })

  assert.equal(candidates.length, 1)
  const candidate = candidates[0]
  assert.equal(candidate.claim.semantic_key, 'cross_record_possible_life_chain')
  assert.equal(candidate.claim.structured_value.relation_status, 'hypothesis')
  assert.equal(candidate.claim.structured_value.object_overlap, true)
  assert.equal(candidate.claim.structured_value.elapsed_minutes, 38)
  assert.equal(candidate.claim.structured_value.beneficiary, null)
  assert.equal(candidate.claim.structured_value.relation_status, 'hypothesis')
  assert.equal(candidate.evidence.length, 2)
  assert.equal(candidate.quality.confidence >= 0.8, true)
})

test('EXP-007 does not create a strong relationship from time proximity alone', () => {
  const current = food('food-1', '2026-08-09T18:20:00+08:00', '米饭')
  const candidates = generateCrossRecordRelationshipCandidates({
    currentRecord: current,
    relatedRecords: [expense('order-1', '2026-08-09T17:42:00+08:00', null)],
    timeZone: 'Asia/Shanghai',
  })

  assert.deepEqual(candidates, [])
})

test('EXP-007 does not claim an event relationship when event time is unavailable', () => {
  const current = food('food-1', '2026-08-09T18:20:00+08:00', '饺子')
  const candidates = generateCrossRecordRelationshipCandidates({
    currentRecord: current,
    relatedRecords: [{ ...expense('order-1', '2026-08-09T17:42:00+08:00', '饺子'), occurred_at: null, created_at: '2026-08-09T17:42:00+08:00' }],
    timeZone: 'Asia/Shanghai',
  })

  assert.deepEqual(candidates, [])
})

test('EXP-007 ignores a record that was learned after the current record', () => {
  const current = food('food-1', '2026-08-09T18:20:00+08:00', '饺子')
  const futureKnown = {
    ...expense('order-1', '2026-08-09T17:42:00+08:00', '饺子'),
    created_at: '2026-08-09T19:00:00+08:00',
  }
  assert.deepEqual(generateCrossRecordRelationshipCandidates({ currentRecord: current, relatedRecords: [futureKnown] }), [])
})
