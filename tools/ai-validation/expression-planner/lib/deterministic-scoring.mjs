export const SURFACE_THRESHOLDS = {
  shortcut_notification: 75,
  pwa_pending_ai_card: 65,
  record_detail: 45,
  weekly_report: 35,
}

export const INTERRUPTION_COSTS = {
  shortcut_notification: 12,
  pwa_pending_ai_card: 6,
  record_detail: 0,
  weekly_report: 0,
}

export const DEFAULT_IMPORTANCE = {
  merchant_daily_count_total: 0.9,
  merchant_daily_amount_structure: 0.68,
  expense_record_name_previous_gap: 0.84,
  merchant_daily_vs_active_day_median: 0.88,
  merchant_week_to_date_vs_previous_week_same_period: 0.92,
  expense_category_week_to_date_vs_previous_week_same_period: 0.92,
  income_current_amount: 0.75,
  income_month_total_count: 0.85,
  income_source_month_pattern: 0.78,
  sleep_current_metric: 0.72,
  sleep_vs_personal_median: 0.84,
  sport_current_metric: 0.72,
  sport_vs_personal_median: 0.84,
  food_current_metric: 0.72,
  food_vs_personal_median: 0.8,
  reading_current_metric: 0.72,
  reading_vs_personal_median: 0.84,
  wallet_current_metric: 0.76,
  wallet_vs_personal_median: 0.82,
  wallet_change_previous: 0.88,
}

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

function roundScore(value) {
  return Math.round(value * 100) / 100
}

function exposureFor(candidate, exposureHistory, surface = null, keyKind = 'exposure') {
  const exposureKey = keyKind === 'dedupe'
    ? candidate.selection_hints?.dedupe_key ?? candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key
    : candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key
  const scopedKey = surface ? `${surface}:${exposureKey}` : exposureKey
  return exposureHistory?.[scopedKey] ?? {
    count: 0,
    last_shown_at: null,
    exposure_key: exposureKey,
    scoped_exposure_key: scopedKey,
  }
}

function noveltyFromExposure(exposure) {
  const count = Number(exposure?.count ?? 0)
  if (count <= 0) return 1
  if (count === 1) return 0.92
  if (count === 2) return 0.8
  if (count === 3) return 0.68
  return 0.55
}

function repetitionPenalty(exposure, preferenceProfile, surface = 'all') {
  const count = Number(exposure?.count ?? 0)
  if (count <= 0) return 0
  const legacyPreferences = preferenceProfile?.rendering_preferences ?? {}
  const tolerance = clamp(Number(
    preferenceProfile?.repetition_tolerance?.[surface]
      ?? preferenceProfile?.repetition_tolerance?.all
      ?? legacyPreferences[`${surface}:repetition_tolerance`]
      ?? legacyPreferences[`all:repetition_tolerance`]
      ?? 1,
  ), 0.7, 1.15)
  return Math.min(20, (count * 2) / tolerance)
}

function preferenceMultiplier(candidate, preferenceProfile, surface = null) {
  const semanticKey = candidate.claim?.semantic_key
  const legacyPreferences = preferenceProfile?.rendering_preferences ?? {}
  const semantic = preferenceProfile?.semantic_key_weights?.[semanticKey]
  const dimension = preferenceProfile?.dimension_weights?.[candidate.dimension]
  const legacyDimension = surface ? legacyPreferences[`${surface}:${candidate.dimension}`] : null
  const legacySemantic = surface ? legacyPreferences[`${surface}:${semanticKey}`] : null
  const claimType = preferenceProfile?.claim_type_weights?.[candidate.claim_type]
  const base = Number(semantic ?? dimension ?? claimType ?? legacyDimension ?? 1)
  if (!surface) return clamp(base, 0.6, 1.2)
  const surfaceSemantic = Number(
    preferenceProfile?.surface_semantic_weights?.[surface]?.[semanticKey]
      ?? (semantic == null ? legacySemantic : null)
      ?? 1,
  )
  const surfaceWeight = Number(
    preferenceProfile?.surface_weights?.[surface]
      ?? legacyPreferences[`${surface}:semantic_preference`]
      ?? 1,
  )
  return clamp(base * surfaceSemantic * surfaceWeight, 0.6, 1.2)
}

function relevanceMultiplier(candidate, context) {
  const candidateEntity = candidate.claim?.structured_value?.entity_id
  if (!context?.entity_id || !candidateEntity) return 1
  return candidateEntity === context.entity_id ? 1 : 0.35
}

function scoreSurface(candidate, surface, baseComponents, preferenceProfile, exposure) {
  const surfaceGate = candidate.eligibility?.surface_eligibility?.[surface]
  if (!candidate.eligibility?.eligible || !surfaceGate?.eligible) {
    return {
      eligible: false,
      score: null,
      threshold: SURFACE_THRESHOLDS[surface],
      passes_threshold: false,
      blocked_reasons: [
        ...(candidate.eligibility?.blocked_reasons ?? []),
        ...(surfaceGate?.blocked_reasons ?? ['surface_not_eligible']),
      ],
    }
  }
  const userPreference = preferenceMultiplier(candidate, preferenceProfile, surface)
  const components = {
    ...baseComponents,
    novelty: noveltyFromExposure(exposure),
  }
  const raw = 100
    * components.importance
    * components.relevance
    * components.confidence
    * components.novelty
    * userPreference
  const surfaceRepetitionPenalty = repetitionPenalty(exposure, preferenceProfile, surface)
  const score = roundScore(clamp(raw - surfaceRepetitionPenalty - INTERRUPTION_COSTS[surface], 0, 100))
  return {
    eligible: true,
    raw_score: roundScore(raw),
    score,
    threshold: SURFACE_THRESHOLDS[surface],
    passes_threshold: score >= SURFACE_THRESHOLDS[surface],
    interruption_cost: INTERRUPTION_COSTS[surface],
    novelty: components.novelty,
    repetition_penalty: surfaceRepetitionPenalty,
    user_preference: userPreference,
    blocked_reasons: [],
  }
}

export function scoreCandidate(candidate, { preferenceProfile = {}, exposureHistory = {}, context = {} } = {}) {
  const baseExposure = exposureFor(candidate, exposureHistory)
  const baseComponents = {
    importance: DEFAULT_IMPORTANCE[candidate.claim?.semantic_key] ?? 0.6,
    relevance: relevanceMultiplier(candidate, context),
    confidence: clamp(Number(candidate.quality?.confidence ?? 0), 0, 1),
  }
  const components = {
    ...baseComponents,
    novelty: noveltyFromExposure(baseExposure),
    user_preference: preferenceMultiplier(candidate, preferenceProfile),
    repetition_penalty: repetitionPenalty(baseExposure, preferenceProfile),
  }
  const exposureBySurface = Object.fromEntries(Object.keys(SURFACE_THRESHOLDS).map(surface => {
    const exposure = exposureFor(candidate, exposureHistory, surface)
    return [surface, exposure]
  }))
  const dedupeExposureBySurface = Object.fromEntries(Object.keys(SURFACE_THRESHOLDS).map(surface => {
    const exposure = exposureFor(candidate, exposureHistory, surface, 'dedupe')
    return [surface, exposure]
  }))
  const surfaceScores = Object.fromEntries(Object.keys(SURFACE_THRESHOLDS).map(surface => [
    surface,
    scoreSurface(candidate, surface, baseComponents, preferenceProfile, exposureBySurface[surface]),
  ]))
  return {
    ...candidate,
    scoring: {
      scoring_version: 'deterministic-score-v0.2',
      formula: '100 × importance × relevance × confidence × novelty × user_preference - repetition_penalty - interruption_cost',
      components,
      exposure: {
        exposure_key: baseExposure.exposure_key ?? candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key,
        count: Number(baseExposure.count ?? 0),
        last_shown_at: baseExposure.last_shown_at ?? null,
      },
      exposure_by_surface: Object.fromEntries(Object.entries(exposureBySurface).map(([surface, exposure]) => [surface, {
        exposure_key: exposure.exposure_key ?? candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key,
        scoped_exposure_key: exposure.scoped_exposure_key ?? `${surface}:${candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key}`,
        count: Number(exposure.count ?? 0),
        last_shown_at: exposure.last_shown_at ?? null,
      }])),
      dedupe_exposure_by_surface: Object.fromEntries(Object.entries(dedupeExposureBySurface).map(([surface, exposure]) => [surface, {
        dedupe_key: exposure.exposure_key ?? candidate.selection_hints?.dedupe_key ?? candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key,
        scoped_dedupe_key: exposure.scoped_exposure_key ?? `${surface}:${candidate.selection_hints?.dedupe_key ?? candidate.selection_hints?.exposure_key ?? candidate.claim?.semantic_key}`,
        count: Number(exposure.count ?? 0),
        last_shown_at: exposure.last_shown_at ?? null,
      }])),
      surfaces: surfaceScores,
    },
  }
}

export function scoreCandidates(candidates, options = {}) {
  return candidates.map(candidate => scoreCandidate(candidate, options))
}

export function summarizeScores(candidates) {
  const summary = {}
  for (const surface of Object.keys(SURFACE_THRESHOLDS)) {
    const ranked = candidates
      .filter(candidate => candidate.scoring?.surfaces?.[surface]?.eligible)
      .map(candidate => ({
        candidate_id: candidate.candidate_id,
        semantic_key: candidate.claim?.semantic_key,
        score: candidate.scoring.surfaces[surface].score,
        passes_threshold: candidate.scoring.surfaces[surface].passes_threshold,
      }))
      .sort((left, right) => right.score - left.score)
    summary[surface] = {
      threshold: SURFACE_THRESHOLDS[surface],
      eligible_count: ranked.length,
      passing_count: ranked.filter(item => item.passes_threshold).length,
      ranking: ranked,
    }
  }
  return summary
}
