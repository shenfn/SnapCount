import test from 'node:test'
import assert from 'node:assert/strict'
import { createExpressionPlanState } from '../createExpressionPlanState.js'

function deferred() {
  let resolve
  let reject
  const promise = new Promise((res, rej) => { resolve = res; reject = rej })
  return { promise, resolve, reject }
}

function delivery(overrides = {}) {
  return {
    available: true,
    plan_token: 'plan-token',
    candidate_id: 'candidate-1',
    presentation_target: 'feedback_card',
    feedback: { candidate_id: 'candidate-1' },
    ...overrides,
  }
}

function makeRepository(handler) {
  const calls = []
  return {
    calls,
    postAction: async (...args) => {
      calls.push(args)
      return handler(...args)
    },
  }
}

test('expression plan state deduplicates loads and exposes the ready cache entry', async () => {
  const repository = makeRepository(async () => delivery())
  const state = createExpressionPlanState({
    repository,
    isDeliveryValid: () => true,
  })

  const first = state.loadRecordExpressionPlan('record-1', { recordKind: 'expense' })
  const second = state.loadRecordExpressionPlan('record-1', { recordKind: 'expense' })

  assert.strictEqual(first, second)
  const result = await first
  assert.equal(repository.calls.length, 1)
  assert.equal(result.status, 'ready')
  assert.equal(state.recordExpressionPlanCache.value['record-1'].candidateId, 'candidate-1')
})

test('invalidating a record prevents an old in-flight response from repopulating the cache', async () => {
  const request = deferred()
  const repository = makeRepository(() => request.promise)
  const state = createExpressionPlanState({ repository, isDeliveryValid: () => true })

  const load = state.loadRecordExpressionPlan('record-2', { recordKind: 'income' })
  state.invalidateRecordExpressionPlan('record-2')
  request.resolve(delivery({ candidate_id: 'stale-candidate' }))

  assert.equal(await load, null)
  assert.equal(state.recordExpressionPlanCache.value['record-2'], undefined)
})

test('invalidating a record prevents an old failure from replacing the cleared cache', async () => {
  const request = deferred()
  const repository = makeRepository(() => request.promise)
  const state = createExpressionPlanState({ repository, isDeliveryValid: () => true })

  const load = state.loadRecordExpressionPlan('record-stale-error', { recordKind: 'expense' })
  state.invalidateRecordExpressionPlan('record-stale-error')
  request.reject(new Error('旧用户请求失败'))

  await assert.rejects(load, /旧用户请求失败/)
  assert.equal(state.recordExpressionPlanCache.value['record-stale-error'], undefined)
})

test('an incomplete delivery identity never enters the ready state', async () => {
  const repository = makeRepository(async () => delivery({ candidate_id: '' }))
  const state = createExpressionPlanState({ repository, isDeliveryValid: () => true })

  await assert.rejects(
    state.loadRecordExpressionPlan('record-incomplete', { recordKind: 'data' }),
    /表达计划响应不完整/,
  )
  assert.equal(state.recordExpressionPlanCache.value['record-incomplete'].status, 'error')
})

test('acknowledgement checks identity and feedback retains the exposure event id', async () => {
  const repository = makeRepository(async action => {
    if (action === 'get_record_expression_plan') return delivery()
    if (action === 'ack_record_expression_plan') return delivery({ exposure_event_id: 'exposure-1' })
    return { accepted: true }
  })
  const state = createExpressionPlanState({
    repository,
    isDeliveryValid: () => true,
    deliveryIdentityMatches: () => true,
  })

  await state.loadRecordExpressionPlan('record-3', { recordKind: 'data' })
  const acknowledged = await state.ackRecordExpressionPlan('record-3')
  assert.equal(acknowledged.status, 'acknowledged')
  assert.equal(acknowledged.feedback.exposure_event_id, 'exposure-1')

  await state.submitExpressionFeedback({
    recordId: 'record-3',
    choice: 'helpful',
    freeText: '保留这个角度',
    exposureEventId: 'exposure-1',
  })
  const feedbackCall = repository.calls.at(-1)
  assert.deepEqual(feedbackCall, [
    'submit_expression_feedback',
    {
      record_id: 'record-3',
      primary_choice: 'helpful',
      free_text: '保留这个角度',
      exposure_event_id: 'exposure-1',
    },
    { keepalive: true },
  ])
})

test('reset clears cache and makes an old response unable to write after user switch', async () => {
  const request = deferred()
  const repository = makeRepository(() => request.promise)
  const state = createExpressionPlanState({ repository, isDeliveryValid: () => true })

  const load = state.loadRecordExpressionPlan('record-4', { recordKind: 'expense' })
  state.reset()
  request.resolve(delivery())

  assert.equal(await load, null)
  assert.deepEqual(state.recordExpressionPlanCache.value, {})
  assert.equal(state.getRecordExpressionPlanCacheRevision('record-4'), 0)
})
