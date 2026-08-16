import test from 'node:test'
import assert from 'node:assert/strict'

import { createScreenshotRepaymentFeature } from '../createScreenshotRepaymentFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

const command = { stagingId: 'staging-1', cycleId: 'cycle-1', paidAmount: 100, debitAccountId: 'debit-1' }
const accepted = { status: 'accepted', reason: 'confirmed_from_screenshot', cycle: { id: 'cycle-1', accountId: 'account-1' } }

test('PWA-067D reuses identical commands and rejects conflicts', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createScreenshotRepaymentFeature({
    repository: { confirmStagingRepayment: () => { calls += 1; return pending.promise } },
    getCurrentUserId: () => 'user-1',
  })
  const first = feature.confirm(command)
  const duplicate = feature.confirm({ ...command })
  const conflict = await feature.confirm({ ...command, paidAmount: 80 })
  assert.equal(first, duplicate)
  assert.equal(conflict.status, 'rejected')
  assert.equal(conflict.reason, 'screenshot_repayment_conflict')
  pending.resolve(accepted)
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-067D reset and user changes make accepted transport stale without hooks', async () => {
  const pending = deferred()
  let userId = 'user-1'
  let hooks = 0
  const feature = createScreenshotRepaymentFeature({
    repository: { confirmStagingRepayment: () => pending.promise },
    getCurrentUserId: () => userId,
  })
  const request = feature.confirm(command, { onAccepted: () => { hooks += 1 }, refresh: () => { hooks += 1 } })
  userId = 'user-2'
  pending.resolve(accepted)
  assert.deepEqual(await request, { status: 'stale', reason: 'session_changed', cycle: null })
  assert.equal(hooks, 0)
})

test('PWA-067E keeps accepted when refresh fails after convergence', async () => {
  const events = []
  const feature = createScreenshotRepaymentFeature({
    repository: { confirmStagingRepayment: async () => accepted },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.confirm(command, {
    onAccepted: value => { events.push(`cycle:${value.cycle.id}`) },
    refresh: async () => { events.push('refresh'); throw new Error('刷新失败') },
  })
  assert.deepEqual(events, ['cycle:cycle-1', 'refresh'])
  assert.equal(result.status, 'accepted')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '刷新失败')
})

test('PWA-067E still refreshes and keeps accepted when local convergence throws', async () => {
  const events = []
  const feature = createScreenshotRepaymentFeature({
    repository: { confirmStagingRepayment: async () => accepted },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.confirm(command, {
    onAccepted: () => { events.push('converge'); throw new Error('本地收敛失败') },
    refresh: async () => { events.push('refresh') },
  })
  assert.deepEqual(events, ['converge', 'refresh'])
  assert.equal(result.status, 'accepted')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '本地收敛失败')
})
