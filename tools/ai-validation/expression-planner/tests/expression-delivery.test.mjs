import test from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const entryPoint = path.join(root, 'supabase/functions/ingest-receipt/expression-delivery.ts')
const userId = '11111111-1111-4111-8111-111111111111'

async function loadModule(environment = {}) {
  globalThis.Deno = { env: { get: key => environment[key] } }
  const bundle = await build({
    absWorkingDir: root,
    entryPoints: [entryPoint],
    bundle: true,
    platform: 'node',
    format: 'esm',
    write: false,
  })
  const url = `data:text/javascript;base64,${Buffer.from(bundle.outputFiles[0].text).toString('base64')}#${Math.random()}`
  return import(url)
}

function compare(left, operator, right) {
  if (operator === 'eq') return left === right
  if (operator === 'in') return right.includes(left)
  if (left === null || left === undefined) return false
  if (operator === 'lte') return String(left) <= String(right)
  if (operator === 'gt') return String(left) > String(right)
  return true
}

function createQuery(table, state) {
  const filters = []
  const orders = []
  let limit = Number.POSITIVE_INFINITY
  let inserted = null

  function rows() {
    const source = state.tables[table] ?? []
    const filtered = source.filter(row => filters.every(filter => (
      compare(row[filter.column], filter.operator, filter.value)
    )))
    filtered.sort((left, right) => {
      for (const order of orders) {
        const comparison = String(left[order.column] ?? '').localeCompare(String(right[order.column] ?? ''))
        if (comparison !== 0) return order.ascending ? comparison : -comparison
      }
      return 0
    })
    return filtered.slice(0, limit)
  }

  const query = {
    select() { return this },
    insert(value) {
      inserted = value
      return this
    },
    eq(column, value) {
      filters.push({ column, operator: 'eq', value })
      return this
    },
    in(column, value) {
      filters.push({ column, operator: 'in', value })
      return this
    },
    lte(column, value) {
      filters.push({ column, operator: 'lte', value })
      return this
    },
    gt(column, value) {
      filters.push({ column, operator: 'gt', value })
      return this
    },
    order(column, options = {}) {
      orders.push({ column, ascending: options.ascending !== false })
      return this
    },
    limit(value) {
      limit = value
      return this
    },
    async maybeSingle() {
      if (inserted) {
        const row = {
          id: `snapshot-${state.tables.expression_delivery_snapshots.length + 1}`,
          created_at: new Date().toISOString(),
          ...structuredClone(inserted),
        }
        state.tables.expression_delivery_snapshots.push(row)
        return { data: row, error: null }
      }
      return { data: rows()[0] ?? null, error: null }
    },
    then(resolve, reject) {
      return Promise.resolve({ data: rows(), error: null }).then(resolve, reject)
    },
  }
  return query
}

function database(seed = {}) {
  const state = {
    tables: {
      transactions: [],
      income_records: [],
      data_records: [],
      expression_preference_revisions: [],
      expression_preference_snapshots: [],
      expression_exposure_events: [],
      expression_delivery_snapshots: [],
      ...structuredClone(seed),
    },
    exposureSources: [],
    rpcCalls: [],
    shadowReads: 0,
  }
  const client = {
    from(table) {
      if (table === 'expression_shadow_runs') {
        state.shadowReads += 1
        throw new Error('record-detail delivery must not read Expression Shadow')
      }
      if (!(table in state.tables)) throw new Error(`Unexpected table: ${table}`)
      return createQuery(table, state)
    },
    async rpc(name, params) {
      state.rpcCalls.push({ name, params })
      if (name !== 'persist_expression_exposure_with_sources') {
        throw new Error(`Unexpected RPC: ${name}`)
      }
      const existing = state.tables.expression_exposure_events.find(row => row.event_key === params.p_event_key)
      if (existing) return { data: { exposure: existing, created: false }, error: null }
      const exposure = {
        id: `exposure-${state.tables.expression_exposure_events.length + 1}`,
        created_at: new Date().toISOString(),
        ...structuredClone(params.p_exposure),
      }
      state.tables.expression_exposure_events.push(exposure)
      state.exposureSources.push(...structuredClone(params.p_sources))
      return { data: { exposure, created: true }, error: null }
    },
  }
  return { client, state }
}

function dataRecord(id, domainKey, payload, occurredAt = '2026-07-25T08:00:00+08:00') {
  return {
    id,
    user_id: userId,
    occurred_at: occurredAt,
    title: `${domainKey} record`,
    summary: null,
    payload_jsonb: payload,
    domain_key: domainKey,
    linked_account_id: payload.linked_account_id ?? null,
    account_snapshot_kind: payload.account_snapshot_kind ?? null,
    snapshot_balance: payload.snapshot_balance ?? null,
    snapshot_at: payload.snapshot_at ?? null,
  }
}

const supportedCases = [
  {
    name: 'expense',
    kind: 'expense',
    recordId: '10000000-0000-4000-8000-000000000002',
    seed: {
      transactions: [
        {
          id: '10000000-0000-4000-8000-000000000001', user_id: userId, type: 'expense',
          transaction_date: '2026-07-24', transaction_time: '08:00:00', created_at: '2026-07-24T08:01:00+08:00',
          amount: 18, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
        },
        {
          id: '10000000-0000-4000-8000-000000000002', user_id: userId, type: 'expense',
          transaction_date: '2026-07-25', transaction_time: '08:30:00', created_at: '2026-07-25T08:31:00+08:00',
          amount: 20, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
        },
      ],
    },
  },
  {
    name: 'income',
    kind: 'income',
    recordId: '20000000-0000-4000-8000-000000000001',
    seed: { income_records: [{
      id: '20000000-0000-4000-8000-000000000001', user_id: userId,
      income_date: '2026-07-25', created_at: '2026-07-25T09:00:00+08:00', amount: 3200,
      source_name: '项目收入', category: '项目',
    }] },
  },
  {
    name: 'sleep',
    kind: 'data',
    recordId: '30000000-0000-4000-8000-000000000001',
    seed: { data_records: [dataRecord('30000000-0000-4000-8000-000000000001', 'sleep', {
      sleep_hours: 7.5, quality_score: 82,
      sleep_start_at: '2026-07-24T23:30:00+08:00', wake_at: '2026-07-25T07:00:00+08:00',
    })] },
  },
  {
    name: 'sport',
    kind: 'data',
    recordId: '40000000-0000-4000-8000-000000000001',
    seed: { data_records: [dataRecord('40000000-0000-4000-8000-000000000001', 'sport', { duration_min: 42 })] },
  },
  {
    name: 'food',
    kind: 'data',
    recordId: '50000000-0000-4000-8000-000000000001',
    seed: { data_records: [dataRecord('50000000-0000-4000-8000-000000000001', 'food', {
      total_calorie_kcal: 630, meal_type: 'dinner', dishes: [{ name: '番茄牛肉' }],
    })] },
  },
  {
    name: 'reading',
    kind: 'data',
    recordId: '60000000-0000-4000-8000-000000000001',
    seed: { data_records: [dataRecord('60000000-0000-4000-8000-000000000001', 'reading', { reading_minutes: 35 })] },
  },
  {
    name: 'wallet',
    kind: 'data',
    recordId: '70000000-0000-4000-8000-000000000001',
    seed: { data_records: [dataRecord('70000000-0000-4000-8000-000000000001', 'wallet', {
      snapshot_balance: 2860, account_snapshot_kind: 'asset', linked_account_id: 'account-1',
      account_name: '招商银行', snapshot_at: '2026-07-25T08:00:00+08:00',
    })] },
  },
]

test('record detail builds reliable feedback for every supported domain without Shadow or improvement opt-in', async () => {
  const module = await loadModule({ EXPRESSION_PLANNER_MODE: 'off' })
  for (const item of supportedCases) {
    const { client, state } = database(item.seed)
    const preview = await module.getRecordExpressionPlan(client, userId, {
      record_id: item.recordId,
      record_kind: item.kind,
    })
    assert.equal(preview.available, true, `${item.name}: ${JSON.stringify(preview)}`)
    assert.equal(preview.record_kind, item.kind)
    assert.equal(preview.feedback.source, 'expression_planner')
    assert.ok(preview.feedback.emotion_line, item.name)
    assert.equal(state.shadowReads, 0)
    assert.equal(state.tables.expression_delivery_snapshots.length, 1)
    const snapshot = state.tables.expression_delivery_snapshots[0]
    assert.equal(snapshot.shadow_run_id, null)
    assert.equal(snapshot.record_kind, item.kind)
    assert.ok(Date.parse(snapshot.expires_at) > Date.now())
    assert.equal('source_record' in snapshot.delivery_plan, false)
    assert.equal('structured_value' in snapshot.delivery_plan.candidates[0].claim, false)
  }
})

test('acknowledgement persists one idempotent core-product exposure', async () => {
  const module = await loadModule({ EXPRESSION_PLANNER_MODE: 'off' })
  const item = supportedCases.find(entry => entry.name === 'sleep')
  const { client, state } = database(item.seed)
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })

  const acknowledged = await module.acknowledgeRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })
  const repeated = await module.acknowledgeRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })

  assert.equal(acknowledged.exposure_event_id, repeated.exposure_event_id)
  assert.equal(state.tables.expression_exposure_events.length, 1)
  assert.equal(state.tables.expression_exposure_events[0].metadata.source, 'shared_expression_planner')
  assert.equal(state.tables.expression_exposure_events[0].surface, 'record_detail')
  assert.equal(state.exposureSources.some(source => source.is_primary === true), true)
})

test('editing a source record after preview invalidates the frozen delivery', async () => {
  const module = await loadModule()
  const item = supportedCases.find(entry => entry.name === 'reading')
  const { client, state } = database(item.seed)
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })
  state.tables.data_records[0].payload_jsonb.reading_minutes = 55

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: item.recordId,
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /plan_dependency_stale/,
  )
  assert.equal(state.tables.expression_exposure_events.length, 0)
})

test('expired delivery snapshots cannot be acknowledged', async () => {
  const module = await loadModule()
  const item = supportedCases.find(entry => entry.name === 'sport')
  const { client, state } = database(item.seed)
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })
  state.tables.expression_delivery_snapshots[0].expires_at = '2000-01-01T00:00:00.000Z'

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: item.recordId,
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /不存在或已失效/,
  )
})

test('low-information and missing records return explicit non-error reasons', async () => {
  const module = await loadModule()
  const sparseId = '80000000-0000-4000-8000-000000000001'
  const { client } = database({
    data_records: [dataRecord(sparseId, 'custom_domain', { note: '只有一段文字' })],
  })

  const sparse = await module.getRecordExpressionPlan(client, userId, {
    record_id: sparseId,
    record_kind: 'data',
  })
  const missing = await module.getRecordExpressionPlan(client, userId, {
    record_id: '90000000-0000-4000-8000-000000000001',
    record_kind: 'data',
  })

  assert.deepEqual(sparse, { available: false, reason: 'no_selected_candidate' })
  assert.deepEqual(missing, { available: false, reason: 'record_missing' })
})

test('record kind is required and prevents cross-table record guessing', async () => {
  const module = await loadModule()
  const item = supportedCases.find(entry => entry.name === 'income')
  const { client } = database(item.seed)

  await assert.rejects(
    module.getRecordExpressionPlan(client, userId, { record_id: item.recordId }),
    /记录编号或类型/,
  )
  const wrongKind = await module.getRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    record_kind: 'expense',
  })
  assert.deepEqual(wrongKind, { available: false, reason: 'record_missing' })
})
