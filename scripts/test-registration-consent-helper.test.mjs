import assert from 'node:assert/strict'
import test from 'node:test'
import {
  CURRENT_PRIVACY_VERSION,
  CURRENT_TERMS_VERSION,
  currentTestRegistrationConsent,
} from './lib/test-registration-consent.mjs'

test('test registration metadata follows the current legal contract', () => {
  const now = new Date('2026-07-21T12:34:56.000Z')
  assert.deepEqual(currentTestRegistrationConsent(now), {
    legal_consent_at: now.toISOString(),
    sensitive_data_consent_at: now.toISOString(),
    terms_version: CURRENT_TERMS_VERSION,
    privacy_version: CURRENT_PRIVACY_VERSION,
  })
  assert.equal(CURRENT_TERMS_VERSION, '2026-07-19')
  assert.equal(CURRENT_PRIVACY_VERSION, '2026-07-22')
})
