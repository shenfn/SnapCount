import { createHash, randomUUID } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { createClient } from '@supabase/supabase-js'
import { currentTestRegistrationConsent } from './lib/test-registration-consent.mjs'

const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL
const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY
const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY

if (!supabaseUrl || !serviceRoleKey || !anonKey) {
  console.error('Missing Supabase URL, service role key, or anon key')
  process.exit(1)
}

const admin = createClient(supabaseUrl, serviceRoleKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const client = createClient(supabaseUrl, anonKey, {
  auth: { persistSession: false, autoRefreshToken: false },
})
const functionUrl = `${supabaseUrl.replace(/\/$/, '')}/functions/v1/ingest-receipt`
const bucketName = 'receipt-images'
const runId = `${Date.now()}-${randomUUID().slice(0, 8)}`
const email = `upload-lifecycle-${runId}@example.invalid`
const password = `T-${randomUUID()}-a9!`

let userId = null
let accessToken = null
let deletionCompleted = false

function assert(condition, message) {
  if (!condition) throw new Error(message)
}

function sleep(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds))
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex')
}

function addJpegComment(bytes, text) {
  assert(bytes[0] === 0xff && bytes[1] === 0xd8, 'Perceptual smoke fixture is not a JPEG')
  const comment = Buffer.from(text, 'utf8')
  assert(comment.length <= 65_533, 'JPEG smoke comment is too long')
  const segmentLength = comment.length + 2
  const segment = Buffer.concat([
    Buffer.from([0xff, 0xfe, segmentLength >> 8, segmentLength & 0xff]),
    comment,
  ])
  return Buffer.concat([bytes.subarray(0, 2), segment, bytes.subarray(2)])
}

async function createTemporaryUser() {
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: currentTestRegistrationConsent(),
  })
  if (error || !data.user) throw new Error(`Failed to create upload test user: ${error?.message ?? 'missing user'}`)
  userId = data.user.id

  const { data: sessionData, error: signInError } = await client.auth.signInWithPassword({ email, password })
  if (signInError || !sessionData.session) {
    throw new Error(`Failed to sign in upload test user: ${signInError?.message ?? 'missing session'}`)
  }
  accessToken = sessionData.session.access_token

  const { error: configError } = await admin.from('user_configs').update({
    is_active: true,
    upload_token: randomUUID(),
    keep_source_images: true,
    image_retention_days: -1,
    ai_logs_enabled: false,
    updated_at: new Date().toISOString(),
  }).eq('user_id', userId)
  if (configError) throw new Error(`Failed to configure upload test user: ${configError.message}`)
}

async function uploadImage(bytes, filename) {
  const form = new FormData()
  form.append('image', new Blob([bytes], { type: 'image/jpeg' }), filename)
  form.append('response_mode', 'json')
  form.append('capture_kind', 'screenshot')
  form.append('source_app', 'codex-upload-lifecycle')
  form.append('client_captured_at', new Date().toISOString())
  form.append('client_request_started_at', new Date().toISOString())
  form.append('test_run_id', runId)
  form.append('test_case_domain', 'expense')
  form.append('test_case_file', filename)

  const startedAt = Date.now()
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
    },
    body: form,
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) {
    throw new Error(`Upload ${filename} returned HTTP ${response.status}: ${payload.error ?? 'unknown error'}`)
  }
  return { payload, elapsedMs: Date.now() - startedAt }
}

async function listStorageFiles(root) {
  const files = []
  const directories = [root]
  while (directories.length > 0) {
    const directory = directories.shift()
    for (let offset = 0; ; offset += 1_000) {
      const { data, error } = await admin.storage.from(bucketName).list(directory, {
        limit: 1_000,
        offset,
        sortBy: { column: 'name', order: 'asc' },
      })
      if (error) throw new Error(`Failed to list ${directory}: ${error.message}`)
      const entries = data ?? []
      for (const entry of entries) {
        const entryPath = `${directory}/${entry.name}`
        if (entry.id || entry.metadata) files.push(entryPath)
        else directories.push(entryPath)
      }
      if (entries.length < 1_000) break
    }
  }
  return files
}

async function assertNoTemporaryReferences() {
  for (const [table, column] of [
    ['transactions', 'image_url'],
    ['income_records', 'image_url'],
    ['data_records', 'source_image_path'],
    ['staging_records', 'image_path'],
    ['ai_recognition_logs', 'image_url'],
  ]) {
    const { count, error } = await admin.from(table)
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId)
      .like(column, `tmp/${userId}/%`)
    if (error) throw new Error(`Failed to verify ${table}.${column}: ${error.message}`)
    assert(count === 0, `${table}.${column} retained ${count} temporary image references`)
  }
}

async function postDeleteAccount() {
  const startedAt = Date.now()
  const response = await fetch(functionUrl, {
    method: 'POST',
    headers: {
      apikey: anonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ action: 'delete_account' }),
  })
  const payload = await response.json().catch(() => ({}))
  assert(response.status === 202 && payload.status === 'deletion_pending', `Unexpected deletion response: HTTP ${response.status}`)
  assert(Date.now() - startedAt < 15_000, 'delete_account did not return within 15 seconds')
}

async function invokeWorker() {
  const { data, error } = await admin.rpc('invoke_image_cleanup_worker')
  if (error || data !== true) throw new Error(`Failed to invoke cleanup worker: ${error?.message ?? 'not accepted'}`)
}

async function waitForDeletion(timeoutMs = 180_000) {
  const deadline = Date.now() + timeoutMs
  let nextWorkerAt = 0
  while (Date.now() < deadline) {
    const { data, error } = await admin.from('account_deletion_requests')
      .select('status,last_error')
      .eq('user_id', userId)
      .maybeSingle()
    if (error) throw new Error(error.message)
    if (data?.status === 'failed') throw new Error(`Account deletion failed: ${data.last_error}`)
    if (!data) {
      const { data: authData, error: authError } = await admin.auth.admin.getUserById(userId)
      if (authError && !/not found|user not found/i.test(authError.message)) throw new Error(authError.message)
      if (authError || !authData.user) return
    }
    if (data?.status === 'deleting') {
      const { error: fastForwardError } = await admin.from('account_deletion_requests')
        .update({ next_retry_at: new Date().toISOString() })
        .eq('user_id', userId)
        .eq('status', 'deleting')
      if (fastForwardError) throw new Error(fastForwardError.message)
    }
    if (Date.now() >= nextWorkerAt) {
      await invokeWorker()
      nextWorkerAt = Date.now() + 5_000
    }
    await sleep(1_500)
  }
  throw new Error('Upload test account deletion timed out')
}

async function emergencyCleanup() {
  if (!userId || deletionCompleted) return
  try {
    const paths = [
      ...await listStorageFiles(userId),
      ...await listStorageFiles(`tmp/${userId}`),
    ]
    for (let offset = 0; offset < paths.length; offset += 100) {
      await admin.storage.from(bucketName).remove(paths.slice(offset, offset + 100))
    }
    await admin.rpc('delete_user_account_data', { p_user_id: userId })
    await admin.from('image_cleanup_queue').delete().eq('user_id', userId)
    await admin.from('account_deletion_requests').delete().eq('user_id', userId)
    await admin.auth.admin.deleteUser(userId)
  } catch (cleanupError) {
    console.error(`Emergency cleanup failed: ${cleanupError instanceof Error ? cleanupError.name : typeof cleanupError}`)
  }
}

try {
  await createTemporaryUser()

  const originalBytes = await readFile(path.resolve('docs/cases/expense.jpg'))
  const first = await uploadImage(originalBytes, 'exact-base.jpg')
  assert(first.payload.id, 'First upload did not create a record')
  assert(first.payload.status !== 'duplicate', 'First upload was unexpectedly treated as an exact duplicate')

  const exact = await uploadImage(originalBytes, 'exact-repeat.jpg')
  assert(exact.payload.status === 'duplicate', `Exact repeat returned ${exact.payload.status ?? 'no status'}`)
  assert(exact.payload.id === first.payload.id, 'Exact repeat did not resolve to the original record')

  const similarBytes = addJpegComment(originalBytes, `SNAPCOUNT-PERCEPTUAL-SMOKE:${runId}`)
  assert(sha256(similarBytes) !== sha256(originalBytes), 'Perceptual test bytes did not change the exact hash')
  const similar = await uploadImage(similarBytes, 'perceptual-similar.jpg')
  assert(similar.payload.status === 'staging', `Perceptual match returned ${similar.payload.status ?? 'no status'}`)
  assert(similar.payload.possible_duplicate === true, 'Perceptual match was not routed to duplicate review')

  const retainedFiles = await listStorageFiles(userId)
  assert(retainedFiles.length >= 2, `Expected retained evidence for two unique images, found ${retainedFiles.length}`)

  const { error: privacyError } = await admin.from('user_configs').update({
    keep_source_images: false,
    updated_at: new Date().toISOString(),
  }).eq('user_id', userId)
  if (privacyError) throw new Error(privacyError.message)

  const noSourceBytes = await readFile(path.resolve('docs/cases/food.jpg'))
  const noSource = await uploadImage(noSourceBytes, 'source-image-disabled.jpg')
  assert(noSource.payload.id, 'Source-image-disabled upload did not create a record or staging item')
  assert((await listStorageFiles(`tmp/${userId}`)).length === 0, 'Temporary Storage object survived the response')
  await assertNoTemporaryReferences()

  await postDeleteAccount()
  await waitForDeletion()
  deletionCompleted = true

  assert((await listStorageFiles(userId)).length === 0, 'Retained Storage objects survived account deletion')
  assert((await listStorageFiles(`tmp/${userId}`)).length === 0, 'Temporary Storage objects survived account deletion')
  const { count: queueCount, error: queueError } = await admin.from('image_cleanup_queue')
    .select('id', { count: 'exact', head: true })
    .eq('user_id', userId)
  if (queueError) throw new Error(queueError.message)
  assert(queueCount === 0, `Image cleanup queue retained ${queueCount} rows`)

  console.log(JSON.stringify({
    status: 'ok',
    checks: [
      'first upload creates a record',
      'exact hash returns the original record',
      'perceptual match keeps evidence and enters review',
      'disabled source images leave no temporary object or reference',
      'account deletion removes retained images, queue rows, business data, and Auth',
    ],
    timing_ms: {
      first_upload: first.elapsedMs,
      exact_duplicate: exact.elapsedMs,
      perceptual_review: similar.elapsedMs,
      source_image_disabled: noSource.elapsedMs,
    },
  }, null, 2))
} finally {
  await emergencyCleanup()
}
