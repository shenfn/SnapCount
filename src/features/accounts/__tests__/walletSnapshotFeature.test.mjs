import test from 'node:test'
import assert from 'node:assert/strict'

import { createWalletSnapshotFeature } from '../createWalletSnapshotFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(r => { resolve = r })
  return { promise, resolve }
}

const accepted = {
  status: 'accepted', reason: 'linked', recordId: 'record-1', linkedAccountId: 'account-1',
  account: { id: 'account-1' }, cycle: null, payment: null,
  balanceChanged: false, reviewRequired: false,
}

test('PWA-068H identical commands share a promise and different targets conflict', async () => {
  const pending = deferred()
  const calls = []
  const feature = createWalletSnapshotFeature({
    repository: { applyWalletSnapshot: command => { calls.push(command); return pending.promise } },
    getCurrentUserId: () => 'user-1',
  })

  const first = feature.apply({ operation: 'link', recordId: 'record-1', accountId: 'account-1' })
  const same = feature.apply({ operation: 'link', recordId: 'record-1', accountId: 'account-1' })
  const conflict = await feature.apply({ operation: 'link', recordId: 'record-1', accountId: 'account-2' })

  assert.equal(first, same)
  assert.equal(conflict.status, 'conflict')
  assert.equal(conflict.reason, 'wallet_snapshot_conflict')
  assert.equal(calls.length, 1)
  pending.resolve(accepted)
  assert.equal((await first).status, 'accepted')
})

test('PWA-068H reset and user switching make old accepted results stale without hooks', async () => {
  const pending = deferred()
  let userId = 'user-1'
  let acceptedCalls = 0
  let refreshCalls = 0
  const feature = createWalletSnapshotFeature({
    repository: { applyWalletSnapshot: () => pending.promise },
    getCurrentUserId: () => userId,
  })

  const request = feature.apply(
    { operation: 'create', recordId: 'record-1' },
    { onAccepted: () => { acceptedCalls += 1 }, refresh: () => { refreshCalls += 1 } },
  )
  userId = 'user-2'
  feature.reset()
  pending.resolve(accepted)

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(acceptedCalls, 0)
  assert.equal(refreshCalls, 0)
})

test('PWA-068H accepted convergence precedes refresh and refresh failure stays accepted', async () => {
  const order = []
  const feature = createWalletSnapshotFeature({
    repository: { applyWalletSnapshot: async () => ({ ...accepted, reason: 'needs_confirmation', reviewRequired: true }) },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.apply(
    { operation: 'link', recordId: 'record-1', accountId: 'account-1' },
    {
      onAccepted: async () => { order.push('accepted') },
      refresh: async () => { order.push('refresh'); throw new Error('刷新失败') },
    },
  )

  assert.deepEqual(order, ['accepted', 'refresh'])
  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'needs_confirmation')
  assert.equal(result.reviewRequired, true)
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '刷新失败')
})

test('PWA-068H malformed and unauthenticated commands stop before transport', async () => {
  let calls = 0
  const repository = { applyWalletSnapshot: async () => { calls += 1; return accepted } }
  const anonymous = createWalletSnapshotFeature({ repository, getCurrentUserId: () => null })
  const signedIn = createWalletSnapshotFeature({ repository, getCurrentUserId: () => 'user-1' })

  assert.equal((await anonymous.apply({ operation: 'create', recordId: 'record-1' })).reason, 'unauthenticated')
  assert.equal((await signedIn.apply({ operation: 'create', recordId: '' })).reason, 'invalid_input')
  assert.equal((await signedIn.apply({ operation: 'link', recordId: 'record-1' })).reason, 'invalid_input')
  assert.equal(calls, 0)
})
