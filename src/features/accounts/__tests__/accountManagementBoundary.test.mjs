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

test('PWA-066C Store delegates account writes and resets the management feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const saveSource = functionSlice(source, 'async function saveAccount()', 'async function archiveAccount(')
  const archiveSource = functionSlice(source, 'async function archiveAccount(', 'async function loadAccountSourceSnapshot(')

  assert.match(source, /createAccountManagementFeature/)
  assert.match(source, /accountManagementFeature\.reset\(\)/)
  assert.match(saveSource, /accountManagementFeature\.save\(/)
  assert.match(archiveSource, /accountManagementFeature\.setArchived\(/)
  assert.doesNotMatch(saveSource, /sb\.from\(['"]accounts['"]\)|unsetOtherDefaults|is_archived/)
  assert.doesNotMatch(archiveSource, /sb\.from\(['"]accounts['"]\)/)
  assert.doesNotMatch(source, /async function unsetOtherDefaults\(/)
})

test('PWA-066E canonical account convergence updates list and selected detail', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const convergence = functionSlice(source, 'function convergeCanonicalAccount(', 'function accountWriteError(')

  assert.match(convergence, /accounts\.value/)
  assert.match(convergence, /selectedAccount\.value/)
  assert.match(source, /refreshAccountsFromDB\(\{ expectedUserId: userId, throwOnError: true \}\)/)
  assert.match(source, /列表刷新失败/)
})

test('PWA-066F archive is a dedicated detail command with explicit effects', async () => {
  const modal = await readFile('src/components/ModalAccount.vue', 'utf8')
  const detail = await readFile('src/components/pages/PageAccountDetail.vue', 'utf8')
  const walletAdapter = await readFile('src/adapters/domain/walletAdapter.js', 'utf8')

  assert.doesNotMatch(modal, /accountModal\.isArchived/)
  assert.match(detail, /store\.archiveAccount\(account, !account\.isArchived\)/)
  assert.match(detail, /归档会保留余额、流水和还款历史/)
  assert.match(detail, /恢复不会自动还原默认项或自动扣款关系/)
  assert.match(walletAdapter, /key: ['"]archived['"]/)
  assert.match(walletAdapter, /title: ['"]已归档账户['"]/)
})
