import test from 'node:test'
import assert from 'node:assert/strict'
import { buildScoringPreferenceProfile, selectCurrentReviewSignals } from '../lib/preference-profile.mjs'
import { scoreCandidate } from '../lib/deterministic-scoring.mjs'

function candidate() {
  return {
    candidate_id: 'food-composition',
    dimension: 'record_composition',
    claim_type: 'fact',
    claim: { semantic_key: 'food_composition', structured_value: { dish_count: 2 } },
    quality: { confidence: 1, data_coverage: 1 },
    eligibility: {
      eligible: true,
      blocked_reasons: [],
      surface_eligibility: Object.fromEntries(['shortcut_notification', 'pwa_pending_ai_card', 'record_detail', 'weekly_report'].map(surface => [surface, { eligible: true, blocked_reasons: [] }])),
    },
  }
}

test('compiles semantic feedback into the score fields consumed by the scorer', () => {
  const profile = buildScoringPreferenceProfile([
    { surface: 'record_detail', semantic_key: 'food_composition', preference_dimension: 'semantic_preference', direction: 'decrease', strength: 0.2 },
    { surface: 'record_detail', semantic_key: 'food_composition', preference_dimension: 'semantic_preference', direction: 'decrease', strength: 0.2 },
    { surface: 'record_detail', preference_dimension: 'repetition_tolerance', direction: 'increase', strength: 0.1 },
  ], { asOf: '2026-07-23T00:00:00Z' })
  assert.equal(profile.profile_version, 'scoring-preference-profile-v0.2')
  assert.equal(profile.surface_semantic_weights.record_detail.food_composition, 0.74)
  assert.equal(profile.repetition_tolerance.record_detail, 1.035)
  const scored = scoreCandidate(candidate(), { preferenceProfile: profile })
  assert.equal(scored.scoring.surfaces.record_detail.user_preference, 0.74)
  assert.equal(scored.scoring.surfaces.shortcut_notification.user_preference, 1)
})

test('ignores legacy reviews and reviews attached to non-detail exposures', () => {
  const feedbackRows = [
    { feedback_key: 'current-detail', source_review_schema: 'record-feedback-v1', exposure_event_id: 'detail-1' },
    { feedback_key: 'wrong-surface', source_review_schema: 'record-feedback-v1', exposure_event_id: 'shortcut-1' },
    { feedback_key: 'legacy', source_review_schema: 'legacy-v0', exposure_event_id: 'detail-2' },
  ]
  const signalRows = [
    { feedback_key: 'current-detail', semantic_key: 'food_composition' },
    { feedback_key: 'wrong-surface', semantic_key: 'sleep_current_metric' },
    { feedback_key: 'legacy', semantic_key: 'merchant_week_to_date_vs_previous_week_same_period' },
  ]
  const selected = selectCurrentReviewSignals(feedbackRows, signalRows, [
    { id: 'detail-1', surface: 'record_detail' },
    { id: 'shortcut-1', surface: 'shortcut_notification' },
    { id: 'detail-2', surface: 'record_detail' },
  ])
  assert.deepEqual(selected.feedbackRows.map(row => row.feedback_key), ['current-detail'])
  assert.deepEqual(selected.signalRows.map(row => row.feedback_key), ['current-detail'])
})
