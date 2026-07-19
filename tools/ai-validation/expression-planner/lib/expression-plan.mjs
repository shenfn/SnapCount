export const SURFACE_CAPACITY = {
  shortcut_notification: {
    max_candidates: 1,
    allow_exact_fact_fallback: true,
    fixed_slots: ['archive_status', 'current_record_summary', 'daily_summary'],
    covered_semantic_keys: ['merchant_daily_count_total'],
  },
  pwa_pending_ai_card: {
    max_candidates: 1,
    allow_exact_fact_fallback: true,
    fixed_slots: ['archive_status', 'domain_destination', 'current_record_summary'],
    covered_semantic_keys: [],
  },
  record_detail: {
    max_candidates: 3,
    allow_exact_fact_fallback: false,
    fixed_slots: ['record_fields', 'domain_destination', 'account_binding', 'record_actions'],
    covered_semantic_keys: [],
  },
  weekly_report: {
    max_candidates: 4,
    allow_exact_fact_fallback: false,
    fixed_slots: ['period_header', 'weekly_totals'],
    covered_semantic_keys: [],
  },
}

function surfaceScore(candidate, surface) {
  return candidate.scoring?.surfaces?.[surface] ?? null
}

function rankedCandidates(candidates, surface) {
  return candidates
    .filter(candidate => surfaceScore(candidate, surface)?.eligible)
    .sort((left, right) => surfaceScore(right, surface).score - surfaceScore(left, surface).score)
}

function exactFactFallback(candidates, surface, covered) {
  return rankedCandidates(candidates, surface).find(candidate =>
    candidate.claim_type === 'fact'
    && !covered.has(candidate.claim?.semantic_key)
    && ['observed', 'aggregated'].includes(candidate.fact_subtype),
  ) ?? null
}

export function buildSurfacePlan(candidates, surface, overrides = {}) {
  const profile = { ...SURFACE_CAPACITY[surface], ...overrides }
  if (!profile.max_candidates) throw new Error(`Unknown or invalid surface: ${surface}`)
  const covered = new Set(profile.covered_semantic_keys ?? [])
  const ranked = rankedCandidates(candidates, surface)
  const selected = []
  const excluded = []

  for (const candidate of ranked) {
    const score = surfaceScore(candidate, surface)
    const semanticKey = candidate.claim?.semantic_key
    if (covered.has(semanticKey)) {
      excluded.push({ candidate_id: candidate.candidate_id, semantic_key: semanticKey, reason: 'covered_by_fixed_content', score: score.score })
      continue
    }
    if (!score.passes_threshold) {
      excluded.push({ candidate_id: candidate.candidate_id, semantic_key: semanticKey, reason: 'below_surface_threshold', score: score.score })
      continue
    }
    if (selected.length >= profile.max_candidates) {
      excluded.push({ candidate_id: candidate.candidate_id, semantic_key: semanticKey, reason: 'surface_capacity_reached', score: score.score })
      continue
    }
    selected.push({
      candidate_id: candidate.candidate_id,
      semantic_key: semanticKey,
      dimension: candidate.dimension,
      claim_type: candidate.claim_type,
      score: score.score,
      selection_mode: 'threshold',
      canonical_text: candidate.claim?.canonical_text ?? null,
    })
  }

  let fallbackUsed = false
  if (!selected.length && profile.allow_exact_fact_fallback) {
    const fallback = exactFactFallback(candidates, surface, covered)
    if (fallback) {
      const score = surfaceScore(fallback, surface)
      selected.push({
        candidate_id: fallback.candidate_id,
        semantic_key: fallback.claim?.semantic_key,
        dimension: fallback.dimension,
        claim_type: fallback.claim_type,
        score: score.score,
        selection_mode: 'exact_fact_fallback',
        canonical_text: fallback.claim?.canonical_text ?? null,
      })
      fallbackUsed = true
      const excludedItem = excluded.find(item => item.candidate_id === fallback.candidate_id)
      if (excludedItem) excludedItem.reason = 'selected_as_exact_fact_fallback'
    }
  }

  return {
    surface,
    plan_version: 'expression-plan-v0.1',
    fixed_slots: profile.fixed_slots,
    covered_semantic_keys: [...covered],
    capacity: profile.max_candidates,
    selected,
    fallback_used: fallbackUsed,
    silent: selected.length === 0,
    excluded,
  }
}

export function buildExpressionPlans(candidates, surfaceOverrides = {}) {
  return Object.fromEntries(Object.keys(SURFACE_CAPACITY).map(surface => [
    surface,
    buildSurfacePlan(candidates, surface, surfaceOverrides[surface]),
  ]))
}

export function summarizePlans(plans) {
  return Object.fromEntries(Object.entries(plans).map(([surface, plan]) => [surface, {
    capacity: plan.capacity,
    selected_count: plan.selected.length,
    selected: plan.selected.map(item => ({ candidate_id: item.candidate_id, semantic_key: item.semantic_key, score: item.score, selection_mode: item.selection_mode })),
    fallback_used: plan.fallback_used,
    silent: plan.silent,
  }]))
}
