import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

function functionSlice(source, startMarker, endMarker) {
  const start = source.indexOf(startMarker)
  const end = source.indexOf(endMarker, start + startMarker.length)
  assert.notEqual(start, -1, `missing start marker: ${startMarker}`)
  assert.notEqual(end, -1, `missing end marker: ${endMarker}`)
  return source.slice(start, end)
}

test('PWA-063A Store binding delegates to Account Binding Feature without direct RPC params', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const binding = functionSlice(source, 'async function bindRecordToAccount(', 'function recommendedUnboundRecords(')

  assert.match(source, /createAccountBindingFeature/)
  assert.match(source, /accountBindingFeature\.reset\(\)/)
  assert.match(binding, /accountBindingFeature\.bind\(/)
  assert.doesNotMatch(binding, /sb\.rpc\('save_(?:income|transaction)_with_account'/)
  assert.doesNotMatch(binding, /p_occurred_at|p_account_id/)
  assert.match(binding, /result\.record/)
})

test('PWA-063E batch delegates once and does not loop over single Store bindings', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const batch = functionSlice(source, 'async function batchBindRecommendedUnboundRecords(', 'function walletSnapshotKindOf(')

  assert.match(batch, /accountBindingFeature\.bindBatch\(/)
  assert.doesNotMatch(batch, /for \(const item of candidates\)/)
  assert.match(batch, /successCount/)
  assert.match(batch, /failedCount/)
})

test('PWA-063F recommendation and preview remain outside the Feature', async () => {
  const feature = await readFile('src/features/finance/createAccountBindingFeature.js', 'utf8')
  const page = await readFile('src/components/pages/PageUnboundRecords.vue', 'utf8')

  assert.doesNotMatch(feature, /recommend|defaultAccount|paymentText|accounts\.value/i)
  assert.match(page, /recommendedUnboundRecords/)
  assert.match(page, /selectedIds/)
  assert.match(page, /confirmBatchBind/)
})
