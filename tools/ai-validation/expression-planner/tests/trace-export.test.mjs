import test from 'node:test'
import assert from 'node:assert/strict'
import { buildExpressionSummary, buildExpressionTrace } from '../lib/trace-export.mjs'

const snapshot = {
  generated_at: '2026-07-13T00:00:00.000Z',
  read_only: true,
  input: { asOf: '2026-07-12T23:59:59+08:00' },
  data_boundary: {
    user_id: 'user-1', as_of: '2026-07-12T23:59:59+08:00', future_profile_used: false,
  },
  entity_filter: { entity_id: 'merchant_example_api_hub', canonical_name: 'Example API Hub' },
  recognition_ledger: {
    summary: { total_events: 2, fact_eligible_events: 2, status_counts: { user_confirmed_distinct: 1, confirmed_transaction: 1 } },
    events: [
      { event_id: '1', ledger_status: 'user_confirmed_distinct', count_in_facts: true, event_time_source: 'known_at_proxy', override: { source: 'user_review' } },
      { event_id: '2', ledger_status: 'confirmed_transaction', count_in_facts: true, event_time_source: 'occurred_at' },
    ],
  },
  comparison_candidates: [
    { candidate_id: 'comparison-1', claim_type: 'comparison', dimension: 'personal_baseline', eligibility: { eligible: true } },
  ],
  records: [{ id: 'record-1' }],
  eligibility_summary: { total_candidates: 2, claim_eligible: 2, claim_blocked: 0 },
  scoring_context: { preference_profile_source: 'neutral_default', exposure_history_source: 'empty_baseline' },
  expression_plans: { pwa_pending_ai_card: { selected: [{ candidate_id: 'fact-1' }] } },
  render_plans: { pwa_pending_ai_card: { selected: [{ candidate_id: 'fact-1' }], render_state: 'rendered_preview', simulation_only: true } },
  exposure_events: [{ candidate_id: 'fact-1', lifecycle_state: 'rendered_preview', simulation_only: true, counts_for_novelty: false }],
  expression_plan_summary: { pwa_pending_ai_card: { capacity: 1, selected_count: 1, fallback_used: false, silent: false } },
  scoring_summary: {
    pwa_pending_ai_card: { threshold: 65, eligible_count: 2, passing_count: 1, ranking: [{ candidate_id: 'fact-1', score: 80 }] },
  },
  fact_candidates: [
    { candidate_id: 'fact-1', claim_type: 'fact', dimension: 'daily_aggregation', eligibility: { eligible: true } },
  ],
  audit: {},
  confirmed_record_summaries: {},
}

test('builds a trace-console compatible expression trace', () => {
  const trace = buildExpressionTrace(snapshot)
  assert.equal(trace.status, 'done')
  assert.equal(trace.steps.length, 7)
  assert.deepEqual(trace.steps[0].artifact_refs, ['event_ledger', 'event_ledger_summary'])
  assert.equal(trace.steps[1].output_snapshot.eligible_count, 1)
  assert.equal(trace.artifacts.event_ledger.length, 2)
  assert.equal(trace.steps[2].step_id, 'comparison_candidate_generate')
  assert.equal(trace.artifacts.comparison_candidates.length, 1)
  assert.equal(trace.steps[3].step_id, 'candidate_eligibility_evaluate')
  assert.equal(trace.artifacts.eligibility_summary.claim_eligible, 2)
  assert.equal(trace.steps[4].step_id, 'candidate_deterministic_score')
  assert.equal(trace.artifacts.scoring_summary.pwa_pending_ai_card.passing_count, 1)
  assert.equal(trace.steps[5].step_id, 'expression_plan_build')
  assert.equal(trace.artifacts.expression_plans.pwa_pending_ai_card.selected.length, 1)
  assert.equal(trace.steps[6].step_id, 'surface_render_contract_apply')
  assert.equal(trace.artifacts.render_plans.pwa_pending_ai_card.simulation_only, true)
  assert.equal(trace.artifacts.exposure_events[0].counts_for_novelty, false)
  assert.match(trace.run_id, /^expression-planner-20260712-/)
})

test('builds a one-case run summary', () => {
  const summary = buildExpressionSummary(buildExpressionTrace(snapshot))
  assert.equal(summary.total_cases, 1)
  assert.equal(summary.success_cases, 1)
  assert.equal(summary.capture_kind, 'historical-replay')
})
