import test from 'node:test'
import assert from 'node:assert/strict'

import { createAccountDetailFeature } from '../createAccountDetailFeature.js'

function deferred() {
  let resolve
  const promise = new Promise(done => { resolve = done })
  return { promise, resolve }
}

function acceptedRows(rows = []) {
  return { status: 'accepted', reason: 'loaded', rows }
}

function createRepository(overrides = {}) {
  return {
    listAccountEntries: async () => acceptedRows([{ id: 'entry-1' }]),
    listAccountPayments: async () => acceptedRows([{ id: 'payment-1' }]),
    listRepaymentCycles: async () => acceptedRows([{ id: 'cycle-1' }]),
    ensureRepaymentCycles: async () => ({ status: 'accepted', reason: 'ensured' }),
    ...overrides,
  }
}

const assetAccount = { id: 'asset-1', type: 'wallet_balance', sourceRecordId: '', sourceRecordTable: '' }
const liabilityAccount = { id: 'liability-1', type: 'credit_line', sourceRecordId: 'snapshot-1', sourceRecordTable: 'data_records' }

test('PWA-065B asset details skip liability-only payments and cycles', async () => {
  let paymentCalls = 0
  let cycleCalls = 0
  let ensureCalls = 0
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      listAccountPayments: async () => { paymentCalls += 1; return acceptedRows() },
      listRepaymentCycles: async () => { cycleCalls += 1; return acceptedRows() },
      ensureRepaymentCycles: async () => { ensureCalls += 1; return { status: 'accepted' } },
    }),
    loadSourceSnapshot: async () => ({ status: 'accepted', data: null, applicable: false }),
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.load(assetAccount)

  assert.equal(result.status, 'accepted')
  assert.equal(result.sections.payments.applicable, false)
  assert.equal(result.sections.repaymentCycles.applicable, false)
  assert.equal(paymentCalls, 0)
  assert.equal(cycleCalls, 0)
  assert.equal(ensureCalls, 0)
})

test('PWA-065C identical detail loads share a promise and account switching makes the old request stale', async () => {
  const firstEntries = deferred()
  let entryCalls = 0
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      listAccountEntries: ({ accountId }) => {
        entryCalls += 1
        return accountId === assetAccount.id ? firstEntries.promise : acceptedRows([{ id: 'entry-2' }])
      },
    }),
    loadSourceSnapshot: async () => ({ status: 'accepted', reason: 'not_applicable', data: null, applicable: false }),
    getCurrentUserId: () => 'user-1',
  })

  const first = feature.load(assetAccount)
  const duplicate = feature.load({ ...assetAccount })
  assert.equal(first, duplicate)

  const second = feature.load({ ...assetAccount, id: 'asset-2' })
  assert.equal((await second).status, 'accepted')
  firstEntries.resolve(acceptedRows([{ id: 'entry-old' }]))
  assert.equal((await first).status, 'stale')
  assert.equal(feature.getState().identity.accountId, 'asset-2')
  assert.equal(entryCalls, 2)
})

test('PWA-065C reset and user switching make old detail results stale', async () => {
  const resetPending = deferred()
  const userPending = deferred()
  let userId = 'user-1'
  let callIndex = 0
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      listAccountEntries: () => (callIndex++ === 0 ? resetPending.promise : userPending.promise),
    }),
    loadSourceSnapshot: async () => ({ status: 'accepted', data: null, applicable: false }),
    getCurrentUserId: () => userId,
  })

  const resetRequest = feature.load(assetAccount)
  feature.reset()
  resetPending.resolve(acceptedRows())
  assert.equal((await resetRequest).status, 'stale')

  const switchedRequest = feature.load(assetAccount)
  userId = 'user-2'
  userPending.resolve(acceptedRows())
  assert.equal((await switchedRequest).status, 'stale')
})

test('PWA-065D a section failure preserves successful sections and returns partial', async () => {
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      listAccountPayments: async () => ({ status: 'failed', reason: 'service_error', rows: [], error: '还款记录读取失败' }),
    }),
    loadSourceSnapshot: async () => ({ status: 'accepted', reason: 'loaded', data: { id: 'snapshot-1' } }),
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.load(liabilityAccount, { ensureCycles: true, cycleMonth: '2026-08' })

  assert.equal(result.status, 'partial')
  assert.equal(result.sections.entries.data[0].id, 'entry-1')
  assert.equal(result.sections.payments.status, 'failed')
  assert.equal(result.sections.payments.error, '还款记录读取失败')
  assert.equal(result.sections.sourceSnapshot.data.id, 'snapshot-1')
})

test('PWA-065D an ensure failure preserves loaded cycles and stays visible', async () => {
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      ensureRepaymentCycles: async () => ({ status: 'failed', reason: 'service_error', error: '周期生成失败' }),
    }),
    loadSourceSnapshot: async () => ({ status: 'accepted', data: null, applicable: false }),
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.load(liabilityAccount, { ensureCycles: true, cycleMonth: '2026-08' })

  assert.equal(result.status, 'partial')
  assert.equal(result.sections.repaymentCycles.status, 'failed')
  assert.equal(result.sections.repaymentCycles.data[0].id, 'cycle-1')
  assert.equal(result.sections.repaymentCycles.error, '周期生成失败')
})

test('PWA-065D all applicable section failures return failed instead of an empty accepted detail', async () => {
  const failure = { status: 'failed', reason: 'service_error', rows: [], error: '读取失败' }
  const feature = createAccountDetailFeature({
    accountRepository: createRepository({
      listAccountEntries: async () => failure,
      listAccountPayments: async () => failure,
      listRepaymentCycles: async () => failure,
    }),
    loadSourceSnapshot: async () => ({ status: 'failed', reason: 'service_error', data: null, error: '快照读取失败' }),
    getCurrentUserId: () => 'user-1',
  })

  const result = await feature.load(liabilityAccount)

  assert.equal(result.status, 'failed')
  assert.equal(result.sections.entries.status, 'failed')
  assert.equal(result.sections.sourceSnapshot.status, 'failed')
})
