import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

test('PWA-033 useStore archive facade delegates all writes to the staging feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const start = source.indexOf('  async function archiveStagingRecord(')
  const end = source.indexOf('  function buildUniversalRecordTitle(', start)
  assert.notEqual(start, -1)
  assert.notEqual(end, -1)

  const archiveFacade = source.slice(start, end)
  assert.match(archiveFacade, /stagingArchiveFeature\.archive\(record, domainKey/)
  assert.doesNotMatch(archiveFacade, /save_transaction_with_account/)
  assert.doesNotMatch(archiveFacade, /save_income_with_account/)
  assert.doesNotMatch(archiveFacade, /from\(['"]data_records['"]\)\.insert/)
  assert.doesNotMatch(archiveFacade, /from\(['"]staging_records['"]\)\.update/)
  assert.doesNotMatch(archiveFacade, /user_routing_feedback/)
  assert.doesNotMatch(archiveFacade, /0\.01/)
  assert.doesNotMatch(source, /function finishStagingArchive/)
})
