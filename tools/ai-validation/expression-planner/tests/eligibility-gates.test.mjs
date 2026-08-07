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
  assert.equal(result.eligibility.materiality, null)
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

function merchantBaselineCandidate({
  currentCount = 1,
  baselineCount = 1,
  currentTotal = 10.33,
  baselineTotal = 10,
  includeDelta = true,
} = {}) {
  const countDelta = currentCount - baselineCount
  const totalDelta = Math.round((currentTotal - baselineTotal) * 100) / 100
  const totalPercent = baselineTotal === 0
    ? null
    : Math.round(((currentTotal - baselineTotal) / baselineTotal) * 10000) / 100
  return candidate({
    claim_type: 'comparison',
    claim: {
      semantic_key: 'merchant_daily_vs_active_day_median',
      structured_value: {
        current: { count: currentCount, total: currentTotal },
        baseline: { sample_days: 5, count: baselineCount, total: baselineTotal },
        ...(includeDelta ? { delta: { count: countDelta, total: totalDelta, total_percent: totalPercent } } : {}),
      },
    },
    quality: { confidence: 0.9, data_coverage: 1, sample_count: 5 },
  })
}

test('keeps a near-identical merchant baseline in telemetry but blocks every user-facing surface', () => {
  const result = evaluateCandidateEligibility(merchantBaselineCandidate())

  assert.equal(result.eligibility.eligible, true)
  assert.deepEqual(result.eligibility.blocked_reasons, [])
  assert.deepEqual(result.eligibility.materiality, {
    evaluated: true,
    passes: false,
    policy_version: 'merchant-active-day-materiality-v0.1',
    reason: 'difference_below_materiality_threshold',
  })
  for (const decision of Object.values(result.eligibility.surface_eligibility)) {
    assert.equal(decision.eligible, false)
    assert.ok(decision.blocked_reasons.includes('difference_below_materiality_threshold'))
  }
})

test('applies merchant baseline materiality boundaries symmetrically', () => {
  const cases = [
    { name: 'positive count boundary', input: { currentCount: 2, baselineCount: 1 }, passes: true },
    { name: 'negative count boundary', input: { currentCount: 1, baselineCount: 2 }, passes: true },
    { name: 'half-count median difference', input: { currentCount: 2, baselineCount: 1.5 }, passes: false },
    { name: 'positive strong amount boundary', input: { currentTotal: 1020, baselineTotal: 1000 }, passes: true },
    { name: 'negative strong amount boundary', input: { currentTotal: 980, baselineTotal: 1000 }, passes: true },
    { name: 'combined absolute and relative boundary', input: { currentTotal: 38.33, baselineTotal: 33.33 }, passes: true },
    { name: 'five-yuan floating-point boundary', input: { currentTotal: 8.04, baselineTotal: 3.04 }, passes: true },
    { name: 'twenty-yuan floating-point boundary', input: { currentTotal: 256.02, baselineTotal: 236.02 }, passes: true },
    { name: 'large percentage at 4.99 absolute delta', input: { currentTotal: 5.49, baselineTotal: 0.5 }, passes: false },
    { name: 'absolute change below strong floor and relative floor', input: { currentTotal: 219.99, baselineTotal: 200 }, passes: false },
    { name: 'ten percent change', input: { currentTotal: 110, baselineTotal: 100 }, passes: false },
    { name: 'zero baseline below strong floor', input: { currentTotal: 5, baselineTotal: 0 }, passes: false },
    { name: 'zero baseline at strong floor', input: { currentTotal: 20, baselineTotal: 0 }, passes: true },
  ]

  for (const item of cases) {
    const result = evaluateCandidateEligibility(merchantBaselineCandidate(item.input))
    assert.equal(result.eligibility.materiality.passes, item.passes, item.name)
    assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, item.passes, item.name)
  }
})

test('derives materiality from finite source metrics instead of trusting redundant deltas', () => {
  const withoutDelta = evaluateCandidateEligibility(merchantBaselineCandidate({ includeDelta: false }))
  assert.equal(withoutDelta.eligibility.materiality.reason, 'difference_below_materiality_threshold')

  const inconsistentDelta = merchantBaselineCandidate()
  inconsistentDelta.claim.structured_value.delta = { count: 99, total: 999, total_percent: 9999 }
  const inconsistentResult = evaluateCandidateEligibility(inconsistentDelta)
  assert.equal(inconsistentResult.eligibility.materiality.reason, 'difference_below_materiality_threshold')
  assert.equal(inconsistentResult.eligibility.surface_eligibility.record_detail.eligible, false)
})

test('blocks a merchant baseline with incomplete source metrics under a distinct reason', () => {
  const invalidCandidates = [
    { path: ['current', 'count'], value: Number.NaN },
    { path: ['current', 'total'], value: Number.NaN },
    { path: ['baseline', 'count'], value: Number.NaN },
    { path: ['baseline', 'total'], value: Number.NaN },
    { path: ['current', 'total'], remove: true },
  ]

  for (const item of invalidCandidates) {
    const invalid = merchantBaselineCandidate()
    const target = invalid.claim.structured_value[item.path[0]]
    if (item.remove) delete target[item.path[1]]
    else target[item.path[1]] = item.value
    const result = evaluateCandidateEligibility(invalid)

    assert.equal(result.eligibility.eligible, true)
    assert.equal(result.eligibility.materiality.reason, 'missing_materiality_metrics')
    assert.ok(result.eligibility.surface_eligibility.record_detail.blocked_reasons.includes('missing_materiality_metrics'))
    assert.equal(result.eligibility.surface_eligibility.record_detail.blocked_reasons.includes('difference_below_materiality_threshold'), false)
  }
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
