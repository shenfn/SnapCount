export const SURFACE_RULES = {
  shortcut_notification: { min_confidence: 0.8, min_data_coverage: 0.75 },
  pwa_pending_ai_card: { min_confidence: 0.7, min_data_coverage: 0.5 },
  record_detail: { min_confidence: 0.5, min_data_coverage: 0.2 },
  weekly_report: { min_confidence: 0.6, min_data_coverage: 0.5 },
}

const MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY = {
  version: 'merchant-active-day-materiality-v0.1',
  min_count_delta: 1,
  min_amount_delta: 5,
  min_amount_delta_percent: 15,
  strong_amount_delta: 20,
}

function finiteNumber(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

function candidateMateriality(candidate) {
  if (candidate?.claim?.semantic_key !== 'merchant_daily_vs_active_day_median') return null

  const value = candidate.claim.structured_value
  const currentCount = value?.current?.count
  const currentAmount = value?.current?.total
  const baselineCount = value?.baseline?.count
  const baselineAmount = value?.baseline?.total

  if (![currentCount, currentAmount, baselineCount, baselineAmount].every(finiteNumber)) {
    return {
      evaluated: true,
      passes: false,
      policy_version: MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.version,
      reason: 'missing_materiality_metrics',
    }
  }

  const countDelta = Math.abs(currentCount - baselineCount)
  const currentAmountCents = Math.round(currentAmount * 100)
  const baselineAmountCents = Math.round(baselineAmount * 100)
  if (!finiteNumber(countDelta) || !Number.isSafeInteger(currentAmountCents) || !Number.isSafeInteger(baselineAmountCents)) {
    return {
      evaluated: true,
      passes: false,
      policy_version: MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.version,
      reason: 'missing_materiality_metrics',
    }
  }
  const amountDelta = Math.abs(currentAmountCents - baselineAmountCents) / 100
  const amountDeltaPercent = baselineAmountCents > 0
    ? amountDelta * 10000 / baselineAmountCents
    : null
  const countIsMaterial = countDelta >= MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.min_count_delta
  const amountIsMaterial = amountDelta >= MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.strong_amount_delta
    || (
      amountDelta >= MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.min_amount_delta
      && baselineAmount > 0
      && amountDeltaPercent !== null
      && amountDeltaPercent >= MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.min_amount_delta_percent
    )
  const passes = countIsMaterial || amountIsMaterial

  return {
    evaluated: true,
    passes,
    policy_version: MERCHANT_ACTIVE_DAY_MATERIALITY_POLICY.version,
    reason: passes ? null : 'difference_below_materiality_threshold',
  }
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

function surfaceDecision(candidate, surface, rule, hardBlocked, planningContext, materiality) {
  const reasons = [...hardBlocked]
  const confidence = candidate.quality?.confidence ?? 0
  const coverage = candidate.quality?.data_coverage ?? 0
  if (confidence < rule.min_confidence) reasons.push('confidence_below_surface_threshold')
  if (coverage < rule.min_data_coverage) reasons.push('data_coverage_below_surface_threshold')
  if (materiality?.passes === false) reasons.push(materiality.reason)

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
  const materiality = candidateMateriality(candidate)
  const surfaceEligibility = Object.fromEntries(
    Object.entries(SURFACE_RULES).map(([surface, rule]) => [
      surface,
      surfaceDecision(candidate, surface, rule, hardBlocked, planningContext, materiality),
    ]),
  )
  return {
    ...candidate,
    eligibility: {
      eligible: hardBlocked.length === 0,
      blocked_reasons: hardBlocked,
      materiality,
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
