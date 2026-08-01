export const ACCOUNT_CONSENT_VERSIONS = Object.freeze({
  terms: '2026-07-19',
  privacy: '2026-07-22',
  sensitiveData: '2026-07-22',
})

const REQUIRED_CONSENT_KEYS = Object.freeze(['terms', 'privacy', 'sensitive_data'])
const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/

function isObject(value) {
  return Boolean(value && typeof value === 'object' && !Array.isArray(value))
}

function normalizeTimestamp(value) {
  if (typeof value !== 'string' || !ISO_TIMESTAMP_PATTERN.test(value)) return null
  return Number.isNaN(Date.parse(value)) ? null : value
}

function normalizeRequiredVersions(value) {
  if (!isObject(value)) return null
  const entries = Object.entries(value)
  if (!entries.length || entries.some(([, version]) => typeof version !== 'string' || !version)) {
    return null
  }
  if (REQUIRED_CONSENT_KEYS.some(key => typeof value[key] !== 'string' || !value[key])) {
    return null
  }
  return Object.fromEntries(entries)
}

function normalizeAcceptedVersions(value, requiredVersions) {
  if (!isObject(value)) return null
  for (const key of Object.keys(requiredVersions)) {
    if (!Object.prototype.hasOwnProperty.call(value, key)) return null
    if (value[key] !== null && (typeof value[key] !== 'string' || !value[key])) return null
  }
  return Object.fromEntries(
    Object.entries(value).filter(([, version]) => version === null || (typeof version === 'string' && version)),
  )
}

export function normalizeAccountConsentStatus(value) {
  if (!isObject(value)) return null
  if (typeof value.is_active !== 'boolean' || typeof value.needs_consent !== 'boolean') return null
  if (!Array.isArray(value.missing) || value.missing.some(item => typeof item !== 'string' || !item)) {
    return null
  }
  const requiredVersions = normalizeRequiredVersions(value.required_versions)
  if (!requiredVersions) return null
  const acceptedVersions = normalizeAcceptedVersions(value.accepted_versions, requiredVersions)
  if (!acceptedVersions) return null
  return {
    needsConsent: value.needs_consent,
    isActive: value.is_active,
    missing: [...value.missing],
    requiredVersions,
    acceptedVersions,
    legalConsentAt: normalizeTimestamp(value.legal_consent_at),
    sensitiveDataConsentAt: normalizeTimestamp(value.sensitive_data_consent_at),
  }
}

export function isAccountConsentCurrent(status) {
  return Boolean(
    status
      && status.isActive === true
      && status.needsConsent === false
      && Array.isArray(status.missing)
      && status.missing.length === 0
      && isObject(status.requiredVersions)
      && isObject(status.acceptedVersions)
      && Object.entries(status.requiredVersions).every(
        ([key, version]) => status.acceptedVersions[key] === version,
      )
      && Boolean(status.legalConsentAt)
      && Boolean(status.sensitiveDataConsentAt),
  )
}

export async function fetchMyAccountConsent(client) {
  const { data, error } = await client.rpc('get_my_consent_status')
  if (error) throw error
  const status = normalizeAccountConsentStatus(data)
  if (!status) throw new Error('同意状态返回格式无效')
  return status
}

export async function acceptCurrentAccountConsent(client) {
  const { data, error } = await client.rpc('accept_my_consent', {
    p_terms_version: ACCOUNT_CONSENT_VERSIONS.terms,
    p_privacy_version: ACCOUNT_CONSENT_VERSIONS.privacy,
    p_sensitive_data_version: ACCOUNT_CONSENT_VERSIONS.sensitiveData,
  })
  if (error) throw error
  const status = normalizeAccountConsentStatus(data)
  if (!isAccountConsentCurrent(status)) {
    throw new Error('同意状态尚未生效，请重试')
  }
  return status
}
