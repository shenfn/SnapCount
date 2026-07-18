import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !serviceRoleKey || !anonKey) {
  console.error('Missing Supabase URL, service role key, or anon key')
  process.exit(1)
}

const endpoint = `${supabaseUrl.replace(/\/$/, '')}/functions/v1/ingest-receipt`
const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const client = createClient(supabaseUrl, anonKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const runId = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`
const email = `expression-feedback-${runId}@example.invalid`
const password = `T-${crypto.randomUUID()}-a9!`
let userId = null
let recordId = null

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

async function postAction(accessToken, body) {
  const response = await fetch(endpoint, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify(body),
  })
  const payload = await response.json().catch(() => ({}))
  return { response, payload }
}

async function cleanup() {
  if (!userId) return
  for (const table of [
    'expression_preference_signals',
    'expression_feedback_events',
    'expression_exposure_events',
    'expression_preference_snapshots',
    'data_records',
    'user_configs',
  ]) {
    await admin.from(table).delete().eq('user_id', userId)
  }
  await admin.auth.admin.deleteUser(userId)
}

try {
  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
  })
  if (createError || !created.user) throw new Error(createError?.message || 'Failed to create user')
  userId = created.user.id

  const { data: sessionData, error: signInError } = await client.auth.signInWithPassword({ email, password })
  if (signInError || !sessionData.session) throw new Error(signInError?.message || 'Failed to sign in')
  const accessToken = sessionData.session.access_token

  const { data: domain, error: domainError } = await admin.from('data_domains')
    .select('id,version')
    .eq('key', 'sleep')
    .eq('is_system', true)
    .is('user_id', null)
    .maybeSingle()
  if (domainError || !domain) throw new Error(domainError?.message || 'Sleep domain not found')

  const { data: record, error: recordError } = await admin.from('data_records').insert({
    user_id: userId,
    domain_id: domain.id,
    domain_key: 'sleep',
    domain_version: domain.version || '1.0',
    occurred_at: new Date().toISOString(),
    title: 'Sleep feedback test',
    summary: '7.9 hours',
    source: 'manual',
    payload_jsonb: {
      duration_minutes: 474,
      ai_feedback: {
        version: 'feedback-v1',
        badge: 'Test',
        emotion_line: 'Persisted feedback without exposure',
        utility_line: '7.9 hours',
        detail_reason: 'Integration test',
        internal_score: 70,
      },
    },
  }).select('id').single()
  if (recordError || !record) throw new Error(recordError?.message || 'Failed to create record')
  recordId = record.id

  const submitted = await postAction(accessToken, {
    action: 'submit_expression_feedback',
    record_id: recordId,
    primary_choice: 'not_helpful',
    free_text: 'The feedback is not useful enough',
  })
  assert(submitted.response.status === 200, `Feedback returned HTTP ${submitted.response.status}: ${JSON.stringify(submitted.payload)}`)
  assert(submitted.payload.ok === true, `Feedback response was not ok: ${JSON.stringify(submitted.payload)}`)

  const checks = {}
  for (const [table, expected] of [
    ['expression_exposure_events', 1],
    ['expression_feedback_events', 1],
    ['expression_preference_signals', 1],
    ['expression_preference_snapshots', 1],
  ]) {
    const { count, error } = await admin.from(table).select('*', { count: 'exact', head: true }).eq('user_id', userId)
    if (error) throw new Error(error.message)
    checks[table] = count
    assert(count === expected, `${table} expected ${expected}, got ${count}`)
  }

  const unsupported = await postAction(accessToken, { action: 'unknown_json_action' })
  assert(unsupported.response.status === 400, `Unknown action returned ${unsupported.response.status}`)
  assert(!String(unsupported.payload.error || '').includes('Body already consumed'), 'Unknown action consumed the body twice')

  console.log(JSON.stringify({
    status: 'ok',
    runId,
    checks,
    feedbackKey: submitted.payload.data?.feedback_key || null,
    unknownActionStatus: unsupported.response.status,
  }, null, 2))
} finally {
  await cleanup()
}
