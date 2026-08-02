const MIN_WEIGHT = 0.7
const MAX_WEIGHT = 1.15

function clamp(value) {
  return Math.max(MIN_WEIGHT, Math.min(MAX_WEIGHT, value))
}

function activation(support) {
  if (support <= 1) return 0.35
  if (support === 2) return 0.65
  return 1
}

function add(groups, key, row) {
  const current = groups.get(key) ?? { net: 0, support: 0 }
  current.net += (row.direction === "increase" ? 1 : -1) * Number(row.strength ?? 0)
  current.support += 1
  groups.set(key, current)
}

function weight(value) {
  return clamp(1 + value.net * activation(value.support))
}

function assign(target, keys, value) {
  let cursor = target
  for (const key of keys.slice(0, -1)) cursor = cursor[key] ??= {}
  cursor[keys.at(-1)] = value
}

export function selectCurrentReviewSignals(feedbackRows = [], signalRows = [], exposureRows = []) {
  const recordDetailExposureIds = new Set(
    exposureRows.filter(row => row?.surface === "record_detail").map(row => row.id),
  )
  const feedback = feedbackRows.filter(row =>
    row?.source_review_schema === "record-feedback-v1"
    && recordDetailExposureIds.has(row.exposure_event_id),
  )
  const allowedFeedbackKeys = new Set(feedback.map(row => row.feedback_key))
  return {
    feedbackRows: feedback,
    signalRows: signalRows.filter(row => allowedFeedbackKeys.has(row?.feedback_key)),
  }
}

export function buildScoringPreferenceProfile(signalRows = [], { asOf = new Date().toISOString() } = {}) {
  const groups = new Map()
  const renderingGroups = new Map()

  for (const row of signalRows) {
    const dimension = String(row?.preference_dimension ?? "")
    const surface = String(row?.surface ?? "all") || "all"
    const semanticKey = String(row?.semantic_key ?? "")
    if (dimension === "semantic_preference" && semanticKey) {
      add(groups, surface === "all" ? `semantic_key_weights\u0000${semanticKey}` : `surface_semantic_weights\u0000${surface}\u0000${semanticKey}`, row)
    } else if (dimension === "repetition_tolerance") {
      add(groups, `repetition_tolerance\u0000${surface}`, row)
    } else if (dimension === "surface_timing_preference" && surface !== "all") {
      add(groups, `surface_weights\u0000${surface}`, row)
    } else if (dimension) {
      add(renderingGroups, `${surface}:${dimension}`, row)
    }
  }

  const profile = {
    profile_version: "scoring-preference-profile-v0.2",
    as_of: asOf,
    semantic_key_weights: {},
    dimension_weights: {},
    claim_type_weights: {},
    surface_semantic_weights: {},
    surface_weights: {},
    repetition_tolerance: {},
    rendering_preferences: {},
  }
  for (const [path, value] of groups) assign(profile, path.split("\u0000"), weight(value))
  for (const [key, value] of renderingGroups) profile.rendering_preferences[key] = weight(value)
  return profile
}
