import test from 'node:test'
import assert from 'node:assert/strict'
import {
  CURRENT_PRIVACY_VERSION,
  CURRENT_TERMS_VERSION,
  createAuthRepository,
} from '../authRepository.js'

function createClient() {
  const calls = []
  let listener = null
  let unsubscribed = false
  const auth = {
    async getSession() {
      calls.push(['getSession'])
      return { data: { session: { user: { id: 'user-1', email: 'a@example.com' } } }, error: null }
    },
    onAuthStateChange(nextListener) {
      calls.push(['subscribe'])
      listener = nextListener
      return { data: { subscription: { unsubscribe: () => { unsubscribed = true } } } }
    },
    async signInWithPassword(input) {
      calls.push(['signIn', input])
      return { data: { user: { id: 'user-1' }, session: {} }, error: null }
    },
    async signUp(input) {
      calls.push(['signUp', input])
      return { data: { user: { id: 'user-1' }, session: {} }, error: null }
    },
    async signOut() {
      calls.push(['signOut'])
      return { error: null }
    },
  }
  return {
    auth,
    calls,
    emit: (event, session) => listener?.(event, session),
    wasUnsubscribed: () => unsubscribed,
    from() {
      throw new Error('Auth Repository 不得访问 user_configs')
    },
  }
}

test('PWA-023 registration sends current consent metadata without writing user_configs', async () => {
  const client = createClient()
  const repository = createAuthRepository({
    client,
    now: () => new Date('2026-08-16T08:00:00.000Z'),
  })

  await repository.signUp({
    email: ' person@example.com ',
    password: '123456',
    acceptedTerms: true,
    acceptedSensitiveData: true,
  })

  const signUpCall = client.calls.find(([kind]) => kind === 'signUp')
  assert.deepEqual(signUpCall[1], {
    email: 'person@example.com',
    password: '123456',
    options: {
      data: {
        legal_consent_at: '2026-08-16T08:00:00.000Z',
        sensitive_data_consent_at: '2026-08-16T08:00:00.000Z',
        terms_version: CURRENT_TERMS_VERSION,
        privacy_version: CURRENT_PRIVACY_VERSION,
      },
    },
  })
})

test('PWA-023 registration rejects missing consent before transport', async () => {
  const client = createClient()
  const repository = createAuthRepository({ client })

  await assert.rejects(repository.signUp({
    email: 'person@example.com',
    password: '123456',
    acceptedTerms: true,
    acceptedSensitiveData: false,
  }), /敏感数据/)
  assert.equal(client.calls.some(([kind]) => kind === 'signUp'), false)
})

test('PWA-024 sign-in errors are propagated without retrying the auth write', async () => {
  const client = createClient()
  const transportError = Object.assign(new Error('网络请求失败'), {
    code: 'network_error',
    retryable: true,
  })
  client.auth.signInWithPassword = async input => {
    client.calls.push(['signIn', input])
    return { data: null, error: transportError }
  }
  const repository = createAuthRepository({ client })

  await assert.rejects(
    repository.signIn({ email: 'person@example.com', password: '123456' }),
    error => error === transportError,
  )
  assert.equal(client.calls.filter(([kind]) => kind === 'signIn').length, 1)
})

test('PWA-022 auth subscription exposes a real unsubscribe function', () => {
  const client = createClient()
  const repository = createAuthRepository({ client })
  const events = []

  const unsubscribe = repository.subscribe((event, session) => events.push([event, session]))
  client.emit('SIGNED_IN', { user: { id: 'user-1' } })
  unsubscribe()

  assert.deepEqual(events, [['SIGNED_IN', { user: { id: 'user-1' } }]])
  assert.equal(client.wasUnsubscribed(), true)
})
