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
