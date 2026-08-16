import test from 'node:test'
import assert from 'node:assert/strict'

import {
  buildAccountBindingInput,
  createAccountBindingFeature,
} from '../createAccountBindingFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

function accepted(kind, id, accountId) {
  return { status: 'accepted', reason: 'saved', kind, record: { id, accountId } }
}

test('PWA-063A maps an expense to the existing repository transport once', () => {
  const input = buildAccountBindingInput('expense', {
    id: 'expense-1', amount: 18.5, name: '早餐', platform: '?', cat: 'food', payment: '微信',
    dateRaw: '2026-08-16', time: '08:20', occurredAt: '2026-08-16T00:20:00Z', note: '豆浆',
    source: 'staging', image_path: 'receipts/a.jpg', image_hash: 'hash', companionMessage: '已记录',
  }, 'account-1')

  assert.deepEqual(input, {
    id: 'expense-1', amount: 18.5, merchantName: '早餐', platform: null, category: 'food',
    paymentMethod: '微信', transactionDate: '2026-08-16', transactionTime: '08:20:00',
    occurredAt: '2026-08-16T00:20:00Z', note: '豆浆', isLargeTransport: false,
    transportType: null, source: 'staging', imageUrl: 'receipts/a.jpg', imageHash: 'hash',
    companionMessage: '已记录', accountId: 'account-1',
  })
})

test('PWA-063A maps an income without inventing a second RPC contract', () => {
  const input = buildAccountBindingInput('income', {
    id: 'income-1', cat: 'salary', source: '工资', amount: 8000, dateRaw: '2026-08-15',
    occurredAt: '2026-08-15T01:00:00Z', note: '八月工资', sourceType: 'staging',
    image_url: 'receipts/income.jpg', companionMessage: '已到账',
  }, 'account-2')

  assert.deepEqual(input, {
    id: 'income-1', category: 'salary', sourceName: '工资', amount: 8000,
    incomeDate: '2026-08-15', occurredAt: '2026-08-15T01:00:00Z', note: '八月工资',
    source: 'staging', imageUrl: 'receipts/income.jpg', imageHash: null,
    companionMessage: '已到账', accountId: 'account-2',
  })
})

test('PWA-063B identical bindings share a promise and a different account conflicts', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createAccountBindingFeature({
    repository: {
      saveExpense: async () => { calls += 1; return pending.promise },
      saveIncome: async () => accepted('income', 'income-1', 'account-1'),
    },
    getCurrentUserId: () => 'user-1',
  })
  const record = { id: 'expense-1', amount: 10, name: '早餐', dateRaw: '2026-08-16' }

  const first = feature.bind('expense', record, 'account-1')
  const duplicate = feature.bind('expense', record, 'account-1')
  const conflict = await feature.bind('expense', record, 'account-2')

  assert.equal(first, duplicate)
  assert.deepEqual(conflict, { status: 'rejected', reason: 'binding_conflict', kind: 'expense', record: null })
  pending.resolve(accepted('expense', 'expense-1', 'account-1'))
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-063C reset makes an old bind stale without convergence or refresh', async () => {
  const pending = deferred()
  let acceptedCalls = 0
  let refreshCalls = 0
  const feature = createAccountBindingFeature({
    repository: { saveExpense: () => pending.promise, saveIncome: () => pending.promise },
    getCurrentUserId: () => 'user-1',
  })
  const request = feature.bind('expense', { id: 'expense-1', amount: 10 }, 'account-1', {
    onAccepted: () => { acceptedCalls += 1 },
    refresh: () => { refreshCalls += 1 },
  })
  feature.reset()
  pending.resolve(accepted('expense', 'expense-1', 'account-1'))

  assert.deepEqual(await request, { status: 'stale', reason: 'session_changed', kind: 'expense', record: null })
  assert.equal(acceptedCalls, 0)
  assert.equal(refreshCalls, 0)
})

test('PWA-063D an accepted bind remains accepted when refresh fails', async () => {
  const feature = createAccountBindingFeature({
    repository: {
      saveExpense: async () => accepted('expense', 'expense-1', 'account-1'),
      saveIncome: async () => accepted('income', 'income-1', 'account-1'),
    },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.bind('expense', { id: 'expense-1', amount: 10 }, 'account-1', {
    refresh: async () => { throw new Error('刷新失败') },
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.record.id, 'expense-1')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '刷新失败')
})

test('PWA-063E batch returns item facts and refreshes once after partial success', async () => {
  let refreshCalls = 0
  const feature = createAccountBindingFeature({
    repository: {
      saveExpense: async input => input.id === 'expense-bad'
        ? { status: 'failed', reason: 'service_error', kind: 'expense', record: null, error: '写入失败' }
        : accepted('expense', input.id, input.accountId),
      saveIncome: async input => accepted('income', input.id, input.accountId),
    },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.bindBatch([
    { kind: 'expense', record: { id: 'expense-ok', amount: 10 }, accountId: 'account-1' },
    { kind: 'expense', record: { id: 'expense-bad', amount: 20 }, accountId: 'account-1' },
    { kind: 'income', record: { id: 'income-ok', amount: 30 }, accountId: 'account-2' },
  ], { refresh: async () => { refreshCalls += 1 } })

  assert.equal(result.status, 'partial')
  assert.equal(result.successCount, 2)
  assert.equal(result.failedCount, 1)
  assert.equal(result.items.length, 3)
  assert.equal(result.refreshStatus, 'ok')
  assert.equal(refreshCalls, 1)
})

test('PWA-063E an all-failed batch keeps failures visible and skips refresh', async () => {
  let refreshCalls = 0
  const failure = kind => ({ status: 'failed', reason: 'service_error', kind, record: null, error: '写入失败' })
  const feature = createAccountBindingFeature({
    repository: {
      saveExpense: async () => failure('expense'),
      saveIncome: async () => failure('income'),
    },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.bindBatch([
    { kind: 'expense', record: { id: 'expense-bad', amount: 10 }, accountId: 'account-1' },
    { kind: 'income', record: { id: 'income-bad', amount: 20 }, accountId: 'account-2' },
  ], { refresh: async () => { refreshCalls += 1 } })

  assert.equal(result.status, 'failed')
  assert.equal(result.successCount, 0)
  assert.equal(result.failedCount, 2)
  assert.equal(result.refreshStatus, 'not_requested')
  assert.equal(refreshCalls, 0)
})

test('PWA-063C batch stops before the next item after a session change', async () => {
  const first = deferred()
  let userId = 'user-1'
  let calls = 0
  let refreshCalls = 0
  const feature = createAccountBindingFeature({
    repository: {
      saveExpense: async input => { calls += 1; return input.id === 'expense-1' ? first.promise : accepted('expense', input.id, input.accountId) },
      saveIncome: async input => accepted('income', input.id, input.accountId),
    },
    getCurrentUserId: () => userId,
  })
  const request = feature.bindBatch([
    { kind: 'expense', record: { id: 'expense-1', amount: 10 }, accountId: 'account-1' },
    { kind: 'expense', record: { id: 'expense-2', amount: 20 }, accountId: 'account-1' },
  ], { refresh: async () => { refreshCalls += 1 } })
  userId = 'user-2'
  first.resolve(accepted('expense', 'expense-1', 'account-1'))

  const result = await request
  assert.equal(result.status, 'stale')
  assert.equal(calls, 1)
  assert.equal(refreshCalls, 0)
})
