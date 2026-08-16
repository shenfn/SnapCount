import test from 'node:test'
import assert from 'node:assert/strict'
import { createStagingRetryFeature } from '../createStagingRetryFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(nextResolve => { resolve = nextResolve })
  return { promise, resolve }
}

test('PWA-028 local retry preflight leaves maxed record visible without transport', async () => {
  let calls = 0
  const feature = createStagingRetryFeature({
    repository: { retry: async () => { calls += 1 } },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.retry({ id: 'staging-1', retryCount: 3 })

  assert.equal(result.status, 'rejected')
  assert.equal(result.reason, 'retry_limit_exceeded')
  assert.equal(result.recordStillVisible, true)
  assert.equal(result.localPreflight, true)
  assert.equal(calls, 0)
})

test('PWA-030 failed retry keeps the record and advances only a completed retry attempt', async () => {
  const feature = createStagingRetryFeature({
    repository: { retry: async () => ({ status: 'failed', reason: 'retry_failed', attempted: true, recordStillVisible: true }) },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.retry({ id: 'staging-2', retryCount: 1 })

  assert.equal(result.status, 'failed')
  assert.equal(result.recordStillVisible, true)
  assert.equal(result.nextRetryCount, 2)
})

test('PWA-031 a session change makes the old response stale', async () => {
  const pending = deferred()
  let userId = 'user-old'
  const feature = createStagingRetryFeature({
    repository: { retry: () => pending.promise },
    getCurrentUserId: () => userId,
  })

  const request = feature.retry({ id: 'staging-3', retryCount: 0 })
  userId = 'user-new'
  feature.reset()
  pending.resolve({ status: 'accepted', recordStillVisible: false })

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(result.recordStillVisible, true)
})

test('PWA-032 duplicate clicks share one retry request', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createStagingRetryFeature({
    repository: { retry: async () => { calls += 1; return pending.promise } },
    getCurrentUserId: () => 'user-1',
  })

  const first = feature.retry({ id: 'staging-4', retryCount: 0 })
  const second = feature.retry({ id: 'staging-4', retryCount: 0 })
  assert.equal(first, second)
  pending.resolve({ status: 'accepted', recordStillVisible: false })
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})
