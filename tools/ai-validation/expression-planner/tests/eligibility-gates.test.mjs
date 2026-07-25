import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluateCandidateEligibility, summarizeEligibility } from '../lib/eligibility-gates.mjs'

function candidate(overrides = {}) {
  return {
    candidate_id: 'candidate-1',
    claim_type: 'fact',
    claim: { semantic_key: 'merchant_daily_activity_span', structured_value: { span_minutes: 630 } },
    evidence: [{ source_id: 'event-1' }],
    numbers: [{ value: 630, derivation: 'last-first' }],
    quality: { confidence: 0.55, data_coverage: 0.25, sample_count: 2 },
    ...overrides,
  }
}

test('keeps the old merchant activity window diagnostic-only', () => {
  const result = evaluateCandidateEligibility(candidate())
  assert.equal(result.eligibility.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.shortcut_notification.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.record_detail.blocked_reasons.includes('diagnostic_temporal_window_not_user_facing'))
})

test('shows a same-name recurrence interval only on the AI card and record detail', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim: {
      semantic_key: 'expense_record_name_previous_gap',
      structured_value: { elapsed_minutes: 120, match_basis: 'normalized_record_name_exact' },
    },
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 2 },
  }))
  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.shortcut_notification.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, false)
})

test('blocks a candidate without evidence at the claim level', () => {
  const result = evaluateCandidateEligibility(candidate({ evidence: [] }))
  assert.equal(result.eligibility.eligible, false)
  assert.deepEqual(result.eligibility.blocked_reasons, ['missing_evidence'])
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, false)
})

test('requires three active days for a personal median comparison', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim_type: 'comparison',
    claim: {
      semantic_key: 'merchant_daily_vs_active_day_median',
      structured_value: { baseline: { sample_days: 2 } },
    },
    quality: { confidence: 0.9, data_coverage: 1, sample_count: 2 },
  }))
  assert.equal(result.eligibility.eligible, false)
  assert.ok(result.eligibility.blocked_reasons.includes('insufficient_active_day_baseline'))
})

test('summarizes eligibility separately by surface', () => {
  const candidates = [
    evaluateCandidateEligibility(candidate()),
    evaluateCandidateEligibility(candidate({
      candidate_id: 'candidate-2',
      claim: {
        semantic_key: 'expense_record_name_previous_gap',
        structured_value: { elapsed_minutes: 120, match_basis: 'normalized_record_name_exact' },
      },
      quality: { confidence: 0.95, data_coverage: 1, sample_count: 2 },
    })),
  ]
  const summary = summarizeEligibility(candidates)
  assert.equal(summary.claim_eligible, 2)
  assert.equal(summary.surface_eligible_counts.record_detail, 1)
  assert.equal(summary.surface_eligible_counts.pwa_pending_ai_card, 1)
  assert.equal(summary.surface_eligible_counts.shortcut_notification, 0)
  assert.equal(summary.surface_eligible_counts.weekly_report, 0)
})

test('routes a period comparison only to its allowed summary surface', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim_type: 'comparison',
    selection_hints: {
      delivery_scope: 'period_summary',
      cadence_scope: 'calendar_week:2026-07-20',
      allowed_surfaces: ['weekly_report'],
      period_owner: true,
    },
    claim: {
      semantic_key: 'expense_category_week_to_date_vs_previous_week_same_period',
      structured_value: { current_period: { count: 8 }, baseline_period: { count: 7 } },
    },
    evidence: [{ source_id: 'current' }, { source_id: 'baseline' }],
    numbers: [{ value: 8 }, { value: 7 }],
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 15 },
  }))
  assert.equal(result.eligibility.surface_eligibility.shortcut_notification.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.shortcut_notification.blocked_reasons.includes('period_comparison_not_interruptive'))
  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.record_detail.blocked_reasons.includes('surface_outside_candidate_delivery_scope'))
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, true)
})

test('defaults period-summary delivery to weekly report when no surface list is provided', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim_type: 'comparison',
    selection_hints: {
      delivery_scope: 'period_summary',
      cadence_scope: 'calendar_week:2026-07-20',
      period_owner: true,
    },
    claim: {
      semantic_key: 'expense_category_week_to_date_vs_previous_week_same_period',
      structured_value: { current_period: { count: 8 }, baseline_period: { count: 7 } },
    },
    evidence: [{ source_id: 'current' }, { source_id: 'baseline' }],
    numbers: [{ value: 8 }, { value: 7 }],
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 15 },
  }))

  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, false)
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, true)
})

test('only the latest record owns a weekly report period comparison', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim_type: 'comparison',
    selection_hints: {
      delivery_scope: 'period_summary',
      cadence_scope: 'calendar_week:2026-07-20',
      allowed_surfaces: ['weekly_report'],
      period_owner: false,
    },
    claim: {
      semantic_key: 'merchant_week_to_date_vs_previous_week_same_period',
      structured_value: {
        current_period: { start: '2026-07-20', end: '2026-07-21', count: 2 },
        baseline_period: { start: '2026-07-13', end: '2026-07-14', count: 2 },
      },
    },
    evidence: [{ source_id: 'current' }, { source_id: 'baseline' }],
    numbers: [{ value: 2 }, { value: 2 }],
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 4 },
  }))
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.weekly_report.blocked_reasons.includes('period_surface_requires_latest_record'))
  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.pwa_pending_ai_card.blocked_reasons.includes('surface_outside_candidate_delivery_scope'))
})

test('per-record planning keeps a period candidate traceable without selecting it anywhere', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim_type: 'comparison',
    selection_hints: {
      delivery_scope: 'period_summary',
      cadence_scope: 'calendar_week:2026-07-20',
      allowed_surfaces: ['weekly_report'],
      period_owner: true,
    },
    claim: {
      semantic_key: 'merchant_week_to_date_vs_previous_week_same_period',
      structured_value: {
        current_period: { start: '2026-07-20', end: '2026-07-21', count: 2 },
        baseline_period: { start: '2026-07-13', end: '2026-07-14', count: 2 },
      },
    },
    evidence: [{ source_id: 'current' }, { source_id: 'baseline' }],
    numbers: [{ value: 2 }, { value: 2 }],
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 4 },
  }), { planningContext: 'record_event' })

  assert.equal(result.eligibility.eligible, true)
  assert.equal(Object.values(result.eligibility.surface_eligibility).some(surface => surface.eligible), false)
  assert.ok(result.eligibility.surface_eligibility.weekly_report.blocked_reasons.includes('period_report_requires_report_context'))
})

test('per-record planning never pretends to be a period report run', () => {
  const result = evaluateCandidateEligibility(candidate({
    claim: { semantic_key: 'merchant_daily_count_total', structured_value: { count: 2, total: 20 } },
    quality: { confidence: 0.95, data_coverage: 1, sample_count: 2 },
  }), { planningContext: 'record_event' })
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.weekly_report.eligible, false)
  assert.ok(result.eligibility.surface_eligibility.weekly_report.blocked_reasons.includes('period_report_requires_report_context'))
})
