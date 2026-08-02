const DAY_MS = 24 * 60 * 60 * 1000

function clamp(value, min, max) {
  return Math.min(max, Math.max(min, value))
}

function round(value, digits = 4) {
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

function decayFactor(occurredAt, asOf, halfLifeDays) {
  const ageMs = Math.max(0, new Date(asOf) - new Date(occurredAt))
  const ageDays = ageMs / DAY_MS
  return 0.5 ** (ageDays / halfLifeDays)
}

function activationForSupport(supportCount) {
  if (supportCount <= 0) return 0
  if (supportCount === 1) return 0.35
  if (supportCount === 2) return 0.65
  return 1
}

function maturityForSupport(supportCount) {
  if (supportCount <= 1) return 'provisional'
  if (supportCount === 2) return 'emerging'
  return 'active'
}

function groupDescriptor(signal) {
  if (signal.preference_dimension === 'semantic_preference') {
    if (!signal.semantic_key) return null
    return { key: `semantic:${signal.semantic_key}`, target: 'semantic', semantic_key: signal.semantic_key }
  }
  if (signal.preference_dimension === 'surface_preference' || signal.preference_dimension === 'surface_timing_preference') {
    if (!signal.surface || !signal.semantic_key) return null
    return {
      key: `surface_semantic:${signal.surface}:${signal.semantic_key}`,
      target: 'surface_semantic', surface: signal.surface, semantic_key: signal.semantic_key,
    }
  }
  if (signal.preference_dimension === 'repetition_tolerance') {
    return { key: `repetition:${signal.surface ?? 'all'}`, target: 'repetition', surface: signal.surface ?? 'all' }
  }
  return {
    key: `rendering:${signal.preference_dimension}:${signal.surface ?? 'all'}`,
    target: 'rendering', surface: signal.surface ?? 'all', preference_dimension: signal.preference_dimension,
  }
}

function setNestedWeight(target, surface, key, value) {
  target[surface] ??= {}
  target[surface][key] = value
}

export function aggregatePreferenceSignals(signals, {
  asOf,
  halfLifeDays = 60,
  minMultiplier = 0.7,
  maxMultiplier = 1.15,
} = {}) {
  if (!asOf) throw new Error('Missing preference aggregation asOf')
  const groups = new Map()
  const unresolvedSignals = []

  for (const signal of signals ?? []) {
    const descriptor = groupDescriptor(signal)
    if (!descriptor) {
      unresolvedSignals.push({ signal_key: signal.signal_key, reason: 'missing_target_context' })
      continue
    }
    const group = groups.get(descriptor.key) ?? {
      ...descriptor,
      contributions: new Map(),
    }
    const direction = signal.direction === 'increase' ? 1 : -1
    const decay = decayFactor(signal.occurred_at, asOf, halfLifeDays)
    const supportKey = signal.exposure_event_id ?? signal.feedback_key ?? signal.signal_key
    const contribution = {
      signal_key: signal.signal_key,
      feedback_key: signal.feedback_key,
      exposure_event_id: signal.exposure_event_id ?? null,
      occurred_at: signal.occurred_at,
      direction: signal.direction,
      original_strength: Number(signal.strength ?? 0),
      decay_factor: round(decay),
      decayed_strength: round(direction * Number(signal.strength ?? 0) * decay),
    }
    const existing = group.contributions.get(supportKey)
    if (!existing || new Date(contribution.occurred_at) >= new Date(existing.occurred_at)) {
      group.contributions.set(supportKey, contribution)
    }
    groups.set(descriptor.key, group)
  }

  const semanticKeyWeights = {}
  const surfaceSemanticWeights = {}
  const repetitionTolerance = {}
  const renderingPreferences = {}
  const evidence = []

  for (const group of groups.values()) {
    const contributions = [...group.contributions.values()]
    const supportCount = contributions.length
    const activation = activationForSupport(supportCount)
    const netEvidence = contributions.reduce((sum, item) => sum + item.decayed_strength, 0)
    const appliedDelta = netEvidence * activation
    const multiplier = round(clamp(1 + appliedDelta, minMultiplier, maxMultiplier))
    const record = {
      group_key: group.key,
      target: group.target,
      semantic_key: group.semantic_key ?? null,
      surface: group.surface ?? null,
      preference_dimension: group.preference_dimension ?? null,
      support_count: supportCount,
      maturity: maturityForSupport(supportCount),
      activation: round(activation),
      net_evidence: round(netEvidence),
      applied_delta: round(appliedDelta),
      multiplier,
      contributions,
    }
    evidence.push(record)

    if (group.target === 'semantic') semanticKeyWeights[group.semantic_key] = multiplier
    if (group.target === 'surface_semantic') setNestedWeight(surfaceSemanticWeights, group.surface, group.semantic_key, multiplier)
    if (group.target === 'repetition') repetitionTolerance[group.surface] = multiplier
    if (group.target === 'rendering') setNestedWeight(renderingPreferences, group.surface, group.preference_dimension, multiplier)
  }

  return {
    snapshot_version: 'preference-snapshot-v0.1',
    as_of: asOf,
    aggregation_policy: {
      half_life_days: halfLifeDays,
      support_activation: { one: 0.35, two: 0.65, three_or_more: 1 },
      multiplier_bounds: { min: minMultiplier, max: maxMultiplier },
    },
    signal_count: signals?.length ?? 0,
    semantic_key_weights: semanticKeyWeights,
    surface_semantic_weights: surfaceSemanticWeights,
    repetition_tolerance: repetitionTolerance,
    rendering_preferences: renderingPreferences,
    unresolved_signals: unresolvedSignals,
    evidence,
  }
}

export function toScoringPreferenceProfile(snapshot) {
  return {
    profile_version: 'scoring-preference-profile-v0.1',
    generated_from_snapshot: snapshot?.snapshot_version ?? null,
    as_of: snapshot?.as_of ?? null,
    semantic_key_weights: snapshot?.semantic_key_weights ?? {},
    surface_semantic_weights: snapshot?.surface_semantic_weights ?? {},
    repetition_tolerance: snapshot?.repetition_tolerance ?? {},
  }
}
