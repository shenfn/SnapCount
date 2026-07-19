export const SURFACE_RULES = {
  shortcut_notification: { min_confidence: 0.8, min_data_coverage: 0.75 },
  pwa_pending_ai_card: { min_confidence: 0.7, min_data_coverage: 0.5 },
  record_detail: { min_confidence: 0.5, min_data_coverage: 0.2 },
  weekly_report: { min_confidence: 0.6, min_data_coverage: 0.5 },
}

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

function hardGate(candidate) {
  const reasons = []
  if (!candidate?.claim?.semantic_key) reasons.push('missing_semantic_key')
  if (!candidate?.claim?.structured_value || typeof candidate.claim.structured_value !== 'object') reasons.push('missing_structured_value')
  if (!Array.isArray(candidate?.evidence) || candidate.evidence.length === 0) reasons.push('missing_evidence')
  if (!Array.isArray(candidate?.numbers) || candidate.numbers.length === 0) reasons.push('missing_numeric_derivation')
  if (!finiteNumber(candidate?.quality?.confidence)) reasons.push('missing_confidence')
  if (!finiteNumber(candidate?.quality?.data_coverage)) reasons.push('missing_data_coverage')

  if (candidate?.claim?.semantic_key === 'merchant_daily_vs_active_day_median') {
    const sampleDays = candidate.claim.structured_value?.baseline?.sample_days
    if (!finiteNumber(sampleDays) || sampleDays < 3) reasons.push('insufficient_active_day_baseline')
  }

  if (candidate?.claim?.semantic_key === 'merchant_week_to_date_vs_previous_week_same_period') {
    const current = candidate.claim.structured_value?.current_period
    const baseline = candidate.claim.structured_value?.baseline_period
    if (!current?.start || !current?.end || !baseline?.start || !baseline?.end) reasons.push('missing_comparison_window')
    if (!finiteNumber(current?.count) || current.count < 1 || !finiteNumber(baseline?.count) || baseline.count < 1) {
      reasons.push('empty_comparison_period')
    }
  }

  return reasons
}

function surfaceDecision(candidate, surface, rule, hardBlocked) {
  const reasons = [...hardBlocked]
  const confidence = candidate.quality?.confidence ?? 0
  const coverage = candidate.quality?.data_coverage ?? 0
  if (confidence < rule.min_confidence) reasons.push('confidence_below_surface_threshold')
  if (coverage < rule.min_data_coverage) reasons.push('data_coverage_below_surface_threshold')

  if (candidate.claim_type === 'comparison' && surface === 'shortcut_notification') {
    const sampleCount = candidate.quality?.sample_count ?? 0
    if (sampleCount < 7) reasons.push('comparison_sample_too_small_for_interruptive_surface')
  }

  return { eligible: reasons.length === 0, blocked_reasons: [...new Set(reasons)] }
}

export function evaluateCandidateEligibility(candidate) {
  const hardBlocked = hardGate(candidate)
  const surfaceEligibility = Object.fromEntries(
    Object.entries(SURFACE_RULES).map(([surface, rule]) => [surface, surfaceDecision(candidate, surface, rule, hardBlocked)]),
  )
  return {
    ...candidate,
    eligibility: {
      eligible: hardBlocked.length === 0,
      blocked_reasons: hardBlocked,
      surface_eligibility: surfaceEligibility,
    },
  }
}

export function evaluateCandidates(candidates) {
  return candidates.map(evaluateCandidateEligibility)
}

export function summarizeEligibility(candidates) {
  const surfaces = Object.keys(SURFACE_RULES)
  return {
    total_candidates: candidates.length,
    claim_eligible: candidates.filter(candidate => candidate.eligibility?.eligible).length,
    claim_blocked: candidates.filter(candidate => !candidate.eligibility?.eligible).length,
    surface_eligible_counts: Object.fromEntries(surfaces.map(surface => [
      surface,
      candidates.filter(candidate => candidate.eligibility?.surface_eligibility?.[surface]?.eligible).length,
    ])),
  }
}
