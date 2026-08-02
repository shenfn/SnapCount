import { readFile, writeFile } from 'node:fs/promises'
import path from 'node:path'

const SURFACES = ['shortcut_notification', 'pwa_pending_ai_card', 'record_detail', 'weekly_report']
const STAGE_FIELDS = ['deep_sleep_minutes', 'light_sleep_minutes', 'rem_minutes']

function parseArgs(argv) {
  const runArg = argv.find(arg => arg.startsWith('--run='))
  if (!runArg) throw new Error('--run=<replay run directory> is required')
  return { runDir: path.resolve(runArg.slice(6)) }
}

function round(value, digits = 2) {
  if (!Number.isFinite(value)) return null
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

function pct(part, total) {
  return total ? round((part / total) * 100, 1) : 0
}

function average(values) {
  return values.length ? values.reduce((sum, value) => sum + value, 0) / values.length : 0
}

function median(values) {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
}

function standardDeviation(values) {
  if (values.length < 2) return 0
  const mean = average(values)
  return Math.sqrt(average(values.map(value => (value - mean) ** 2)))
}

function countBy(items, keyOf) {
  const counts = new Map()
  for (const item of items) {
    const key = String(keyOf(item) ?? 'null')
    counts.set(key, (counts.get(key) ?? 0) + 1)
  }
  return Object.fromEntries([...counts.entries()].sort((left, right) => right[1] - left[1] || left[0].localeCompare(right[0])))
}

function mode(values) {
  if (!values.length) return { value: null, count: 0, share: 0 }
  const counts = countBy(values, value => value)
  const [value, count] = Object.entries(counts)[0]
  return { value: Number(value), count, share: pct(count, values.length) }
}

function scoreStats(values) {
  const numeric = values.filter(Number.isFinite)
  const mostCommon = mode(numeric)
  return {
    count: numeric.length,
    min: numeric.length ? Math.min(...numeric) : null,
    max: numeric.length ? Math.max(...numeric) : null,
    mean: round(average(numeric)),
    median: round(median(numeric)),
    standard_deviation: round(standardDeviation(numeric), 3),
    distinct_values: new Set(numeric).size,
    mode: mostCommon.value,
    mode_share_pct: mostCommon.share,
  }
}

function present(value) {
  return Array.isArray(value) ? value.length > 0 : value !== null && value !== undefined && value !== ''
}

function payload(row) {
  return row.current_record?.payload ?? {}
}

function hasPayloadField(row, field) {
  return Object.prototype.hasOwnProperty.call(payload(row), field) && present(payload(row)[field])
}

function candidateByKey(row, semanticKey) {
  return row.local_candidates.find(candidate => candidate.semantic_key === semanticKey) ?? null
}

function candidateSummary(candidate) {
  return candidate ? {
    semantic_key: candidate.semantic_key,
    dimension: candidate.dimension,
    canonical_text: candidate.canonical_text,
    structured_value: candidate.structured_value,
    scores: candidate.scores,
  } : null
}

function recordSummary(row) {
  const current = row.current_record ?? {}
  return {
    record_id: row.record_id,
    user_key: row.user_key,
    domain_key: row.domain_key,
    occurred_at: row.occurred_at,
    causal_history_count: row.causal_history_count,
    title: current.title ?? current.merchant_name ?? null,
    summary: current.summary ?? null,
    current_record: current,
    candidate_count: row.local_candidates.length,
    candidate_keys: row.local_candidates.map(candidate => candidate.semantic_key),
    selected: row.comparison?.local?.selected ?? {},
  }
}

function historyBucket(value) {
  if (value <= 1) return '1'
  if (value <= 4) return '2-4'
  if (value <= 9) return '5-9'
  if (value <= 19) return '10-19'
  return '20+'
}

function selectedCandidates(row, surface) {
  const keys = row.comparison?.local?.selected?.[surface] ?? []
  return keys.map(key => candidateByKey(row, key)).filter(Boolean)
}

function stableObject(value) {
  if (Array.isArray(value)) return value.map(stableObject)
  if (!value || typeof value !== 'object') return value
  return Object.fromEntries(Object.keys(value).sort().map(key => [key, stableObject(value[key])]))
}

function duplicateSignature(row) {
  const current = row.current_record ?? {}
  const data = payload(row)
  const coreByDomain = {
    expense: {
      amount: current.amount, merchant_name: current.merchant_name, category: current.category,
      platform: current.platform, payment_method: current.payment_method,
    },
    food: {
      meal_type: data.meal_type, total_calorie_kcal: data.total_calorie_kcal, dishes: data.dishes,
    },
    sleep: {
      title: current.title,
      duration_minutes: present(data.sleep_minutes) && Number.isFinite(Number(data.sleep_minutes))
        ? Number(data.sleep_minutes)
        : (present(data.sleep_hours) && Number.isFinite(Number(data.sleep_hours)) ? Math.round(Number(data.sleep_hours) * 60) : null),
    },
    sport: {
      sport_type: data.sport_type, duration_minutes: data.duration_minutes, duration_min: data.duration_min,
      distance_km: data.distance_km, calories: data.calories, avg_heart_rate: data.avg_heart_rate,
    },
    reading: { book_name: data.book_name, reading_minutes: data.reading_minutes, progress_percent: data.progress_percent },
    wallet: {
      account_name: data.account_name, account_snapshot_kind: data.account_snapshot_kind,
      record_kind: data.record_kind, amount: data.amount, snapshot_balance: data.snapshot_balance,
    },
  }
  return JSON.stringify(stableObject({
    user_key: row.user_key,
    domain_key: row.domain_key,
    occurred_at: Number.isFinite(new Date(row.occurred_at).getTime()) ? new Date(row.occurred_at).toISOString() : row.occurred_at,
    core: coreByDomain[row.domain_key] ?? current,
  }))
}

function duplicateGroups(rows) {
  const grouped = new Map()
  for (const row of rows) {
    const signature = duplicateSignature(row)
    const group = grouped.get(signature) ?? []
    group.push(row)
    grouped.set(signature, group)
  }
  return [...grouped.values()]
    .filter(group => group.length > 1)
    .sort((left, right) => right.length - left.length)
    .map(group => ({ count: group.length, records: group.slice(0, 8).map(recordSummary) }))
}

function fieldCoverage(rows) {
  const keys = new Set()
  for (const row of rows) for (const key of Object.keys(payload(row))) keys.add(key)
  return Object.fromEntries([...keys].sort().map(key => [key, rows.filter(row => hasPayloadField(row, key)).length]))
}

function domainCandidateMetrics(rows) {
  const candidates = rows.flatMap(row => row.local_candidates)
  const candidateCounts = rows.map(row => row.local_candidates.length)
  const poolDimensionCounts = rows.map(row => new Set(row.local_candidates.map(candidate => candidate.dimension)).size)
  const detailDimensionCounts = rows.map(row => new Set(selectedCandidates(row, 'record_detail').map(candidate => candidate.dimension)).size)
  const detailCounts = rows.map(row => row.comparison?.local?.selected?.record_detail?.length ?? 0)
  const zero = rows.filter(row => row.local_candidates.length === 0)
  return {
    records: rows.length,
    zero_candidates: zero.length,
    zero_candidate_pct: pct(zero.length, rows.length),
    candidate_count_distribution: countBy(rows, row => row.local_candidates.length),
    candidate_count_mean: round(average(candidateCounts)),
    candidate_count_median: median(candidateCounts),
    unique_semantic_keys: new Set(candidates.map(candidate => candidate.semantic_key)).size,
    unique_dimensions: new Set(candidates.map(candidate => candidate.dimension)).size,
    pool_dimension_mean: round(average(poolDimensionCounts)),
    records_with_2plus_pool_dimensions: rows.filter((row, index) => poolDimensionCounts[index] >= 2).length,
    detail_selected_mean: round(average(detailCounts)),
    detail_dimension_mean: round(average(detailDimensionCounts)),
    records_with_2plus_detail_dimensions: rows.filter((row, index) => detailDimensionCounts[index] >= 2).length,
    records_with_3plus_detail_dimensions: rows.filter((row, index) => detailDimensionCounts[index] >= 3).length,
    candidate_keys: countBy(candidates, candidate => candidate.semantic_key),
    dimensions: countBy(candidates, candidate => candidate.dimension),
    zero_by_history_bucket: countBy(zero, row => historyBucket(row.causal_history_count)),
  }
}

function semanticKeyStats(rows) {
  const byKey = new Map()
  for (const row of rows) {
    for (const candidate of row.local_candidates) {
      const item = byKey.get(candidate.semantic_key) ?? {
        semantic_key: candidate.semantic_key,
        domain_key: row.domain_key,
        dimension: candidate.dimension,
        claim_type: candidate.claim_type,
        candidates: [],
        record_ids: [],
      }
      item.candidates.push(candidate)
      item.record_ids.push(row.record_id)
      byKey.set(candidate.semantic_key, item)
    }
  }
  return [...byKey.values()].map(item => ({
    semantic_key: item.semantic_key,
    domain_key: item.domain_key,
    dimension: item.dimension,
    claim_type: item.claim_type,
    count: item.candidates.length,
    scores: Object.fromEntries(SURFACES.map(surface => [surface, scoreStats(item.candidates.map(candidate => candidate.scores?.[surface]))])),
    selected: Object.fromEntries(SURFACES.map(surface => [surface, rows.filter(row => (row.comparison?.local?.selected?.[surface] ?? []).includes(item.semantic_key)).length])),
    sample_record_ids: item.record_ids.slice(0, 5),
  })).sort((left, right) => right.count - left.count || left.semantic_key.localeCompare(right.semantic_key))
}

function surfaceStats(rows) {
  return Object.fromEntries(SURFACES.map(surface => {
    const selected = rows.map(row => row.comparison?.local?.selected?.[surface] ?? [])
    const nonempty = selected.filter(keys => keys.length)
    const firstCounts = countBy(nonempty, keys => keys[0])
    const selectedCounts = countBy(nonempty.flat(), key => key)
    const top = Object.entries(firstCounts)[0] ?? [null, 0]
    return [surface, {
      records: rows.length,
      silent_records: rows.length - nonempty.length,
      silent_pct: pct(rows.length - nonempty.length, rows.length),
      selected_count_distribution: countBy(selected, keys => keys.length),
      first_selected_keys: firstCounts,
      all_selected_keys: selectedCounts,
      top_first_key: top[0],
      top_first_key_count: top[1],
      top_first_key_share_pct: pct(top[1], nonempty.length),
    }]
  }))
}

function combinationStats(rows) {
  return {
    candidate_sets: countBy(rows, row => row.local_candidates.map(candidate => candidate.semantic_key).sort().join(' + ') || '(zero)'),
    record_detail_sets: countBy(rows, row => (row.comparison?.local?.selected?.record_detail ?? []).join(' + ') || '(silent)'),
  }
}

function candidateEffect(candidate) {
  const value = candidate?.structured_value ?? {}
  if (Number.isFinite(Number(value.delta))) return Math.abs(Number(value.delta))
  if (Number.isFinite(Number(value.delta?.total))) return Math.abs(Number(value.delta.total))
  if (Number.isFinite(Number(value.current)) && Number.isFinite(Number(value.median))) return Math.abs(Number(value.current) - Number(value.median))
  return null
}

function fixedScoreContrasts(rows) {
  const output = []
  const grouped = new Map()
  for (const row of rows) for (const candidate of row.local_candidates) {
    const effect = candidateEffect(candidate)
    const score = candidate.scores?.record_detail
    if (effect === null || !Number.isFinite(score)) continue
    const group = grouped.get(candidate.semantic_key) ?? []
    group.push({ record_id: row.record_id, effect: round(effect), score, canonical_text: candidate.canonical_text, structured_value: candidate.structured_value })
    grouped.set(candidate.semantic_key, group)
  }
  for (const [semanticKey, items] of grouped) {
    const byScore = new Map()
    for (const item of items) {
      const group = byScore.get(item.score) ?? []
      group.push(item)
      byScore.set(item.score, group)
    }
    let best = null
    for (const [score, sameScore] of byScore) {
      if (sameScore.length < 2) continue
      const sorted = [...sameScore].sort((left, right) => left.effect - right.effect)
      const spread = sorted.at(-1).effect - sorted[0].effect
      if (!best || spread > best.effect_spread) best = {
        semantic_key: semanticKey,
        same_record_detail_score: score,
        effect_spread: round(spread),
        smallest_effect: sorted[0],
        largest_effect: sorted.at(-1),
      }
    }
    if (best) output.push(best)
  }
  return output.sort((left, right) => right.effect_spread - left.effect_spread)
}

function replayComparisonAnalysis(rows) {
  const oldShadow = rows.filter(row => row.old_shadow)
  const matched = rows.filter(row => row.comparison?.old?.status && row.comparison.old.status !== 'not_run')
  const changedSet = matched.filter(row => (row.comparison.added_candidate_keys?.length ?? 0) || (row.comparison.removed_candidate_keys?.length ?? 0))
  return {
    old_shadow_rows: oldShadow.length,
    comparable_rows: matched.length,
    comparable_pct: pct(matched.length, rows.length),
    old_statuses: countBy(matched, row => row.comparison.old.status),
    candidate_set_changed: changedSet.length,
    candidate_set_changed_pct: pct(changedSet.length, matched.length),
    record_detail_selection_changed: matched.filter(row => row.comparison.record_detail_selection_changed).length,
    shortcut_selection_changed: matched.filter(row => row.comparison.shortcut_selection_changed).length,
    by_domain: Object.fromEntries([...new Set(rows.map(row => row.domain_key))].sort().map(domainKey => {
      const scoped = matched.filter(row => row.domain_key === domainKey)
      return [domainKey, {
        comparable: scoped.length,
        candidate_set_changed: scoped.filter(row => (row.comparison.added_candidate_keys?.length ?? 0) || (row.comparison.removed_candidate_keys?.length ?? 0)).length,
        record_detail_selection_changed: scoped.filter(row => row.comparison.record_detail_selection_changed).length,
        shortcut_selection_changed: scoped.filter(row => row.comparison.shortcut_selection_changed).length,
      }]
    })),
  }
}

function expenseZeroAnalysis(rows) {
  const zero = rows.filter(row => row.local_candidates.length === 0)
  const coreFields = ['amount', 'merchant_name', 'category', 'platform', 'payment_method']
  const coverage = Object.fromEntries(coreFields.map(field => [field, zero.filter(row => present(row.current_record?.[field])).length]))
  const fullContext = zero.filter(row => coreFields.every(field => present(row.current_record?.[field])))
  const detailedBucket = value => {
    if (value <= 1) return '1'
    if (value <= 4) return '2-4'
    if (value <= 9) return '5-9'
    if (value <= 24) return '10-24'
    if (value <= 49) return '25-49'
    if (value <= 99) return '50-99'
    if (value <= 199) return '100-199'
    if (value <= 299) return '200-299'
    return '300+'
  }
  const allByHistory = countBy(rows, row => detailedBucket(row.causal_history_count))
  const zeroByHistory = countBy(zero, row => detailedBucket(row.causal_history_count))
  return {
    count: zero.length,
    by_history_bucket: countBy(zero, row => historyBucket(row.causal_history_count)),
    core_field_coverage: coverage,
    full_context_records: fullContext.length,
    full_context_pct: pct(fullContext.length, zero.length),
    reason_classes: {
      first_causal_record: zero.filter(row => row.causal_history_count === 1).length,
      history_2_to_4_but_no_supported_pattern: zero.filter(row => row.causal_history_count >= 2 && row.causal_history_count <= 4).length,
      history_5plus_but_no_supported_pattern: zero.filter(row => row.causal_history_count >= 5).length,
    },
    zero_rate_by_history: Object.fromEntries(Object.entries(allByHistory).map(([bucket, total]) => [bucket, {
      records: total,
      zero_candidates: zeroByHistory[bucket] ?? 0,
      zero_candidate_pct: pct(zeroByHistory[bucket] ?? 0, total),
    }])),
    categories: countBy(rows, row => row.current_record?.category ?? 'missing'),
    high_history_samples: [...zero].sort((left, right) => right.causal_history_count - left.causal_history_count).slice(0, 10).map(recordSummary),
    samples: zero.slice(0, 12).map(recordSummary),
  }
}

function genericZeroAnalysis(rows) {
  const zero = rows.filter(row => row.local_candidates.length === 0)
  return zero.map(row => ({
    ...recordSummary(row),
    available_payload_fields: Object.keys(payload(row)).filter(key => present(payload(row)[key])),
    diagnosis: 'primary_metric_missing_blocks_all_domain_specific_generators',
  }))
}

function sleepAnalysis(rows) {
  const qualityFalse = []
  const stageAllMissing = []
  const stagePartialMissing = []
  const stageDurationMismatch = []
  const stageTotalExceedsDuration = []
  const timingDurationMismatch = []
  const napComparedWithNight = []
  for (const row of rows) {
    const quality = candidateByKey(row, 'sleep_quality_current')
    if (quality && !hasPayloadField(row, 'quality_score')) {
      qualityFalse.push({ ...recordSummary(row), candidate: candidateSummary(quality) })
    }
    const stages = candidateByKey(row, 'sleep_stage_composition')
    if (!stages) continue
    const presentFields = STAGE_FIELDS.filter(field => hasPayloadField(row, field))
    const missingFields = STAGE_FIELDS.filter(field => !hasPayloadField(row, field))
    const item = { ...recordSummary(row), present_fields: presentFields, missing_fields: missingFields, candidate: candidateSummary(stages) }
    if (!presentFields.length) stageAllMissing.push(item)
    else if (missingFields.length) stagePartialMissing.push(item)

    const sleepMinutes = Number(payload(row).sleep_minutes)
    const total = Number(stages.structured_value?.observed_total_minutes)
    if (presentFields.length === 3 && Number.isFinite(sleepMinutes) && sleepMinutes > 0 && Number.isFinite(total)) {
      const ratio = total / sleepMinutes
      if (ratio < 0.8 || ratio > 1.2) stageDurationMismatch.push({ ...item, sleep_minutes: sleepMinutes, stage_total_minutes: total, ratio: round(ratio, 3) })
      if (total > sleepMinutes) stageTotalExceedsDuration.push({ ...item, sleep_minutes: sleepMinutes, stage_total_minutes: total, excess_minutes: round(total - sleepMinutes) })
    }
    const start = new Date(payload(row).sleep_start_at).getTime()
    const wake = new Date(payload(row).wake_at).getTime()
    if (Number.isFinite(start) && Number.isFinite(wake) && Number.isFinite(sleepMinutes) && sleepMinutes > 0) {
      const windowMinutes = (wake - start) / 60000
      const difference = windowMinutes - sleepMinutes
      if (windowMinutes > 0 && Math.abs(difference) > 30) timingDurationMismatch.push({
        ...recordSummary(row), sleep_start_at: payload(row).sleep_start_at, wake_at: payload(row).wake_at,
        sleep_minutes: sleepMinutes, clock_window_minutes: round(windowMinutes), difference_minutes: round(difference),
      })
    }
    const baseline = candidateByKey(row, 'sleep_vs_personal_median')
    if (baseline && Number(baseline.structured_value?.current) <= 1.5 && Number(baseline.structured_value?.median) >= 4) {
      napComparedWithNight.push({ ...recordSummary(row), candidate: candidateSummary(baseline) })
    }
  }
  const detailCombinations = countBy(rows, row => (row.comparison?.local?.selected?.record_detail ?? []).join(' + ') || '(silent)')
  const candidateVisibility = Object.fromEntries(['sleep_current_metric', 'sleep_vs_personal_median', 'sleep_timing', 'sleep_quality_current', 'sleep_stage_composition'].map(key => [key, {
    generated: rows.filter(row => candidateByKey(row, key)).length,
    selected_record_detail: rows.filter(row => (row.comparison?.local?.selected?.record_detail ?? []).includes(key)).length,
  }]))
  return {
    records: rows.length,
    field_coverage: Object.fromEntries(['sleep_hours', 'sleep_minutes', 'sleep_start_at', 'wake_at', 'quality_score', ...STAGE_FIELDS, 'awake_minutes'].map(field => [field, rows.filter(row => hasPayloadField(row, field)).length])),
    quality_candidates: rows.filter(row => candidateByKey(row, 'sleep_quality_current')).length,
    quality_candidates_from_missing_field: qualityFalse.length,
    stage_candidates: rows.filter(row => candidateByKey(row, 'sleep_stage_composition')).length,
    stage_candidates_with_all_fields_missing: stageAllMissing.length,
    stage_candidates_with_partial_fields_missing: stagePartialMissing.length,
    complete_stage_duration_mismatches: stageDurationMismatch.length,
    stage_total_exceeds_sleep_duration: stageTotalExceedsDuration.length,
    timing_window_duration_mismatches: timingDurationMismatch.length,
    nap_compared_with_night_baseline: napComparedWithNight.length,
    candidate_visibility: candidateVisibility,
    detail_combinations: detailCombinations,
    quality_false_samples: qualityFalse.slice(0, 8),
    all_stage_missing_samples: stageAllMissing.slice(0, 8),
    partial_stage_missing_samples: stagePartialMissing.slice(0, 8),
    stage_duration_mismatch_samples: stageDurationMismatch.slice(0, 8),
    stage_total_exceeds_samples: stageTotalExceedsDuration.slice(0, 8),
    timing_duration_mismatch_samples: timingDurationMismatch.slice(0, 10),
    nap_baseline_samples: napComparedWithNight.slice(0, 8),
  }
}

function numericDishTotal(row, field) {
  const dishes = payload(row).dishes
  if (!Array.isArray(dishes) || !dishes.length) return null
  const values = dishes.map(dish => dish?.[field])
  if (values.some(value => !present(value) || !Number.isFinite(Number(value)))) return null
  return values.reduce((sum, value) => sum + Number(value), 0)
}

function foodAnalysis(rows) {
  const mismatches20 = []
  const mismatches50 = []
  let comparableCalories = 0
  for (const row of rows) {
    const declared = Number(payload(row).total_calorie_kcal)
    const dishes = numericDishTotal(row, 'calorie_kcal')
    if (!Number.isFinite(declared) || declared <= 0 || dishes === null) continue
    comparableCalories += 1
    const relativeDifference = Math.abs(dishes - declared) / declared
    const item = { ...recordSummary(row), declared_total_kcal: declared, dish_sum_kcal: round(dishes), relative_difference: round(relativeDifference, 3) }
    if (relativeDifference > 0.2) mismatches20.push(item)
    if (relativeDifference > 0.5) mismatches50.push(item)
  }
  const contextShortcut = rows.filter(row => (row.comparison?.local?.selected?.shortcut_notification ?? [])[0] === 'food_record_context')
  const dishesRows = rows.filter(row => Array.isArray(payload(row).dishes) && payload(row).dishes.length)
  const candidateVisibility = Object.fromEntries(['food_current_metric', 'food_record_context', 'food_composition', 'food_meal_vs_personal_median', 'food_recurring_dish'].map(key => [key, {
    generated: rows.filter(row => candidateByKey(row, key)).length,
    selected_record_detail: rows.filter(row => (row.comparison?.local?.selected?.record_detail ?? []).includes(key)).length,
    selected_shortcut: rows.filter(row => (row.comparison?.local?.selected?.shortcut_notification ?? []).includes(key)).length,
  }]))
  const recurring = rows.map(row => ({ row, candidate: candidateByKey(row, 'food_recurring_dish') })).filter(item => item.candidate)
  const recurringWithComposition = recurring.filter(item => candidateByKey(item.row, 'food_composition'))
  return {
    records: rows.length,
    field_coverage: Object.fromEntries(['meal_type', 'total_calorie_kcal', 'dishes', 'time_context', 'is_estimated', 'confidence_note'].map(field => [field, rows.filter(row => hasPayloadField(row, field)).length])),
    dish_field_complete_records: Object.fromEntries(['name', 'calorie_kcal', 'protein_g', 'carb_g', 'fat_g', 'estimated_grams'].map(field => [field, dishesRows.filter(row => payload(row).dishes.every(dish => present(dish?.[field]))).length])),
    context_selected_first_for_shortcut: contextShortcut.length,
    context_selected_first_for_shortcut_pct: pct(contextShortcut.length, rows.length),
    calorie_comparable_records: comparableCalories,
    calorie_mismatch_over_20pct: mismatches20.length,
    calorie_mismatch_over_50pct: mismatches50.length,
    meal_types: countBy(rows, row => payload(row).meal_type ?? 'missing'),
    candidate_visibility: candidateVisibility,
    recurring_dishes: countBy(recurring, item => item.candidate.structured_value?.dish_name ?? 'unknown'),
    recurring_with_composition: recurringWithComposition.length,
    recurring_with_composition_selected: recurringWithComposition.filter(item => (item.row.comparison?.local?.selected?.record_detail ?? []).includes('food_composition')).length,
    mismatch_samples: mismatches20.sort((left, right) => right.relative_difference - left.relative_difference).slice(0, 10),
  }
}

function sportAnalysis(rows) {
  const grouped = new Map()
  for (const row of rows) {
    const group = grouped.get(row.user_key) ?? []
    group.push(row)
    grouped.set(row.user_key, group)
  }
  const mixedType = []
  const insufficientSameType = []
  for (const group of grouped.values()) {
    group.sort((left, right) => new Date(left.occurred_at) - new Date(right.occurred_at))
    for (let index = 0; index < group.length; index += 1) {
      const row = group[index]
      const baseline = candidateByKey(row, 'sport_vs_personal_median')
      if (!baseline) continue
      const prior = group.slice(0, index)
      const currentType = payload(row).sport_type ?? row.current_record?.title ?? null
      const priorTypes = new Set(prior.map(item => payload(item).sport_type ?? item.current_record?.title).filter(Boolean))
      const sameTypeCount = prior.filter(item => (payload(item).sport_type ?? item.current_record?.title ?? null) === currentType).length
      const item = { ...recordSummary(row), current_type: currentType, prior_types: [...priorTypes], same_type_prior_count: sameTypeCount, candidate: candidateSummary(baseline) }
      if (priorTypes.size > 1) mixedType.push(item)
      if (sameTypeCount < 3) insufficientSameType.push(item)
    }
  }
  return {
    records: rows.length,
    personal_median_candidates: rows.filter(row => candidateByKey(row, 'sport_vs_personal_median')).length,
    baselines_with_multiple_prior_sport_types: mixedType.length,
    baselines_with_fewer_than_3_same_type_priors: insufficientSameType.length,
    mixed_type_samples: mixedType.slice(0, 8),
    insufficient_same_type_samples: insufficientSameType.slice(0, 8),
  }
}

function walletAnalysis(rows) {
  const crossAccount = []
  const crossKind = []
  const mixedMedian = []
  const grouped = new Map()
  for (const row of rows) {
    const group = grouped.get(row.user_key) ?? []
    group.push(row)
    grouped.set(row.user_key, group)
  }
  for (const group of grouped.values()) {
    group.sort((left, right) => new Date(left.occurred_at) - new Date(right.occurred_at))
    for (let index = 0; index < group.length; index += 1) {
      const row = group[index]
      const previous = group[index - 1]
      const change = candidateByKey(row, 'wallet_change_previous')
      if (change && previous) {
        const comparison = {
          current: recordSummary(row),
          previous: recordSummary(previous),
          candidate: candidateSummary(change),
          current_account: payload(row).account_name ?? payload(row).institution ?? null,
          previous_account: payload(previous).account_name ?? payload(previous).institution ?? null,
          current_kind: payload(row).account_snapshot_kind ?? payload(row).record_kind ?? null,
          previous_kind: payload(previous).account_snapshot_kind ?? payload(previous).record_kind ?? null,
        }
        if (comparison.current_account !== comparison.previous_account) crossAccount.push(comparison)
        if (comparison.current_kind !== comparison.previous_kind) crossKind.push(comparison)
      }
      if (candidateByKey(row, 'wallet_vs_personal_median')) {
        const history = group.slice(0, index + 1)
        const accounts = new Set(history.map(item => payload(item).account_name ?? payload(item).institution).filter(Boolean))
        const kinds = new Set(history.map(item => payload(item).account_snapshot_kind ?? payload(item).record_kind).filter(Boolean))
        if (accounts.size > 1 || kinds.size > 1) mixedMedian.push({ ...recordSummary(row), account_count_in_history: accounts.size, kinds: [...kinds] })
      }
    }
  }
  return {
    records: rows.length,
    change_previous_candidates: rows.filter(row => candidateByKey(row, 'wallet_change_previous')).length,
    cross_account_previous_comparisons: crossAccount.length,
    cross_kind_previous_comparisons: crossKind.length,
    personal_median_candidates: rows.filter(row => candidateByKey(row, 'wallet_vs_personal_median')).length,
    mixed_scope_personal_medians: mixedMedian.length,
    cross_account_samples: crossAccount.slice(0, 10),
    cross_kind_samples: crossKind.slice(0, 10),
    mixed_median_samples: mixedMedian.slice(0, 10),
  }
}

function attributeUtilization(rows, domainKey) {
  const used = {
    food: ['total_calorie_kcal', 'total_calories', 'calorie_kcal', 'calories', 'meal_type', 'dishes', 'is_estimated', 'confidence_note'],
    sleep: ['sleep_hours', 'sleep_minutes', 'sleep_start_at', 'wake_at', 'quality_score', 'deep_sleep_minutes', 'light_sleep_minutes', 'rem_minutes'],
    sport: ['duration_min', 'duration_minutes', 'duration'],
    reading: ['reading_minutes', 'duration_minutes', 'duration_min'],
    wallet: ['amount', 'balance', 'wallet_amount', 'liability_amount'],
  }[domainKey] ?? []
  const coverage = fieldCoverage(rows)
  return {
    used_by_candidate_generators: used,
    observed_fields: coverage,
    observed_but_not_used: Object.fromEntries(Object.entries(coverage).filter(([field]) => !used.includes(field))),
  }
}

function feedbackAnalysis(source) {
  const exposureById = new Map(source.exposures.map(exposure => [exposure.id, exposure]))
  const rows = source.feedback.map(feedback => {
    const exposure = exposureById.get(feedback.exposure_event_id) ?? null
    const text = feedback.free_text ?? ''
    let topic = 'other'
    if (/少|角度|重复|一直|每次|上周/.test(text)) topic = 'dimension_or_repetition'
    if (/夸张|语气|不合理|并非|钱包变厚/.test(text)) topic = 'tone_or_inference_overreach'
    if (/还款|不准|准不准|识别|数字|金额/.test(text)) topic = 'fact_or_recognition_correction'
    if (/挺好|还行|方向对|说到点/.test(text) && topic === 'other') topic = 'positive_or_acceptable'
    const usableRecordDetail = Boolean(exposure && exposure.surface === 'record_detail')
    return {
      feedback_id: feedback.id,
      created_at: feedback.created_at,
      record_id: feedback.metadata?.record_id ?? exposure?.record_id ?? null,
      primary_choice: feedback.primary_choice ?? null,
      free_text: text,
      topic,
      matched_exposure: Boolean(exposure),
      usable_record_detail: usableRecordDetail,
      surface: exposure?.surface ?? feedback.surface ?? null,
      domain_key: exposure?.domain_key ?? null,
      semantic_key: exposure?.semantic_key ?? feedback.semantic_key ?? null,
      source_review_schema: feedback.source_review_schema ?? null,
    }
  })
  const usable = rows.filter(row => row.usable_record_detail)
  return {
    feedback_count: rows.length,
    exposure_count: source.exposures.length,
    matched_feedback: rows.filter(row => row.matched_exposure).length,
    usable_record_detail_feedback: usable.length,
    topic_counts: countBy(rows, row => row.topic),
    rows,
  }
}

function shadowAnalysis(source) {
  const times = source.shadow_runs.map(run => new Date(run.created_at).getTime()).filter(Number.isFinite)
  const latest = times.length ? new Date(Math.max(...times)).toISOString() : null
  return {
    runs: source.shadow_runs.length,
    latest_created_at: latest,
    collector_versions: countBy(source.shadow_runs, run => run.collector_version ?? 'unknown'),
    statuses: countBy(source.shadow_runs, run => run.status ?? run.run_status ?? (run.proposed_plan ? 'has_plan' : 'no_plan')),
  }
}

function userConcentration(rows) {
  const users = countBy(rows, row => row.user_key)
  const top = Object.entries(users)[0] ?? [null, 0]
  return {
    users,
    top_user: top[0],
    top_user_records: top[1],
    top_user_share_pct: pct(top[1], rows.length),
    by_domain: Object.fromEntries([...new Set(rows.map(row => row.domain_key))].sort().map(domainKey => {
      const scoped = rows.filter(row => row.domain_key === domainKey)
      const counts = countBy(scoped, row => row.user_key)
      const first = Object.entries(counts)[0] ?? [null, 0]
      return [domainKey, { users: Object.keys(counts).length, top_user_records: first[1], top_user_share_pct: pct(first[1], scoped.length) }]
    })),
  }
}

function transactionReplayCoverage(source, replayRows) {
  const replayedIds = new Set(replayRows.filter(row => row.domain_key === 'expense').map(row => row.record_id))
  const omitted = source.transactions.filter(row => !replayedIds.has(row.id))
  return {
    source_transactions: source.transactions.length,
    replayed_transactions: replayedIds.size,
    omitted_transactions: omitted.length,
    omitted_by_status: countBy(omitted, row => row.status ?? 'null'),
    omitted_missing_date: omitted.filter(row => !present(row.transaction_date)).length,
    omitted_samples: omitted.slice(0, 10),
  }
}

function markdownTable(headers, rows) {
  const escape = value => String(value ?? '').replaceAll('|', '\\|').replaceAll('\n', ' ')
  return [
    `| ${headers.map(escape).join(' | ')} |`,
    `| ${headers.map(() => '---').join(' | ')} |`,
    ...rows.map(row => `| ${row.map(escape).join(' | ')} |`),
  ].join('\n')
}

function topEntries(object, limit = 10) {
  return Object.entries(object).slice(0, limit)
}

function formatSample(sample) {
  const title = sample.title ?? sample.summary ?? sample.current_record?.merchant_name ?? '未命名记录'
  return `${sample.record_id} · ${sample.occurred_at} · ${title}`
}

function buildReport(analysis, runDir) {
  const domains = Object.entries(analysis.domains)
  const keyRows = analysis.semantic_keys.map(item => [
    item.domain_key,
    item.semantic_key,
    item.dimension,
    item.count,
    item.scores.record_detail.mode,
    `${item.scores.record_detail.mode_share_pct}%`,
    item.scores.record_detail.standard_deviation,
  ])
  const expense = analysis.domain_findings.expense
  const sleep = analysis.domain_findings.sleep
  const food = analysis.domain_findings.food
  const wallet = analysis.domain_findings.wallet
  const sport = analysis.domain_findings.sport
  const feedback = analysis.feedback
  const duplicates = analysis.duplicate_groups
  const replayComparison = analysis.replay_comparison
  const lines = [
    '# Expression Planner 717 条真实回放详细诊断',
    '',
    `> 生成时间：${analysis.generated_at}`,
    `> 固定回放：${runDir}`,
    '> 数据边界：脱敏真实数据，仅限本地诊断。原始记录可用于确定性回归，不等于偏好训练标签。',
    '',
    '## 一、先给结论',
    '',
    '用户关于“内容太死板、维度不足”的判断是对的，而且原因不是一个。框架文档已经设计了事实、比较、节奏、模式、意图和跨域等候选层级，但当前 v0.2 本地实现只覆盖其中很窄的一部分；同时还存在事实解析错误、候选生成早退、统计作用域错误、固定类型分数和 Surface 价值规则不足。',
    '',
    `- **P0 事实正确性未过线**：睡眠有 ${sleep.quality_candidates_from_missing_field} 条缺失评分却生成评分候选，${sleep.stage_candidates_with_all_fields_missing} 条三个睡眠阶段全缺失却生成“0/0/0 分钟”，${sleep.nap_compared_with_night_baseline} 条午睡与夜间基线比较；钱包 ${wallet.cross_account_previous_comparisons}/${wallet.change_previous_candidates} 条“较上次变化”跨账户比较，${wallet.mixed_scope_personal_medians}/${wallet.personal_median_candidates} 条个人中位数混合了多个账户或资产/负债口径。`,
    `- **P1 候选覆盖不足**：支出 ${expense.count} 条零候选，占 ${analysis.domains.expense.zero_candidate_pct}%；其中 ${expense.full_context_records} 条仍同时具有金额、商户、分类、平台和支付方式。运动、阅读等域大量真实字段完全没有进入候选生成器。`,
    `- **P2 排序与 Surface 仍偏模板化**：快捷通知第一候选集中在少数 semantic key；饮食的 food_record_context 有 ${food.context_selected_first_for_shortcut}/${food.records} 条成为快捷通知第一候选，说明“上下文事实”被当成“值得打断用户的通知价值”。`,
    `- **P3 学习数据不足**：717 条足够做规则回归，但只有 ${feedback.usable_record_detail_feedback} 条点评能关联到真实 record_detail exposure，不能训练可靠的偏好权重或学习排序。`,
    '',
    '因此当前应进入的是“事实治理 + Planner v0.2 离线迭代”，不是直接进入生产 owner-only 接管。',
    '',
    '## 二、数据概览',
    '',
    markdownTable(
      ['域', '记录', '零候选', '零候选率', '平均候选', '候选 key', '候选维度', '详情 >=2 维记录'],
      domains.map(([domain, item]) => [domain, item.records, item.zero_candidates, `${item.zero_candidate_pct}%`, item.candidate_count_mean, item.unique_semantic_keys, item.unique_dimensions, `${item.records_with_2plus_detail_dimensions}/${item.records}`]),
    ),
    '',
    `回放覆盖 ${analysis.overview.rows} 条记录、${analysis.overview.users} 个脱敏用户，时间范围 ${analysis.overview.first_occurred_at} 至 ${analysis.overview.last_occurred_at}。源交易 ${analysis.transaction_replay_coverage.source_transactions} 条，其中 ${analysis.transaction_replay_coverage.replayed_transactions} 条符合 done + 可解析发生时间的支出回放条件，另外 ${analysis.transaction_replay_coverage.omitted_transactions} 条被过滤。`,
    '',
    '## 三、P0：不是“文案不好”，而是事实层会说错',
    '',
    '### 3.1 睡眠缺失值被解析为 0',
    '',
    '代码中的 `num(value)` 直接执行 `Number(value)`；JavaScript 的 `Number(null) === 0`。而 `payloadValue()` 对缺失字段返回 null，所以“缺失”被当成真实 0。这个错误发生在候选生成前，后续调分、去重或 Prompt 都无法修复。',
    '',
    markdownTable(
      ['检查项', '实际条数', '应有行为'],
      [
        ['缺失 quality_score 但生成 sleep_quality_current', sleep.quality_candidates_from_missing_field, '不生成评分候选，并记录 missing_field reason'],
        ['三个阶段都缺失但生成 sleep_stage_composition', sleep.stage_candidates_with_all_fields_missing, '不生成阶段候选'],
        ['阶段字段部分缺失', sleep.stage_candidates_with_partial_fields_missing, '缺失项显示 unknown；coverage 按真实字段计算'],
        ['完整阶段合计与总时长偏差 >20%', sleep.complete_stage_duration_mismatches, '进入一致性 gate 或标注设备口径差异'],
        ['阶段合计大于总睡眠时长', sleep.stage_total_exceeds_sleep_duration, '禁止直接展示，先校验设备口径'],
        ['入睡-醒来窗口与 sleep_minutes 差 >30 分钟', sleep.timing_window_duration_mismatches, '检查跨日日期解析与时区'],
        ['短午睡与夜间睡眠中位数比较', sleep.nap_compared_with_night_baseline, '按 sleep_session_type 分 cohort'],
      ],
    ),
    '',
    ...sleep.all_stage_missing_samples.slice(0, 3).map(sample => `- ${formatSample(sample)}；错误候选：“${sample.candidate.canonical_text}”`),
    ...sleep.nap_baseline_samples.slice(0, 3).map(sample => `- ${formatSample(sample)}；错误 cohort：“${sample.candidate.canonical_text}”`),
    '',
    '### 3.2 钱包比较的统计作用域错误',
    '',
    '当前钱包历史按 `user + wallet domain` 聚合，而不是按 `account identity + asset/liability kind` 聚合。“微信零钱余额”和“花呗待还”可能互相成为上一条记录，资产与负债也可能进入同一个个人中位数。数字计算本身可以正确，但比较语义是错误的。',
    '',
    markdownTable(
      ['检查项', '条数', '占相关候选'],
      [
        ['跨账户 previous 比较', wallet.cross_account_previous_comparisons, `${pct(wallet.cross_account_previous_comparisons, wallet.change_previous_candidates)}%`],
        ['跨资产/负债 kind 比较', wallet.cross_kind_previous_comparisons, `${pct(wallet.cross_kind_previous_comparisons, wallet.change_previous_candidates)}%`],
        ['中位数混合多个账户/kind', wallet.mixed_scope_personal_medians, `${pct(wallet.mixed_scope_personal_medians, wallet.personal_median_candidates)}%`],
      ],
    ),
    '',
    ...wallet.cross_account_samples.slice(0, 3).map(sample => `- ${sample.current.record_id}：${sample.previous_account ?? '未知账户'} -> ${sample.current_account ?? '未知账户'}，却生成“${sample.candidate.canonical_text}”`),
    '',
    '### 3.3 识别事实与表达偏好没有完全分流',
    '',
    '真实点评中的“花呗还款”和“背面说明每 100 克 1572 千焦，不确定准不准”不是风格偏好，而是事件方向/识别可信度问题。它们必须回到事实契约、识别证据和单位换算层，不能拿来降低某个文案 key 的偏好权重。',
    '',
    '### 3.4 当前本地回放还不是完整的生产因果路径',
    '',
    '- 线上画像刷新与 Shadow 调度是并发 fire-and-forget，Planner 可能读到旧画像，也可能读到已包含当前记录的新画像；补录历史记录还缺严格 `as_of` 截断，存在未来数据泄漏风险。',
    '- 本地回放固定传入空 `domainProfile`，所以没有覆盖线上画像分支。当前 717 条结果适合验证无画像的确定性候选，不代表生产画像路径已回归。',
    '- 多候选点评即使传入 exposure，后端仍可能重新取该记录最新的详情曝光，存在点评错候选风险。',
    '- Planner finalize 时丢弃 `evidence` 和 `numbers`，持久化结果无法复核“这个结论由哪些记录和计算得到”。',
    '',
    '这些问题对应 `ingest-receipt/index.ts` 的画像刷新/Shadow 调度、`expression-shadow.ts` 的画像读取、`expression-feedback.ts` 的曝光关联，以及 `expression-shadow-planner.ts` 的最终持久化。它们应和数值解析、钱包 cohort 一起列为 P0，而不是等上线后靠点评发现。',
    '',
    '## 四、P1：候选空间不足，很多字段根本没有被算法看见',
    '',
    '### 4.1 支出：135 条零候选是结构性缺口',
    '',
    `零候选中 ${expense.full_context_records}/${expense.count} 条具有金额、商户、分类、平台、支付方式五个核心字段。它们没有候选的主要原因是当前生成器依赖“同商户同日 >=2 笔、历史活跃日中位数、本周对比上周、分类周同比”等聚合模式，没有单笔当前事实、发生时间、支付上下文、首次/低频商户或金额位置候选。`,
    '',
    markdownTable(['零候选原因代理', '条数'], Object.entries(expense.reason_classes)),
    '',
    markdownTable(['历史条数', '记录', '零候选', '零候选率'], Object.entries(expense.zero_rate_by_history).map(([bucket, item]) => [bucket, item.records, item.zero_candidates, `${item.zero_candidate_pct}%`])),
    '',
    ...expense.samples.slice(0, 5).map(sample => `- ${formatSample(sample)}；金额 ${sample.current_record.amount ?? '缺失'}，分类 ${sample.current_record.category ?? '缺失'}，历史 ${sample.causal_history_count} 条，仍为 0 候选。`),
    ...expense.high_history_samples.slice(0, 3).map(sample => `- 高历史仍漏：${formatSample(sample)}；历史 ${sample.causal_history_count} 条，金额 ${sample.current_record.amount ?? '缺失'} 元。`),
    '',
    '建议先补“可核验但不强行点评”的基础候选：单笔金额与商户事实、发生时段、支付渠道/账户上下文、首次出现/距离上次出现、同分类金额分位。是否进入通知由 Surface 决定，不是所有基础事实都要打断用户。',
    '',
    '### 4.2 通用域：主指标缺失会让全部领域候选提前返回',
    '',
    '`generateBuiltinDomainCandidates()` 在主指标不存在时直接 `return []`，导致即使记录还有其它可用事实，也不会执行 food/sleep 的专用生成器。下面是真实零候选记录及其仍然存在的字段：',
    '',
    ...analysis.domain_findings.generic_zero.slice(0, 12).map(sample => `- ${formatSample(sample)}；仍有字段：${sample.available_payload_fields.join('、') || '无'}。`),
    '',
    '这些零候选多数本身也是“无法确定数据域/识别不完整”记录，因此不能一律强造洞察；但生成流程仍应改为“各候选族独立判定依赖”，并输出 `missing_primary_metric`、`recognition_unresolved` 等沉默 reason code，而不是让一个主指标成为整个数据域的无解释总开关。',
    '',
    '### 4.3 运动、阅读、钱包字段利用率过低',
    '',
    ...['sport', 'reading', 'wallet'].map(domain => {
      const item = analysis.attribute_utilization[domain]
      const ignored = topEntries(item.observed_but_not_used, 20).map(([field, count]) => `${field}(${count})`).join('、')
      return `- **${domain}**：生成器使用 ${item.used_by_candidate_generators.join('、')}；真实存在但未进入候选逻辑的字段包括 ${ignored || '无'}。`
    }),
    '',
    '例如运动真实样本包含距离、热量、平均心率、配速、步频、步数、爬升和训练效果，但当前 Planner 只生成“本次运动 N 分钟”。这正是“不是没触发，而是候选生成框架尚未实现”的直接证据。',
    '',
    `运动的 ${sport.personal_median_candidates} 条个人中位数候选中，${sport.baselines_with_multiple_prior_sport_types} 条历史包含多个运动类型，${sport.baselines_with_fewer_than_3_same_type_priors} 条当前运动的同类型历史不足 3 条。跑步、羽毛球和步行的“时长中位数”不应混成同一个 cohort。`,
    '',
    ...sport.insufficient_same_type_samples.slice(0, 3).map(sample => `- ${formatSample(sample)}；当前 ${sample.current_type ?? '未知类型'}，同类型历史 ${sample.same_type_prior_count} 条，却生成“${sample.candidate.canonical_text}”。`),
    '',
    '分类枚举也未统一：支出同时存在 food/餐饮、other/其他、shopping/购物、life/生活、transport/出行；饮食餐次同时存在 dinner/中文“晚餐”。这些同义值按原字符串分 cohort，会拆散历史并让候选不触发。',
    '',
    markdownTable(['支出 category 原值', '条数'], topEntries(expense.categories, 20)),
    '',
    markdownTable(['饮食 meal_type 原值', '条数'], Object.entries(food.meal_types)),
    '',
    '### 4.4 饮食：已有多维候选，但缺可信度与一致性治理',
    '',
    `饮食已经从只有热量扩展到 record_context、composition、meal baseline 和 recurring dish，证明字段是够用的。但 ${food.calorie_comparable_records} 条可核对总热量与菜品热量之和的记录中，${food.calorie_mismatch_over_20pct} 条偏差超过 20%，${food.calorie_mismatch_over_50pct} 条超过 50%。在一致性检查前，不应生成“严重不足”等确定性评价。`,
    '',
    ...food.mismatch_samples.slice(0, 5).map(sample => `- ${formatSample(sample)}；总热量 ${sample.declared_total_kcal} kcal，菜品合计 ${sample.dish_sum_kcal} kcal，差异 ${round(sample.relative_difference * 100, 1)}%。`),
    '',
    markdownTable(['饮食候选', '生成', '入选详情', '入选快捷通知'], Object.entries(food.candidate_visibility).map(([key, item]) => [key, item.generated, item.selected_record_detail, item.selected_shortcut])),
    '',
    `food_recurring_dish 生成 ${food.candidate_visibility.food_recurring_dish.generated} 次且全部入选详情；其中与 food_composition 同时存在 ${food.recurring_with_composition} 次，但 composition 只保留 ${food.recurring_with_composition_selected} 次。复现菜名主要为：${topEntries(food.recurring_dishes, 8).map(([name, count]) => `${name}(${count})`).join('、')}。低信息量的“又吃了米饭”不应固定挤掉营养结构。`,
    '',
    '下一层应补的是：营养能量占比、份量与单位证据、同餐次/同菜品趋势、进食时点与个人作息、估算置信度、总热量与菜品明细一致性；不是继续增加一个固定模板。',
    '',
    '## 五、P2：分数和 Surface 组合为什么显得死板',
    '',
    '### 5.1 同一候选类型的分数大多接近常量',
    '',
    '当前公式以 semantic key 的默认 importance 和固定 confidence 为主；真实记录内容通常不改变 importance，relevance 也几乎恒为 1。于是同一 key 常出现 72、78、75.44 等固定分数。下表的“众数占比”和标准差可以直接看出模板化程度：',
    '',
    markdownTable(['域', 'semantic key', '维度', '条数', '详情分众数', '众数占比', '详情分标准差'], keyRows),
    '',
    markdownTable(['semantic key', '相同详情分', '最小变化', '最大变化', '跨度'], analysis.fixed_score_contrasts.slice(0, 8).map(item => [item.semantic_key, item.same_record_detail_score, item.smallest_effect.effect, item.largest_effect.effect, item.effect_spread])),
    '',
    '这不表示确定性评分本身错误，而是现有特征不足。下一步应该引入可解释的记录级效用特征，例如异常幅度但经过稳健基线、证据完整度、一致性、时效性、行动价值、Surface 新信息量；不要先训练黑盒排序。',
    '',
    '### 5.2 “候选多”不等于“维度多”',
    '',
    markdownTable(
      ['域', '平均候选', '平均候选维度', '平均详情条数', '平均详情维度'],
      domains.map(([domain, item]) => [domain, item.candidate_count_mean, item.pool_dimension_mean, item.detail_selected_mean, item.detail_dimension_mean]),
    ),
    '',
    '支出常见的分类周同比和商户周同比在数字上是两个候选，但语义上都属于 period comparison。本地修改已经阻止它们同时占详情槽位，这是正确方向；还需要把“事实/上下文/个人基线/模式/行动提示”定义成 Surface 级覆盖目标。',
    '',
    `睡眠阶段候选生成 ${sleep.candidate_visibility.sleep_stage_composition.generated} 次，却仅 ${sleep.candidate_visibility.sleep_stage_composition.selected_record_detail} 次进入详情；评分候选生成 ${sleep.candidate_visibility.sleep_quality_current.generated} 次，仅 ${sleep.candidate_visibility.sleep_quality_current.selected_record_detail} 次进入详情。最常见详情组合是 ${topEntries(sleep.detail_combinations, 1)[0]?.[0]}，出现 ${topEntries(sleep.detail_combinations, 1)[0]?.[1]} 次。候选池看似丰富，最终展示仍高度固定。`,
    '',
    '### 5.3 Surface 没有真正按用户价值分工',
    '',
    markdownTable(
      ['Surface', '静默记录', '第一候选 Top key', 'Top 占比'],
      Object.entries(analysis.surfaces).map(([surface, item]) => [surface, `${item.silent_records}/${item.records}`, item.top_first_key, `${item.top_first_key_share_pct}%`]),
    ),
    '',
    `food_record_context 在 ${food.context_selected_first_for_shortcut} 条饮食记录里成为快捷通知第一候选。原因是通知阈值未通过时，exact-fact fallback 仍按同一套候选分数选最高项；record_context 默认 importance 高于 current metric。发生时间和餐次适合详情固定字段，但通常不值得单独发通知。`,
    '',
    '建议明确 Surface 价值函数：快捷通知只放新颖、及时、可行动且高置信的变化；AI 卡片放一条有解释价值的补充；记录详情展示 2–3 个互补维度；周报优先趋势和聚合，不重复单笔事实。',
    '',
    '## 六、重复数据与回放边界',
    '',
    `按同用户、同域、同发生时间，并去除 ai_feedback、companion_message 和 time_context 后的核心内容签名，发现 ${duplicates.length} 组高度疑似重复，涉及 ${duplicates.reduce((sum, group) => sum + group.count, 0)} 条记录。它们不能自动删除，但必须进入 duplicate fact gate，否则会污染计数、中位数和“复现”候选。`,
    '',
    ...duplicates.slice(0, 8).map(group => `- ${group.count} 条：${group.records.map(formatSample).join('；')}`),
    '',
    `样本也高度集中：最大单一脱敏用户占 ${analysis.user_concentration.top_user_records}/${analysis.overview.rows}（${analysis.user_concentration.top_user_share_pct}%）；饮食域最大用户占 ${analysis.user_concentration.by_domain.food.top_user_share_pct}%，睡眠域占 ${analysis.user_concentration.by_domain.sleep.top_user_share_pct}%。因此它能很好地发现该用户真实问题，但不能代表全体用户分布。`,
    '',
    '### 6.1 旧 Shadow 对照范围有限',
    '',
    `717 条中有旧 Shadow 数据 ${replayComparison.old_shadow_rows} 条，真正状态可比 ${replayComparison.comparable_rows} 条（${replayComparison.comparable_pct}%）。其中候选集合变化 ${replayComparison.candidate_set_changed} 条，详情选择变化 ${replayComparison.record_detail_selection_changed} 条，快捷通知变化 ${replayComparison.shortcut_selection_changed} 条。food/sleep 的丰富度改善是真实的，但可比样本太少，且 P0 事实错误尚未清理，不能据此直接判断全面生产效果。`,
    '',
    '## 七、真实点评能告诉我们什么',
    '',
    markdownTable(['主题', '条数'], Object.entries(feedback.topic_counts)),
    '',
    ...feedback.rows.map(item => `- ${item.created_at} · ${item.domain_key ?? '未关联域'} · ${item.surface ?? '无 surface'} · ${item.usable_record_detail ? '可作详情监督' : '不可作当前详情监督'}：${item.free_text || '(无文本)'}`),
    '',
    `这 ${feedback.feedback_count} 条反馈可以作为问题发现证据，但当前只有 ${feedback.usable_record_detail_feedback} 条是可用的详情曝光监督。建议从 717 条中分层抽取 100–200 条，人工标注 fact correctness、candidate completeness、ranking、within-plan diversity、surface fit、render overreach、expected action 和 root layer。717 条原始记录本身不能直接“训练”；它们可以稳定地做回归输入。`,
    '',
    '## 八、改进顺序',
    '',
    markdownTable(
      ['优先级', '改动层', '具体动作', '验收指标'],
      [
        ['P0', '事实解析', '修复 null/空字符串数值解析；睡眠缺字段不生成 0；补单元测试', '伪 0 候选为 0；事实错误为 0'],
        ['P0', '统计作用域', '钱包按账户 identity 与 asset/liability kind 分组；禁止跨口径 previous/median', '跨账户、跨 kind 比较为 0'],
        ['P0', '事实契约', '还款/转账/消费方向分流；单位、估算、重复记录、睡眠 session type gate', '人工集方向错误为 0'],
        ['P0', '因果与审计', '画像 as_of/version；Shadow 顺序确定；点评精确绑定 exposure/candidate；保留 evidence/numbers', '无未来泄漏、错归因；候选证据可追溯'],
        ['P1', '候选生成', '支出单笔事实/时间/支付上下文；各候选族独立依赖，取消主指标总早退', '支出零候选有 reason code；基础事实覆盖显著提高'],
        ['P1', '领域候选', '运动强度/距离/配速；阅读进度/书名；饮食营养与置信度；睡眠时点/结构', '每个高频域至少 3 个有效候选族'],
        ['P2', 'Surface 组合', '按 Surface 价值、信息增益和 diversity group 选取；context 不做通知 fallback', '详情 >=2 维覆盖提高；通知重复率下降'],
        ['P2', '评分', '加入幅度、证据、一致性、时效、行动价值等记录级特征', '同 key 分数有合理方差且可解释'],
        ['P3', '反馈学习', '100–200 条人工集 + 线上真实 exposure；质量错误与偏好标签分流', '标签规模和一致性达标后才校准权重/LTR'],
      ],
    ),
    '',
    '每轮只改一层并对同一固定快照重放：先 P0 事实层，再 P1 候选层，再 P2 组合/评分。否则指标变化无法归因。',
    '',
    '## 九、什么时候算进入“第二阶段”',
    '',
    '项目文档里有三套编号：设计路线的 Phase 2 是 Shadow；生产 rollout 的阶段 2 是 owner-only；冻结实践计划的阶段 2 是 Planner v0.2。按当前讨论，最合适的说法是：**本地已经开始 Planner v0.2 实验，但尚未完成阶段 2 准入；生产仍未满足 owner-only 条件。**',
    '',
    '进入本地 Planner v0.2 正式迭代前，至少要完成 P0 事实修复、100–200 条分层人工标注、zero-candidate reason code 和固定快照验收。进入生产 owner-only 前，还要从真实 origin/main 重建工作树，获准部署 Shadow，并连续 7 天满足：主流程无故障、曝光/反馈写入成功率 >=99.9%、阈值变化可追溯、质量问题误入偏好为 0、写入幂等、人工抽查无方向错误扩大，以及可用 kill switch。',
    '',
    '现在没有可信的固定日期。即使所有修复今天完成并在 2026-07-23 获准部署，理论最早也要在连续观察 7 天后的 2026-07-30 才能评估 owner-only；当前未部署且人工集未完成，所以这只是理论下限，不是承诺日期。',
    '',
    '## 十、Git 与部署风险',
    '',
    '当前 `表达规划器第二阶段` 工作树不是正常的 origin/main 基线：HEAD 不存在、分支显示 No commits yet、全仓库呈 staged A。这个目录不能安全 commit，更不能 push。下一轮实现必须从干净的 `origin/main` 重新建立中文独立工作树，再按文件级 diff 搬运已验证改动。',
    '',
    '此外，当前 deploy workflow 对 `tools/ai-validation/expression-planner/**` 也会触发生产 Edge Function 部署，范围过宽；CI 尚未把敏感路径扫描和固定快照回归作为门禁。即便未来提交纯分析工具，也应先修正或确认部署触发规则。',
    '',
    '## 十一、产物与复跑',
    '',
    '- `analysis.json`：完整机器可读统计和真实样本索引。',
    '- `详细分析.md`：本报告。',
    '- `逐条查看.html`：逐条核对真实记录、旧 Shadow、本地候选和 Surface 入选。',
    '',
    '复跑命令：',
    '',
    '```powershell',
    `node tools/ai-validation/expression-planner/analyze-production-replay.mjs --run="${runDir}"`,
    '```',
    '',
  ]
  return lines.join('\n')
}

async function main() {
  const { runDir } = parseArgs(process.argv.slice(2))
  const [source, replay, summary] = await Promise.all([
    readFile(path.join(runDir, 'source.snapshot.json'), 'utf8').then(JSON.parse),
    readFile(path.join(runDir, 'replay-results.json'), 'utf8').then(JSON.parse),
    readFile(path.join(runDir, 'summary.json'), 'utf8').then(JSON.parse),
  ])
  const rows = replay.rows.filter(row => row.comparison)
  const domains = Object.fromEntries([...new Set(rows.map(row => row.domain_key))].sort().map(domainKey => {
    const scoped = rows.filter(row => row.domain_key === domainKey)
    return [domainKey, domainCandidateMetrics(scoped)]
  }))
  const occurred = rows.map(row => new Date(row.occurred_at).getTime()).filter(Number.isFinite)
  const expenseRows = rows.filter(row => row.domain_key === 'expense')
  const foodRows = rows.filter(row => row.domain_key === 'food')
  const sleepRows = rows.filter(row => row.domain_key === 'sleep')
  const sportRows = rows.filter(row => row.domain_key === 'sport')
  const walletRows = rows.filter(row => row.domain_key === 'wallet')
  const genericRows = rows.filter(row => row.domain_key !== 'expense')
  const analysis = {
    schema_version: 'expression-production-replay-analysis-v0.1',
    generated_at: new Date().toISOString(),
    source_generated_at: replay.generated_at,
    run_directory: runDir,
    planner_git: replay.planner_git,
    overview: {
      rows: rows.length,
      users: new Set(rows.map(row => row.user_key)).size,
      first_occurred_at: occurred.length ? new Date(Math.min(...occurred)).toISOString() : null,
      last_occurred_at: occurred.length ? new Date(Math.max(...occurred)).toISOString() : null,
      source_counts: summary.source_counts,
    },
    transaction_replay_coverage: transactionReplayCoverage(source, rows),
    domains,
    semantic_keys: semanticKeyStats(rows),
    fixed_score_contrasts: fixedScoreContrasts(rows),
    surfaces: surfaceStats(rows),
    combinations: combinationStats(rows),
    replay_comparison: replayComparisonAnalysis(rows),
    user_concentration: userConcentration(rows),
    duplicate_groups: duplicateGroups(rows),
    attribute_utilization: Object.fromEntries(['food', 'sleep', 'sport', 'reading', 'wallet'].map(domainKey => [domainKey, attributeUtilization(rows.filter(row => row.domain_key === domainKey), domainKey)])),
    domain_findings: {
      expense: expenseZeroAnalysis(expenseRows),
      generic_zero: genericZeroAnalysis(genericRows),
      sleep: sleepAnalysis(sleepRows),
      food: foodAnalysis(foodRows),
      sport: sportAnalysis(sportRows),
      wallet: walletAnalysis(walletRows),
    },
    feedback: feedbackAnalysis(source),
    shadow: shadowAnalysis(source),
  }
  await writeFile(path.join(runDir, 'analysis.json'), `${JSON.stringify(analysis, null, 2)}\n`, 'utf8')
  await writeFile(path.join(runDir, '详细分析.md'), `${buildReport(analysis, runDir)}\n`, 'utf8')
  process.stdout.write(`${JSON.stringify({
    analysis: path.join(runDir, 'analysis.json'),
    report: path.join(runDir, '详细分析.md'),
    rows: rows.length,
    p0: {
      sleep_quality_false: analysis.domain_findings.sleep.quality_candidates_from_missing_field,
      sleep_stage_all_missing: analysis.domain_findings.sleep.stage_candidates_with_all_fields_missing,
      wallet_cross_account: analysis.domain_findings.wallet.cross_account_previous_comparisons,
    },
  }, null, 2)}\n`)
}

await main()
