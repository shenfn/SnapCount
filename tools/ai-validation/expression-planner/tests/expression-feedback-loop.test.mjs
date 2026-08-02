import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({ entryPoints: ['supabase/functions/ingest-receipt/expression-feedback.ts'], bundle: true, platform: 'node', format: 'esm', write: false })
const { submitExpressionFeedback } = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64'))

function createDb(seed) {
  const tables = structuredClone(seed)
  let nextId = 1
  class Query {
    constructor(table) { this.table = table; this.filters = []; this.mode = 'select'; this.payload = null; this.options = {}; this.countMode = false }
    select(_columns, options = {}) { if (this.mode === 'select') this.countMode = options.head === true; return this }
    eq(key, value) { this.filters.push(row => row[key] === value); return this }
    order() { return this }
    limit(value) { this.limitValue = value; return this }
    upsert(payload, options = {}) { this.mode = 'upsert'; this.payload = payload; this.options = options; return this }
    async maybeSingle() { const result = await this.execute(); return { data: result.data?.[0] ?? null, error: result.error ?? null } }
    async single() { const result = await this.execute(); return { data: result.data?.[0] ?? null, error: result.error ?? null } }
    then(resolve, reject) { return this.execute().then(resolve, reject) }
    async execute() {
      tables[this.table] ??= []
      if (this.mode === 'upsert') {
        const rows = Array.isArray(this.payload) ? this.payload : [this.payload]
        const keys = String(this.options.onConflict || '').split(',').filter(Boolean)
        const output = []
        for (const raw of rows) {
          const row = Object.fromEntries(Object.entries(raw).filter(([, value]) => value !== undefined))
          const existing = keys.length ? tables[this.table].find(item => keys.every(key => item[key] === row[key])) : null
          if (existing) { if (!this.options.ignoreDuplicates) Object.assign(existing, row); output.push(existing); continue }
          const inserted = { id: row.id || 'mock-' + nextId++, created_at: row.created_at || new Date().toISOString(), ...row }
          tables[this.table].push(inserted); output.push(inserted)
        }
        return { data: output, error: null }
      }
      let rows = tables[this.table].filter(row => this.filters.every(filter => filter(row)))
      if (this.limitValue) rows = rows.slice(0, this.limitValue)
      if (this.countMode) return { data: null, count: rows.length, error: null }
      return { data: rows, error: null }
    }
  }
  return { client: { from: table => new Query(table) }, tables }
}

test('feedback creates reviewed exposure, preference signal, and snapshot', async () => {
  const userId = 'user-1'
  const { client, tables } = createDb({
    expression_exposure_events: [{
      id: 'exposure-1', event_key: 'delivery-1', delivery_attempt_id: 'delivery-1', occurred_at: '2026-07-13T10:00:00Z',
      user_id: userId, record_id: 'record-1', candidate_id: 'candidate-1', semantic_key: 'merchant_daily_count_total',
      claim_type: 'fact', surface: 'shortcut_notification', lifecycle_state: 'returned_to_shortcut', counts_for_novelty: true,
      expression_plan_version: 'v1', render_contract_version: 'v1', visible_field_paths: ['notification'], metadata: {},
    }],
    expression_feedback_events: [], expression_preference_signals: [], expression_preference_snapshots: [],
  })
  const result = await submitExpressionFeedback(client, userId, { record_id: 'record-1', primary_choice: 'repetitive', free_text: '最近重复得有点多' })
  assert.equal(result.preference_signal_count, 1)
  assert.equal(tables.expression_feedback_events.length, 1)
  assert.equal(tables.expression_preference_signals[0].preference_dimension, 'repetition_tolerance')
  assert.equal(tables.expression_preference_snapshots.length, 1)
  assert.ok(tables.expression_preference_snapshots[0].scoring_profile.repetition_tolerance.record_detail < 1)
  assert.equal(tables.expression_exposure_events.at(-1).surface, 'record_detail')
  assert.equal(tables.expression_exposure_events.at(-1).lifecycle_state, 'user_reviewed')
})
