import test from 'node:test'
import assert from 'node:assert/strict'
import { buildExposureEvents, buildRenderPlans, compileExposureHistory } from '../lib/render-contract.mjs'

const candidates = [{
  candidate_id: 'weekly',
  claim_type: 'comparison',
  dimension: 'period_comparison',
  claim: { semantic_key: 'merchant_week_to_date_vs_previous_week_same_period', structured_value: { total: 251 }, canonical_text: '本周高于上周同期' },
}]
const plans = {
  shortcut_notification: {
    selected: [{ candidate_id: 'weekly', semantic_key: 'merchant_week_to_date_vs_previous_week_same_period', claim_type: 'comparison', dimension: 'period_comparison', score: 75.4, selection_mode: 'threshold' }],
  },
}

test('projects selected candidates through a surface render contract', () => {
  const render = buildRenderPlans(plans, candidates).shortcut_notification
  assert.equal(render.surface_kind, 'external_notification')
  assert.ok(render.selected[0].visible_field_paths.includes('rendered_feedback.emotion_line'))
  assert.ok(render.selected[0].persisted_only_field_paths.includes('rendered_feedback.detail_reason'))
  assert.equal(render.simulation_only, true)
})

test('historical replay previews never count as real exposure', () => {
  const renderPlans = buildRenderPlans(plans, candidates)
  const events = buildExposureEvents(renderPlans, { traceId: 'trace-1', occurredAt: '2026-07-12T23:59:59+08:00' })
  assert.equal(events[0].lifecycle_state, 'rendered_preview')
  assert.equal(events[0].counts_for_novelty, false)
  assert.deepEqual(compileExposureHistory(events), {})
})

test('confirmed delivery events compile into novelty history', () => {
  const events = [{
    semantic_key: 'merchant_daily_count_total', lifecycle_state: 'returned_to_shortcut',
    simulation_only: false, counts_for_novelty: true, occurred_at: '2026-07-12T20:00:00+08:00',
  }]
  assert.deepEqual(compileExposureHistory(events), {
    merchant_daily_count_total: { count: 1, last_shown_at: '2026-07-12T20:00:00+08:00' },
  })
})
