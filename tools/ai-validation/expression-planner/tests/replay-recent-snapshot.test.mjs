import test from 'node:test'
import assert from 'node:assert/strict'
import { compareRecords, replaySnapshot } from '../replay-recent-snapshot.mjs'

const evaluationWindow = {
  start: '2026-08-07T00:00:00+08:00',
  end_exclusive: '2026-08-08T00:00:00+08:00',
}

function expense({ id, userId, day, amount = 6.28, merchant = '示例茶饮' }) {
  return {
    id,
    ...(userId ? { user_id: userId } : {}),
    type: 'expense',
    transaction_date: day,
    transaction_time: '12:00:00',
    created_at: `${day}T12:01:00+08:00`,
    amount,
    merchant_name: merchant,
    category: 'food',
    platform: '外卖',
    payment_method: '微信支付',
    status: 'done',
  }
}

function candidateKeys(record) {
  return record.candidates.map(candidate => candidate.semantic_key)
}

test('replay isolates first-occurrence history by user without leaking user ids', async () => {
  const firstUserId = '11111111-1111-4111-8111-111111111111'
  const secondUserId = '22222222-2222-4222-8222-222222222222'
  const output = await replaySnapshot({
    schema_version: 'expression-planner-public-replay-fixture-v0.1',
    window: evaluationWindow,
    transactions: [
      expense({ id: 'first-user-history', userId: firstUserId, day: '2026-08-06' }),
      expense({ id: 'first-user-current', userId: firstUserId, day: '2026-08-07' }),
      expense({ id: 'second-user-current', userId: secondUserId, day: '2026-08-07' }),
    ],
    domain_records: [],
  })

  const firstUser = output.records.find(record => record.record_id === 'first-user-current')
  const secondUser = output.records.find(record => record.record_id === 'second-user-current')
  assert.ok(firstUser)
  assert.ok(secondUser)
  assert.equal(candidateKeys(firstUser).includes('expense_merchant_first_occurrence'), false)
  assert.equal(candidateKeys(secondUser).includes('expense_merchant_first_occurrence'), true)

  const serialized = JSON.stringify(output)
  assert.equal(serialized.includes('user_id'), false)
  assert.equal(serialized.includes(firstUserId), false)
  assert.equal(serialized.includes(secondUserId), false)
})

test('replay keeps a missing-user-id snapshot compatible as one anonymized account', async () => {
  const output = await replaySnapshot({
    schema_version: 'expression-planner-public-replay-fixture-v0.1',
    window: evaluationWindow,
    transactions: [
      expense({ id: 'anonymous-history', day: '2026-08-06' }),
      expense({ id: 'anonymous-current', day: '2026-08-07' }),
    ],
    domain_records: [],
  })

  const current = output.records.find(record => record.record_id === 'anonymous-current')
  assert.ok(current)
  assert.equal(candidateKeys(current).includes('expense_merchant_first_occurrence'), false)
})

test('replay isolates generic-domain baselines by user and domain', async () => {
  const sleepRecord = ({ id, userId, occurredAt, hours }) => ({
    id,
    user_id: userId,
    domain_key: 'sleep',
    created_at: occurredAt,
    occurred_at: occurredAt,
    payload_jsonb: { sleep_hours: hours },
  })
  const firstUserId = '33333333-3333-4333-8333-333333333333'
  const secondUserId = '44444444-4444-4444-8444-444444444444'
  const output = await replaySnapshot({
    schema_version: 'expression-planner-public-replay-fixture-v0.1',
    window: evaluationWindow,
    transactions: [],
    domain_records: [
      sleepRecord({ id: 'sleep-history-1', userId: firstUserId, occurredAt: '2026-08-03T08:00:00+08:00', hours: 7 }),
      sleepRecord({ id: 'sleep-history-2', userId: firstUserId, occurredAt: '2026-08-04T08:00:00+08:00', hours: 7 }),
      sleepRecord({ id: 'sleep-history-3', userId: firstUserId, occurredAt: '2026-08-05T08:00:00+08:00', hours: 7 }),
      sleepRecord({ id: 'sleep-first-user-current', userId: firstUserId, occurredAt: '2026-08-07T08:00:00+08:00', hours: 5 }),
      sleepRecord({ id: 'sleep-second-user-current', userId: secondUserId, occurredAt: '2026-08-07T09:00:00+08:00', hours: 5 }),
    ],
  })

  const firstUser = output.records.find(record => record.record_id === 'sleep-first-user-current')
  const secondUser = output.records.find(record => record.record_id === 'sleep-second-user-current')
  assert.ok(firstUser)
  assert.ok(secondUser)
  assert.equal(candidateKeys(firstUser).includes('sleep_vs_personal_median'), true)
  assert.equal(candidateKeys(secondUser).includes('sleep_vs_personal_median'), false)
})

test('baseline comparison reports candidate, selection, and zero-candidate regressions', () => {
  const baseline = [{
    record_id: 'record-1', domain_key: 'expense', candidate_count: 1,
    candidates: [{ semantic_key: 'candidate-before' }],
    plan_summary: { record_detail: { selected: [{ semantic_key: 'candidate-before' }] } },
  }, {
    record_id: 'record-stable', domain_key: 'sleep', candidate_count: 1,
    candidates: [{ semantic_key: 'sleep_current_metric' }],
    plan_summary: { record_detail: { selected: [{ semantic_key: 'sleep_current_metric' }] } },
  }]
  const current = [{
    record_id: 'record-1', domain_key: 'expense', candidate_count: 0,
    candidates: [], plan_summary: { record_detail: { selected: [] } },
  }, baseline[1]]

  const comparison = compareRecords(baseline, current)
  assert.equal(comparison.candidate_change_count, 1)
  assert.equal(comparison.selection_change_count, 1)
  assert.equal(comparison.zero_candidate_regression_count, 1)
  assert.equal(comparison.zero_candidate_regressions[0].record_id, 'record-1')
})

test('baseline comparison stays empty when records are unchanged', () => {
  const record = {
    record_id: 'record-stable', domain_key: 'reading', candidate_count: 1,
    candidates: [{ semantic_key: 'reading_current_metric' }],
    plan_summary: { record_detail: { selected: [{ semantic_key: 'reading_current_metric' }] } },
  }
  assert.deepEqual(compareRecords([record], [record]), {
    candidate_change_count: 0,
    selection_change_count: 0,
    zero_candidate_regression_count: 0,
    candidate_changes: [],
    selection_changes: [],
    zero_candidate_regressions: [],
  })
})
