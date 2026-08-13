import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const entryPoint = path.join(root, 'supabase/functions/ingest-receipt/expression-delivery.ts')
const ingestEntryPoint = path.join(root, 'supabase/functions/ingest-receipt/index.ts')
const userId = '11111111-1111-4111-8111-111111111111'

async function loadModule(environment = {}) {
  const resolvedEnvironment = {
    EXPRESSION_PLANNER_OWNER_ENABLED: 'true',
    EXPRESSION_PLANNER_OWNER_USER_ID: userId,
    ...environment,
  }
  globalThis.Deno = { env: { get: key => resolvedEnvironment[key] } }
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

async function loadIngestFeedbackModule() {
  const source = await readFile(ingestEntryPoint, 'utf8')
  const serverStart = source.indexOf('Deno.serve(async (req) => {')
  assert.ok(serverStart > 0, 'Edge request handler boundary must remain discoverable')
  const testableSource = `${source.slice(0, serverStart)}\nexport { generateVoiceFeedback, regenerateFeedbackWithSecondCall };\n`
  const bundle = await build({
    absWorkingDir: root,
    stdin: {
      contents: testableSource,
      resolveDir: path.dirname(ingestEntryPoint),
      sourcefile: ingestEntryPoint,
      loader: 'ts',
    },
    bundle: true,
    platform: 'node',
    format: 'esm',
    write: false,
    plugins: [{
      name: 'stub-deno-npm-imports',
      setup(buildContext) {
        buildContext.onResolve({ filter: /^npm:/ }, args => ({
          path: args.path,
          namespace: 'deno-npm-stub',
          sideEffects: false,
        }))
        buildContext.onLoad({ filter: /.*/, namespace: 'deno-npm-stub' }, () => ({
          contents: 'export const createClient = () => null; export const decode = () => null; export default {};',
          loader: 'js',
        }))
      },
    }],
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
  let rangeStart = 0
  let rangeEnd = Number.POSITIVE_INFINITY
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
    const upper = Math.min(filtered.length, rangeEnd + 1, rangeStart + limit)
    return filtered.slice(rangeStart, upper)
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
    range(from, to) {
      rangeStart = from
      rangeEnd = to
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
      user_domain_profiles: [],
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

function plannerExposure(candidate, index) {
  const hints = candidate.selection_hints ?? {}
  const semanticKey = candidate.claim?.semantic_key
  const exposureKey = hints.exposure_key ?? semanticKey
  const dedupeKey = hints.dedupe_key ?? exposureKey
  return {
    id: `seed-exposure-${index}`,
    user_id: userId,
    semantic_key: semanticKey,
    occurred_at: `2026-07-25T07:5${index}:00+08:00`,
    metadata: {
      exposure_key: exposureKey,
      scoped_exposure_key: `record_detail:${exposureKey}`,
      dedupe_key: dedupeKey,
      scoped_dedupe_key: `record_detail:${dedupeKey}`,
    },
    selection_mode: 'threshold',
    lifecycle_state: 'client_rendered',
    simulation_only: false,
    counts_for_novelty: true,
    surface: 'record_detail',
  }
}

function expenseBaselineSeed() {
  return {
    transactions: [
      {
        id: '11000000-0000-4000-8000-000000000001', user_id: userId, type: 'expense',
        transaction_date: '2026-07-22', transaction_time: '08:00:00', created_at: '2026-07-22T08:01:00+08:00',
        amount: 12, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
      },
      {
        id: '11000000-0000-4000-8000-000000000002', user_id: userId, type: 'expense',
        transaction_date: '2026-07-23', transaction_time: '08:00:00', created_at: '2026-07-23T08:01:00+08:00',
        amount: 18, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
      },
      {
        id: '11000000-0000-4000-8000-000000000003', user_id: userId, type: 'expense',
        transaction_date: '2026-07-24', transaction_time: '08:00:00', created_at: '2026-07-24T08:01:00+08:00',
        amount: 24, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
      },
      {
        id: '11000000-0000-4000-8000-000000000004', user_id: userId, type: 'expense',
        transaction_date: '2026-07-25', transaction_time: '08:30:00', created_at: '2026-07-25T08:31:00+08:00',
        amount: 40, merchant_name: '便利店', category: 'shopping', platform: '线下', payment_method: '微信支付', status: 'confirmed',
      },
    ],
  }
}

function expenseNearBaselineSeed() {
  const seed = expenseBaselineSeed()
  const amounts = [100, 101, 99, 103.27]
  seed.transactions.forEach((transaction, index) => {
    transaction.amount = amounts[index]
  })
  return seed
}

async function previewPersonalBaseline(module, client, state) {
  const input = {
    record_id: '11000000-0000-4000-8000-000000000004',
    record_kind: 'expense',
  }
  const first = await module.getRecordExpressionPlan(client, userId, input)
  assert.equal(first.available, true)
  const firstCandidate = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.candidates[0]
  if (firstCandidate.claim.semantic_key === 'merchant_daily_vs_active_day_median') {
    return { preview: first, candidate: firstCandidate, input }
  }

  state.tables.expression_exposure_events.push(
    plannerExposure(firstCandidate, 1),
    plannerExposure(firstCandidate, 2),
  )
  const preview = await module.getRecordExpressionPlan(client, userId, input)
  assert.equal(preview.available, true)
  const candidate = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.candidates[0]
  assert.equal(candidate.claim.semantic_key, 'merchant_daily_vs_active_day_median')
  return { preview, candidate, input }
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

test('shortcut delivery consumes a planner candidate and persists one real exposure', async () => {
  const module = await loadModule()
  const currentId = '90000000-0000-4000-8000-000000000004'
  const transactions = [1, 2, 3, 4].map((index) => ({
    id: `90000000-0000-4000-8000-${String(index).padStart(12, '0')}`,
    user_id: userId,
    type: 'expense',
    transaction_date: '2026-07-25',
    transaction_time: `${String(8 + index).padStart(2, '0')}:00:00`,
    created_at: `2026-07-25T${String(8 + index).padStart(2, '0')}:01:00+08:00`,
    amount: 10,
    merchant_name: '便利店',
    category: 'shopping',
    platform: '线下',
    payment_method: '微信支付',
    status: 'done',
  }))
  const { client, state } = database({ transactions })
  const input = {
    record_id: currentId,
    record_kind: 'expense',
    occurred_at: '2026-07-25T12:00:00+08:00',
    delivery_attempt_id: 'shortcut-attempt-1',
  }

  const first = await module.deliverShortcutExpressionPlan(client, userId, input)
  const second = await module.deliverShortcutExpressionPlan(client, userId, input)

  assert.equal(first.available, true)
  assert.equal(first.semantic_key, 'merchant_daily_count_total')
  assert.match(first.message, /4 笔/)
  assert.equal(second.exposure_event_id, first.exposure_event_id)
  assert.equal(state.tables.expression_exposure_events.length, 1)
  assert.equal(state.tables.expression_exposure_events[0].surface, 'shortcut_notification')
  assert.equal(state.tables.expression_exposure_events[0].lifecycle_state, 'returned_to_shortcut')
  assert.notEqual(state.tables.expression_exposure_events[0].selection_mode, 'legacy_voice')
})

test('shortcut exposes the actual companion text when the covered claim is shortcut-eligible', async () => {
  const module = await loadModule()
  const currentId = '90500000-0000-4000-8000-000000000004'
  const transactions = [1, 2, 3, 4].map((index) => ({
    id: `90500000-0000-4000-8000-${String(index).padStart(12, '0')}`,
    user_id: userId,
    type: 'expense',
    transaction_date: '2026-07-25',
    transaction_time: `${String(8 + index).padStart(2, '0')}:00:00`,
    created_at: `2026-07-25T${String(8 + index).padStart(2, '0')}:01:00+08:00`,
    amount: 10,
    merchant_name: '便利店',
    category: 'shopping',
    platform: '线下',
    payment_method: '微信支付',
    status: 'done',
  }))
  const { client, state } = database({ transactions })
  const first = await module.deliverShortcutExpressionPlan(client, userId, {
    record_id: currentId,
    record_kind: 'expense',
    occurred_at: '2026-07-25T12:00:00+08:00',
    delivery_attempt_id: 'shortcut-discovery',
  })
  assert.equal(first.available, true)
  state.tables.expression_exposure_events.length = 0

  const visibleCompanion = first.message
  const current = state.tables.transactions.find(row => row.id === currentId)
  current.companion_message = visibleCompanion
  current.ai_feedback = {
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: first.semantic_key,
      expressed_semantic_keys: [first.semantic_key],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'shortcut-covered-packet',
      claim_fingerprint: first.claim_fingerprint,
      presentation_target: 'companion_message',
      rendered_text_fingerprint: module.expressionRenderedTextFingerprint(visibleCompanion),
    },
  }

  const delivered = await module.deliverShortcutExpressionPlan(client, userId, {
    record_id: currentId,
    record_kind: 'expense',
    occurred_at: '2026-07-25T12:00:00+08:00',
    delivery_attempt_id: 'shortcut-companion',
  })
  assert.equal(delivered.available, true)
  assert.equal(delivered.presentation_target, 'companion_message')
  assert.equal(delivered.semantic_key, first.semantic_key)
  assert.equal(delivered.message, visibleCompanion)
  assert.equal(state.tables.expression_exposure_events.length, 1)
  assert.deepEqual(state.tables.expression_exposure_events[0].rendered_payload, {
    companion_message: visibleCompanion,
  })
  assert.deepEqual(state.tables.expression_exposure_events[0].visible_field_paths, ['companion_message'])
  assert.equal(state.tables.expression_exposure_events[0].metadata.presentation_target, 'companion_message')
  assert.equal(
    state.tables.expression_exposure_events[0].metadata.rendered_text_fingerprint,
    delivered.rendered_text_fingerprint,
  )
})

test('pre-insert Voice brief becomes the same persisted companion delivery and is exposed only after ACK', async () => {
  const module = await loadModule()
  const realId = '91000000-0000-4000-8000-000000000002'
  const synthetic = {
    id: 'preinsert:voice-brief-1',
    type: 'expense',
    transaction_date: '2026-08-07',
    transaction_time: '12:10:00',
    created_at: '2026-08-07T12:11:00+08:00',
    amount: 6.28,
    merchant_name: '青禾茶饮',
    category: 'dining',
    platform: '外卖',
    payment_method: '微信支付',
    status: 'done',
  }
  const { client, state } = database({
    transactions: [{
      id: '91000000-0000-4000-8000-000000000001',
      user_id: userId,
      type: 'expense',
      transaction_date: '2026-08-06',
      transaction_time: '08:00:00',
      created_at: '2026-08-06T08:01:00+08:00',
      amount: 12,
      merchant_name: '便利店',
      category: 'shopping',
      platform: '线下',
      payment_method: '微信支付',
      status: 'done',
    }],
  })

  const brief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'expense',
    domain_key: 'expense',
    current_record: synthetic,
  })
  assert.equal(brief.semantic_key, 'expense_merchant_first_occurrence')
  assert.deepEqual(brief.count_numbers, [1])

  state.tables.transactions.push({ ...synthetic, id: realId, user_id: userId })
  const persisted = await module.getRecordExpressionPlan(client, userId, {
    record_id: realId,
    record_kind: 'expense',
  })
  assert.equal(persisted.available, true)
  assert.equal(persisted.feedback.semantic_key, brief.semantic_key)
  assert.match(
    persisted.feedback.detail_reason,
    /商户历史|当前记录/,
    'EXP-005 first-occurrence delivery must explain its deterministic evidence source',
  )
  assert.notEqual(persisted.candidate_id, brief.candidate_id)

  const visibleCompanion = '第一次记录「青禾茶饮」，这家外卖商户是芥子新见到的。'
  state.tables.transactions.at(-1).companion_message = visibleCompanion
  state.tables.transactions.at(-1).ai_feedback = {
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: brief.semantic_key,
      expressed_semantic_keys: [brief.semantic_key],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'fnv1a32:test-packet',
      claim_fingerprint: brief.claim_fingerprint,
      presentation_target: 'companion_message',
      rendered_text_fingerprint: module.expressionRenderedTextFingerprint(visibleCompanion),
    },
  }
  const composed = await module.getRecordExpressionPlan(client, userId, {
    record_id: realId,
    record_kind: 'expense',
  })
  assert.equal(composed.available, true)
  assert.equal(composed.feedback.semantic_key, brief.semantic_key)
  assert.equal(composed.presentation_target, 'companion_message')
  assert.equal(composed.feedback.emotion_line, visibleCompanion)
  assert.equal(state.tables.expression_exposure_events.length, 0)
  const decision = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.decision
  assert.equal(decision.action_set.some(action => action.semantic_key === brief.semantic_key), true)
  const ack = await module.acknowledgeRecordExpressionPlan(client, userId, {
    record_id: realId,
    plan_token: composed.plan_token,
    candidate_id: composed.candidate_id,
  })
  assert.equal(ack.presentation_target, 'companion_message')
  assert.equal(ack.feedback.emotion_line, visibleCompanion)
  assert.equal(ack.feedback.detail_reason, composed.feedback.detail_reason)
  assert.equal(state.tables.expression_exposure_events.length, 1)
  assert.deepEqual(state.tables.expression_exposure_events[0].rendered_payload, {
    companion_message: visibleCompanion,
  })
  assert.deepEqual(state.tables.expression_exposure_events[0].visible_field_paths, ['companion_message'])
  assert.equal(state.tables.expression_exposure_events[0].metadata.presentation_target, 'companion_message')
  assert.equal(
    state.tables.expression_exposure_events[0].metadata.rendered_text_fingerprint,
    composed.rendered_text_fingerprint,
  )
})

test('coverage fails open when its contract or Planner version is stale', async () => {
  const module = await loadModule()
  const valid = {
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: 'expense_merchant_first_occurrence',
      expressed_semantic_keys: ['expense_merchant_first_occurrence'],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'fnv1a32:valid',
      claim_fingerprint: 'fnv1a64:valid',
      presentation_target: 'companion_message',
      rendered_text_fingerprint: 'fnv1a64:valid-text',
    },
  }

  assert.deepEqual(module.expressedSemanticKeysFromFeedback(valid), ['expense_merchant_first_occurrence'])
  assert.deepEqual(module.expressedSemanticKeysFromFeedback({
    expression_coverage: { ...valid.expression_coverage, planner_version: 'expression-shadow-auto-v0.5' },
  }), [])
  assert.deepEqual(module.expressedSemanticKeysFromFeedback({
    expression_coverage: { ...valid.expression_coverage, packet_fingerprint: '' },
  }), [])
})

test('coverage fails open when the same semantic key belongs to an edited claim', async () => {
  const module = await loadModule()
  const { client, state } = database()
  const oldBrief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'expense',
    domain_key: 'expense',
    current_record: {
      id: 'preinsert:old-merchant', type: 'expense', transaction_date: '2026-08-07',
      transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00', amount: 6.28,
      merchant_name: '旧商户', category: 'food', platform: '外卖', payment_method: '支付宝', status: 'done',
    },
  })
  assert.equal(oldBrief.semantic_key, 'expense_merchant_first_occurrence')

  const staleCompanion = '第一次记录旧商户，芥子先把它记下来。'
  state.tables.transactions.push({
    id: '92000000-0000-4000-8000-000000000001', user_id: userId, type: 'expense',
    transaction_date: '2026-08-07', transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00',
    amount: 6.28, merchant_name: '新商户', category: 'food', platform: '外卖', payment_method: '支付宝', status: 'done',
    companion_message: staleCompanion,
    ai_feedback: {
      expression_coverage: {
        coverage_version: 'expression-coverage-v1',
        expressed_semantic_key: oldBrief.semantic_key,
        expressed_semantic_keys: [oldBrief.semantic_key],
        source_surface: 'record_detail',
        planner_version: 'expression-shadow-auto-v0.6',
        packet_fingerprint: 'before-edit',
        claim_fingerprint: oldBrief.claim_fingerprint,
        presentation_target: 'companion_message',
        rendered_text_fingerprint: module.expressionRenderedTextFingerprint(staleCompanion),
      },
    },
  })

  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: '92000000-0000-4000-8000-000000000001',
    record_kind: 'expense',
  })
  assert.equal(preview.available, true)
  assert.equal(preview.presentation_target, 'feedback_card')
  assert.equal(preview.feedback.semantic_key, 'expense_merchant_first_occurrence')
  assert.notEqual(preview.feedback.claim_fingerprint, oldBrief.claim_fingerprint)
})

test('forged coverage and rendered text fingerprints cannot turn generic copy into a companion delivery', async () => {
  const module = await loadModule()
  const recordId = '92500000-0000-4000-8000-000000000001'
  const current = {
    id: recordId, user_id: userId, type: 'expense', transaction_date: '2026-08-07',
    transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00', amount: 6.28,
    merchant_name: '青禾茶饮', category: 'food', platform: '外卖', payment_method: '支付宝', status: 'done',
  }
  const { client, state } = database()
  const brief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'expense', domain_key: 'expense', current_record: { ...current, id: 'preinsert:forged-coverage' },
  })
  const genericCompanion = '日常琐碎也被妥善归档，生活自有其节奏。'
  state.tables.transactions.push({
    ...current,
    companion_message: genericCompanion,
    ai_feedback: {
      expression_coverage: {
        coverage_version: 'expression-coverage-v1',
        expressed_semantic_key: brief.semantic_key,
        expressed_semantic_keys: [brief.semantic_key],
        source_surface: 'record_detail',
        planner_version: 'expression-shadow-auto-v0.6',
        packet_fingerprint: 'forged-packet',
        claim_fingerprint: brief.claim_fingerprint,
        presentation_target: 'companion_message',
        rendered_text_fingerprint: module.expressionRenderedTextFingerprint(genericCompanion),
      },
    },
  })
  const genericPreview = await module.getRecordExpressionPlan(client, userId, {
    record_id: recordId, record_kind: 'expense',
  })
  assert.equal(genericPreview.presentation_target, 'feedback_card')

  const groundedCompanion = '第一次记录青禾茶饮，芥子先把这个新商户记下来。'
  state.tables.transactions[0].companion_message = groundedCompanion
  state.tables.transactions[0].ai_feedback.expression_coverage.rendered_text_fingerprint = 'fnv1a64:wrong-text'
  const wrongFingerprintPreview = await module.getRecordExpressionPlan(client, userId, {
    record_id: recordId, record_kind: 'expense',
  })
  assert.equal(wrongFingerprintPreview.presentation_target, 'feedback_card')
})

test('expense novelty reads beyond the first 500 history rows before claiming first occurrence', async () => {
  const module = await loadModule()
  const history = Array.from({ length: 501 }, (_, index) => ({
    id: `history-${String(index).padStart(4, '0')}`,
    user_id: userId,
    type: 'expense',
    transaction_date: '2026-08-01',
    transaction_time: `${String(Math.floor(index / 60) % 24).padStart(2, '0')}:${String(index % 60).padStart(2, '0')}:00`,
    created_at: `2026-08-01T${String(Math.floor(index / 60) % 24).padStart(2, '0')}:${String(index % 60).padStart(2, '0')}:00+08:00`,
    amount: 10,
    merchant_name: index === 0 ? '远期旧商户' : `其他商户-${index}`,
    category: 'shopping',
    platform: '线下',
    payment_method: '支付宝',
    status: 'done',
  }))
  const { client } = database({ transactions: history })
  const brief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'expense',
    domain_key: 'expense',
    current_record: {
      id: 'preinsert:page-two', type: 'expense', transaction_date: '2026-08-07',
      transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00', amount: 12,
      merchant_name: '远期旧商户', category: 'shopping', platform: '线下', payment_method: '支付宝', status: 'done',
    },
  })

  assert.notEqual(brief?.semantic_key, 'expense_merchant_first_occurrence')
})

test('persisted domain planning consumes the same profile-backed candidates as pre-insert Voice', async () => {
  const module = await loadModule()
  const recordId = '93000000-0000-4000-8000-000000000001'
  const profile = { meal_baseline: { dinner: { n: 11, median_kcal: 750 } } }
  const current = dataRecord(recordId, 'food', {
    total_calorie_kcal: 638,
    meal_type: 'dinner',
  }, '2026-08-07T19:00:00+08:00')
  const { client, state } = database({
    user_domain_profiles: [{ user_id: userId, domain_key: 'food', profile }],
  })
  const profileProbe = await client.from('user_domain_profiles')
    .select('profile')
    .eq('user_id', userId)
    .eq('domain_key', 'food')
    .maybeSingle()
  assert.deepEqual(profileProbe.data?.profile, profile)

  const brief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'data',
    domain_key: 'food',
    current_record: current,
    domain_profile: profile,
  })
  state.tables.data_records.push(current)
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: recordId,
    record_kind: 'data',
  })
  assert.equal(preview.available, true)
  assert.equal(preview.feedback.semantic_key, brief.semantic_key)
  const persistedKeys = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.decision.action_set
    .map(action => action.semantic_key)
  assert.ok(persistedKeys.includes('food_meal_vs_personal_median'))
  assert.ok(persistedKeys.includes(brief.semantic_key))
})

test('second-call failures preserve verified Planner feedback without impersonating Voice', async () => {
  const module = await loadIngestFeedbackModule()
  const semanticKey = 'expense_merchant_first_occurrence'
  const plannerBrief = {
    candidate_id: 'fact:expense:merchant-first-occurrence:preinsert-test',
    semantic_key: semanticKey,
    dimension: 'first_occurrence',
    canonical_text: '第一次记录「青禾茶饮」',
    source_surface: 'record_detail',
    planner_version: 'expression-shadow-auto-v0.6',
    numbers: [1, 6.28],
    count_numbers: [1],
    number_facts: [
      { value: 1, meaning: 'first_occurrence_count', role: 'count' },
      { value: 6.28, meaning: 'current_record_amount', role: 'measure' },
    ],
    claim_fingerprint: 'fnv1a64:first-occurrence',
  }
  const baseOptions = {
    ai: {
      record_type: 'expense',
      domain_key: 'expense',
      image_type: 'screenshot',
      amount: 6.28,
      merchant_name: '青禾茶饮',
      category: 'dining',
      platform: '外卖',
      occurred_at: '2026-08-07T12:10:00+08:00',
      confidence: 0.98,
    },
    domainKey: 'expense',
    builtPayload: null,
    domainProfiles: {},
    memory: null,
    timeContext: null,
    timingSignal: null,
    promptCtx: {
      clientLocalTime: '2026-08-07 12:10:00',
      weekday: '星期五',
      persona: 'observer',
      memoryStrength: 'balanced',
      expressionStyle: 'plain',
    },
    plannerBrief,
    plannerFallbackReason: null,
  }
  const provider = {
    name: 'qwen',
    model: 'qwen3.6-flash',
    endpoint: 'https://example.invalid/v1/chat/completions',
    apiKey: 'fixture',
  }
  const assertVerifiedFallback = (result, errorPattern) => {
    assert.match(result.error, errorPattern)
    assert.equal(result.companion_message, null)
    assert.equal(result.raw_text, null)
    assert.equal(result.ai_feedback.source, 'rule')
    assert.equal(result.ai_feedback.tone, 'signal_fallback')
    assert.equal(result.ai_feedback.detail_reason, null)
    assert.equal(result.ai_feedback.expression_coverage == null, true)
    assert.equal(result.expression_trace.context_packet_version, 'context-packet-v2')
    assert.equal(result.expression_trace.planner_brief_status, 'selected')
    assert.equal(result.expression_trace.planner_semantic_key, semanticKey)
    assert.match(result.expression_trace.packet_fingerprint, /^[0-9a-f]{8}$/)
  }

  const noProvider = await module.regenerateFeedbackWithSecondCall({
    ...baseOptions,
    textProvider: null,
  })
  assertVerifiedFallback(noProvider, /^no_text_provider$/)

  const originalFetch = globalThis.fetch
  try {
    globalThis.fetch = async () => new Response(null, { status: 503 })
    const httpFailure = await module.regenerateFeedbackWithSecondCall({
      ...baseOptions,
      textProvider: provider,
    })
    assertVerifiedFallback(httpFailure, /qwen text API error 503/)

    globalThis.fetch = async () => new Response(JSON.stringify({
      choices: [{ message: { content: 'not-json' } }],
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })
    const jsonFailure = await module.regenerateFeedbackWithSecondCall({
      ...baseOptions,
      textProvider: provider,
    })
    assertVerifiedFallback(jsonFailure, /Failed to parse feedback JSON/)
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('generic model copy remains Voice copy while grounded copy may claim coverage', async () => {
  const module = await loadIngestFeedbackModule()
  const plannerBrief = {
    candidate_id: 'fact:expense:merchant-first-occurrence:voice-coverage-test',
    semantic_key: 'expense_merchant_first_occurrence',
    dimension: 'first_occurrence',
    canonical_text: '第一次记录「青禾茶饮」',
    source_surface: 'record_detail',
    planner_version: 'expression-shadow-auto-v0.6',
    numbers: [1],
    count_numbers: [1],
    number_facts: [{ value: 1, meaning: 'first_occurrence_count', role: 'count' }],
    claim_fingerprint: 'fnv1a64:first-occurrence-voice',
  }
  const options = {
    ai: {
      record_type: 'expense', domain_key: 'expense', image_type: 'screenshot', amount: 6.28,
      merchant_name: '青禾茶饮', category: 'dining', platform: '外卖', payment_method: '微信支付',
      occurred_at: '2026-08-07T12:10:00+08:00', confidence: 0.98,
    },
    domainKey: 'expense',
    builtPayload: null,
    normalizedAmount: 6.28,
    domainProfiles: {},
    timingSignal: null,
    timeContext: null,
    clientLocalTime: '2026-08-07 12:10:00',
    weekday: '星期五',
    persona: 'observer',
    memoryStrength: 'balanced',
    expressionStyle: 'plain',
    recentCompanionLines: [],
    memory: null,
    plannerBrief,
    plannerFallbackReason: null,
    textProvider: {
      name: 'qwen', model: 'qwen3.6-flash', endpoint: 'https://example.invalid/v1/chat/completions', apiKey: 'fixture',
    },
  }
  const modelPayload = (emotionLine) => JSON.stringify({
    companion_message: null,
    ai_feedback: {
      version: 'feedback-v1', domain_key: 'expense', badge: '即时反馈', icon: '💸', band: 'neutral',
      tone: 'warm', emotion_line: emotionLine, utility_line: null, detail_reason: null,
      confidence: 0.8, source: 'hybrid',
    },
  })
  const originalFetch = globalThis.fetch
  try {
    globalThis.fetch = async () => new Response(JSON.stringify({
      choices: [{ message: { content: modelPayload('日常琐碎也被妥善归档，生活自有其节奏。') } }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    const generic = await module.generateVoiceFeedback(options)
    assert.equal(generic.companion_message, '日常琐碎也被妥善归档，生活自有其节奏。')
    assert.equal(generic.ai_feedback.expression_coverage == null, true)

    globalThis.fetch = async () => new Response(JSON.stringify({
      choices: [{ message: { content: modelPayload('第一次记录青禾茶饮，芥子记住这个新商户了。') } }],
    }), { status: 200, headers: { 'Content-Type': 'application/json' } })
    const grounded = await module.generateVoiceFeedback(options)
    assert.equal(grounded.companion_message, '第一次记录青禾茶饮，芥子记住这个新商户了。')
    assert.equal(grounded.ai_feedback.expression_coverage.expressed_semantic_key, plannerBrief.semantic_key)
    assert.equal(grounded.ai_feedback.expression_coverage.presentation_target, 'companion_message')
  } finally {
    globalThis.fetch = originalFetch
  }
})

test('single-user owner gate defaults closed for disabled or non-owner access', async () => {
  const item = supportedCases.find(entry => entry.name === 'expense')
  const disabledModule = await loadModule({ EXPRESSION_PLANNER_OWNER_ENABLED: 'false' })
  const disabledDatabase = database(item.seed)
  const disabled = await disabledModule.getRecordExpressionPlan(disabledDatabase.client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })
  assert.deepEqual(disabled, { available: false, reason: 'owner_only_unavailable' })
  assert.equal(disabledDatabase.state.tables.expression_delivery_snapshots.length, 0)

  const nonOwnerModule = await loadModule({
    EXPRESSION_PLANNER_OWNER_USER_ID: '22222222-2222-4222-8222-222222222222',
  })
  const nonOwnerDatabase = database(item.seed)
  const nonOwner = await nonOwnerModule.getRecordExpressionPlan(nonOwnerDatabase.client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })
  assert.deepEqual(nonOwner, { available: false, reason: 'owner_only_unavailable' })
  await assert.rejects(
    nonOwnerModule.acknowledgeRecordExpressionPlan(nonOwnerDatabase.client, userId, {
      record_id: item.recordId,
      plan_token: 'not-used',
      candidate_id: 'not-used',
    }),
    /当前未启用/,
  )
})

test('edge route applies the owner gate after JWT authentication and before delivery', async () => {
  const source = await readFile(path.join(root, 'supabase/functions/ingest-receipt/index.ts'), 'utf8')
  const authIndex = source.indexOf('const actionUserId = await authenticatedUserId(req)')
  const gateIndex = source.indexOf('if (!isRecordExpressionOwnerEnabled(actionUserId))')
  const deliveryIndex = source.indexOf('? await getRecordExpressionPlan(supabase, actionUserId, jsonBody)')

  assert.ok(authIndex >= 0)
  assert.ok(gateIndex > authIndex)
  assert.ok(deliveryIndex > gateIndex)
  assert.match(source.slice(gateIndex, deliveryIndex), /status: 403/)
})

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
    assert.ok(preview.feedback.detail_reason, `${item.name}: Planner feedback must expose an evidence summary`)
    assert.equal(state.shadowReads, 0)
    assert.equal(state.tables.expression_delivery_snapshots.length, 1)
    const snapshot = state.tables.expression_delivery_snapshots[0]
    assert.equal(snapshot.shadow_run_id, null)
    assert.equal(snapshot.record_kind, item.kind)
    assert.ok(Date.parse(snapshot.expires_at) > Date.now())
    assert.equal('source_record' in snapshot.delivery_plan, false)
    assert.equal('structured_value' in snapshot.delivery_plan.candidates[0].claim, false)
    assert.equal(snapshot.delivery_plan.decision.policy_name, 'deterministic_rule')
    assert.equal(snapshot.delivery_plan.decision.selection_probability, 1)
    assert.equal(snapshot.delivery_plan.decision.action_count, snapshot.delivery_plan.decision.action_set.length)
    assert.ok(new TextEncoder().encode(JSON.stringify(snapshot.delivery_plan.decision)).byteLength <= 64 * 1024)
    assert.equal(snapshot.delivery_plan.decision.action_set.every(action => action.passes_threshold === true), true)
    assert.ok(snapshot.delivery_plan.decision.action_set.some(action => action.selection_probability === 1))
    assert.equal(snapshot.delivery_plan.decision.action_set.every(action => action.action_id !== action.candidate_fingerprint), true)
    assert.equal(
      snapshot.delivery_plan.decision.action_set.find(action => action.selection_probability === 1).action_id,
      snapshot.delivery_plan.decision.chosen_action_id,
    )
    assert.equal(snapshot.delivery_plan.decision.action_set.some(action => 'canonical_text' in action), false)
    assert.equal(snapshot.delivery_plan.decision.action_set.some(action => 'candidate_id' in action), false)
    assert.equal(snapshot.delivery_plan.decision.action_set.some(action => 'exposure_key' in action), false)
  }
})

test('pending expense returns a reviewable verified-fact candidate without entering aggregates', async () => {
  const module = await loadModule()
  const recordId = '12000000-0000-4000-8000-000000000001'
  const { client, state } = database({
    transactions: [{
      id: recordId, user_id: userId, type: 'expense', transaction_date: '2026-07-25', transaction_time: '20:16:00',
      created_at: '2026-07-25T20:17:00+08:00', amount: 32, merchant_name: '示例记录', category: null,
      platform: '线下', payment_method: null, status: 'pending',
    }],
  })

  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: recordId,
    record_kind: 'expense',
  })

  assert.equal(preview.available, true)
  assert.equal(preview.feedback.source, 'expression_planner')
  assert.equal(preview.feedback.semantic_key, 'expense_merchant_first_occurrence')
  assert.match(preview.feedback.emotion_line, /第一次记录/)
  const candidate = state.tables.expression_delivery_snapshots[0].delivery_plan.candidates[0]
  assert.equal(candidate.claim.structured_value, undefined)
  assert.equal(candidate.source_dependencies.length, 1)

  const acknowledged = await module.acknowledgeRecordExpressionPlan(client, userId, {
    record_id: recordId,
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })
  assert.ok(acknowledged.exposure_event_id)
  assert.equal(acknowledged.feedback.exposure_event_id, acknowledged.exposure_event_id)
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
  const decision = state.tables.expression_delivery_snapshots[0].delivery_plan.decision
  const exposureMetadata = state.tables.expression_exposure_events[0].metadata
  assert.equal(exposureMetadata.decision_id, decision.decision_id)
  assert.equal(exposureMetadata.policy_name, 'deterministic_rule')
  assert.equal(exposureMetadata.selection_probability, 1)
  assert.equal(exposureMetadata.chosen_action_id, decision.chosen_action_id)
  assert.ok(exposureMetadata.action_set.length >= 2)
  assert.equal(exposureMetadata.action_set.filter(action => action.selection_probability === 1).length, 1)
  assert.equal(state.exposureSources.some(source => source.is_primary === true), true)
})

test('delivery excludes a near-identical personal baseline from the record-detail action set', async () => {
  const module = await loadModule()
  const { client, state } = database(expenseNearBaselineSeed())
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: '11000000-0000-4000-8000-000000000004',
    record_kind: 'expense',
  })

  assert.equal(preview.available, true)
  assert.notEqual(preview.feedback.semantic_key, 'merchant_daily_vs_active_day_median')
  const decision = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.decision
  assert.equal(
    decision.action_set.some(action => action.semantic_key === 'merchant_daily_vs_active_day_median'),
    false,
    JSON.stringify(decision.action_set, null, 2),
  )
})

test('delivery skips a record-detail candidate whose scoped dedupe key reached its cap', async () => {
  const module = await loadModule()
  const { client, state } = database(expenseBaselineSeed())
  const baseline = await previewPersonalBaseline(module, client, state)

  state.tables.expression_exposure_events.push(plannerExposure(baseline.candidate, 3))
  const next = await module.getRecordExpressionPlan(client, userId, baseline.input)
  assert.equal(next.available, true)
  const nextCandidate = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.candidates[0]
  const nextActionSet = state.tables.expression_delivery_snapshots.at(-1).delivery_plan.decision.action_set

  assert.notEqual(next.candidate_id, baseline.preview.candidate_id)
  assert.notEqual(nextCandidate.claim.semantic_key, 'merchant_daily_vs_active_day_median')
  assert.equal(
    nextActionSet.some(action => action.semantic_key === 'merchant_daily_vs_active_day_median'),
    false,
    JSON.stringify(nextActionSet, null, 2),
  )
})

test('changing a historical dependency invalidates a frozen comparison delivery', async () => {
  const module = await loadModule()
  const { client, state } = database(expenseBaselineSeed())
  const baseline = await previewPersonalBaseline(module, client, state)
  state.tables.transactions[0].amount = 99

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: baseline.input.record_id,
      plan_token: baseline.preview.plan_token,
      candidate_id: baseline.preview.candidate_id,
    }),
    /plan_dependency_stale/,
  )
  assert.equal(state.tables.expression_exposure_events.filter(row => row.id?.startsWith('exposure-')).length, 0)
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

test('changing the persisted companion after preview invalidates companion acknowledgement', async () => {
  const module = await loadModule()
  const recordId = '93500000-0000-4000-8000-000000000001'
  const current = {
    id: recordId, user_id: userId, type: 'expense', transaction_date: '2026-08-07',
    transaction_time: '12:00:00', created_at: '2026-08-07T12:01:00+08:00', amount: 6.28,
    merchant_name: '青禾茶饮', category: 'food', platform: '外卖', payment_method: '支付宝', status: 'done',
  }
  const { client, state } = database()
  const brief = await module.buildPreInsertPlannerVoiceBrief(client, userId, {
    record_kind: 'expense', domain_key: 'expense', current_record: { ...current, id: 'preinsert:companion-stale' },
  })
  const visibleCompanion = '第一次记录青禾茶饮，芥子先把这个新商户记下来。'
  state.tables.transactions.push({
    ...current,
    companion_message: visibleCompanion,
    ai_feedback: {
      expression_coverage: {
        coverage_version: 'expression-coverage-v1',
        expressed_semantic_key: brief.semantic_key,
        expressed_semantic_keys: [brief.semantic_key],
        source_surface: 'record_detail',
        planner_version: 'expression-shadow-auto-v0.6',
        packet_fingerprint: 'companion-stale-packet',
        claim_fingerprint: brief.claim_fingerprint,
        presentation_target: 'companion_message',
        rendered_text_fingerprint: module.expressionRenderedTextFingerprint(visibleCompanion),
      },
    },
  })
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: recordId, record_kind: 'expense',
  })
  assert.equal(preview.presentation_target, 'companion_message')
  state.tables.transactions[0].companion_message = '这段文案在预览后被改写了。'

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: recordId,
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /plan_companion_stale/,
  )
  assert.equal(state.tables.expression_exposure_events.length, 0)
})

test('editing an older merchant into a first occurrence invalidates acknowledgement', async () => {
  const module = await loadModule()
  const oldId = '94000000-0000-4000-8000-000000000001'
  const currentId = '94000000-0000-4000-8000-000000000002'
  const { client, state } = database({
    transactions: [
      {
        id: oldId, user_id: userId, type: 'expense', transaction_date: '2026-08-06', transaction_time: '08:00:00',
        created_at: '2026-08-06T08:01:00+08:00', amount: 12, merchant_name: '其他商户', category: 'shopping',
        platform: '线下', payment_method: '支付宝', status: 'done',
      },
      {
        id: currentId, user_id: userId, type: 'expense', transaction_date: '2026-08-07', transaction_time: '08:00:00',
        created_at: '2026-08-07T08:01:00+08:00', amount: 6.28, merchant_name: '新商户', category: 'food',
        platform: '外卖', payment_method: '支付宝', status: 'done',
      },
    ],
  })
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: currentId,
    record_kind: 'expense',
  })
  assert.equal(preview.feedback.semantic_key, 'expense_merchant_first_occurrence')
  state.tables.transactions.find(row => row.id === oldId).merchant_name = '新商户'

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: currentId,
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /plan_claim_stale/,
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

test('delivery snapshots from the previous planner version cannot be acknowledged', async () => {
  const module = await loadModule()
  const item = supportedCases.find(entry => entry.name === 'sport')
  const { client, state } = database(item.seed)
  const preview = await module.getRecordExpressionPlan(client, userId, {
    record_id: item.recordId,
    record_kind: item.kind,
  })
  state.tables.expression_delivery_snapshots[0].delivery_plan.planner_version = 'expression-shadow-auto-v0.5'

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, userId, {
      record_id: item.recordId,
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /内容已失效/,
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
