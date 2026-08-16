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

test('PWA-067C Store delegates screenshot repayment transport and candidate rules', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const confirmSource = functionSlice(source, 'async function confirmStagingRepayment(', 'function stagingArchivePayload(')
  const candidateSource = functionSlice(source, 'function buildRepaymentCandidateForStaging(', 'function formatYuan(')
  assert.match(source, /createScreenshotRepaymentFeature/)
  assert.match(source, /buildScreenshotRepaymentCandidate/)
  assert.match(source, /screenshotRepaymentFeature\.reset\(\)/)
  assert.match(confirmSource, /screenshotRepaymentFeature\.confirm\(/)
  assert.doesNotMatch(confirmSource, /sb\.rpc|confirm_staging_repayment|p_status/)
  assert.doesNotMatch(candidateSource, /score \+=|openStatuses|repaymentCycles\.value\.filter/)
})

test('PWA-067F and PWA-067G keep repayment targets reachable and only advance accepted commands', async () => {
  const store = await readFile('src/composables/useStore.js', 'utf8')
  const page = await readFile('src/components/pages/PagePending.vue', 'utf8')
  const repository = await readFile('src/repositories/stagingRepository.js', 'utf8')
  assert.match(repository, /repayment_cycle/)
  assert.match(store, /targetKind === 'repayment_cycle'/)
  assert.match(page, /result\?\.status === 'accepted'/)
})
