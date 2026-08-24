import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const appStatePath = 'ios/SnapCount/App/AppState.swift'
const recordsPath = 'ios/SnapCount/Features/Records/RecordsView.swift'

async function source(path) {
  return readFile(path, 'utf8')
}

test('LOCAL-003B1 local detail facade must not require a cloud session', async () => {
  const appState = await source(appStatePath)
  const start = appState.indexOf('func loadRecordDetail(reference:')
  const end = appState.indexOf('\n    private func hydrateRecordDetailImageIfNeeded', start)
  assert.ok(start >= 0 && end > start, 'detail load boundary is missing')
  const block = appState.slice(start, end)
  assert.match(block, /local-expense|localExpense|LocalExpense/u)
  assert.match(block, /recordDetailCache|selectedRecordDetail/u)
  assert.doesNotMatch(block, /validSession\(\)/u)
  assert.doesNotMatch(block, /recordRepository\.fetchDetail/u)
})

test('LOCAL-003B2 records page already has one detail destination as a baseline', async () => {
  const records = await source(recordsPath)
  assert.match(records, /navigationDestination\(for: NativeRecordRoute\.self\)/u)
  assert.doesNotMatch(records, /if appState\.isSignedIn[\s\S]*RecordDetailView/u)
})

test('LOCAL-003B3 local edit and delete stay behind AppState local facade', async () => {
  const appState = await source(appStatePath)
  const saveStart = appState.indexOf('func saveRecordDetail(')
  const saveEnd = appState.indexOf('\n    func deleteRecord(', saveStart)
  const deleteStart = saveEnd
  const deleteEnd = appState.indexOf('\n    func confirmPendingRecord(', deleteStart)
  assert.ok(saveStart >= 0 && saveEnd > saveStart, 'save boundary is missing')
  assert.ok(deleteStart >= 0 && deleteEnd > deleteStart, 'delete boundary is missing')
  const block = appState.slice(saveStart, deleteEnd)
  assert.match(block, /local-expense|localExpense|LocalExpense/u)
  assert.doesNotMatch(block, /guard isSignedIn/u)
  assert.doesNotMatch(block, /recordRepository\.(saveDetail|delete)/u)
})

console.log('iOS LOCAL-003B local detail boundary checks passed')
