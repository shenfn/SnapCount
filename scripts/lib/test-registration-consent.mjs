export const CURRENT_TERMS_VERSION = '2026-07-19'
export const CURRENT_PRIVACY_VERSION = '2026-07-19'

export function currentTestRegistrationConsent(now = new Date()) {
  const acceptedAt = now.toISOString()
  return {
    legal_consent_at: acceptedAt,
    sensitive_data_consent_at: acceptedAt,
    terms_version: CURRENT_TERMS_VERSION,
    privacy_version: CURRENT_PRIVACY_VERSION,
  }
}
