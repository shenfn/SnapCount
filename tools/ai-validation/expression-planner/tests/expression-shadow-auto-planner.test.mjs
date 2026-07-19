import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({
  entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  write: false,
})
const url = 'data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64')
const { buildExpressionShadowPlan } = await import(url)

const repeatedApiMerchant = [
  { id: 'a', transaction_date: '2026-07-13', transaction_time: '10:00:00', amount: 10, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'b', transaction_date: '2026-07-13', transaction_time: '13:00:00', amount: 10, merchant_name: 'Example API Hub', status: 'done' },
  { id: 'c', transaction_date: '2026-07-13', transaction_time: '16:00:00', amount: 15, merchant_name: 'ExampleAPIHub', status: 'done' },
  { id: 'd', transaction_date: '2026-07-13', transaction_time: '19:07:00', amount: 12, merchant_name: 'Example API Hub', status: 'done' },
 ]

test('automatically plans a synthetic repeated merchant shadow sample', () => {
  const plan = buildExpressionShadowPlan({ transactions: repeatedApiMerchant, currentRecordId: 'd' })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.changes_user_output, false)
  assert.ok(plan.shared_modules.includes('deterministic-scoring'))
  assert.equal(plan.selected.length, 1)
  assert.equal(plan.selected[0].semantic_key, 'merchant_daily_count_total')
  assert.match(plan.selected[0].canonical_text, /4 笔/)
  assert.equal(plan.shortcut_plan.selected[0].selection_mode, 'threshold')
  assert.equal(plan.current_record.entity_id, 'merchant_unmapped_exampleapihub')
  assert.equal(plan.current_record.raw_merchant_name, 'Example API Hub')
  assert.equal(plan.current_record.merchant_observation.entity_first_seen, false)
  assert.equal(plan.current_record.merchant_observation.alias_first_seen, false)
  assert.deepEqual(
    plan.current_record.merchant_observation.observed_aliases.sort(),
    ['Example API Hub', 'ExampleAPIHub'].sort(),
  )
})

test('does not invent an insight from a single isolated expense', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{ id: 'only', transaction_date: '2026-07-13', amount: 14.98, merchant_name: '晚饭', status: 'done' }],
    currentRecordId: 'only',
  })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.selected.length, 0)
  assert.equal(plan.shortcut_plan.silent, true)
})
