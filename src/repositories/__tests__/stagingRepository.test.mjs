import test from 'node:test'
import assert from 'node:assert/strict'
import { createStagingRepository } from '../stagingRepository.js'

function createClient() {
  return {
    auth: {
      async getSession() {
        return { data: { session: { access_token: 'token-1' } }, error: null }
      },
    },
  }
}

test('PWA-028 repository sends only staging id and maps server retry limit', async () => {
  let request
  const repository = createStagingRepository({
    client: createClient(),
    baseUrl: 'https://api.example.test/',
    anonKey: 'anon-1',
    fetchImpl: async (url, options) => {
      request = { url, options }
      return new Response(JSON.stringify({ error: 'Retry limit exceeded (max 3)' }), { status: 400 })
    },
  })

  const result = await repository.retry('staging-1')

  assert.equal(result.status, 'rejected')
  assert.equal(result.reason, 'retry_limit_exceeded')
  assert.equal(result.recordStillVisible, true)
  assert.equal(request.url, 'https://api.example.test/functions/v1/ingest-receipt')
  assert.equal(request.options.headers.Authorization, 'Bearer token-1')
  assert.equal(request.options.headers.apikey, 'anon-1')
  assert.equal(await request.options.body.get('staging_record_id'), 'staging-1')
  assert.equal(request.options.body.get('user_id'), null)
})

test('PWA-030 repository preserves a retry failure as a visible structured result', async () => {
  const repository = createStagingRepository({
    client: createClient(),
    baseUrl: 'https://api.example.test',
    fetchImpl: async () => new Response(JSON.stringify({
      status: 'staging',
      message: '重试未确定',
    }), { status: 200 }),
  })

  const result = await repository.retry('staging-2')

  assert.deepEqual(
    {
      status: result.status,
      reason: result.reason,
      attempted: result.attempted,
      recordStillVisible: result.recordStillVisible,
    },
    {
      status: 'failed',
      reason: 'retry_failed',
      attempted: true,
      recordStillVisible: true,
    },
  )
})

test('PWA-040 repository archives through the atomic RPC without user_id', async () => {
  let rpcCall
  const repository = createStagingRepository({
    client: {
      ...createClient(),
      async rpc(name, payload) {
        rpcCall = { name, payload }
        return {
          data: {
            target_record_id: 'target-1',
            target_reference: 'expense/target-1',
            idempotent_retry: false,
          },
          error: null,
        }
      },
    },
    baseUrl: 'https://api.example.test',
    anonKey: 'anon-1',
    fetchImpl: async () => new Response('{}'),
  })

  const result = await repository.archive({
    stagingId: 'staging-1',
    domainKey: 'expense',
    amount: 12.5,
    title: '午餐',
    accountId: 'account-1',
    payload: { source: 'contract-test' },
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.targetRecordId, 'target-1')
  assert.equal(rpcCall.name, 'archive_staging_record')
  assert.equal(rpcCall.payload.p_staging_id, 'staging-1')
  assert.equal(rpcCall.payload.p_domain_key, 'expense')
  assert.equal(rpcCall.payload.p_amount, 12.5)
  assert.equal(rpcCall.payload.p_account_id, 'account-1')
  assert.equal(Object.hasOwn(rpcCall.payload, 'user_id'), false)
})

test('PWA-042 repository discards through the authoritative RPC and maps cleanup facts', async () => {
  let rpcCall
  const repository = createStagingRepository({
    client: {
      ...createClient(),
      async rpc(name, payload) {
        rpcCall = { name, payload }
        return {
          data: {
            staging_id: 'staging-discard-1',
            status: 'discarded',
            cleanup_status: 'pending',
            cleanup_queued: true,
            bucket_path: 'user-1/receipt.png',
          },
          error: null,
        }
      },
    },
    baseUrl: 'https://api.example.test',
    fetchImpl: async () => new Response('{}'),
  })

  const result = await repository.discard({
    stagingId: 'staging-discard-1',
    reason: 'user_discarded',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'discarded')
  assert.equal(result.cleanupStatus, 'pending')
  assert.equal(result.cleanupQueued, true)
  assert.equal(result.recordStillVisible, false)
  assert.equal(rpcCall.name, 'discard_staging_record')
  assert.deepEqual(rpcCall.payload, {
    p_staging_id: 'staging-discard-1',
    p_reason: 'user_discarded',
  })
  assert.equal(Object.hasOwn(rpcCall.payload, 'user_id'), false)
})
