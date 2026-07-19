import test from 'node:test'
import assert from 'node:assert/strict'
import { scoreCandidate, summarizeScores } from '../lib/deterministic-scoring.mjs'

function candidate(overrides = {}) {
  return {
    candidate_id: 'daily-total',
    dimension: 'daily_aggregation',
    claim_type: 'fact',
    claim: { semantic_key: 'merchant_daily_count_total', structured_value: { entity_id: 'merchant_qlhazycoder' } },
    quality: { confidence: 1, data_coverage: 1 },
    eligibility: {
      eligible: true,
      blocked_reasons: [],
      surface_eligibility: {
        shortcut_notification: { eligible: true, blocked_reasons: [] },
        pwa_pending_ai_card: { eligible: true, blocked_reasons: [] },
        record_detail: { eligible: true, blocked_reasons: [] },
        weekly_report: { eligible: true, blocked_reasons: [] },
      },
    },
    ...overrides,
  }
}

test('scores a new precise daily fact above notification threshold', () => {
  const result = scoreCandidate(candidate(), { context: { entity_id: 'merchant_qlhazycoder' } })
  assert.equal(result.scoring.surfaces.shortcut_notification.score, 78)
  assert.equal(result.scoring.surfaces.shortcut_notification.passes_threshold, true)
  assert.equal(result.scoring.components.novelty, 1)
})

test('allows occasional repetition but lowers its score deterministically', () => {
  const result = scoreCandidate(candidate(), {
    context: { entity_id: 'merchant_qlhazycoder' },
    exposureHistory: { merchant_daily_count_total: { count: 1, last_shown_at: '2026-07-12T12:00:00+08:00' } },
  })
  assert.equal(result.scoring.components.novelty, 0.92)
  assert.equal(result.scoring.components.repetition_penalty, 2)
  assert.equal(result.scoring.surfaces.record_detail.score, 80.8)
})

test('applies explicit user preference without exceeding bounded multipliers', () => {
  const result = scoreCandidate(candidate(), {
    preferenceProfile: { dimension_weights: { daily_aggregation: 2 } },
  })
  assert.equal(result.scoring.components.user_preference, 1.2)
  assert.equal(result.scoring.surfaces.record_detail.score, 100)
})

test('does not score a surface rejected by eligibility gates', () => {
  const base = candidate()
  base.eligibility.surface_eligibility.shortcut_notification = { eligible: false, blocked_reasons: ['low_confidence'] }
  const result = scoreCandidate(base)
  assert.equal(result.scoring.surfaces.shortcut_notification.score, null)
  assert.equal(result.scoring.surfaces.shortcut_notification.passes_threshold, false)
})

test('summarizes ranked candidates per surface', () => {
  const high = scoreCandidate(candidate())
  const low = scoreCandidate(candidate({
    candidate_id: 'amounts',
    claim: { semantic_key: 'merchant_daily_amount_structure', structured_value: { entity_id: 'merchant_qlhazycoder' } },
  }))
  const summary = summarizeScores([low, high])
  assert.equal(summary.pwa_pending_ai_card.ranking[0].candidate_id, 'daily-total')
  assert.equal(summary.pwa_pending_ai_card.passing_count, 1)
})


test('applies surface-specific semantic preference only to the matching surface', () => {
  const result = scoreCandidate(candidate(), {
    preferenceProfile: {
      surface_semantic_weights: {
        shortcut_notification: { merchant_daily_count_total: 0.8 },
      },
    },
  })
  assert.equal(result.scoring.components.user_preference, 1)
  assert.equal(result.scoring.surfaces.shortcut_notification.user_preference, 0.8)
  assert.equal(result.scoring.surfaces.shortcut_notification.score, 60)
  assert.equal(result.scoring.surfaces.record_detail.user_preference, 1)
  assert.equal(result.scoring.surfaces.record_detail.score, 90)
})
