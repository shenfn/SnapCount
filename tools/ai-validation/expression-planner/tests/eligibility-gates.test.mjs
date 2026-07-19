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

test('keeps a low-confidence temporal fact for record detail only', () => {
  const result = evaluateCandidateEligibility(candidate())
  assert.equal(result.eligibility.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.record_detail.eligible, true)
  assert.equal(result.eligibility.surface_eligibility.pwa_pending_ai_card.eligible, false)
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
      candidate_id: 'candidate-2', quality: { confidence: 0.95, data_coverage: 1, sample_count: 10 },
    })),
  ]
  const summary = summarizeEligibility(candidates)
  assert.equal(summary.claim_eligible, 2)
  assert.equal(summary.surface_eligible_counts.record_detail, 2)
  assert.equal(summary.surface_eligible_counts.shortcut_notification, 1)
})
