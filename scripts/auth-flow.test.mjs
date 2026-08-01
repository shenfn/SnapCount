import assert from 'node:assert/strict'
import test from 'node:test'
import {
  authCallbackError,
  authRedirectURL,
  friendlyAuthError,
  hasAuthCallbackPayload,
  readAuthCallbackIntent,
  sanitizedAuthCallbackPath,
} from '../src/lib/authFlow.js'
import {
  ACCOUNT_CONSENT_VERSIONS,
  acceptCurrentAccountConsent,
  isAccountConsentCurrent,
  normalizeAccountConsentStatus,
} from '../src/lib/accountConsent.js'
import {
  canLoadBusinessData,
  createUserDataContext,
  isSameSessionUser,
  isUserDataContextCurrent,
} from '../src/lib/userSessionGuard.js'
import {
  loadAccountDeletionReceipt,
  normalizeAccountDeletionResult,
  requestAccountDeletion,
  saveAccountDeletionReceipt,
} from '../src/lib/accountDeletion.js'

test('recognizes only callback URLs with recovery evidence', () => {
  assert.equal(
    readAuthCallbackIntent('https://snapflow.me/?auth_action=recovery&code=one-time-code'),
    'recovery',
  )
  assert.equal(
    readAuthCallbackIntent('https://snapflow.me/#access_token=token&type=recovery'),
    'recovery',
  )
  assert.equal(readAuthCallbackIntent('https://snapflow.me/?auth_action=recovery'), null)
})

test('isolates legacy PKCE callbacks before their auth event reveals the flow', () => {
  const legacyCallback = 'https://snapflow.me/?code=one-time-code'
  assert.equal(readAuthCallbackIntent(legacyCallback), null)
  assert.equal(hasAuthCallbackPayload(legacyCallback), true)
})

test('recognizes confirmation callbacks and callback failures', () => {
  assert.equal(
    readAuthCallbackIntent('https://snapflow.me/?auth_action=confirm&code=one-time-code'),
    'confirmation',
  )
  assert.equal(
    readAuthCallbackIntent('https://snapflow.me/#access_token=token&type=signup'),
    'confirmation',
  )
  assert.deepEqual(
    authCallbackError('https://snapflow.me/?auth_action=recovery&error=access_denied&error_code=otp_expired&error_description=expired'),
    { code: 'otp_expired', message: 'expired' },
  )
})

test('removes one-time auth material without dropping unrelated query parameters', () => {
  assert.equal(
    sanitizedAuthCallbackPath('https://snapflow.me/?utm_source=mail&auth_action=confirm&code=secret#access_token=secret'),
    '/?utm_source=mail',
  )
})

test('builds exact same-origin redirect URLs', () => {
  assert.equal(
    authRedirectURL('recovery', 'https://snapflow.me'),
    'https://snapflow.me/?auth_action=recovery',
  )
})

test('maps Supabase errors to stable messages without exposing internals', () => {
  assert.equal(friendlyAuthError({ message: 'Invalid login credentials' }), '邮箱或密码不正确')
  assert.equal(friendlyAuthError({ code: 'over_email_send_rate_limit' }), '操作过于频繁，请稍后再试')
  assert.equal(
    friendlyAuthError({ message: 'relation user_configs does not exist' }),
    '操作失败，请稍后重试',
  )
})

test('blocks historical accounts with no sensitive-data version', () => {
  const status = normalizeAccountConsentStatus({
    is_active: true,
    needs_consent: true,
    missing: ['sensitive_data'],
    required_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-22',
      sensitive_data: '2026-07-22',
    },
    accepted_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-22',
      sensitive_data: null,
    },
  })
  assert.equal(isAccountConsentCurrent(status), false)
})

test('fails closed for incomplete or malformed consent responses', () => {
  const requiredVersions = {
    terms: '2026-07-19',
    privacy: '2026-07-22',
    sensitive_data: '2026-07-22',
  }
  const acceptedVersions = { ...requiredVersions }
  const valid = {
    is_active: true,
    needs_consent: false,
    missing: [],
    required_versions: requiredVersions,
    accepted_versions: acceptedVersions,
    legal_consent_at: '2026-08-01T00:00:00Z',
    sensitive_data_consent_at: '2026-08-01T00:00:00Z',
  }

  assert.equal(normalizeAccountConsentStatus({ required_versions: requiredVersions }), null)
  assert.equal(normalizeAccountConsentStatus({ ...valid, is_active: 'true' }), null)
  assert.equal(normalizeAccountConsentStatus({ ...valid, needs_consent: null }), null)
  assert.equal(normalizeAccountConsentStatus({ ...valid, missing: 'none' }), null)
  assert.equal(normalizeAccountConsentStatus({
    ...valid,
    required_versions: { terms: requiredVersions.terms, privacy: requiredVersions.privacy },
  }), null)
  assert.equal(normalizeAccountConsentStatus({
    ...valid,
    accepted_versions: { terms: acceptedVersions.terms, privacy: acceptedVersions.privacy },
  }), null)
  assert.equal(isAccountConsentCurrent(normalizeAccountConsentStatus({
    ...valid,
    legal_consent_at: 'not-a-timestamp',
  })), false)
  assert.equal(isAccountConsentCurrent(normalizeAccountConsentStatus({
    ...valid,
    sensitive_data_consent_at: null,
  })), false)
  assert.equal(isAccountConsentCurrent({ isActive: true, needsConsent: false }), false)
})

test('fails closed when accepted consent versions are older than required versions', () => {
  const status = normalizeAccountConsentStatus({
    is_active: true,
    needs_consent: false,
    missing: [],
    required_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-22',
      sensitive_data: '2026-07-22',
    },
    accepted_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-19',
      sensitive_data: '2026-07-19',
    },
    legal_consent_at: '2026-08-01T00:00:00Z',
    sensitive_data_consent_at: '2026-08-01T00:00:00Z',
  })
  assert.equal(isAccountConsentCurrent(status), false)
})

test('accepts only an active status with no missing consent versions', () => {
  const status = normalizeAccountConsentStatus({
    is_active: true,
    needs_consent: false,
    missing: [],
    required_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-22',
      sensitive_data: '2026-07-22',
    },
    accepted_versions: {
      terms: '2026-07-19',
      privacy: '2026-07-22',
      sensitive_data: '2026-07-22',
    },
    legal_consent_at: '2026-08-01T00:00:00Z',
    sensitive_data_consent_at: '2026-08-01T00:00:00Z',
  })
  assert.equal(isAccountConsentCurrent(status), true)
})

test('submits fixed current versions to the server-owned consent RPC', async () => {
  let request = null
  const client = {
    async rpc(name, args) {
      request = { name, args }
      return {
        data: {
          is_active: true,
          needs_consent: false,
          missing: [],
          required_versions: {
            terms: ACCOUNT_CONSENT_VERSIONS.terms,
            privacy: ACCOUNT_CONSENT_VERSIONS.privacy,
            sensitive_data: ACCOUNT_CONSENT_VERSIONS.sensitiveData,
          },
          accepted_versions: {
            terms: ACCOUNT_CONSENT_VERSIONS.terms,
            privacy: ACCOUNT_CONSENT_VERSIONS.privacy,
            sensitive_data: ACCOUNT_CONSENT_VERSIONS.sensitiveData,
          },
          legal_consent_at: '2026-08-01T00:00:00Z',
          sensitive_data_consent_at: '2026-08-01T00:00:00Z',
        },
        error: null,
      }
    },
  }

  await acceptCurrentAccountConsent(client)
  assert.deepEqual(request, {
    name: 'accept_my_consent',
    args: {
      p_terms_version: ACCOUNT_CONSENT_VERSIONS.terms,
      p_privacy_version: ACCOUNT_CONSENT_VERSIONS.privacy,
      p_sensitive_data_version: ACCOUNT_CONSENT_VERSIONS.sensitiveData,
    },
  })
})

test('business data remains blocked until both session and auth gate allow it', () => {
  assert.equal(canLoadBusinessData(true, 'none'), true)
  assert.equal(canLoadBusinessData(true, 'consent-checking'), false)
  assert.equal(canLoadBusinessData(true, 'consent'), false)
  assert.equal(canLoadBusinessData(true, 'consent-error'), false)
  assert.equal(canLoadBusinessData(false, 'none'), false)
})

test('session and data-run guards reject cross-user and stale generations', () => {
  const session = { user: { id: 'user-a' } }
  assert.equal(isSameSessionUser(session, 'user-a'), true)
  assert.equal(isSameSessionUser(session, 'user-b'), false)

  const context = createUserDataContext('user-a', 4)
  assert.equal(isUserDataContextCurrent(context, {
    userId: 'user-a', generation: 4, isLoggedIn: true,
  }), true)
  assert.equal(isUserDataContextCurrent(context, {
    userId: 'user-b', generation: 4, isLoggedIn: true,
  }), false)
  assert.equal(isUserDataContextCurrent(context, {
    userId: 'user-a', generation: 5, isLoggedIn: true,
  }), false)
  assert.equal(isUserDataContextCurrent(context, {
    userId: 'user-a', generation: 4, isLoggedIn: false,
  }), false)
})

test('normalizes and persists only complete account-deletion receipts', () => {
  const raw = {
    status: 'deletion_pending',
    deletion_status: 'requested',
    request_id: '11111111-1111-4111-8111-111111111111',
    requested_at: '2026-08-01T00:00:00Z',
    estimated_completion_at: '2026-08-02T00:00:00Z',
    support_reference: 'DEL-AB12CD34EF56',
    retryable: true,
    message: '账户删除请求已受理',
  }
  const receipt = normalizeAccountDeletionResult(raw)
  assert.equal(receipt.deletionStatus, 'requested')
  assert.equal(receipt.supportReference, 'DEL-AB12CD34EF56')
  assert.equal(normalizeAccountDeletionResult({ ...raw, request_id: null }), null)
  assert.equal(normalizeAccountDeletionResult({ ...raw, support_reference: 'DEL-AB12CD34' }), null)
  assert.equal(normalizeAccountDeletionResult({ ...raw, status: 'deleted' }), null)
  assert.equal(normalizeAccountDeletionResult({ ...raw, requested_at: 'not-a-time' }), null)
  assert.equal(normalizeAccountDeletionResult({ ...raw, retryable: false }), null)

  const values = new Map()
  const storage = {
    getItem(key) { return values.get(key) ?? null },
    setItem(key, value) { values.set(key, value) },
    removeItem(key) { values.delete(key) },
  }
  saveAccountDeletionReceipt(receipt, storage)
  assert.equal(loadAccountDeletionReceipt(storage)?.requestId, raw.request_id)

  assert.throws(() => saveAccountDeletionReceipt(receipt, {
    getItem() { return null },
    setItem() {},
  }), /未能保存/)
})

test('reconciles an account deletion when the first response is lost', async () => {
  const client = {
    auth: {
      async getSession() {
        return {
          data: { session: { access_token: 'test-token', user: { id: 'user-a' } } },
          error: null,
        }
      },
    },
  }
  let calls = 0
  const result = await requestAccountDeletion({
    client,
    functionUrl: 'https://example.test/functions/v1/ingest-receipt',
    anonKey: 'anon-test',
    async fetchImpl(_url, init) {
      calls += 1
      const action = JSON.parse(init.body).action
      if (action === 'delete_account') throw new TypeError('response lost')
      return {
        ok: true,
        async json() {
          return {
            status: 'deletion_pending',
            deletion_status: 'cleaning',
            request_id: '11111111-1111-4111-8111-111111111111',
            requested_at: '2026-08-01T00:00:00Z',
            estimated_completion_at: '2026-08-02T00:00:00Z',
            support_reference: 'DEL-AB12CD34EF56',
            retryable: true,
          }
        },
      }
    },
  })
  assert.equal(calls, 2)
  assert.equal(result.deletionStatus, 'cleaning')
})
