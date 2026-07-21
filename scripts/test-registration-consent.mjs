import { createClient } from '@supabase/supabase-js'
import {
  CURRENT_PRIVACY_VERSION,
  CURRENT_TERMS_VERSION,
  currentTestRegistrationConsent,
} from './lib/test-registration-consent.mjs'

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY

if (!supabaseUrl || !serviceRoleKey) {
  console.error('Missing SUPABASE_URL/VITE_SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY')
  process.exit(1)
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const runId = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`
const password = `T-${crypto.randomUUID()}-a9!`
const createdUserIds = []

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

async function cleanup() {
  for (const userId of createdUserIds) {
    await admin.auth.admin.deleteUser(userId)
  }
}

try {
  const rejected = await admin.auth.admin.createUser({
    email: `registration-rejected-${runId}@example.invalid`,
    password,
    email_confirm: true,
  })
  if (rejected.data.user?.id) createdUserIds.push(rejected.data.user.id)
  assert(rejected.error, 'Registration without consent unexpectedly succeeded')

  const consent = currentTestRegistrationConsent()
  const accepted = await admin.auth.admin.createUser({
    email: `registration-accepted-${runId}@example.invalid`,
    password,
    email_confirm: true,
    user_metadata: consent,
  })
  if (accepted.error || !accepted.data.user) {
    throw new Error(`Registration with consent failed: ${accepted.error?.message ?? 'missing user'}`)
  }
  createdUserIds.push(accepted.data.user.id)

  const { data: config, error: configError } = await admin.from('user_configs')
    .select('legal_consent_at,sensitive_data_consent_at,terms_version,privacy_version,ai_logs_enabled')
    .eq('user_id', accepted.data.user.id)
    .single()
  if (configError) throw new Error(configError.message)

  assert(config.terms_version === CURRENT_TERMS_VERSION, 'Terms version was not persisted')
  assert(config.privacy_version === CURRENT_PRIVACY_VERSION, 'Privacy version was not persisted')
  assert(config.legal_consent_at === config.sensitive_data_consent_at, 'Server consent timestamps differ')
  assert(Date.parse(config.legal_consent_at) >= Date.now() - 60_000, 'Consent did not use current server time')
  assert(config.ai_logs_enabled === false, 'AI logs must default to disabled')

  console.log(JSON.stringify({
    status: 'ok',
    checks: [
      'registration without consent rejected',
      'registration with current consent accepted',
      'server consent timestamp persisted',
      'AI logs default disabled',
    ],
  }, null, 2))
} finally {
  await cleanup()
}
