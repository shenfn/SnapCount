import { createClient } from '@supabase/supabase-js'
import { currentTestRegistrationConsent } from './lib/test-registration-consent.mjs'

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
let legacyTestPath = null
let lateAccountDeletionPath = null

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

async function waitForAccountDeletionStatus(expectedStatus, timeoutMs = 180_000) {
  const deadline = Date.now() + timeoutMs
  let nextWorkerInvocationAt = 0
  while (Date.now() < deadline) {
    const { data, error } = await admin.from('account_deletion_requests')
      .select('status,last_error')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) throw new Error(error.message)
    if (data?.status === expectedStatus) return data
    if (data?.status === 'failed') throw new Error(`Account deletion failed: ${data.last_error}`)
    if (!data) throw new Error(`Account deletion request disappeared before reaching ${expectedStatus}`)
    if (Date.now() >= nextWorkerInvocationAt) {
      await invokeWorker()
      nextWorkerInvocationAt = Date.now() + 10_000
    }
    await sleep(2_000)
  }
  throw new Error(`Account deletion did not reach ${expectedStatus} before timeout`)
}

async function waitForDeletion(timeoutMs = 180_000) {
  const deadline = Date.now() + timeoutMs
  let nextWorkerInvocationAt = 0
  while (Date.now() < deadline) {
    const { data, error } = await admin.from('account_deletion_requests')
      .select('status,last_error,remaining_images')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) throw new Error(error.message)
    if (data?.status === 'completed') return data
    if (data?.status === 'failed') throw new Error(`Account deletion failed: ${data.last_error}`)
    if (!data) {
      const { data: authData, error: authError } = await admin.auth.admin.getUserById(userId)
      if (authError && !/not found|user not found/i.test(authError.message)) throw new Error(authError.message)
      if (authError || !authData.user) return { status: 'completed', remaining_images: 0 }
    }
    if (data?.status === 'deleting') {
      const { error: fastForwardError } = await admin.from('account_deletion_requests').update({
        next_retry_at: new Date().toISOString(),
      }).eq('user_id', userId).eq('status', 'deleting')
      if (fastForwardError) throw new Error(`Failed to fast-forward deletion grace period: ${fastForwardError.message}`)
    }
    if (Date.now() >= nextWorkerInvocationAt) {
      await invokeWorker()
      nextWorkerInvocationAt = Date.now() + 10_000
    }
    await sleep(2_000)
  }
  throw new Error('Account deletion did not complete before timeout')
}

async function createTemporaryUser() {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: currentTestRegistrationConsent(),
  })
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

async function testLegacyPathCleanup() {
  const legacyPath = `2099-12-31/${runId}.jpg`
  legacyTestPath = legacyPath
  const { error: uploadError } = await admin.storage.from('receipt-images').upload(
    legacyPath,
    new Blob(['legacy-image-cleanup-test'], { type: 'image/jpeg' }),
    { upsert: false },
  )
  if (uploadError) throw new Error(`Failed to upload legacy test object: ${uploadError.message}`)
  const { data: logRow, error: logError } = await admin.from('ai_recognition_logs').insert({
    user_id: userId,
    status: 'success',
    image_url: legacyPath,
    image_hash: `legacy-${runId}`,
  }).select('id').single()
  if (logError) throw new Error(`Failed to seed legacy reference: ${logError.message}`)

  const { payload } = await postAction('cleanup_all_images', accessToken, [200, 202])
  assert(payload.deleted >= 1, `Legacy object was not processed: ${JSON.stringify(payload)}`)
  const { data: updatedLog, error: updatedLogError } = await admin.from('ai_recognition_logs')
    .select('image_url')
    .eq('id', logRow.id)
    .single()
  if (updatedLogError) throw new Error(updatedLogError.message)
  assert(updatedLog.image_url === null, 'Legacy database reference was not cleared')
  const { data: objectData } = await admin.storage.from('receipt-images').download(legacyPath)
  assert(!objectData, 'Legacy Storage object still exists after cleanup')
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
  const queueRows = Array.from({ length: 501 }, (_, index) => ({
    user_id: userId,
    bucket_path: `${userId}/tests/${runId}-delete-${index}.jpg`,
    status: 'pending',
    attempts: 0,
    cleanup_reason: 'account_delete',
    next_retry_at: new Date().toISOString(),
  }))
  const { error: queueError } = await admin.from('image_cleanup_queue').insert(queueRows)
  if (queueError) throw new Error(`Failed to seed account cleanup queue: ${queueError.message}`)

  const deleteStartedAt = Date.now()
  const { response, payload } = await postAction('delete_account', accessToken, [202])
  const deleteResponseMs = Date.now() - deleteStartedAt
  assert(response.status === 202 && payload.status === 'deletion_pending', `Expected deletion_pending, got ${JSON.stringify(payload)}`)
  assert(deleteResponseMs < 15_000, `delete_account took ${deleteResponseMs}ms instead of returning immediately`)

  const blockedUpload = new FormData()
  const blockedResponse = await fetch(functionUrl, {
    method: 'POST',
    headers: { apikey: anonKey, Authorization: `Bearer ${accessToken}` },
    body: blockedUpload,
  })
  assert(blockedResponse.status === 410, `Expected old JWT upload to be blocked with 410, got ${blockedResponse.status}`)

  await waitForAccountDeletionStatus('deleting')
  lateAccountDeletionPath = `${userId}/tests/${runId}-late-inflight.jpg`
  const { error: lateUploadError } = await admin.storage.from('receipt-images').upload(
    lateAccountDeletionPath,
    new Blob(['late-inflight-account-deletion-image'], { type: 'image/jpeg' }),
    { upsert: false },
  )
  if (lateUploadError) throw new Error(`Failed to seed late in-flight object: ${lateUploadError.message}`)

  await waitForDeletion()

  const { count: expressionCount, error: expressionError } = await admin.from('expression_shadow_runs')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
  if (expressionError) throw new Error(expressionError.message)
  assert(expressionCount === 0, `Expression rows survived account deletion: ${expressionCount}`)

  const { data: authData, error: authError } = await admin.auth.admin.getUserById(userId)
  assert(authError || !authData.user, 'Auth user survived account deletion')
  const { data: lateObject } = await admin.storage.from('receipt-images').download(lateAccountDeletionPath)
  assert(!lateObject, 'Object uploaded after the first account scan survived deletion')
}

async function cleanupTemporaryUser() {
  if (legacyTestPath) await admin.storage.from('receipt-images').remove([legacyTestPath])
  if (lateAccountDeletionPath) await admin.storage.from('receipt-images').remove([lateAccountDeletionPath])
  if (!userId) return
  await admin.from('image_cleanup_queue').delete().eq('user_id', userId)
  await admin.from('account_deletion_requests').delete().eq('user_id', userId)
  await admin.auth.admin.deleteUser(userId)
}

try {
  await createTemporaryUser()
  await testPaginationAndExternalPaths()
  await testLegacyPathCleanup()
  await testProcessingWriteGuard()
  await testDeadLetterAndWorkerAudit()
  await testAsyncAccountDeletion()
  console.log(JSON.stringify({
    status: 'ok',
    runId,
    checks: [
      '501-row pagination and external-path classification',
      'legacy unscoped path cleanup with exclusive ownership',
      'processing-path reference guard',
      'dead-letter transition and worker audit',
      'expression-data deletion',
      'asynchronous account deletion with 501 queued images',
      'delete-account request returns within 15 seconds',
      'final rescan removes an object uploaded after the first account scan',
      'old JWT upload rejection',
    ],
  }, null, 2))
} finally {
  await cleanupTemporaryUser()
}
