import test from 'node:test'
import assert from 'node:assert/strict'

import { createAccountRepository, mapRepaymentCycleRow } from '../accountRepository.js'

function createReadClient(responseQueues = {}) {
  const calls = []
  const queues = Object.fromEntries(
    Object.entries(responseQueues).map(([name, responses]) => [
      name,
      Array.isArray(responses) ? [...responses] : [responses],
    ]),
  )

  return {
    calls,
    client: {
      from(table) {
        const response = queues[table]?.shift() || { data: [], error: null }
        const query = {
          select(fields) {
            calls.push({ table, method: 'select', fields })
            return query
          },
          eq(column, value) {
            calls.push({ table, method: 'eq', column, value })
            return query
          },
          order(column, options) {
            calls.push({ table, method: 'order', column, options })
            return query
          },
          limit(value) {
            calls.push({ table, method: 'limit', value })
            return Promise.resolve(response)
          },
          then(resolve, reject) {
            return Promise.resolve(response).then(resolve, reject)
          },
        }
        return query
      },
      async rpc(name, params) {
        calls.push({ name, method: 'rpc', params })
        return queues[name]?.shift() || { data: null, error: null }
      },
    },
  }
}

function createRpcClient(responses = {}) {
  const calls = []
  const queues = Object.fromEntries(
    Object.entries(responses).map(([name, value]) => [name, Array.isArray(value) ? [...value] : [value]]),
  )
  return {
    calls,
    client: {
      async rpc(name, params) {
        calls.push({ name, params })
        return queues[name]?.shift() || { data: null, error: null }
      },
    },
  }
}

const cycleRow = {
  id: 'cycle-1',
  user_id: 'user-1',
  account_id: 'liability-1',
  cycle_month: '2026-08',
  statement_start_date: '2026-07-01',
  statement_end_date: '2026-07-31',
  due_date: '2026-08-20',
  statement_amount: '100.00',
  paid_amount: '40.00',
  remaining_amount: '60.00',
  carried_over_amount: '0.00',
  original_statement_amount: '100.00',
  min_payment_amount: '20.00',
  refund_applied_amount: '0.00',
  status: 'partial_paid',
  auto_debit_account_id: 'debit-1',
  auto_confirm_repayment: false,
  source: 'manual',
  evidence_record_id: null,
  confidence: '0.98',
  statement_source_priority: 30,
  note: '部分还款',
  confirmed_at: '2026-08-16T08:00:00Z',
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-16T08:00:00Z',
}

test('PWA-064B maps the canonical repayment cycle DTO once', () => {
  const cycle = mapRepaymentCycleRow(cycleRow)

  assert.equal(cycle.id, 'cycle-1')
  assert.equal(cycle.accountId, 'liability-1')
  assert.equal(cycle.statementAmount, 100)
  assert.equal(cycle.paidAmount, 40)
  assert.equal(cycle.remainingAmount, 60)
  assert.equal(cycle.minPaymentAmount, 20)
  assert.equal(cycle.confidence, 0.98)
  assert.equal(cycle.autoDebitAccountId, 'debit-1')
})

test('PWA-064B confirmation owns RPC params without accepting a user id', async () => {
  const { client, calls } = createRpcClient({
    set_repayment_cycle_paid_amount: { data: cycleRow, error: null },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.confirmRepayment({
    cycleId: 'cycle-1',
    paidAmount: 40,
    paidAt: '2026-08-16T08:00:00Z',
    debitAccountId: 'debit-1',
    status: 'partial_paid',
    note: '部分还款',
    userId: 'must-not-cross-transport',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'confirmed')
  assert.equal(result.cycle.id, 'cycle-1')
  assert.deepEqual(calls, [{
    name: 'set_repayment_cycle_paid_amount',
    params: {
      p_cycle_id: 'cycle-1',
      p_paid_amount: 40,
      p_paid_at: '2026-08-16T08:00:00Z',
      p_debit_account_id: 'debit-1',
      p_status: 'partial_paid',
      p_note: '部分还款',
    },
  }])
  assert.equal(Object.hasOwn(calls[0].params, 'user_id'), false)
})

test('PWA-064B revocation preserves a null canonical cycle and service failures', async () => {
  const { client, calls } = createRpcClient({
    revoke_liability_payment: [
      { data: null, error: null },
      { data: null, error: { message: '撤销失败' } },
    ],
  })
  const repository = createAccountRepository({ client })

  const accepted = await repository.revokePayment({ paymentId: 'payment-1', reason: '用户撤销还款' })
  const failed = await repository.revokePayment({ paymentId: 'payment-2', reason: '用户撤销还款' })

  assert.deepEqual(accepted, { status: 'accepted', reason: 'revoked', cycle: null })
  assert.equal(failed.status, 'failed')
  assert.equal(failed.reason, 'service_error')
  assert.equal(failed.error, '撤销失败')
  assert.deepEqual(calls[0], {
    name: 'revoke_liability_payment',
    params: { p_payment_id: 'payment-1', p_reason: '用户撤销还款' },
  })
})

test('PWA-064B invalid canonical responses are not reported as accepted', async () => {
  const { client } = createRpcClient({
    set_repayment_cycle_paid_amount: { data: null, error: null },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.confirmRepayment({ cycleId: 'cycle-1', paidAmount: 40 })

  assert.equal(result.status, 'failed')
  assert.equal(result.reason, 'invalid_response')
  assert.equal(result.cycle, null)
})

test('PWA-067C screenshot confirmation owns RPC params and returns canonical cycle', async () => {
  const { client, calls } = createRpcClient({
    confirm_staging_repayment: { data: cycleRow, error: null },
  })
  const repository = createAccountRepository({ client })
  const result = await repository.confirmStagingRepayment({
    stagingId: 'staging-1', cycleId: 'cycle-1', paidAmount: 40,
    paidAt: '2026-08-16T08:00:00Z', debitAccountId: 'debit-1', note: '截图确认',
    userId: 'must-not-cross', status: 'paid',
  })
  assert.equal(result.status, 'accepted')
  assert.equal(result.cycle.id, 'cycle-1')
  assert.deepEqual(calls[0], {
    name: 'confirm_staging_repayment',
    params: {
      p_staging_id: 'staging-1', p_cycle_id: 'cycle-1', p_paid_amount: 40,
      p_paid_at: '2026-08-16T08:00:00Z', p_debit_account_id: 'debit-1',
      p_status: null, p_note: '截图确认',
    },
  })
  assert.equal(Object.hasOwn(calls[0].params, 'user_id'), false)
})

test('PWA-065A account list transport maps rows without a user filter', async () => {
  const { client, calls } = createReadClient({
    accounts: {
      data: [{
        id: 'account-1',
        user_id: 'user-1',
        name: '微信钱包',
        type: 'wallet_balance',
        current_balance: '120.50',
        initial_balance: '100.00',
        sort_order: 2,
      }],
      error: null,
    },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.listAccounts()

  assert.equal(result.status, 'accepted')
  assert.equal(result.rows[0].id, 'account-1')
  assert.equal(result.rows[0].currentBalance, 120.5)
  assert.ok(calls.some(call => call.table === 'accounts' && call.method === 'order' && call.column === 'sort_order'))
  assert.equal(calls.some(call => call.column === 'user_id'), false)
})

test('PWA-065A account list preserves transport failure instead of accepted empty rows', async () => {
  const { client } = createReadClient({
    accounts: { data: null, error: { message: '账户列表读取失败' } },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.listAccounts()

  assert.deepEqual(result, {
    status: 'failed',
    reason: 'service_error',
    rows: [],
    error: '账户列表读取失败',
  })
})

test('PWA-065B detail transports map sections and keep ensure separate from cycle reads', async () => {
  const { client, calls } = createReadClient({
    account_entries: {
      data: [{
        id: 'entry-1',
        account_id: 'account-1',
        direction: 'in',
        amount: '20.50',
        entry_type: 'income',
        occurred_at: '2026-08-16T08:00:00Z',
      }],
      error: null,
    },
    liability_payments: {
      data: [{
        id: 'payment-1',
        account_id: 'account-1',
        statement_id: 'cycle-1',
        amount: '40.00',
        paid_at: '2026-08-16T08:00:00Z',
        status: 'confirmed',
      }],
      error: null,
    },
    account_repayment_cycles: { data: [cycleRow], error: null },
    ensure_liability_repayment_cycles: { data: null, error: null },
  })
  const repository = createAccountRepository({ client })

  const entries = await repository.listAccountEntries({ accountId: 'account-1', limit: 50 })
  const payments = await repository.listAccountPayments({ accountId: 'account-1', limit: 30 })
  const cycles = await repository.listRepaymentCycles({ accountId: 'account-1', limit: 80 })
  const ensured = await repository.ensureRepaymentCycles({ cycleMonth: '2026-08' })

  assert.equal(entries.rows[0].amount, 20.5)
  assert.equal(entries.rows[0].entryType, 'income')
  assert.equal(payments.rows[0].statementId, 'cycle-1')
  assert.equal(cycles.rows[0].remainingAmount, 60)
  assert.deepEqual(ensured, { status: 'accepted', reason: 'ensured' })
  assert.ok(calls.some(call => call.table === 'account_entries' && call.method === 'eq' && call.value === 'account-1'))
  assert.ok(calls.some(call => call.table === 'liability_payments' && call.method === 'limit' && call.value === 30))
  assert.ok(calls.some(call => call.table === 'account_repayment_cycles' && call.method === 'eq' && call.value === 'account-1'))
  assert.deepEqual(calls.find(call => call.name === 'ensure_liability_repayment_cycles'), {
    name: 'ensure_liability_repayment_cycles',
    method: 'rpc',
    params: { p_cycle_month: '2026-08' },
  })
})

test('PWA-065B missing payment table stays distinguishable from an empty result', async () => {
  const { client } = createReadClient({
    liability_payments: {
      data: null,
      error: { code: 'PGRST205', message: "Could not find the table 'liability_payments'" },
    },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.listAccountPayments({ accountId: 'account-1' })

  assert.equal(result.status, 'unavailable')
  assert.equal(result.reason, 'not_available')
  assert.deepEqual(result.rows, [])
})

test('PWA-066C account writes use canonical RPC params without user or archive fields', async () => {
  const accountRow = {
    id: 'account-1', user_id: 'user-1', name: '微信钱包', type: 'wallet_balance',
    current_balance: '120.50', initial_balance: '100.00', is_archived: false,
  }
  const { client, calls } = createRpcClient({
    save_account: { data: accountRow, error: null },
    set_account_archived: { data: accountRow, error: null },
  })
  const repository = createAccountRepository({ client })

  const saved = await repository.saveAccount({
    name: '微信钱包', type: 'wallet_balance', accountId: 'account-1', initialBalance: 999,
    institution: '微信', last4: '1234', billDay: null, paymentDueDay: null,
    autoDebitAccountId: null, autoConfirmRepayment: false,
    isDefaultExpense: true, isDefaultIncome: false, isArchived: true, userId: 'must-not-cross',
  })
  const archived = await repository.setAccountArchived({ accountId: 'account-1', archived: true, userId: 'must-not-cross' })

  assert.equal(saved.status, 'accepted')
  assert.equal(saved.account.id, 'account-1')
  assert.equal(archived.status, 'accepted')
  assert.deepEqual(calls, [
    {
      name: 'save_account',
      params: {
        p_name: '微信钱包', p_type: 'wallet_balance', p_account_id: 'account-1',
        p_institution: '微信', p_last4: '1234', p_initial_balance: 999,
        p_bill_day: null, p_payment_due_day: null, p_auto_debit_account_id: null,
        p_auto_confirm_repayment: false, p_is_default_expense: true, p_is_default_income: false,
      },
    },
    { name: 'set_account_archived', params: { p_account_id: 'account-1', p_archived: true } },
  ])
})

test('PWA-066C account writes map stable database reasons and reject empty canonical responses', async () => {
  const { client } = createRpcClient({
    save_account: [
      { data: null, error: { message: 'account_type_transition_blocked' } },
      { data: null, error: null },
      { data: null, error: { message: 'network down' } },
    ],
    set_account_archived: { data: null, error: { message: 'invalid_auto_debit_account' } },
  })
  const repository = createAccountRepository({ client })

  assert.equal((await repository.saveAccount({ name: 'a', type: 'cash' })).reason, 'account_type_transition_blocked')
  assert.equal((await repository.saveAccount({ name: 'a', type: 'cash' })).reason, 'invalid_response')
  assert.equal((await repository.saveAccount({ name: 'a', type: 'cash' })).reason, 'service_error')
  assert.equal((await repository.setAccountArchived({ accountId: 'a', archived: true })).reason, 'invalid_auto_debit_account')
})
