import test from 'node:test'
import assert from 'node:assert/strict'
import { createRecordRepository } from '../recordRepository.js'

function createReadClient(responseQueues = {}) {
  const calls = []
  const queues = Object.fromEntries(
    Object.entries(responseQueues).map(([table, responses]) => [
      table,
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
          is(column, value) {
            calls.push({ table, method: 'is', column, value })
            return query
          },
          or(filter) {
            calls.push({ table, method: 'or', filter })
            return query
          },
          order(column, options) {
            calls.push({ table, method: 'order', column, options })
            return query
          },
          limit(value) {
            calls.push({ table, method: 'limit', value })
            return query
          },
          maybeSingle() {
            calls.push({ table, method: 'maybeSingle' })
            return Promise.resolve(response)
          },
          then(resolve, reject) {
            return Promise.resolve(response).then(resolve, reject)
          },
        }
        return query
      },
    },
  }
}

function createWriteClient(responseQueues = {}) {
  const calls = []
  const queues = Object.fromEntries(
    Object.entries(responseQueues).map(([rpc, responses]) => [
      rpc,
      Array.isArray(responses) ? [...responses] : [responses],
    ]),
  )

  return {
    calls,
    client: {
      from() {
        throw new Error('write test must not query a table')
      },
      async rpc(name, params) {
        calls.push({ name, params })
        return queues[name]?.shift() || { data: null, error: { message: `missing response for ${name}` } }
      },
    },
  }
}

test('PWA-052 repository owns monthly and pending expense queries without user_id', async () => {
  const { client, calls } = createReadClient({
    transactions: [
      { data: [{ id: 'expense-1', amount: 12.5, merchant_name: '午餐', transaction_date: '2026-08-16', status: 'done', type: 'expense' }], error: null },
      { data: [{ id: 'pending-1', amount: 8, merchant_name: '待补全', transaction_date: '2026-08-15', status: 'pending', type: 'expense' }], error: null },
    ],
  })
  const repository = createRecordRepository({ client })

  const monthly = await repository.listExpenses({ start: '2026-08-01', end: '2026-08-31' })
  const pending = await repository.listPendingExpenses({ limit: 25 })

  assert.equal(monthly.status, 'accepted')
  assert.equal(monthly.rows[0].id, 'expense-1')
  assert.equal(monthly.rows[0].name, '午餐')
  assert.equal(pending.status, 'accepted')
  assert.equal(pending.rows[0].status, 'pending')
  assert.ok(calls.some(call => call.table === 'transactions' && call.method === 'or' && call.filter.includes('transaction_date.gte.2026-08-01')))
  assert.ok(calls.some(call => call.table === 'transactions' && call.method === 'eq' && call.column === 'status' && call.value === 'pending'))
  assert.ok(calls.some(call => call.table === 'transactions' && call.method === 'limit' && call.value === 25))
  assert.equal(calls.some(call => call.column === 'user_id' || String(call.filter || '').includes('user_id')), false)
})

test('PWA-053 repository maps monthly and recent income and preserves read failures', async () => {
  const { client, calls } = createReadClient({
    income_records: [
      { data: [{ id: 'income-1', category: 'salary', source_name: '工资', amount: '4620', income_date: '2026-08-10', occurred_at: '2026-08-10T01:30:00Z' }], error: null },
      { data: [], error: { message: 'recent income failed' } },
    ],
  })
  const repository = createRecordRepository({ client })

  const monthly = await repository.listIncomes({ start: '2026-08-01', end: '2026-08-31' })
  const recent = await repository.listRecentIncomes({ limit: 10 })

  assert.equal(monthly.status, 'accepted')
  assert.equal(monthly.rows[0].source, '工资')
  assert.equal(monthly.rows[0].amount, 4620)
  assert.equal(monthly.rows[0].dateRaw, '2026-08-10')
  assert.equal(recent.status, 'failed')
  assert.equal(recent.error, 'recent income failed')
  assert.deepEqual(recent.rows, [])
  assert.ok(calls.some(call => call.table === 'income_records' && call.method === 'limit' && call.value === 10))
})

test('PWA-054 repository keeps Shanghai occurrence and created_at fallback for universal records', async () => {
  const { client, calls } = createReadClient({
    data_records: {
      data: [{
        id: 'data-1',
        domain_id: 'domain-1',
        domain_key: 'wallet',
        domain_version: '1.0',
        occurred_at: null,
        created_at: '2026-08-11T03:00:00Z',
        title: '微信钱包',
        payload_jsonb: { snapshot_balance: 100 },
        linked_account_id: 'account-1',
        snapshot_balance: 120,
      }],
      error: null,
    },
  })
  const repository = createRecordRepository({ client })

  const result = await repository.listUniversalRecords({
    start: '2026-08-01',
    end: '2026-08-31',
    limit: 120,
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.rows[0].domainKey, 'wallet')
  assert.equal(result.rows[0].payload.linked_account_id, 'account-1')
  assert.equal(result.rows[0].payload.snapshot_balance, 120)
  const rangeCall = calls.find(call => call.table === 'data_records' && call.method === 'or')
  assert.match(rangeCall.filter, /occurred_at\.gte\.2026-07-31T16:00:00\.000Z/)
  assert.match(rangeCall.filter, /occurred_at\.is\.null,created_at\.gte\./)
  assert.ok(calls.some(call => call.table === 'data_records' && call.method === 'limit' && call.value === 120))
})

test('PWA-055 unbound reads reuse record DTOs and do not own account rules', async () => {
  const { client, calls } = createReadClient({
    transactions: { data: [{ id: 'expense-unbound', amount: 20, merchant_name: '晚餐', transaction_date: '2026-08-12', status: 'done', type: 'expense' }], error: null },
    income_records: { data: [{ id: 'income-unbound', amount: 100, source_name: '报销', income_date: '2026-08-12', category: 'reimbursement' }], error: null },
  })
  const repository = createRecordRepository({ client })

  const result = await repository.listUnboundRecords({
    start: '2026-08-01',
    end: '2026-08-31',
    limit: 100,
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.expenses[0].name, '晚餐')
  assert.equal(result.incomes[0].source, '报销')
  assert.equal(calls.filter(call => call.method === 'is' && call.column === 'account_id' && call.value === null).length, 2)
  assert.equal(calls.some(call => /recommend|balance|account_entries/i.test(JSON.stringify(call))), false)
})

test('PWA-052 repository returns structured failure instead of accepted empty rows', async () => {
  const { client } = createReadClient({ transactions: { data: null, error: { message: 'expense read failed' } } })
  const repository = createRecordRepository({ client })

  const result = await repository.listExpenses({ start: '2026-08-01', end: '2026-08-31' })

  assert.equal(result.status, 'failed')
  assert.equal(result.reason, 'service_error')
  assert.equal(result.error, 'expense read failed')
  assert.deepEqual(result.rows, [])
})

test('PWA-056E getRecordByTarget reads only the table selected by target kind', async () => {
  const { client, calls } = createReadClient({
    transactions: {
      data: {
        id: 'expense-1',
        amount: 12.5,
        merchant_name: '午餐',
        transaction_date: '2026-08-16',
        status: 'done',
        type: 'expense',
      },
      error: null,
    },
  })
  const repository = createRecordRepository({ client })

  const result = await repository.getRecordByTarget({
    targetKind: 'expense',
    targetRecordId: 'expense-1',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'loaded')
  assert.equal(result.kind, 'expense')
  assert.equal(result.record.id, 'expense-1')
  assert.deepEqual(calls.filter(call => call.method === 'maybeSingle'), [
    { table: 'transactions', method: 'maybeSingle' },
  ])
  assert.equal(calls.some(call => ['income_records', 'data_records'].includes(call.table)), false)
})

test('PWA-056E unknown or invalid target cannot trigger a formal record request', async () => {
  const { client, calls } = createReadClient()
  const repository = createRecordRepository({ client })

  for (const targetKind of [null, '', 'wallet', 'unknown']) {
    const result = await repository.getRecordByTarget({
      targetKind,
      targetRecordId: 'target-1',
    })
    assert.equal(result.status, 'rejected')
    assert.equal(result.reason, 'invalid_target')
  }
  const missingId = await repository.getRecordByTarget({
    targetKind: 'income',
    targetRecordId: '',
  })
  assert.equal(missingId.status, 'rejected')
  assert.equal(missingId.reason, 'invalid_target')
  assert.equal(calls.length, 0)
})

test('PWA-056E single-target reads preserve not-found and service failures', async () => {
  const { client, calls } = createReadClient({
    data_records: { data: null, error: null },
    income_records: { data: null, error: { message: 'income read failed' } },
  })
  const repository = createRecordRepository({ client })

  const missing = await repository.getRecordByTarget({
    targetKind: 'data',
    targetRecordId: 'data-missing',
  })
  const failed = await repository.getRecordByTarget({
    targetKind: 'income',
    targetRecordId: 'income-1',
  })

  assert.deepEqual(missing, {
    status: 'accepted',
    reason: 'not_found',
    kind: 'data',
    record: null,
  })
  assert.equal(failed.status, 'failed')
  assert.equal(failed.reason, 'service_error')
  assert.equal(failed.error, 'income read failed')
  assert.deepEqual(calls.filter(call => call.method === 'maybeSingle'), [
    { table: 'data_records', method: 'maybeSingle' },
    { table: 'income_records', method: 'maybeSingle' },
  ])
})

test('PWA-058 expense saves use the canonical RPC and map its returned row', async () => {
  const { client, calls } = createWriteClient({
    save_transaction_with_account: {
      data: {
        id: 'expense-save-1',
        amount: '28.5',
        merchant_name: '晚餐',
        platform: '微信',
        category: '餐饮',
        payment_method: '微信支付',
        transaction_date: '2026-08-16',
        transaction_time: '19:30:00',
        occurred_at: '2026-08-16T11:30:00Z',
        status: 'done',
        type: 'expense',
        account_id: 'account-1',
      },
      error: null,
    },
  })
  const repository = createRecordRepository({ client })

  const result = await repository.saveExpense({
    id: null,
    amount: 28.5,
    merchantName: '晚餐',
    platform: '微信',
    category: '餐饮',
    paymentMethod: '微信支付',
    transactionDate: '2026-08-16',
    transactionTime: '19:30:00',
    occurredAt: '2026-08-16T11:30:00Z',
    note: null,
    isLargeTransport: false,
    transportType: null,
    source: 'manual',
    imageUrl: null,
    imageHash: null,
    companionMessage: null,
    accountId: 'account-1',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'saved')
  assert.equal(result.kind, 'expense')
  assert.equal(result.record.id, 'expense-save-1')
  assert.equal(result.record.accountId, 'account-1')
  assert.equal(result.record.occurredAt, '2026-08-16T11:30:00Z')
  assert.deepEqual(calls, [{
    name: 'save_transaction_with_account',
    params: {
      p_id: null,
      p_amount: 28.5,
      p_merchant_name: '晚餐',
      p_platform: '微信',
      p_category: '餐饮',
      p_payment_method: '微信支付',
      p_transaction_date: '2026-08-16',
      p_transaction_time: '19:30:00',
      p_occurred_at: '2026-08-16T11:30:00Z',
      p_note: null,
      p_is_large_transport: false,
      p_transport_type: null,
      p_source: 'manual',
      p_image_url: null,
      p_image_hash: null,
      p_companion_message: null,
      p_account_id: 'account-1',
    },
  }])
  assert.equal(Object.hasOwn(calls[0].params, 'user_id'), false)
})

test('PWA-058 income saves map canonical rows and preserve service failures', async () => {
  const { client, calls } = createWriteClient({
    save_income_with_account: [
      {
        data: {
          id: 'income-save-1',
          category: 'salary',
          source_name: '工资',
          amount: '4620',
          income_date: '2026-08-16',
          occurred_at: '2026-08-15T16:00:00Z',
          account_id: 'account-2',
        },
        error: null,
      },
      { data: null, error: { message: 'income save failed' } },
    ],
  })
  const repository = createRecordRepository({ client })
  const input = {
    id: 'income-existing',
    category: 'salary',
    sourceName: '工资',
    amount: 4620,
    incomeDate: '2026-08-16',
    occurredAt: '2026-08-15T16:00:00Z',
    note: null,
    source: null,
    imageUrl: null,
    imageHash: null,
    companionMessage: null,
    accountId: 'account-2',
  }

  const accepted = await repository.saveIncome(input)
  const failed = await repository.saveIncome(input)

  assert.equal(accepted.status, 'accepted')
  assert.equal(accepted.kind, 'income')
  assert.equal(accepted.record.id, 'income-save-1')
  assert.equal(accepted.record.accountId, 'account-2')
  assert.equal(failed.status, 'failed')
  assert.equal(failed.reason, 'service_error')
  assert.equal(failed.error, 'income save failed')
  assert.equal(failed.record, null)
  assert.deepEqual(calls[0], {
    name: 'save_income_with_account',
    params: {
      p_id: 'income-existing',
      p_category: 'salary',
      p_source_name: '工资',
      p_amount: 4620,
      p_income_date: '2026-08-16',
      p_occurred_at: '2026-08-15T16:00:00Z',
      p_note: null,
      p_source: null,
      p_image_url: null,
      p_image_hash: null,
      p_companion_message: null,
      p_account_id: 'account-2',
    },
  })
})
