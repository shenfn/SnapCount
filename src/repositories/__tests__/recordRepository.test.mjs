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
          then(resolve, reject) {
            return Promise.resolve(response).then(resolve, reject)
          },
        }
        return query
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
