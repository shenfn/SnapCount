import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

function functionSource(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start + startMarker.length)
  assert.notEqual(start, -1, `missing marker: ${startMarker}`)
  assert.notEqual(end, -1, `missing marker: ${endMarker}`)
  return source.slice(start, end)
}

test('PWA-052 to PWA-054 loadData delegates formal record reads and keeps the run guard', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const loadData = functionSource(source, 'async function loadData(', 'async function getSignedImageUrl(')

  assert.match(source, /createRecordRepository/)
  assert.match(loadData, /recordRepository\.listExpenses\(/)
  assert.match(loadData, /recordRepository\.listPendingExpenses\(/)
  assert.match(loadData, /recordRepository\.listIncomes\(/)
  assert.match(loadData, /recordRepository\.listRecentIncomes\(/)
  assert.match(loadData, /recordRepository\.listUniversalRecords\(/)
  assert.doesNotMatch(loadData, /sb\.from\(['"](?:transactions|income_records|data_records)['"]\)/)
  assert.match(loadData, /const isCurrentDataLoad = \(\) =>/)
  assert.match(loadData, /if \(!isCurrentDataLoad\(\)\) return \{ ok: false, stale: true \}/)
})

test('PWA-055 unbound records delegate transport while Store keeps loading and page state', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const loadUnbound = functionSource(source, 'async function loadUnboundRecords(', 'async function openUnboundRecordsPage(')

  assert.match(loadUnbound, /unboundRecordsLoading\.value = true/)
  assert.match(loadUnbound, /recordRepository\.listUnboundRecords\(/)
  assert.match(loadUnbound, /unboundRecords\.value =/)
  assert.doesNotMatch(loadUnbound, /sb\.from\(['"](?:transactions|income_records)['"]\)/)
})

test('PWA-052 to PWA-055 record repository stays outside account, staging, signing, and direct table writes', async () => {
  const source = await readFile('src/repositories/recordRepository.js', 'utf8')

  assert.doesNotMatch(source, /from\(['"](?:accounts|account_entries|staging_records)['"]\)/)
  assert.doesNotMatch(source, /\.insert\(|\.update\(|\.delete\(/)
  assert.match(source, /saveRecord\(client, 'save_transaction_with_account'/)
  assert.match(source, /saveRecord\(client, 'save_income_with_account'/)
  assert.doesNotMatch(source, /getSignedImageUrl|ensure_liability_repayment_cycles|buildRepaymentCandidate|accountCandidate/i)
})

test('PWA-056E processed staging navigation uses explicit kind and the record repository', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const openProcessed = functionSource(source, 'async function openProcessedStagingRecord(', '  // 账户 CRUD')

  assert.match(openProcessed, /record\.targetKind/)
  assert.match(openProcessed, /recordRepository\.getRecordByTarget\(/)
  assert.doesNotMatch(openProcessed, /Promise\.all\(/)
  assert.doesNotMatch(openProcessed, /sb\.from\(['"](?:transactions|income_records|data_records)['"]\)/)
  assert.match(openProcessed, /targetKind === ['"]expense['"]|targetKind === ['"]income['"]|targetKind === ['"]data['"]/)
})
