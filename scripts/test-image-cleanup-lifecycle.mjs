import { createClient } from '@supabase/supabase-js'

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY
const functionUrl = `${supabaseUrl?.replace(/\/$/, '')}/functions/v1/ingest-receipt`

if (!supabaseUrl || !serviceRoleKey || !anonKey) {
  console.error('Missing SUPABASE_URL/VITE_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, or SUPABASE_ANON_KEY/VITE_SUPABASE_ANON_KEY')
  process.exit(1)
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const client = createClient(supabaseUrl, anonKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const runId = `${Date.now()}-${crypto.randomUUID().slice(0, 8)}`
const email = `image-cleanup-${runId}@example.invalid`
const password = `T-${crypto.randomUUID()}-a9!`
let userId = null
let accessToken = null

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

async function postAction(action, token, expectedStatuses = [200]) {
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ action }),
  })
  const payload = await response.json().catch(() => ({}))
  assert(expectedStatuses.includes(response.status), `${action} returned HTTP ${response.status}: ${JSON.stringify(payload)}`)
  return { response, payload }
}

async function invokeWorker() {
  const { data, error } = await admin.rpc('invoke_image_cleanup_worker')
  if (error) throw new Error(`Worker invocation failed: ${error.message}`)
  assert(data === true, 'Worker invocation was not accepted')
}

async function waitForQueueStatus(queueId, expectedStatus, timeoutMs = 45_000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const { data, error } = await admin.from('image_cleanup_queue').select('status,attempts').eq('id', queueId).maybeSingle()
    if (error) throw new Error(error.message)
    if (data?.status === expectedStatus) return data
    await sleep(1_500)
  }
  throw new Error(`Queue ${queueId} did not reach ${expectedStatus}`)
}

async function waitForDeletion(timeoutMs = 90_000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const { data, error } = await admin.from('account_deletion_requests')
      .select('status,last_error,remaining_images')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) throw new Error(error.message)
    if (data?.status === 'completed') return data
    if (data?.status === 'failed') throw new Error(`Account deletion failed: ${data.last_error}`)
    await sleep(2_000)
  }
  throw new Error('Account deletion did not complete before timeout')
}

async function createTemporaryUser() {
  const { data, error } = await admin.auth.admin.createUser({ email, password, email_confirm: true })
  if (error || !data.user) throw new Error(`Failed to create test user: ${error?.message ?? 'missing user'}`)
  userId = data.user.id
  const { data: sessionData, error: signInError } = await client.auth.signInWithPassword({ email, password })
  if (signInError || !sessionData.session) throw new Error(`Failed to sign in test user: ${signInError?.message ?? 'missing session'}`)
  accessToken = sessionData.session.access_token
  const { error: configError } = await admin.from('user_configs').upsert({
    user_id: userId,
    is_active: true,
    upload_token: crypto.randomUUID(),
    keep_source_images: true,
    image_retention_days: -1,
  }, { onConflict: 'user_id' })
  if (configError) throw new Error(`Failed to configure test user: ${configError.message}`)
}

async function testPaginationAndExternalPaths() {
  const rows = Array.from({ length: 501 }, (_, index) => ({
    user_id: userId,
    status: 'success',
    image_url: `https://example.invalid/${runId}/${index}.jpg`,
    image_hash: `${runId}-${index}`,
  }))
  for (let offset = 0; offset < rows.length; offset += 100) {
    const { error } = await admin.from('ai_recognition_logs').insert(rows.slice(offset, offset + 100))
    if (error) throw new Error(`Failed to seed pagination rows: ${error.message}`)
  }
  const { payload } = await postAction('cleanup_all_images', accessToken, [200, 202])
  assert(payload.total === 501, `Expected 501 collected paths, got ${payload.total}`)
  assert(payload.skipped_external === 501, `Expected 501 skipped external paths, got ${payload.skipped_external}`)
}

async function testProcessingWriteGuard() {
  const path = `${userId}/tests/${runId}-processing.jpg`
  const { data: queueRow, error: queueError } = await admin.from('image_cleanup_queue').insert({
    user_id: userId,
    bucket_path: path,
    status: 'processing',
    attempts: 1,
    cleanup_reason: 'record_delete',
  }).select('id').single()
  if (queueError) throw new Error(queueError.message)
  const { error: insertError } = await admin.from('transactions').insert({
    user_id: userId,
    type: 'expense',
    amount: 1,
    status: 'done',
    source: 'manual',
    image_url: path,
  })
  assert(insertError?.message?.includes('image cleanup is in progress'), 'Processing-path write guard did not reject a new reference')
  await admin.from('image_cleanup_queue').delete().eq('id', queueRow.id)
}

async function testDeadLetterAndWorkerAudit() {
  const { data: queueRow, error: queueError } = await admin.from('image_cleanup_queue').insert({
    user_id: userId,
    bucket_path: `not-owned/${runId}.jpg`,
    status: 'failed',
    attempts: 7,
    cleanup_reason: 'record_delete',
    next_retry_at: new Date().toISOString(),
  }).select('id').single()
  if (queueError) throw new Error(queueError.message)
  await invokeWorker()
  const deadLetter = await waitForQueueStatus(queueRow.id, 'dead_letter')
  assert(deadLetter.attempts === 8, `Expected 8 attempts, got ${deadLetter.attempts}`)
  const { data: workerRun, error: workerError } = await admin.from('image_cleanup_worker_runs')
    .select('status,completed_at')
    .order('started_at', { ascending: false })
    .limit(1)
    .maybeSingle()
  if (workerError) throw new Error(workerError.message)
  assert(workerRun?.status === 'succeeded' && workerRun.completed_at, 'Worker audit did not record a successful run')
  await admin.from('image_cleanup_queue').delete().eq('id', queueRow.id)
}

async function seedExpressionData() {
  const { error } = await admin.from('expression_shadow_runs').insert({
    user_id: userId,
    occurred_at: new Date().toISOString(),
    event_key: `cleanup-test-${runId}`,
    surface: 'shortcut_notification',
    response_mode: 'json',
    rollout_mode: 'shadow',
    lifecycle_state: 'returned_to_shortcut',
    collector_version: 'cleanup-lifecycle-test',
  })
  if (error) throw new Error(`Failed to seed expression data: ${error.message}`)
}

async function testAsyncAccountDeletion() {
  await seedExpressionData()
  const queueRows = Array.from({ length: 51 }, (_, index) => ({
    user_id: userId,
    bucket_path: `${userId}/tests/${runId}-delete-${index}.jpg`,
    status: 'pending',
    attempts: 0,
    cleanup_reason: 'account_delete',
    next_retry_at: new Date().toISOString(),
  }))
  const { error: queueError } = await admin.from('image_cleanup_queue').insert(queueRows)
  if (queueError) throw new Error(`Failed to seed account cleanup queue: ${queueError.message}`)

  const { response, payload } = await postAction('delete_account', accessToken, [202])
  assert(response.status === 202 && payload.status === 'deletion_pending', `Expected deletion_pending, got ${JSON.stringify(payload)}`)

  const blockedUpload = new FormData()
  const blockedResponse = await fetch(functionUrl, {
    method: 'POST',
    headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
    body: blockedUpload,
  })
  assert(blockedResponse.status === 410, `Expected old JWT upload to be blocked with 410, got ${blockedResponse.status}`)

  await invokeWorker()
  await waitForDeletion()

  const { count: expressionCount, error: expressionError } = await admin.from('expression_shadow_runs')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
  if (expressionError) throw new Error(expressionError.message)
  assert(expressionCount === 0, `Expression rows survived account deletion: ${expressionCount}`)

  const { data: authData, error: authError } = await admin.auth.admin.getUserById(userId)
  assert(authError || !authData.user, 'Auth user survived account deletion')
}

async function cleanupTemporaryUser() {
  if (!userId) return
  await admin.from('image_cleanup_queue').delete().eq('user_id', userId)
  await admin.from('account_deletion_requests').delete().eq('user_id', userId)
  await admin.auth.admin.deleteUser(userId)
}

try {
  await createTemporaryUser()
  await testPaginationAndExternalPaths()
  await testProcessingWriteGuard()
  await testDeadLetterAndWorkerAudit()
  await testAsyncAccountDeletion()
  console.log(JSON.stringify({
    status: 'ok',
    runId,
    checks: [
      '501-row pagination and external-path classification',
      'processing-path reference guard',
      'dead-letter transition and worker audit',
      'expression-data deletion',
      'asynchronous account deletion with 51 queued images',
      'old JWT upload rejection',
    ],
  }, null, 2))
} finally {
  await cleanupTemporaryUser()
}
