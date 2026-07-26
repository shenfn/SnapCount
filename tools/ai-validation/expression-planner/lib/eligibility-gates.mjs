export const SURFACE_RULES = {
  shortcut_notification: { min_confidence: 0.8, min_data_coverage: 0.75 },
  pwa_pending_ai_card: { min_confidence: 0.7, min_data_coverage: 0.5 },
  record_detail: { min_confidence: 0.5, min_data_coverage: 0.2 },
  weekly_report: { min_confidence: 0.6, min_data_coverage: 0.5 },
}

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

function allowedSurfacesFor(candidate) {
  const configured = candidate.selection_hints?.allowed_surfaces
  if (Array.isArray(configured)) return configured
  if (candidate.selection_hints?.delivery_scope === 'period_summary') return ['weekly_report']
  return null
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

function surfaceDecision(candidate, surface, rule, hardBlocked, planningContext) {
  const reasons = [...hardBlocked]
  const confidence = candidate.quality?.confidence ?? 0
  const coverage = candidate.quality?.data_coverage ?? 0
  if (confidence < rule.min_confidence) reasons.push('confidence_below_surface_threshold')
  if (coverage < rule.min_data_coverage) reasons.push('data_coverage_below_surface_threshold')

  const allowedSurfaces = allowedSurfacesFor(candidate)
  if (Array.isArray(allowedSurfaces) && !allowedSurfaces.includes(surface)) {
    reasons.push('surface_outside_candidate_delivery_scope')
  }

  if (candidate.claim_type === 'comparison' && surface === 'shortcut_notification') {
    reasons.push('period_comparison_not_interruptive')
  }

  if (candidate.claim_type === 'comparison' && surface === 'weekly_report' && candidate.selection_hints?.period_owner === false) {
    reasons.push('period_surface_requires_latest_record')
  }

  if (surface === 'weekly_report' && planningContext === 'record_event') {
    reasons.push('period_report_requires_report_context')
  }

  if (candidate.claim?.semantic_key === 'merchant_daily_activity_span') {
    reasons.push('diagnostic_temporal_window_not_user_facing')
  }

  if (candidate.claim?.semantic_key === 'expense_record_name_previous_gap') {
    if (surface === 'shortcut_notification') reasons.push('repeat_interval_not_interruptive')
    if (surface === 'weekly_report') reasons.push('record_level_fact_not_weekly_summary')
  }

  return { eligible: reasons.length === 0, blocked_reasons: [...new Set(reasons)] }
}

export function evaluateCandidateEligibility(candidate, { planningContext = 'surface_preview' } = {}) {
  const hardBlocked = hardGate(candidate)
  const surfaceEligibility = Object.fromEntries(
    Object.entries(SURFACE_RULES).map(([surface, rule]) => [surface, surfaceDecision(candidate, surface, rule, hardBlocked, planningContext)]),
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

export function evaluateCandidates(candidates, options = {}) {
  return candidates.map(candidate => evaluateCandidateEligibility(candidate, options))
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
