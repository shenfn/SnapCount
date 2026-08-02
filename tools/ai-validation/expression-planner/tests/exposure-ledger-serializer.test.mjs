import test from 'node:test'
import assert from 'node:assert/strict'
import { buildExposureEvents, buildRenderPlans } from '../lib/render-contract.mjs'
import { toProductionExposureRows } from '../lib/exposure-ledger-serializer.mjs'

const candidate = {
  candidate_id: 'weekly', claim_type: 'comparison', dimension: 'period_comparison',
  claim: { semantic_key: 'merchant_week_to_date_vs_previous_week_same_period', structured_value: {}, canonical_text: '周比较' },
}
const expressionPlans = {
  shortcut_notification: {
    plan_version: 'expression-plan-v0.1',
    selected: [{ candidate_id: 'weekly', semantic_key: candidate.claim.semantic_key, claim_type: 'comparison', dimension: 'period_comparison', score: 75.4, selection_mode: 'threshold' }],
  },
}

test('rejects replay preview events from production inserts', () => {
  const preview = buildExposureEvents(buildRenderPlans(expressionPlans, [candidate]), { traceId: 'trace-1' })
  assert.throws(() => toProductionExposureRows(preview, {
    userId: '00000000-0000-4000-8000-000000000001', deliveryAttemptId: 'attempt-1',
  }), /Simulation exposure cannot be serialized/)
})

test('serializes a real shortcut delivery into an append-only row', () => {
  const renderPlans = buildRenderPlans(expressionPlans, [candidate])
  const delivered = buildExposureEvents(renderPlans, {
    traceId: 'trace-1', occurredAt: '2026-07-12T20:00:00+08:00', simulationOnly: false,
  })
  const rows = toProductionExposureRows(delivered, {
    userId: '00000000-0000-4000-8000-000000000001',
    deliveryAttemptId: 'attempt-1', traceId: 'trace-1', aiLogId: '00000000-0000-4000-8000-000000000002',
    recordType: 'expense', entityId: 'merchant_example_api_hub',
  })
  assert.equal(rows[0].lifecycle_state, 'returned_to_shortcut')
  assert.equal(rows[0].simulation_only, false)
  assert.equal(rows[0].counts_for_novelty, true)
  assert.equal(rows[0].event_key, 'attempt-1:shortcut_notification:weekly:returned_to_shortcut')
})
