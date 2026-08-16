import test from 'node:test'
import assert from 'node:assert/strict'
import { createStagingArchiveFeature } from '../createStagingArchiveFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(nextResolve => { resolve = nextResolve })
  return { promise, resolve }
}

test('PWA-035 missing finance amount is rejected before the repository', async () => {
  let calls = 0
  const feature = createStagingArchiveFeature({
    repository: { archive: async () => { calls += 1 } },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.archive({ id: 'staging-1' }, 'expense', { payload: {} })

  assert.equal(result.status, 'rejected')
  assert.equal(result.reason, 'missing_amount')
  assert.equal(result.recordStillVisible, true)
  assert.equal(calls, 0)
})

test('PWA-040 duplicate archive clicks share one atomic request', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createStagingArchiveFeature({
    repository: {
      archive: async () => {
        calls += 1
        return pending.promise
      },
    },
    getCurrentUserId: () => 'user-1',
  })

  const input = { id: 'staging-2' }
  const first = feature.archive(input, 'expense', { payload: { amount: 12 } })
  const second = feature.archive(input, 'expense', { payload: { amount: 12 } })
  assert.equal(first, second)
  pending.resolve({ status: 'accepted', targetRecordId: 'target-2', recordStillVisible: false })
  assert.equal((await first).targetRecordId, 'target-2')
  assert.equal(calls, 1)
})

test('PWA-040 session change marks an in-flight archive stale', async () => {
  const pending = deferred()
  let userId = 'user-old'
  const feature = createStagingArchiveFeature({
    repository: { archive: () => pending.promise },
    getCurrentUserId: () => userId,
  })

  const request = feature.archive({ id: 'staging-3' }, 'sport', { payload: {} })
  userId = 'user-new'
  feature.reset()
  pending.resolve({ status: 'accepted', targetRecordId: 'target-3', recordStillVisible: false })

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(result.reason, 'session_changed')
  assert.equal(result.recordStillVisible, true)
})

test('PWA-040 accepted archive remains a success even when the caller refresh fails', async () => {
  const feature = createStagingArchiveFeature({
    repository: {
      archive: async () => ({
        status: 'accepted',
        targetRecordId: 'target-4',
        recordStillVisible: false,
      }),
    },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.archive({ id: 'staging-4' }, 'sport', {
    payload: {},
    afterAccepted: async () => { throw new Error('refresh failed') },
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.targetRecordId, 'target-4')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.recordStillVisible, false)
})
