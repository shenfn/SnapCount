import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

function between(source, start, end) {
  const startIndex = source.indexOf(start)
  const endIndex = source.indexOf(end, startIndex + start.length)
  assert.notEqual(startIndex, -1, `missing start: ${start}`)
  assert.ok(endIndex > startIndex, `missing end: ${end}`)
  return source.slice(startIndex, endIndex)
}

test('PWA-042 useStore discard facade delegates transport to the staging feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const discardFacade = between(source, '  async function discardStagingRecord(', '  function toggleBatchMode(')

  assert.match(source, /createStagingDiscardFeature/)
  assert.match(source, /stagingDiscardFeature\?\.reset\(\)/)
  assert.match(discardFacade, /stagingDiscardFeature\.discard\(record, reason/)
  assert.doesNotMatch(discardFacade, /sb\.rpc\(['"]discard_staging_record['"]/)
})

test('PWA-045 page and batch flows advance only accepted discard results', async () => {
  const [store, page] = await Promise.all([
    readFile('src/composables/useStore.js', 'utf8'),
    readFile('src/components/pages/PagePending.vue', 'utf8'),
  ])
  const batchDiscard = between(store, '  async function batchDiscard()', '  async function batchArchive(')
  const discardFromVerdict = between(page, 'async function discardFromVerdict(', 'async function confirmRepaymentFromVerdict(')

  assert.match(batchDiscard, /result\.value\?\.status\s*===\s*['"]accepted['"]/)
  assert.match(discardFromVerdict, /const result\s*=\s*await store\.discardStagingRecord\(record\)/)
  assert.match(discardFromVerdict, /if \(result\?\.status === ['"]accepted['"]\) settleVerdictAfterAction/)
})
