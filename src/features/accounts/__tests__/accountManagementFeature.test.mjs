import test from 'node:test'
import assert from 'node:assert/strict'

import { createAccountManagementFeature } from '../createAccountManagementFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

function accepted(id = 'account-1') {
  return { status: 'accepted', reason: 'saved', account: { id, name: '账户' } }
}

const saveCommand = {
  accountId: 'account-1', name: '账户', type: 'cash', initialBalance: 0,
  isDefaultExpense: true, isDefaultIncome: false,
}

test('PWA-066D identical account commands share a promise and different commands conflict', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createAccountManagementFeature({
    repository: { saveAccount: () => { calls += 1; return pending.promise }, setAccountArchived: async () => accepted() },
    getCurrentUserId: () => 'user-1',
  })

  const first = feature.save(saveCommand)
  const duplicate = feature.save({ ...saveCommand })
  const conflicting = await feature.save({ ...saveCommand, name: '不同名称' })

  assert.equal(first, duplicate)
  assert.deepEqual(conflicting, { status: 'conflict', reason: 'account_command_conflict', account: null })
  pending.resolve(accepted())
  assert.equal((await first).status, 'accepted')
  assert.equal(calls, 1)
})

test('PWA-066D create forms use a local command key while different forms can submit', async () => {
  const pending = deferred()
  let calls = 0
  const feature = createAccountManagementFeature({
    repository: { saveAccount: command => { calls += 1; return command.commandKey === 'form-1' ? pending.promise : accepted('account-2') }, setAccountArchived: async () => accepted() },
    getCurrentUserId: () => 'user-1',
  })
  const first = feature.save({ commandKey: 'form-1', name: '账户', type: 'cash' })
  const duplicate = feature.save({ commandKey: 'form-1', name: '账户', type: 'cash' })
  const second = await feature.save({ commandKey: 'form-2', name: '账户', type: 'cash' })

  assert.equal(first, duplicate)
  assert.equal(second.account.id, 'account-2')
  pending.resolve(accepted('account-1'))
  await first
  assert.equal(calls, 2)
})

test('PWA-066D reset and user switch make old account writes stale before convergence', async () => {
  const pending = deferred()
  let userId = 'user-1'
  let acceptedCalls = 0
  let refreshCalls = 0
  const feature = createAccountManagementFeature({
    repository: { saveAccount: () => pending.promise, setAccountArchived: async () => accepted() },
    getCurrentUserId: () => userId,
  })
  const hooks = { onAccepted: () => { acceptedCalls += 1 }, refresh: () => { refreshCalls += 1 } }

  const resetRequest = feature.save(saveCommand, hooks)
  feature.reset()
  pending.resolve(accepted())
  assert.deepEqual(await resetRequest, { status: 'stale', reason: 'session_changed', account: null })

  const switchedPending = deferred()
  // The feature keeps its public method stable; this branch only checks user identity on a live request.
  const secondFeature = createAccountManagementFeature({
    repository: { saveAccount: () => switchedPending.promise, setAccountArchived: async () => accepted() },
    getCurrentUserId: () => userId,
  })
  const switched = secondFeature.save(saveCommand, hooks)
  userId = 'user-2'
  switchedPending.resolve(accepted())
  assert.deepEqual(await switched, { status: 'stale', reason: 'session_changed', account: null })
  assert.equal(acceptedCalls, 0)
  assert.equal(refreshCalls, 0)
})

test('PWA-066E accepted canonical account converges before refresh and preserves accepted on refresh failure', async () => {
  const events = []
  const feature = createAccountManagementFeature({
    repository: { saveAccount: async () => accepted(), setAccountArchived: async () => accepted() },
    getCurrentUserId: () => 'user-1',
  })
  const result = await feature.save(saveCommand, {
    onAccepted: account => { events.push(`account:${account.id}`) },
    refresh: async () => { events.push('refresh'); return { status: 'failed', error: '列表刷新失败' } },
  })

  assert.deepEqual(events, ['account:account-1', 'refresh'])
  assert.equal(result.status, 'accepted')
  assert.equal(result.refreshStatus, 'failed')
  assert.equal(result.refreshError, '列表刷新失败')
})

test('PWA-066D unauthenticated and malformed commands stop before transport', async () => {
  let calls = 0
  const feature = createAccountManagementFeature({
    repository: { saveAccount: async () => { calls += 1; return accepted() }, setAccountArchived: async () => { calls += 1; return accepted() } },
    getCurrentUserId: () => '',
  })
  assert.equal((await feature.save(saveCommand)).reason, 'unauthenticated')
  assert.equal((await feature.setArchived({ accountId: 'account-1', archived: true })).reason, 'unauthenticated')

  const authenticated = createAccountManagementFeature({
    repository: { saveAccount: async () => { calls += 1; return accepted() }, setAccountArchived: async () => { calls += 1; return accepted() } },
    getCurrentUserId: () => 'user-1',
  })
  assert.equal((await authenticated.save({ ...saveCommand, name: '' })).reason, 'invalid_input')
  assert.equal((await authenticated.setArchived({ accountId: '', archived: true })).reason, 'invalid_input')
  assert.equal(calls, 0)
})
