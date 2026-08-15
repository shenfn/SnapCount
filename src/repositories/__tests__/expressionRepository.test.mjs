import test from 'node:test'
import assert from 'node:assert/strict'
import { createExpressionRepository } from '../expressionRepository.js'

function authWithToken(token = 'token-1') {
  return { auth: { getSession: async () => ({ data: { session: token ? { access_token: token } : null }, error: null }) } }
}

test('expression repository posts an authenticated action and returns data', async () => {
  const requests = []
  const repository = createExpressionRepository({
    client: authWithToken(),
    baseUrl: 'https://api.example.test',
    anonKey: 'anon-key',
    fetchImpl: async (url, init) => {
      requests.push({ url, init })
      return new Response(JSON.stringify({ ok: true, data: { available: false, reason: 'plan_not_ready' } }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      })
    },
  })

  const data = await repository.postAction('get_record_expression_plan', { record_id: 'record-1' })

  assert.deepEqual(data, { available: false, reason: 'plan_not_ready' })
  assert.equal(requests.length, 1)
  assert.equal(requests[0].url, 'https://api.example.test/functions/v1/ingest-receipt')
  assert.equal(requests[0].init.method, 'POST')
  assert.equal(requests[0].init.headers.Authorization, 'Bearer token-1')
  assert.equal(requests[0].init.headers.apikey, 'anon-key')
  assert.deepEqual(JSON.parse(requests[0].init.body), {
    action: 'get_record_expression_plan',
    record_id: 'record-1',
  })
})

test('expression repository rejects an expired session before making a request', async () => {
  let requestCount = 0
  const repository = createExpressionRepository({
    client: authWithToken(''),
    baseUrl: 'https://api.example.test',
    anonKey: 'anon-key',
    fetchImpl: async () => {
      requestCount += 1
      return new Response('{}', { status: 200 })
    },
  })

  await assert.rejects(
    repository.postAction('ack_record_expression_plan', {}),
    /登录状态已失效，请重新登录/,
  )
  assert.equal(requestCount, 0)
})

test('expression repository preserves retry metadata from action failures', async () => {
  const repository = createExpressionRepository({
    client: authWithToken(),
    baseUrl: 'https://api.example.test',
    anonKey: 'anon-key',
    fetchImpl: async () => new Response(JSON.stringify({ ok: false, error: '稍后重试' }), { status: 503 }),
  })

  await assert.rejects(repository.postAction('submit_expression_feedback', {}), error => {
    assert.equal(error.message, '稍后重试')
    assert.equal(error.status, 503)
    assert.equal(error.retryable, true)
    return true
  })
})
