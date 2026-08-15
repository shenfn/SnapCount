import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')

function between(source, start, end) {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)
  assert.ok(startIndex >= 0, `missing section start: ${start}`)
  assert.ok(endIndex > startIndex, `missing section end: ${end}`)
  return source.slice(startIndex, endIndex)
}

function occurrenceIndexes(source, text) {
  const indexes = []
  let from = 0
  while (from < source.length) {
    const index = source.indexOf(text, from)
    if (index < 0) break
    indexes.push(index)
    from = index + text.length
  }
  return indexes
}

function assertInvalidatesAfterFailureGuard(section, mutationMarker, failureMarker, invalidationMarker, label) {
  const mutationIndex = section.indexOf(mutationMarker)
  const failureIndex = section.indexOf(failureMarker, mutationIndex + mutationMarker.length)
  const invalidationIndex = section.indexOf(invalidationMarker, failureIndex + failureMarker.length)
  assert.ok(mutationIndex >= 0, `${label}: missing mutation`)
  assert.ok(failureIndex > mutationIndex, `${label}: missing failure guard after mutation`)
  assert.ok(invalidationIndex > failureIndex, `${label}: invalidation must follow the failure guard`)
  assert.match(
    section.slice(failureIndex, invalidationIndex),
    /return|throw/,
    `${label}: the failure path must exit before invalidation`,
  )
}

test('PWA invalidates one record plan without weakening the user-switch reset', async () => {
  const [store, feature] = await Promise.all([
    readFile(path.join(root, 'src/composables/useStore.js'), 'utf8'),
    readFile(path.join(root, 'src/features/expression/createExpressionPlanState.js'), 'utf8'),
  ])
  const reset = between(store, 'function resetUserData()', 'function isActionPending')
  const invalidation = between(
    feature,
    'function invalidateRecordExpressionPlan(recordId)',
    'function loadRecordExpressionPlan',
  )

  assert.match(store, /createExpressionPlanState\(\{/)
  assert.match(store, /recordExpressionPlanCache,[\s\S]*loadRecordExpressionPlan,[\s\S]*ackRecordExpressionPlan,[\s\S]*submitExpressionFeedback/)
  assert.match(reset, /expressionPlanState\.reset\(\)/)
  assert.doesNotMatch(feature, /\b(?:fetch|SUPABASE_URL|SUPABASE_ANON_KEY)\b|from ['"][^'"]*supabase/i)
  assert.match(feature, /const cacheRevisions\s*=\s*new Map\(\)/)
  assert.match(feature, /recordExpressionPlanCache\.value\s*=\s*\{\}/)
  assert.match(feature, /loadRequests\.clear\(\)/)
  assert.match(feature, /ackRequests\.clear\(\)/)
  assert.match(feature, /cacheRevisions\.clear\(\)/)
  assert.match(feature, /cacheVersion\s*\+=\s*1/)

  assert.match(invalidation, /delete nextCache\[normalizedRecordId\]/)
  assert.match(invalidation, /recordExpressionPlanCache\.value\s*=\s*nextCache/)
  assert.match(invalidation, /for \(const recordKind of \['expense', 'income', 'data'\]\)/)
  assert.match(invalidation, /loadRequests\.delete\(`\$\{recordKind\}:\$\{normalizedRecordId\}`\)/)
  assert.match(invalidation, /ackRequests\.delete\(normalizedRecordId\)/)
  assert.match(invalidation, /cacheRevisions\.set\(/)
})

test('invalidated records reject stale in-flight plan and acknowledgement writes', async () => {
  const feature = await readFile(
    path.join(root, 'src/features/expression/createExpressionPlanState.js'),
    'utf8',
  )
  const load = between(feature, 'function loadRecordExpressionPlan', 'function ackRecordExpressionPlan')
  const acknowledge = between(feature, 'function ackRecordExpressionPlan', 'function submitExpressionFeedback')

  assert.match(load, /const revision\s*=\s*getRecordExpressionPlanCacheRevision\(normalizedRecordId\)/)
  assert.ok(
    occurrenceIndexes(load, 'isCacheCurrent(normalizedRecordId, version, revision)').length >= 2,
    'plan loads must guard both successful and failed responses against stale record revisions',
  )
  assert.match(acknowledge, /const revision\s*=\s*getRecordExpressionPlanCacheRevision\(normalizedRecordId\)/)
  assert.ok(
    occurrenceIndexes(acknowledge, 'isCacheCurrent(normalizedRecordId, version, revision)').length >= 2,
    'acknowledgements must guard both successful and failed responses against stale record revisions',
  )
})

test('successful PWA record mutations invalidate the affected planner cache', async () => {
  const store = await readFile(path.join(root, 'src/composables/useStore.js'), 'utf8')
  const confirmEntry = between(store, 'async function confirmEntry()', 'async function confirmStagingRepayment')
  const confirmIncome = between(store, 'async function confirmIncome()', 'function markIncomeImageUnavailable')
  const confirmExpense = between(store, 'async function confirmExpense()', 'function markExpenseImageUnavailable')
  const confirmUniversal = between(store, 'async function confirmUniversalRecord()', 'function markUniversalImageUnavailable')
  const finishArchive = between(store, 'async function finishStagingArchive', 'function buildUniversalRecordTitle')
  const bindRecord = between(store, 'async function bindRecordToAccount', 'function recommendedUnboundRecords')
  const createWalletAccount = between(store, 'async function createAccountFromWalletSnapshot', 'async function linkWalletSnapshotToAccount')
  const linkWalletAccount = between(store, 'async function linkWalletSnapshotToAccount', 'function mapIncomeRow')
  const deleteRecord = between(store, 'async function deleteRecordThroughBackend', 'async function confirmDelete')

  const pendingInvalidations = occurrenceIndexes(confirmEntry, 'invalidateRecordExpressionPlan(pendingId)')
  assert.equal(pendingInvalidations.length, 2, 'income and expense pending confirmations must both invalidate')
  assertInvalidatesAfterFailureGuard(
    confirmEntry,
    "p_entry_type: 'income'",
    'if (error)',
    'invalidateRecordExpressionPlan(pendingId)',
    'pending income confirmation',
  )
  assertInvalidatesAfterFailureGuard(
    confirmEntry.slice(confirmEntry.indexOf("p_entry_type: 'expense'")),
    "p_entry_type: 'expense'",
    'if (error)',
    'invalidateRecordExpressionPlan(pendingId)',
    'pending expense confirmation',
  )
  assert.match(confirmEntry, /invalidateRecordExpressionPlan\(confirmedIncomeId\)/)
  assert.match(confirmEntry, /invalidateRecordExpressionPlan\(confirmedExpenseId\)/)

  assertInvalidatesAfterFailureGuard(
    confirmIncome,
    'p_id: incomeModal.id',
    'if (error)',
    'invalidateRecordExpressionPlan(incomeModal.id)',
    'income edit',
  )
  assertInvalidatesAfterFailureGuard(
    confirmIncome,
    'p_id: null',
    'if (error)',
    'invalidateRecordExpressionPlan(newRow?.id)',
    'income create',
  )
  assert.match(confirmIncome, /invalidateRecordExpressionPlan\(incomeModal\.id\)/)
  assert.match(confirmIncome, /invalidateRecordExpressionPlan\(newRow\?\.id\)/)
  assertInvalidatesAfterFailureGuard(
    confirmExpense,
    'p_id: expenseModal.id',
    'if (error)',
    'invalidateRecordExpressionPlan(expenseModal.id)',
    'expense edit',
  )
  assertInvalidatesAfterFailureGuard(
    confirmExpense,
    'p_id: null',
    'if (error)',
    'invalidateRecordExpressionPlan(newRow?.id)',
    'expense create',
  )
  assert.match(confirmExpense, /invalidateRecordExpressionPlan\(expenseModal\.id\)/)
  assert.match(confirmExpense, /invalidateRecordExpressionPlan\(newRow\?\.id\)/)

  assertInvalidatesAfterFailureGuard(
    confirmUniversal,
    "sb.rpc('archive_staging_record'",
    'if (error)',
    'invalidateRecordExpressionPlan(stagingSource.id)',
    'universal staging completion',
  )
  assertInvalidatesAfterFailureGuard(
    confirmUniversal,
    ".update(body).eq('id', universalModal.id)",
    'if (error)',
    'invalidateRecordExpressionPlan(universalModal.id)',
    'universal edit',
  )
  assertInvalidatesAfterFailureGuard(
    confirmUniversal,
    ".insert({ ...body, user_id: currentUserId.value })",
    'if (error)',
    'invalidateRecordExpressionPlan(newRow?.id)',
    'universal create',
  )
  assert.match(confirmUniversal, /invalidateRecordExpressionPlan\(stagingSource\.id\)/)
  assert.match(confirmUniversal, /invalidateRecordExpressionPlan\(data\?\.target_record_id\)/)
  assert.match(confirmUniversal, /invalidateRecordExpressionPlan\(universalModal\.id\)/)
  assert.match(confirmUniversal, /invalidateRecordExpressionPlan\(newRow\?\.id\)/)
  assert.match(finishArchive, /invalidateRecordExpressionPlan\(targetRecordId\)/)

  assert.match(bindRecord, /invalidateRecordExpressionPlan\(record\.id\)/)
  assert.match(createWalletAccount, /invalidateRecordExpressionPlan\(record\.id\)/)
  assert.match(linkWalletAccount, /invalidateRecordExpressionPlan\(record\.id\)/)
  assert.match(deleteRecord, /if \(!response\.ok\) throw[\s\S]*invalidateRecordExpressionPlan\(recordId\)/)
})
