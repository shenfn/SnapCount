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

test('PWA-065A and PWA-065B Store delegates account reads without hidden repair writes', async () => {
  const store = await readFile('src/composables/useStore.js', 'utf8')
  const repository = await readFile('src/repositories/accountRepository.js', 'utf8')
  const loadData = functionSlice(store, 'async function loadData(', 'async function changeMonth(')
  const detail = functionSlice(store, 'async function loadAccountEntries(', 'function convergeRepaymentCycle(')
  const refreshAccounts = functionSlice(store, 'async function refreshAccountsFromDB(', 'function defaultAccountIdForKind(')

  assert.match(store, /createAccountDetailFeature/)
  assert.match(store, /accountDetailFeature\.reset\(\)/)
  assert.match(loadData, /accountRepository\.listAccounts\(/)
  assert.match(refreshAccounts, /accountRepository\.listAccounts\(/)
  assert.match(loadData, /accountListState\.value/)
  assert.match(refreshAccounts, /accountListState\.value/)
  assert.doesNotMatch(loadData, /sb\.from\('accounts'\)/)
  assert.doesNotMatch(loadData, /accounts\.value = \[\]/)
  assert.doesNotMatch(refreshAccounts, /sb\.from\('accounts'\)|repairEmptyAccountSnapshotBalances/)
  assert.doesNotMatch(refreshAccounts, /accounts\.value = \[\]/)
  assert.doesNotMatch(detail, /sb\.from\('account_entries'\)|sb\.from\('liability_payments'\)|sb\.from\('account_repayment_cycles'\)/)
  assert.match(repository, /listAccountEntries/)
  assert.match(repository, /listAccountPayments/)
  assert.match(repository, /listRepaymentCycles/)
  assert.match(repository, /ensureRepaymentCycles/)
  assert.doesNotMatch(repository, /data_records|getSignedImageUrl/)
})

test('PWA-065C and PWA-065D Store exposes structured detail state and refresh results', async () => {
  const store = await readFile('src/composables/useStore.js', 'utf8')
  const openDetail = functionSlice(store, 'async function loadAccountEntries(', 'function convergeRepaymentCycle(')

  assert.match(store, /accountDetailState/)
  assert.match(openDetail, /accountDetailFeature\.load\(/)
  assert.match(openDetail, /status === 'stale'/)
  assert.match(store, /result\.sections/)
  assert.match(store, /entries\.status/)
  assert.match(store, /payments\.status/)
  assert.match(store, /cycles\.status/)
  assert.match(store, /sourceSnapshot\.status/)
  assert.match(openDetail, /return result/)
})

test('PWA-065E account detail page distinguishes loading, empty, and section failures', async () => {
  const page = await readFile('src/components/pages/PageAccountDetail.vue', 'utf8')

  assert.match(page, /accountDetailSectionErrors/)
  assert.match(page, /账户流水加载失败/)
  assert.match(page, /还款记录加载失败/)
  assert.match(page, /账单周期加载失败/)
  assert.match(page, /来源快照加载失败/)
  assert.match(page, /store\.refreshAccountDetail\(\)/)
  assert.match(page, /account-detail-section-error/)
})
