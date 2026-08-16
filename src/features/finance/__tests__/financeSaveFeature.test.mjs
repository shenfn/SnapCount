import test from 'node:test'
import assert from 'node:assert/strict'
import { createFinanceSaveFeature } from '../createFinanceSaveFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(nextResolve => { resolve = nextResolve })
  return { promise, resolve }
}

test('PWA-059 duplicate saves share one request while different records remain independent', async () => {
  const expenseOne = deferred()
  const expenseTwo = deferred()
  let calls = 0
  const feature = createFinanceSaveFeature({
    repository: {
      saveExpense: ({ id }) => {
        calls += 1
        return id === 'expense-1' ? expenseOne.promise : expenseTwo.promise
      },
      saveIncome: async () => ({ status: 'accepted', kind: 'income', record: { id: 'income-1' } }),
    },
    getCurrentUserId: () => 'user-1',
  })

  const first = feature.saveExpense({ id: 'expense-1' })
  const duplicate = feature.saveExpense({ id: 'expense-1' })
  const independent = feature.saveExpense({ id: 'expense-2' })

  assert.equal(first, duplicate)
  assert.notEqual(first, independent)
  assert.equal(calls, 2)
  expenseOne.resolve({ status: 'accepted', kind: 'expense', record: { id: 'expense-1' } })
  expenseTwo.resolve({ status: 'accepted', kind: 'expense', record: { id: 'expense-2' } })
  assert.equal((await first).record.id, 'expense-1')
  assert.equal((await independent).record.id, 'expense-2')
})

test('PWA-060 a session change makes the old save stale without convergence or refresh', async () => {
  const pending = deferred()
  let userId = 'user-old'
  let acceptedCalls = 0
  let refreshCalls = 0
  const feature = createFinanceSaveFeature({
    repository: {
      saveExpense: () => pending.promise,
      saveIncome: async () => ({ status: 'accepted', kind: 'income', record: { id: 'income-1' } }),
    },
    getCurrentUserId: () => userId,
  })

  const request = feature.saveExpense({ id: null }, {
    onAccepted: () => { acceptedCalls += 1 },
    refresh: () => { refreshCalls += 1 },
  })
  userId = 'user-new'
  feature.reset()
  pending.resolve({ status: 'accepted', kind: 'expense', record: { id: 'expense-old' } })

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(result.reason, 'session_changed')
  assert.equal(acceptedCalls, 0)
  assert.equal(refreshCalls, 0)
})

test('PWA-061 an accepted save remains accepted when its refresh fails', async () => {
  let acceptedRecord = null
  const feature = createFinanceSaveFeature({
    repository: {
      saveExpense: async () => ({ status: 'accepted', kind: 'expense', record: { id: 'expense-1' } }),
      saveIncome: async () => ({ status: 'accepted', kind: 'income', record: { id: 'income-1' } }),
    },
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.saveIncome({ id: null }, {
    onAccepted: ({ record }) => { acceptedRecord = record },
    refresh: async () => { throw new Error('account refresh failed') },
  })

  assert.equal(acceptedRecord.id, 'income-1')
  assert.equal(result.status, 'accepted')
  assert.equal(result.record.id, 'income-1')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, 'account refresh failed')
})

test('PWA-059 unauthenticated saves are rejected before the repository', async () => {
  let calls = 0
  const feature = createFinanceSaveFeature({
    repository: {
      saveExpense: async () => { calls += 1 },
      saveIncome: async () => { calls += 1 },
    },
    getCurrentUserId: () => null,
  })

  const result = await feature.saveExpense({ id: null })

  assert.equal(result.status, 'rejected')
  assert.equal(result.reason, 'unauthenticated')
  assert.equal(calls, 0)
})
