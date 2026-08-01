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
