import test from 'node:test'
import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'

const rootPath = 'ios/SnapCount/Features/Root/RootView.swift'
const recordsPath = 'ios/SnapCount/Features/Records/RecordsView.swift'
const settingsPath = 'ios/SnapCount/Features/Settings/SettingsView.swift'
const localSettingsPath = 'ios/SnapCount/Features/Settings/LocalSettingsView.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'

async function source(path) {
  return readFile(path, 'utf8')
}

test('LOCAL-003A1 Root only owns one business Tab tree', async () => {
  const root = await source(rootPath)

  assert.doesNotMatch(root, /private var localTabRoot/u)
  assert.doesNotMatch(root, /private var cloudTabRoot/u)
  assert.equal((root.match(/\bTabView\b/gu) ?? []).length, 1)
  assert.match(root, /SettingsView\(\)/u)
  assert.doesNotMatch(root, /LocalSettingsView\(\)/u)
})

test('LOCAL-003A2 Records page does not branch its business UI on auth state', async () => {
  const records = await source(recordsPath)
  const bodyStart = records.indexOf('var body: some View')
  const bodyEnd = records.indexOf('\n    private var prefetchKey', bodyStart)
  assert.ok(bodyStart >= 0 && bodyEnd > bodyStart, 'Records body boundary is missing')

  const body = records.slice(bodyStart, bodyEnd)
  assert.doesNotMatch(body, /appState\.isSignedIn/u)
  assert.doesNotMatch(body, /LocalAccountPreparationView|LocalExpenseEntryView/u)
  assert.match(body, /recordGroups\(monthKey:/u)
})

test('LOCAL-003A3 Settings uses one page and exposes local storage and sync state', async () => {
  const settings = await source(settingsPath)

  assert.match(settings, /数据存储/u)
  assert.match(settings, /云同步|同步状态/u)
  assert.match(settings, /仅保存在此 iPhone|本机|本地/u)
  assert.match(settings, /登录|开启同步|云端/u)
  await assert.rejects(access(localSettingsPath), 'the temporary local-only settings page must be removed')
})

test('LOCAL-003A4 AppState delegates month reads instead of selecting remote/local branches', async () => {
  const appState = await source(appStatePath)
  const start = appState.indexOf('func loadRecordMonth(')
  const end = appState.indexOf('\n    private func loadLocalExpenseMonth', start)
  assert.ok(start >= 0 && end > start, 'loadRecordMonth boundary is missing')

  const block = appState.slice(start, end)
  assert.doesNotMatch(block, /guard isSignedIn else/u)
  assert.doesNotMatch(block, /recordRepository\.fetchMonth/u)
  assert.doesNotMatch(block, /loadLocalExpenseMonth/u)
  assert.match(block, /records|readModel|UseCase/u)
})

test('LOCAL-003A5 unified manual expense writes locally regardless of cloud session', async () => {
  const appState = await source(appStatePath)
  const start = appState.indexOf('func createManualRecord(')
  const end = appState.indexOf('\n    private func createLocalExpense(', start)
  assert.ok(start >= 0 && end > start, 'createManualRecord boundary is missing')

  const block = appState.slice(start, end)
  assert.doesNotMatch(block, /!isSignedIn/u)
  assert.doesNotMatch(block, /createRemoteManualRecord/u)
  assert.match(block, /localExpenseUseCase|LocalExpense/u)
})

console.log('iOS LOCAL-003A unified shell boundary checks passed')
