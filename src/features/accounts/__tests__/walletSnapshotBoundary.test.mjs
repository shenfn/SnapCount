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

test('PWA-068G and PWA-068I Store delegates wallet snapshot writes and resets the feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const createSource = functionSlice(source, 'async function createAccountFromWalletSnapshot(', 'async function linkWalletSnapshotToAccount(')
  const linkSource = functionSlice(source, 'async function linkWalletSnapshotToAccount(', 'async function loadUnboundRecords(')

  assert.match(source, /createWalletSnapshotFeature/)
  assert.match(source, /walletSnapshotFeature\.reset\(\)/)
  assert.match(createSource, /walletSnapshotFeature\.apply\(/)
  assert.match(linkSource, /walletSnapshotFeature\.apply\(/)
  assert.doesNotMatch(createSource, /sb\.from|account_repayment_cycles|account_entries/)
  assert.doesNotMatch(linkSource, /sb\.from|account_repayment_cycles|account_entries/)
  assert.doesNotMatch(source, /async function upsertRepaymentCycleFromWalletSnapshot\(/)
  assert.doesNotMatch(source, /async function reconcileLiabilityAccountFromWalletSnapshot\(/)
})

test('PWA-068I Page keeps failed commands open and filters incompatible accounts', async () => {
  const page = await readFile('src/components/pages/PageDomainDetail.vue', 'utf8')
  const linkAction = functionSlice(page, 'async function linkSnapshotToExistingAccount(', '</script>')

  assert.match(page, /compatibleWalletSnapshotAccounts/)
  assert.match(linkAction, /result\?\.status === 'accepted'/)
  assert.match(linkAction, /expandedSnapshotId\.value = null/)
})

test('PWA-068J account reads keep the historical repair helper disconnected', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  assert.equal(source.split('repairEmptyAccountSnapshotBalances(').length - 1, 1)
})
