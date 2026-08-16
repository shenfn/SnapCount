import test from 'node:test'
import assert from 'node:assert/strict'
import { createStagingDiscardFeature } from '../createStagingDiscardFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(nextResolve => { resolve = nextResolve })
  return { promise, resolve }
}

test('PWA-043 duplicate discard clicks share one authoritative request', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createStagingDiscardFeature({
    repository: {
      discard: async () => {
        calls += 1
        return pending.promise
      },
    },
    getCurrentUserId: () => 'user-1',
  })

  const record = { id: 'staging-1' }
  const first = feature.discard(record, 'user_discarded')
  const second = feature.discard(record, 'user_discarded')
  assert.equal(first, second)
  pending.resolve({ status: 'accepted', reason: 'discarded', recordStillVisible: false })
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-044 session change marks an in-flight discard stale', async () => {
  const pending = deferred()
  let userId = 'user-old'
  const feature = createStagingDiscardFeature({
    repository: { discard: () => pending.promise },
    getCurrentUserId: () => userId,
  })

  const request = feature.discard({ id: 'staging-2' })
  userId = 'user-new'
  feature.reset()
  pending.resolve({ status: 'accepted', reason: 'discarded', recordStillVisible: false })

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(result.reason, 'session_changed')
  assert.equal(result.recordStillVisible, true)
})

test('PWA-045 repository failure keeps the staging record visible', async () => {
  const feature = createStagingDiscardFeature({
    repository: {
      discard: async () => ({
        status: 'failed',
        reason: 'service_error',
        recordStillVisible: true,
        error: 'discard failed',
      }),
    },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.discard({ id: 'staging-3' })
  assert.equal(result.status, 'failed')
  assert.equal(result.recordStillVisible, true)
})

test('PWA-046 accepted discard remains successful when local convergence fails', async () => {
  const feature = createStagingDiscardFeature({
    repository: {
      discard: async () => ({
        status: 'accepted',
        reason: 'discarded',
        recordStillVisible: false,
      }),
    },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.discard({ id: 'staging-4' }, 'user_discarded', {
    afterAccepted: async () => { throw new Error('local convergence failed') },
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.convergenceStatus, 'failed')
  assert.equal(result.recordStillVisible, false)
  assert.match(result.convergenceError, /local convergence failed/)
})
