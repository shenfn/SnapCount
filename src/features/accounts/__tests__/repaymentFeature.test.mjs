import test from 'node:test'
import assert from 'node:assert/strict'

import { createRepaymentFeature } from '../createRepaymentFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

function accepted(id = 'cycle-1') {
  return { status: 'accepted', reason: 'confirmed', cycle: { id, accountId: 'liability-1' } }
}

const confirmCommand = {
  cycleId: 'cycle-1',
  accountId: 'liability-1',
  paidAmount: 40,
  debitAccountId: 'debit-1',
  status: 'partial_paid',
  note: '部分还款',
}

test('PWA-064C identical confirmations share a promise and cycle conflicts do not write', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createRepaymentFeature({
    repository: {
      confirmRepayment: command => { calls += 1; assert.equal(command.paidAt, '2026-08-16T08:00:00.000Z'); return pending.promise },
      revokePayment: async () => accepted(),
    },
    getCurrentUserId: () => 'user-1',
    now: () => new Date('2026-08-16T08:00:00Z'),
  })

  const first = feature.confirm(confirmCommand)
  const duplicate = feature.confirm({ ...confirmCommand })
  const conflictingAmount = await feature.confirm({ ...confirmCommand, paidAmount: 50 })
  const conflictingRevoke = await feature.revoke({ paymentId: 'payment-1', cycleId: 'cycle-1', accountId: 'liability-1' })

  assert.equal(first, duplicate)
  assert.deepEqual(conflictingAmount, { status: 'rejected', reason: 'repayment_conflict', cycle: null })
  assert.deepEqual(conflictingRevoke, { status: 'rejected', reason: 'repayment_conflict', cycle: null })
  pending.resolve(accepted())
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-064C identical revocations share one repository write', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createRepaymentFeature({
    repository: {
      confirmRepayment: async () => accepted(),
      revokePayment: () => { calls += 1; return pending.promise },
    },
    getCurrentUserId: () => 'user-1',
  })
  const command = { paymentId: 'payment-1', cycleId: 'cycle-1', accountId: 'liability-1' }

  const first = feature.revoke(command)
  const duplicate = feature.revoke({ ...command })

  assert.equal(first, duplicate)
  pending.resolve({ status: 'accepted', reason: 'revoked', cycle: { id: 'cycle-1' } })
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-064D reset and user switching make old results stale without callbacks', async () => {
  const firstPending = deferred()
  const secondPending = deferred()
  let userId = 'user-1'
  let acceptedCalls = 0
  let refreshCalls = 0
  let callIndex = 0
  const feature = createRepaymentFeature({
    repository: {
      confirmRepayment: () => (callIndex++ === 0 ? firstPending.promise : secondPending.promise),
      revokePayment: async () => accepted(),
    },
    getCurrentUserId: () => userId,
  })
  const options = {
    onAccepted: () => { acceptedCalls += 1 },
    refresh: () => { refreshCalls += 1 },
  }

  const resetRequest = feature.confirm(confirmCommand, options)
  feature.reset()
  firstPending.resolve(accepted())
  assert.deepEqual(await resetRequest, { status: 'stale', reason: 'session_changed', cycle: null })

  const switchedRequest = feature.confirm(confirmCommand, options)
  userId = 'user-2'
  secondPending.resolve(accepted())
  assert.deepEqual(await switchedRequest, { status: 'stale', reason: 'session_changed', cycle: null })
  assert.equal(acceptedCalls, 0)
  assert.equal(refreshCalls, 0)
})

test('PWA-064E canonical convergence precedes refresh and refresh failure stays accepted', async () => {
  const events = []
  const feature = createRepaymentFeature({
    repository: {
      confirmRepayment: async () => accepted(),
      revokePayment: async () => accepted(),
    },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.confirm(confirmCommand, {
    onAccepted: value => { events.push(`cycle:${value.cycle.id}`) },
    refresh: async () => { events.push('refresh'); throw new Error('账户列表刷新失败') },
  })

  assert.deepEqual(events, ['cycle:cycle-1', 'refresh'])
  assert.equal(result.status, 'accepted')
  assert.equal(result.cycle.id, 'cycle-1')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '账户列表刷新失败')
})

test('PWA-064D unauthenticated and malformed commands stop before transport', async () => {
  let calls = 0
  const feature = createRepaymentFeature({
    repository: {
      confirmRepayment: async () => { calls += 1; return accepted() },
      revokePayment: async () => { calls += 1; return accepted() },
    },
    getCurrentUserId: () => '',
  })

  assert.equal((await feature.confirm(confirmCommand)).reason, 'unauthenticated')
  assert.equal((await feature.revoke({ paymentId: 'payment-1', cycleId: 'cycle-1', accountId: 'liability-1' })).reason, 'unauthenticated')

  const authenticated = createRepaymentFeature({
    repository: {
      confirmRepayment: async () => { calls += 1; return accepted() },
      revokePayment: async () => { calls += 1; return accepted() },
    },
    getCurrentUserId: () => 'user-1',
  })
  assert.equal((await authenticated.confirm({ ...confirmCommand, paidAmount: 0 })).reason, 'invalid_input')
  assert.equal((await authenticated.revoke({ paymentId: '', cycleId: 'cycle-1', accountId: 'liability-1' })).reason, 'invalid_input')
  assert.equal(calls, 0)
})
