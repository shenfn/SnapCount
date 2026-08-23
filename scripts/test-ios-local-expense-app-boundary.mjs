import test from 'node:test'
import assert from 'node:assert/strict'
import { access } from 'node:fs/promises'
import { readFile } from 'node:fs/promises'

const expectedFiles = [
  'ios/SnapCount/LocalData/LocalProfileStore.swift',
  'ios/SnapCount/Features/Records/LocalExpenseUseCase.swift',
  'ios/SnapCount/Features/Records/LocalExpenseMapper.swift',
  'ios/SnapCount/Features/Records/LocalExpenseReadModel.swift',
]

test('LOCAL-002-APP application boundary files exist', async () => {
  for (const file of expectedFiles) {
    await access(file)
  }
})

test('AppState does not own the local transaction implementation', async () => {
  const source = await readFile('ios/SnapCount/App/AppState.swift', 'utf8')
  const start = source.indexOf('func createManualRecord(')
  const end = source.indexOf('private func createLocalExpense(', start)
  assert.ok(start >= 0 && end > start, 'missing local expense compatibility boundary')
  const createBlock = source.slice(start, end)
  assert.doesNotMatch(
    createBlock,
    /validSession\(\)|recordRepository\.create/u,
    'AppState still directly gates local expense creation on a remote session'
  )
})

console.log('iOS LOCAL-002-APP boundary checks passed')
