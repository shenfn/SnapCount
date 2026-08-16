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

test('PWA-062 manual and edit finance saves delegate to the Finance Save Feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const income = functionSlice(source, 'async function confirmIncome()', 'function markIncomeImageUnavailable()')
  const expense = functionSlice(source, 'async function confirmExpense()', 'function markExpenseImageUnavailable()')

  assert.match(source, /createFinanceSaveFeature/)
  assert.match(source, /financeSaveFeature\.reset\(\)/)
  assert.match(income, /financeSaveFeature\.saveIncome\(/)
  assert.match(expense, /financeSaveFeature\.saveExpense\(/)
  assert.doesNotMatch(income, /sb\.rpc\('save_income_with_account'/)
  assert.doesNotMatch(expense, /sb\.rpc\('save_transaction_with_account'/)
  assert.doesNotMatch(income, /const mapped\s*=\s*\{/)
  assert.match(income, /result\.record/)
  assert.match(expense, /result\.record/)
})

test('PWA-062 account rebinding remains outside the modal Finance Save Feature', async () => {
  const source = await readFile('src/composables/useStore.js', 'utf8')
  const binding = functionSlice(source, 'async function bindRecordToAccount(', 'async function batchBindRecommendedUnboundRecords(')

  assert.match(binding, /accountBindingFeature\.bind\(/)
  assert.doesNotMatch(binding, /financeSaveFeature\./)
})
