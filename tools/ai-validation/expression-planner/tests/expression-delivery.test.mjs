import test from 'node:test'
import assert from 'node:assert/strict'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { build } from 'esbuild'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const entryPoint = path.join(root, 'supabase/functions/ingest-receipt/expression-delivery.ts')

async function loadModule(environment) {
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

function canonicalValue(value) {
  if (Array.isArray(value)) return value.map(canonicalValue)
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value)
      .filter(([, item]) => item !== undefined)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, item]) => [key, canonicalValue(item)]))
  }
  return typeof value === 'number' && !Number.isFinite(value) ? null : value
}

function sourceFingerprint(value) {
  const bytes = new TextEncoder().encode(JSON.stringify(canonicalValue(value)))
  let hash = 0xcbf29ce484222325n
  for (const byte of bytes) {
    hash ^= BigInt(byte)
    hash = BigInt.asUintN(64, hash * 0x100000001b3n)
  }
  return `fnv1a64:${hash.toString(16).padStart(16, '0')}`
}

function samplePlan() {
  const plan = {
    status: 'auto_planned',
    planner_version: 'expression-shadow-auto-v0.4',
    domain_key: 'expense',
    source_record: {
      id: 'record-1',
      transaction_date: '2026-07-25',
      occurred_at: '2026-07-25T08:00:00+08:00',
      amount: 4,
      merchant_name: '示例记录',
      category: 'other',
      platform: null,
      payment_method: null,
      status: 'completed',
      type: 'expense',
    },
    candidates: [{
      candidate_id: 'candidate-1',
      dimension: 'repeat_interval',
      claim_type: 'fact',
      claim: {
        semantic_key: 'expense_record_name_previous_gap',
        canonical_text: '距离上一次同名记录已经过去 2 小时 30 分钟',
        structured_value: { elapsed_minutes: 150 },
      },
      evidence: [{ source: 'transaction', record_id: 'record-1' }],
      numbers: [{ value: 150, meaning: 'elapsed_minutes', derivation: 'current-previous' }],
      quality: { confidence: 0.9, data_coverage: 1, sample_count: 2 },
      selection_hints: { exposure_key: 'expense:record_name:example' },
      scoring: { scoring_version: 'deterministic-score-v0.2' },
    }],
    render_plans: {
      record_detail: {
        expression_plan_version: 'expression-plan-v0.1',
        render_contract_version: 'surface-render-contract-v0.1',
        selected: [{
          candidate_id: 'candidate-1',
          canonical_text: '距离上一次同名记录已经过去 2 小时 30 分钟',
          visible_field_paths: ['rendered_feedback.emotion_line'],
          expandable_field_paths: [],
          persisted_only_field_paths: [],
          selection_mode: 'threshold',
          score: 79.8,
        }],
      },
    },
  }
  const dependency = {
    source_table: 'transactions',
    source_record_id: plan.source_record.id,
    source_fingerprint: sourceFingerprint(plan.source_record),
    is_primary: true,
  }
  plan.source_dependencies = [dependency]
  plan.candidates[0].source_dependencies = [dependency]
  return plan
}

function database(plan, transactionOverrides = {}, historicalExposureRows = [], shadowRowsOverride = null) {
  const state = {
    deliverySnapshots: [],
    exposureRows: [],
    exposureQueries: [],
    rpcCalls: [],
  }
  const shadowRow = {
    id: 'shadow-1',
    created_at: '2026-07-25T08:00:01+08:00',
    user_id: 'owner-1',
    record_id: 'record-1',
    record_type: 'expense',
    occurred_at: '2026-07-25T08:00:00+08:00',
    proposed_plan: plan,
    processed_at: '2026-07-25T08:00:01+08:00',
    rollout_mode: 'enforced_owner_only',
  }
  const shadowRows = shadowRowsOverride ?? [shadowRow]
  const transaction = {
    id: 'record-1',
    user_id: 'owner-1',
    transaction_date: '2026-07-25',
    transaction_time: '08:00:00',
    created_at: '2026-07-25T08:00:01+08:00',
    amount: 4,
    merchant_name: '示例记录',
    category: 'other',
    platform: null,
    payment_method: null,
    status: 'completed',
    type: 'expense',
    ...transactionOverrides,
  }
  state.transaction = transaction
  const client = {
    async rpc(name, params) {
      state.rpcCalls.push({ name, params })
      if (name !== 'persist_expression_exposure_with_sources') {
        throw new Error(`Unexpected RPC: ${name}`)
      }
      const existing = state.exposureRows.find(row => row.event_key === params.p_event_key)
      if (existing) return { data: { exposure: existing, created: false }, error: null }
      const exposure = {
        id: `exposure-${state.exposureRows.length + 1}`,
        ...params.p_exposure,
      }
      state.exposureRows.push(exposure)
      return { data: { exposure, created: true }, error: null }
    },
    from(table) {
      if (table === 'expression_shadow_runs') {
        const filters = new Map()
        let orderColumn = ''
        let orderAscending = true
        let resultLimit = Number.POSITIVE_INFINITY
        const query = {
          select() { return this },
          eq(column, value) {
            filters.set(column, value)
            return this
          },
          not() { return this },
          order(column, options = {}) {
            orderColumn = column
            orderAscending = options.ascending !== false
            return this
          },
          limit(value) {
            resultLimit = value
            return this
          },
          async maybeSingle() {
            const rows = shadowRows
              .filter(row => [...filters].every(([column, value]) => row[column] === value))
              .sort((left, right) => {
                if (!orderColumn) return 0
                const comparison = String(left[orderColumn] ?? '').localeCompare(String(right[orderColumn] ?? ''))
                return orderAscending ? comparison : -comparison
              })
              .slice(0, resultLimit)
            return { data: rows[0] ?? null, error: null }
          },
        }
        return query
      }
      if (table === 'expression_exposure_events') {
        const filters = new Map()
        const query = {
          select() { return this },
          eq(column, value) {
            filters.set(column, value)
            return this
          },
          order() { return this },
          limit() { return this },
          then(resolve, reject) {
            const rows = [...historicalExposureRows, ...state.exposureRows]
              .filter(row => [...filters].every(([column, value]) => row[column] === value))
            state.exposureQueries.push(Object.fromEntries(filters))
            return Promise.resolve({ data: rows, error: null }).then(resolve, reject)
          },
        }
        return query
      }
      if (table === 'expression_delivery_snapshots') {
        const filters = new Map()
        let pendingInsert = null
        return {
          upsert(row) {
            pendingInsert = row
            return this
          },
          select() { return this },
          eq(column, value) {
            filters.set(column, value)
            return this
          },
          async maybeSingle() {
            if (pendingInsert) {
              const duplicate = state.deliverySnapshots.find(row => (
                row.user_id === pendingInsert.user_id
                && row.shadow_run_id === pendingInsert.shadow_run_id
                && row.surface === pendingInsert.surface
                && row.content_fingerprint === pendingInsert.content_fingerprint
              ))
              if (duplicate) return { data: null, error: null }
              const inserted = {
                id: `snapshot-${state.deliverySnapshots.length + 1}`,
                created_at: '2026-07-25T08:00:02+08:00',
                ...pendingInsert,
              }
              state.deliverySnapshots.push(inserted)
              return { data: inserted, error: null }
            }
            const data = state.deliverySnapshots.find(row => (
              [...filters].every(([column, value]) => row[column] === value)
            )) ?? null
            return { data, error: null }
          },
        }
      }
      if (table === 'expression_preference_revisions') {
        return {
          select() { return this },
          eq() { return this },
          async maybeSingle() { return { data: null, error: null } },
        }
      }
      if (table === 'expression_preference_snapshots') {
        return {
          select() { return this },
          eq() { return this },
          async maybeSingle() { return { data: null, error: null } },
        }
      }
      if (table === 'transactions') {
        const filters = new Map()
        let includedIds = null
        const query = {
          select() { return this },
          eq(column, value) {
            filters.set(column, value)
            return this
          },
          in(column, values) {
            if (column === 'id') includedIds = values
            return this
          },
          async maybeSingle() {
            const matches = [...filters].every(([column, value]) => transaction[column] === value)
            return { data: matches ? transaction : null, error: null }
          },
          then(resolve, reject) {
            const matches = [...filters].every(([column, value]) => transaction[column] === value)
              && (!includedIds || includedIds.includes(transaction.id))
            return Promise.resolve({ data: matches ? [transaction] : [], error: null }).then(resolve, reject)
          },
        }
        return query
      }
      throw new Error(`Unexpected table: ${table}`)
    },
  }
  return { client, state }
}

test('owner-only delivery returns one selected record-detail candidate and binds its exposure', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const { client, state } = database(samplePlan())
  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })
  assert.equal(preview.available, true, JSON.stringify(preview))
  assert.equal(preview.plan_token, 'snapshot-1')
  assert.equal(preview.feedback.emotion_line, '距离上一次同名记录已经过去 2 小时 30 分钟')
  assert.equal(preview.feedback.exposure_event_id, undefined)

  const beforeAcknowledgement = Date.now()
  const acknowledged = await module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
    record_id: 'record-1',
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })
  assert.equal(acknowledged.exposure_event_id, 'exposure-1')
  assert.equal(acknowledged.feedback.exposure_event_id, 'exposure-1')
  assert.equal(state.exposureRows.length, 1)
  assert.equal(state.exposureRows[0].surface, 'record_detail')
  assert.ok(Date.parse(state.exposureRows[0].occurred_at) >= beforeAcknowledgement)
  assert.notEqual(state.exposureRows[0].occurred_at, state.deliverySnapshots[0].created_at)
  assert.equal(state.exposureRows[0].metadata.scoped_dedupe_key, 'record_detail:expense:record_name:example')
  assert.deepEqual(state.exposureRows[0].rendered_payload, preview.feedback)
  assert.equal('structured_value' in state.exposureRows[0].rendered_payload, false)
  assert.deepEqual(state.exposureRows[0].visible_field_paths, [
    'feedback.badge',
    'feedback.emotion_line',
    'feedback.detail_reason',
  ])

  const repeated = await module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
    record_id: 'record-1',
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })
  assert.equal(repeated.exposure_event_id, acknowledged.exposure_event_id)
  assert.equal(state.exposureRows.length, 1)
})

test('shadow mode never exposes a proposed plan to the client', async () => {
  const module = await loadModule({ EXPRESSION_PLANNER_MODE: 'shadow' })
  const result = await module.getRecordExpressionPlan({ from() { throw new Error('database should not be read') } }, 'owner-1', { record_id: 'record-1' })
  assert.deepEqual(result, { available: false, reason: 'rollout_not_enabled' })
})

test('ack rejects a secondary candidate that was never returned as the preview', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const plan = samplePlan()
  plan.candidates.push({
    ...plan.candidates[0],
    candidate_id: 'candidate-2',
    claim: {
      ...plan.candidates[0].claim,
      semantic_key: 'merchant_daily_vs_active_day_median',
      canonical_text: '当天 2 笔，历史活跃日中位数 1 笔',
      structured_value: {
        current: { count: 2, total: 20 },
        baseline: { kind: 'historical_active_day_median', sample_days: 3, count: 1, total: 10 },
      },
    },
  })
  plan.render_plans.record_detail.selected.push({
    ...plan.render_plans.record_detail.selected[0],
    candidate_id: 'candidate-2',
    canonical_text: '当天 2 笔，历史活跃日中位数 1 笔',
  })
  const { client, state } = database(plan)
  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })
  const candidateNotReturned = preview.candidate_id === 'candidate-1' ? 'candidate-2' : 'candidate-1'

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
      record_id: 'record-1',
      plan_token: preview.plan_token,
      candidate_id: candidateNotReturned,
    }),
    /候选不是本次下发的记录详情内容/,
  )
  assert.equal(state.exposureRows.length, 0)
})

test('delivery skips a capped dedupe key and ack binds the replacement candidate', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const plan = samplePlan()
  plan.candidates[0].selection_hints = {
    exposure_key: 'expense:record_name:per-record-scoring-key',
    dedupe_key: 'expense:record_name:example',
    max_exposure_count: { record_detail: 1 },
  }
  plan.candidates.push({
    ...plan.candidates[0],
    candidate_id: 'candidate-2',
    dimension: 'personal_baseline',
    claim: {
      ...plan.candidates[0].claim,
      semantic_key: 'merchant_daily_vs_active_day_median',
      canonical_text: '当天 2 笔，历史活跃日中位数 1 笔',
      structured_value: {
        current: { count: 2, total: 20 },
        baseline: { kind: 'historical_active_day_median', sample_days: 3, count: 1, total: 10 },
      },
    },
    selection_hints: {
      exposure_key: 'expense:merchant:example:daily-active-scoring-key',
      dedupe_key: 'expense:merchant:example:daily_active_median:2026-07-25',
      max_exposure_count: { record_detail: 1 },
    },
  })
  plan.render_plans.record_detail.selected.push({
    ...plan.render_plans.record_detail.selected[0],
    candidate_id: 'candidate-2',
    canonical_text: '当天 2 笔，历史活跃日中位数 1 笔',
  })
  const historicalExposureRows = [{
    user_id: 'owner-1',
    surface: 'record_detail',
    semantic_key: 'expense_record_name_previous_gap',
    lifecycle_state: 'client_rendered',
    selection_mode: 'threshold',
    simulation_only: false,
    counts_for_novelty: true,
    metadata: {
      dedupe_key: 'expense:record_name:example',
      scoped_dedupe_key: 'record_detail:expense:record_name:example',
    },
  }]
  const { client, state } = database(plan, {}, historicalExposureRows)

  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })

  assert.equal(preview.available, true, JSON.stringify(preview))
  assert.equal(preview.candidate_id, 'candidate-2')
  assert.equal(preview.feedback.emotion_line, '当天 2 笔，历史活跃日中位数 1 笔')
  const exposureQueryCountAfterPreview = state.exposureQueries.length
  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
      record_id: 'record-1',
      plan_token: preview.plan_token,
      candidate_id: 'candidate-1',
    }),
    /候选不是本次下发的记录详情内容/,
  )

  const acknowledged = await module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
    record_id: 'record-1',
    plan_token: preview.plan_token,
    candidate_id: preview.candidate_id,
  })

  assert.equal(acknowledged.candidate_id, 'candidate-2')
  assert.equal(state.exposureRows.length, 1)
  assert.equal(state.exposureRows[0].candidate_id, 'candidate-2')
  assert.equal(
    state.exposureRows[0].metadata.scoped_dedupe_key,
    'record_detail:expense:merchant:example:daily_active_median:2026-07-25',
  )
  assert.equal(state.exposureQueries.length, exposureQueryCountAfterPreview)
})

test('an edited source record invalidates an otherwise selected plan', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const { client, state } = database(samplePlan(), { amount: 5 })

  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })

  assert.deepEqual(preview, { available: false, reason: 'plan_stale' })
  assert.equal(state.exposureRows.length, 0)
})

test('an edit after preview invalidates ack without changing the frozen candidate', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const { client, state } = database(samplePlan())
  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })
  state.transaction.amount = 5

  await assert.rejects(
    module.acknowledgeRecordExpressionPlan(client, 'owner-1', {
      record_id: 'record-1',
      plan_token: preview.plan_token,
      candidate_id: preview.candidate_id,
    }),
    /plan_dependency_stale/,
  )
  assert.equal(state.exposureRows.length, 0)
})

test('a plan produced by the previous planner version is never delivered', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const plan = samplePlan()
  plan.planner_version = 'expression-shadow-auto-v0.3'
  const { client, state } = database(plan)

  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })

  assert.deepEqual(preview, { available: false, reason: 'plan_version_mismatch' })
  assert.equal(state.exposureRows.length, 0)
})

test('a latest unprocessed shadow run never falls back to an older completed plan', async () => {
  const module = await loadModule({
    EXPRESSION_PLANNER_MODE: 'enforced_owner_only',
    EXPRESSION_PLANNER_OWNER_USER_IDS: 'owner-1',
  })
  const plan = samplePlan()
  const olderCompleted = {
    id: 'shadow-completed',
    created_at: '2026-07-25T08:00:01+08:00',
    occurred_at: '2026-07-25T08:00:00+08:00',
    user_id: 'owner-1',
    record_id: 'record-1',
    record_type: 'expense',
    proposed_plan: plan,
    processed_at: '2026-07-25T08:00:02+08:00',
    processing_error: null,
    rollout_mode: 'enforced_owner_only',
  }
  const latestPending = {
    ...olderCompleted,
    id: 'shadow-pending',
    created_at: '2026-07-25T08:00:03+08:00',
    proposed_plan: {},
    processed_at: null,
  }
  const { client, state } = database(plan, {}, [], [olderCompleted, latestPending])

  const preview = await module.getRecordExpressionPlan(client, 'owner-1', { record_id: 'record-1' })

  assert.deepEqual(preview, { available: false, reason: 'plan_not_ready' })
  assert.equal(state.deliverySnapshots.length, 0)
  assert.equal(state.exposureRows.length, 0)
})
