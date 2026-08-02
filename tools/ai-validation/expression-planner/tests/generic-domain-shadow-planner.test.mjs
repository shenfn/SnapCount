import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({ entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'], bundle: true, platform: 'node', format: 'esm', write: false })
const { buildExpressionShadowPlan, buildGenericExpressionShadowPlan } = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64'))

test('income planner recognizes fixed notification coverage and keeps richer plans for details', () => {
  const records = [
    { id: 'i1', occurred_at: '2026-07-01T12:00:00+08:00', amount: 1000, source_name: '项目款' },
    { id: 'i2', occurred_at: '2026-07-13T12:00:00+08:00', amount: 500, source_name: '项目款' },
  ]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'income', records, currentRecordId: 'i2' })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.domain_key, 'income')
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_month_total_count'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_source_month_pattern'))
  assert.equal(plan.shortcut_plan.silent, true)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('sleep planner creates a personal median comparison from history', () => {
  const records = [6, 7, 7.5, 8, 5.5, 6.5, 7, 8.5].map((hours, index) => ({
    id: 's' + index, occurred_at: `2026-07-${String(index + 1).padStart(2, '0')}T08:00:00+08:00`, payload: { sleep_hours: hours },
  }))
  records.push({ id: 'current', occurred_at: '2026-07-13T08:00:00+08:00', payload: { sleep_hours: 5 } })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records, currentRecordId: 'current' })
  const comparison = plan.candidates.find(item => item.claim.semantic_key === 'sleep_vs_personal_median')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.sample_count, 8)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('food planner reads the production total_calorie_kcal field', () => {
  const records = [{
    id: 'food-current',
    occurred_at: '2026-07-14T19:00:00+08:00',
    payload: { total_calorie_kcal: 638, meal_type: 'dinner' },
  }]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records, currentRecordId: 'food-current' })
  const fact = plan.candidates.find(item => item.claim.semantic_key === 'food_current_metric')
  assert.ok(fact)
  assert.equal(fact.claim.structured_value.value, 638)
  assert.equal(fact.claim.structured_value.unit, '千卡')
})

test('food planner exposes context and composition instead of only calories', () => {
  const history = [1, 2, 3].map((index) => ({
    id: `food-${index}`,
    occurred_at: `2026-07-${String(index).padStart(2, '0')}T19:00:00+08:00`,
    payload: { total_calorie_kcal: 600 + index, meal_type: 'dinner', dishes: [{ name: '鸡腿饭', protein_g: 25, carb_g: 50, fat_g: 18 }] },
  }))
  const current = {
    id: 'food-current-rich',
    occurred_at: '2026-07-14T19:00:00+08:00',
    payload: {
      total_calorie_kcal: 638,
      meal_type: 'dinner',
      time_context: '晚间',
      dishes: [{ name: '鸡腿饭', protein_g: 25, carb_g: 50, fat_g: 18 }],
    },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records: [...history, current], currentRecordId: current.id })
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'food_record_context'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'food_composition'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'food_meal_vs_personal_median'))
  assert.equal(plan.candidates.find(item => item.claim.semantic_key === 'food_composition').dimension, 'record_composition')
})

test('food planner compares against the matching meal profile', () => {
  const current = { id: 'food-profile-current', occurred_at: '2026-07-14T19:00:00+08:00', payload: { total_calorie_kcal: 638, meal_type: 'dinner' } }
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'food', records: [current], currentRecordId: current.id,
    domainProfile: { meal_baseline: { dinner: { n: 11, median_kcal: 750 } } },
  })
  const comparison = plan.candidates.find(item => item.claim.semantic_key === 'food_meal_vs_personal_median')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.median, 750)
  assert.equal(comparison.claim.structured_value.baseline_source, 'domain_profile')
})

test('sleep planner exposes timing, quality, and stage facts', () => {
  const records = [1, 2, 3].map((index) => ({
    id: `sleep-${index}`,
    occurred_at: `2026-07-${String(index).padStart(2, '0')}T08:00:00+08:00`,
    payload: { sleep_hours: 7, quality_score: 80, sleep_start_at: `2026-07-${String(index).padStart(2, '0')}T00:30:00+08:00`, wake_at: `2026-07-${String(index).padStart(2, '0')}T07:30:00+08:00` },
  }))
  const current = {
    id: 'sleep-current-rich',
    occurred_at: '2026-07-14T08:00:00+08:00',
    payload: {
      sleep_hours: 7.18,
      quality_score: 82,
      sleep_start_at: '2026-07-14T01:10:00+08:00',
      wake_at: '2026-07-14T08:20:00+08:00',
      deep_sleep_minutes: 90,
      light_sleep_minutes: 240,
      rem_minutes: 100,
    },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records: [...records, current], currentRecordId: current.id })
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'sleep_timing'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'sleep_quality_current'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'sleep_stage_composition'))
})

test('sleep planner uses the domain profile for a timing comparison', () => {
  const current = {
    id: 'sleep-profile-current',
    occurred_at: '2026-07-14T08:00:00+08:00',
    payload: { sleep_hours: 7, sleep_start_at: '2026-07-14T02:00:00+08:00', wake_at: '2026-07-14T08:00:00+08:00' },
  }
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'sleep', records: [current], currentRecordId: current.id,
    domainProfile: { chronotype: { typical_sleep_start: '00:40', typical_wake: '07:30', n: 12 } },
  })
  const timing = plan.candidates.find(item => item.claim.semantic_key === 'sleep_timing_vs_typical')
  assert.ok(timing)
  assert.equal(timing.claim.structured_value.sleep_start_delta_minutes, 80)
  assert.equal(timing.claim.structured_value.wake_delta_minutes, 30)
})

test('expense planner normalizes legacy category aliases without changing raw records', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{
      id: 'expense-current', transaction_date: '2026-07-14', transaction_time: '18:00:00',
      amount: 30, merchant_name: '社区药房', category: '医疗', status: 'done',
    }],
    currentRecordId: 'expense-current',
  })
  assert.equal(plan.current_record.category, 'health')
})
