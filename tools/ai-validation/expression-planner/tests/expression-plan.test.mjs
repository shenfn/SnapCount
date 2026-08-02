import test from 'node:test'
import assert from 'node:assert/strict'
import { buildExpressionPlans, buildSurfacePlan } from '../lib/expression-plan.mjs'

function candidate(id, semanticKey, claimType, subtype, scores) {
  return {
    candidate_id: id,
    dimension: semanticKey,
    claim_type: claimType,
    fact_subtype: subtype,
    claim: { semantic_key: semanticKey, canonical_text: semanticKey },
    scoring: { surfaces: Object.fromEntries(Object.entries(scores).map(([surface, score]) => [surface, {
      eligible: score !== null, score, passes_threshold: score !== null && score >= ({ shortcut_notification: 75, pwa_pending_ai_card: 65, record_detail: 45, weekly_report: 35 }[surface]),
    }])) },
  }
}

const daily = candidate('daily', 'merchant_daily_count_total', 'fact', 'aggregated', {
  shortcut_notification: 78, pwa_pending_ai_card: 84, record_detail: 90, weekly_report: 90,
})
const weekly = candidate('weekly', 'merchant_week_to_date_vs_previous_week_same_period', 'comparison', null, {
  shortcut_notification: 75.4, pwa_pending_ai_card: 81.4, record_detail: 87.4, weekly_report: 87.4,
})
const baseline = candidate('baseline', 'merchant_daily_vs_active_day_median', 'comparison', null, {
  shortcut_notification: 67.2, pwa_pending_ai_card: 73.2, record_detail: 79.2, weekly_report: 79.2,
})
const amounts = candidate('amounts', 'merchant_daily_amount_structure', 'fact', 'aggregated', {
  shortcut_notification: 56, pwa_pending_ai_card: 62, record_detail: 68, weekly_report: 68,
})

test('does not repeat the fixed daily summary in shortcut notification', () => {
  const plan = buildSurfacePlan([daily, weekly, baseline, amounts], 'shortcut_notification')
  assert.equal(plan.selected[0].candidate_id, 'weekly')
  assert.equal(plan.excluded.find(item => item.candidate_id === 'daily').reason, 'covered_by_fixed_content')
})

test('selects one primary candidate for the PWA pending AI card', () => {
  const plan = buildSurfacePlan([daily, weekly, baseline], 'pwa_pending_ai_card')
  assert.equal(plan.selected.length, 1)
  assert.equal(plan.selected[0].candidate_id, 'daily')
  assert.equal(plan.excluded.find(item => item.candidate_id === 'weekly').reason, 'surface_capacity_reached')
})

test('uses an exact fact fallback instead of silence when no candidate passes', () => {
  const lowFact = candidate('low-fact', 'merchant_daily_amount_structure', 'fact', 'aggregated', {
    shortcut_notification: 60, pwa_pending_ai_card: 60, record_detail: 60, weekly_report: 60,
  })
  const plan = buildSurfacePlan([lowFact], 'pwa_pending_ai_card')
  assert.equal(plan.fallback_used, true)
  assert.equal(plan.silent, false)
  assert.equal(plan.selected[0].selection_mode, 'exact_fact_fallback')
})

test('respects record detail capacity while retaining multiple angles', () => {
  const plans = buildExpressionPlans([daily, weekly, baseline, amounts])
  assert.deepEqual(plans.record_detail.selected.map(item => item.candidate_id), ['daily', 'weekly', 'baseline'])
  assert.equal(plans.record_detail.excluded.find(item => item.candidate_id === 'amounts').reason, 'surface_capacity_reached')
})
