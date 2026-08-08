import test from 'node:test'
import assert from 'node:assert/strict'
import { scoreCandidate, summarizeScores } from '../lib/deterministic-scoring.mjs'

function candidate(overrides = {}) {
  return {
    candidate_id: 'daily-total',
    dimension: 'daily_aggregation',
    claim_type: 'fact',
    claim: { semantic_key: 'merchant_daily_count_total', structured_value: { entity_id: 'merchant_fixture_alpha' } },
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
  const result = scoreCandidate(candidate(), { context: { entity_id: 'merchant_fixture_alpha' } })
  assert.equal(result.scoring.surfaces.shortcut_notification.score, 78)
  assert.equal(result.scoring.surfaces.shortcut_notification.passes_threshold, true)
  assert.equal(result.scoring.components.novelty, 1)
})

test('keeps first occurrence importance between history insights and record context fallback', () => {
  const firstOccurrence = scoreCandidate(candidate({
    candidate_id: 'first-occurrence',
    dimension: 'first_occurrence',
    claim: { semantic_key: 'expense_merchant_first_occurrence', structured_value: { entity_id: 'merchant_fixture_alpha' } },
  }))
  const recurrence = scoreCandidate(candidate({
    candidate_id: 'recurrence',
    dimension: 'repeat_interval',
    claim: { semantic_key: 'expense_record_name_previous_gap', structured_value: { entity_id: 'merchant_fixture_alpha' } },
  }))
  const baseline = scoreCandidate(candidate({
    candidate_id: 'baseline',
    dimension: 'personal_baseline',
    claim: { semantic_key: 'merchant_daily_vs_active_day_median', structured_value: { entity_id: 'merchant_fixture_alpha' } },
  }))
  const recordContext = scoreCandidate(candidate({
    candidate_id: 'record-context',
    dimension: 'record_context',
    claim: { semantic_key: 'expense_current_record_context', structured_value: { entity_id: 'merchant_fixture_alpha' } },
  }))

  assert.equal(firstOccurrence.scoring.components.importance, 0.8)
  assert.ok(baseline.scoring.surfaces.record_detail.score > firstOccurrence.scoring.surfaces.record_detail.score)
  assert.ok(recurrence.scoring.surfaces.record_detail.score > firstOccurrence.scoring.surfaces.record_detail.score)
  assert.ok(firstOccurrence.scoring.surfaces.record_detail.score > recordContext.scoring.surfaces.record_detail.score)
})

test('allows occasional repetition but lowers its score deterministically', () => {
  const result = scoreCandidate(candidate(), {
    context: { entity_id: 'merchant_fixture_alpha' },
    exposureHistory: { 'record_detail:merchant_daily_count_total': { count: 1, last_shown_at: '2026-07-12T12:00:00+08:00' } },
  })
  assert.equal(result.scoring.components.novelty, 1)
  assert.equal(result.scoring.exposure_by_surface.record_detail.count, 1)
  assert.equal(result.scoring.surfaces.record_detail.novelty, 0.92)
  assert.equal(result.scoring.surfaces.record_detail.score, 80.8)
  assert.equal(result.scoring.surfaces.shortcut_notification.score, 78)
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
    claim: { semantic_key: 'merchant_daily_amount_structure', structured_value: { entity_id: 'merchant_fixture_alpha' } },
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

test('uses a stable period exposure key instead of a global semantic count', () => {
  const scoped = candidate({
    selection_hints: { exposure_key: 'expense:merchant:merchant_fixture_alpha:week_to_date:2026-07-20' },
  })
  const result = scoreCandidate(scoped, {
    exposureHistory: {
      merchant_daily_count_total: { count: 5, last_shown_at: '2026-07-23T12:00:00+08:00' },
      'record_detail:expense:merchant:merchant_fixture_alpha:week_to_date:2026-07-20': { count: 1, last_shown_at: '2026-07-22T12:00:00+08:00' },
    },
  })
  assert.equal(result.scoring.exposure.exposure_key, 'expense:merchant:merchant_fixture_alpha:week_to_date:2026-07-20')
  assert.equal(result.scoring.exposure.count, 0)
  assert.equal(result.scoring.exposure_by_surface.record_detail.count, 1)
  assert.equal(result.scoring.surfaces.record_detail.novelty, 0.92)
  assert.equal(result.scoring.exposure_by_surface.shortcut_notification.count, 0)
})

test('accepts the legacy rendering preference snapshot shape while new profiles migrate', () => {
  const result = scoreCandidate(candidate(), {
    preferenceProfile: { rendering_preferences: { 'record_detail:semantic_preference': 0.8 } },
  })
  assert.equal(result.scoring.surfaces.record_detail.user_preference, 0.8)
})
