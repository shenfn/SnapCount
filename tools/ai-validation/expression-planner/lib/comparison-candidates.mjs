const COMPARISON_TIME_ZONE = 'Asia/Shanghai'
const COMPARISON_TIME_ZONE_OFFSET = '+08:00'

import { parseFiniteNumber, roundMoney } from './expression-core-adapter.mjs'

function dateAtUtc(localDate) {
  return new Date(`${localDate}T00:00:00Z`)
}

function addDays(localDate, days) {
  const date = dateAtUtc(localDate)
  date.setUTCDate(date.getUTCDate() + days)
  return date.toISOString().slice(0, 10)
}

function startOfWeek(localDate) {
  const date = dateAtUtc(localDate)
  const mondayOffset = (date.getUTCDay() + 6) % 7
  return addDays(localDate, -mondayOffset)
}

function median(values) {
  if (!values.length) return null
  const sorted = [...values].sort((left, right) => left - right)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : roundMoney((sorted[middle - 1] + sorted[middle]) / 2)
}

function summarizeAmounts(items) {
  const amounts = items.map(item => parseFiniteNumber(item.amount)).filter(amount => amount !== null)
  return {
    count: amounts.length,
    total: roundMoney(amounts.reduce((sum, amount) => sum + amount, 0)),
  }
}

function signedPercent(current, baseline) {
  if (!baseline) return null
  return roundMoney(((current - baseline) / baseline) * 100)
}

function directionOf(delta) {
  if (delta > 0) return 'increase'
  if (delta < 0) return 'decrease'
  return 'unchanged'
}

function metricChange(current, baseline) {
  const delta = roundMoney(current - baseline)
  return {
    current,
    baseline,
    delta,
    delta_percent: signedPercent(current, baseline),
    direction: directionOf(delta),
  }
}

function zonedDateTimeParts(timestamp, timeZone = COMPARISON_TIME_ZONE) {
  const date = new Date(timestamp)
  if (!Number.isFinite(date.getTime())) return null
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(date)
  return Object.fromEntries(parts.map(part => [part.type, part.value]))
}

function zonedIso(timestamp) {
  const parts = zonedDateTimeParts(timestamp)
  if (!parts) return null
  return `${parts.year}-${parts.month}-${parts.day}T${parts.hour}:${parts.minute}:${parts.second}${COMPARISON_TIME_ZONE_OFFSET}`
}

function cutoffLabel(timestamp) {
  const parts = zonedDateTimeParts(timestamp)
  if (!parts) return '当前时点'
  return `${Number(parts.month)} 月 ${Number(parts.day)} 日 ${parts.hour}:${parts.minute}`
}

function recordEvidence(records) {
  return records.map(record => ({
    source_type: 'transaction',
    source_id: record.id,
    ledger_status: record.fact_contract?.fact_status ?? 'confirmed',
    fields: {
      amount: parseFiniteNumber(record.amount),
      transaction_date: record.transaction_date,
      occurred_at: record.occurred_at,
      category: record.category ?? null,
      comparison_cohort: record.fact_contract?.comparison_cohort ?? null,
    },
  }))
}

function ledgerEvidence(events) {
  return events.map(event => ({
    source_type: event.source_type,
    source_id: event.event_id,
    ledger_status: event.ledger_status,
    fields: { amount: event.amount, event_at: event.event_at, known_at: event.known_at },
  }))
}

function comparisonCandidate({ id, semanticKey, dimension, value, text, evidence, numbers, quality, selectionHints }) {
  return {
    candidate_id: id,
    candidate_version: 'candidate-v0.1',
    domain_key: 'expense',
    dimension,
    claim_type: 'comparison',
    comparison_subtype: 'period_baseline',
    interaction_mode: 'inform',
    claim: { semantic_key: semanticKey, structured_value: value, canonical_text: text },
    evidence,
    numbers,
    quality,
    selection_hints: selectionHints ?? {},
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

function periodSummarySelectionHints(periodStart) {
  return {
    delivery_scope: 'period_summary',
    cadence_scope: `calendar_week:${periodStart}`,
    allowed_surfaces: ['weekly_report'],
  }
}

/**
 * @param {{
 *   records: any[],
 *   currentDayEvents: any[],
 *   entityId?: string | null,
 *   localDate: string,
 *   currentRecordId?: string | null,
 * }} input
 */
export function generateComparisonCandidates({ records, currentDayEvents, entityId, localDate, currentRecordId = null }) {
  const historicalRecords = records
    .map(record => ({ ...record, amount: parseFiniteNumber(record.amount) }))
    .filter(record => record.amount !== null)
    .filter(record => !entityId || record.merchant?.entity_id === entityId)
    .filter(record => record.transaction_date < localDate)
  const trustedCurrentEvents = currentDayEvents
    .map(event => ({ ...event, amount: parseFiniteNumber(event.amount) }))
    .filter(event => event.count_in_facts && event.amount !== null)
    .filter(event => !entityId || event.merchant?.entity_id === entityId)
  const currentDay = summarizeAmounts(trustedCurrentEvents)
  const candidates = []

  const byDate = new Map()
  for (const record of historicalRecords) {
    if (!byDate.has(record.transaction_date)) byDate.set(record.transaction_date, [])
    byDate.get(record.transaction_date).push(record)
  }
  const activeDays = [...byDate.entries()]
    .map(([date, dayRecords]) => ({ date, records: dayRecords, ...summarizeAmounts(dayRecords) }))
    .filter(day => day.count > 0)
  if (currentDay.count > 0 && activeDays.length >= 3) {
    const medianCount = median(activeDays.map(day => day.count))
    const medianTotal = median(activeDays.map(day => day.total))
    const countMetric = metricChange(currentDay.count, medianCount)
    const totalMetric = metricChange(currentDay.total, medianTotal)
    candidates.push(comparisonCandidate({
      id: `comparison:${entityId}:daily-active-median:${localDate}:${currentRecordId ?? localDate}`,
      semanticKey: 'merchant_daily_vs_active_day_median',
      dimension: 'personal_baseline',
      selectionHints: {
        exposure_key: `expense:merchant:${entityId}:daily_active_median:${localDate}`,
        dedupe_key: `expense:merchant:${entityId}:daily_active_median:${localDate}`,
        max_exposure_count: { pwa_pending_ai_card: 1, record_detail: 1 },
      },
      value: {
        entity_id: entityId,
        current_date: localDate,
        current: currentDay,
        baseline: { kind: 'historical_active_day_median', sample_days: activeDays.length, count: medianCount, total: medianTotal },
        delta: { count: countMetric.delta, total: totalMetric.delta, count_percent: countMetric.delta_percent, total_percent: totalMetric.delta_percent },
        metrics: { count: countMetric, total: totalMetric },
        directions: { count: countMetric.direction, total: totalMetric.direction },
        narrative_focus: 'current_period',
      },
      text: `${localDate} 共 ${currentDay.count} 笔、${currentDay.total} 元；历史活跃日中位数为 ${medianCount} 笔、${medianTotal} 元`,
      evidence: [...ledgerEvidence(trustedCurrentEvents), ...recordEvidence(historicalRecords)],
      numbers: [
        { value: currentDay.count, meaning: 'current_day_count', derivation: 'count(current_day_fact_events)' },
        { value: currentDay.total, meaning: 'current_day_total', derivation: 'sum(current_day_fact_events.amount)' },
        { value: medianCount, meaning: 'historical_active_day_median_count', derivation: 'median(group_count_by_active_date)' },
        { value: medianTotal, meaning: 'historical_active_day_median_total', derivation: 'median(group_total_by_active_date)' },
      ],
      quality: { confidence: 0.9, sample_count: activeDays.length, data_coverage: 1 },
    }))
  }

  const currentWeekStart = startOfWeek(localDate)
  const elapsedDays = Math.round((dateAtUtc(localDate) - dateAtUtc(currentWeekStart)) / 86400000)
  const previousWeekStart = addDays(currentWeekStart, -7)
  const previousWeekEnd = addDays(previousWeekStart, elapsedDays)
  const currentPriorRecords = historicalRecords.filter(record => record.transaction_date >= currentWeekStart && record.transaction_date < localDate)
  const previousPeriodRecords = historicalRecords.filter(record => record.transaction_date >= previousWeekStart && record.transaction_date <= previousWeekEnd)
  const currentPeriodRecords = [...currentPriorRecords, ...trustedCurrentEvents]
  const latestCurrentPeriod = currentPeriodRecords
    .map(record => ({ record, occurredAt: new Date(record.occurred_at ?? `${record.transaction_date}T00:00:00${COMPARISON_TIME_ZONE_OFFSET}`).getTime() }))
    .filter(item => Number.isFinite(item.occurredAt))
    .sort((left, right) => right.occurredAt - left.occurredAt)[0]?.record
  const periodOwner = !currentRecordId || latestCurrentPeriod?.id === currentRecordId || latestCurrentPeriod?.event_id === `transaction:${currentRecordId}`
  const currentWeek = summarizeAmounts([...currentPriorRecords, ...trustedCurrentEvents])
  const previousWeek = summarizeAmounts(previousPeriodRecords)
  if (currentWeek.count > 0 && previousWeek.count > 0) {
    const countMetric = metricChange(currentWeek.count, previousWeek.count)
    const totalMetric = metricChange(currentWeek.total, previousWeek.total)
    const averageMetric = metricChange(roundMoney(currentWeek.total / currentWeek.count), roundMoney(previousWeek.total / previousWeek.count))
    candidates.push(comparisonCandidate({
      id: `comparison:${entityId}:week-over-week-to-date:${localDate}:${currentRecordId ?? localDate}`,
      semanticKey: 'merchant_week_to_date_vs_previous_week_same_period',
      dimension: 'period_comparison',
      selectionHints: {
        ...periodSummarySelectionHints(currentWeekStart),
        diversity_groups: {
          weekly_report: 'expense_week_to_date_comparison',
        },
        exposure_key: `expense:merchant:${entityId}:week_to_date:${currentWeekStart}`,
        dedupe_key: `expense:merchant:${entityId}:week_to_date:${currentWeekStart}`,
        period_owner: periodOwner,
        max_exposure_count: { weekly_report: 1 },
      },
      value: {
        entity_id: entityId,
        comparison_window: {
          kind: 'week_to_date_same_elapsed_date',
          time_zone: COMPARISON_TIME_ZONE,
          current_end_date: localDate,
          baseline_end_date: previousWeekEnd,
        },
        current_period: { start: currentWeekStart, end: localDate, ...currentWeek },
        baseline_period: { start: previousWeekStart, end: previousWeekEnd, ...previousWeek },
        delta: {
          count: countMetric.delta,
          total: totalMetric.delta,
          average: averageMetric.delta,
          count_percent: countMetric.delta_percent,
          total_percent: totalMetric.delta_percent,
          average_percent: averageMetric.delta_percent,
        },
        metrics: { count: countMetric, total: totalMetric, average: averageMetric },
        directions: { count: countMetric.direction, total: totalMetric.direction, average: averageMetric.direction },
        narrative_focus: 'current_period',
      },
      text: `本周截至 ${localDate} 共 ${currentWeek.count} 笔、${currentWeek.total} 元；上周同期为 ${previousWeek.count} 笔、${previousWeek.total} 元`,
      evidence: [...recordEvidence(currentPriorRecords), ...ledgerEvidence(trustedCurrentEvents), ...recordEvidence(previousPeriodRecords)],
      numbers: [
        { value: currentWeek.count, meaning: 'current_week_to_date_count', derivation: 'count(current_week_prior_records)+count(current_day_fact_events)' },
        { value: currentWeek.total, meaning: 'current_week_to_date_total', derivation: 'sum(current_week_prior_records.amount)+sum(current_day_fact_events.amount)' },
        { value: previousWeek.count, meaning: 'previous_week_same_period_count', derivation: 'count(previous_week_same_elapsed_days_records)' },
        { value: previousWeek.total, meaning: 'previous_week_same_period_total', derivation: 'sum(previous_week_same_elapsed_days_records.amount)' },
      ],
      quality: { confidence: 0.95, sample_count: currentWeek.count + previousWeek.count, data_coverage: 1 },
    }))
  }

  return candidates
}

function categoryLabel(category) {
  return ({
    food: '餐饮', shopping: '购物', transport: '出行', entertainment: '娱乐',
    life: '生活', health: '健康', education: '教育', other: '其他',
  })[category] ?? category
}

function inTimeRange(record, startAt, endAt) {
  const occurredAt = new Date(record.occurred_at).getTime()
  return Number.isFinite(occurredAt) && occurredAt >= startAt && occurredAt <= endAt
}

function average(total, count) {
  return count > 0 ? roundMoney(total / count) : null
}

function directionToken(direction) {
  return ({ increase: 'up', decrease: 'down', unchanged: 'stable' })[direction]
}

function symmetricCountAverageDecomposition(current, baseline, totalDelta) {
  const currentAverage = current.total / current.count
  const baselineAverage = baseline.total / baseline.count
  const frequencyEffect = roundMoney((current.count - baseline.count) * ((currentAverage + baselineAverage) / 2))
  const averageEffect = roundMoney(totalDelta - frequencyEffect)
  const frequencyMagnitude = Math.abs(frequencyEffect)
  const averageMagnitude = Math.abs(averageEffect)
  let dominantEffect = 'none'
  if (frequencyMagnitude > averageMagnitude) dominantEffect = 'record_frequency'
  else if (averageMagnitude > frequencyMagnitude) dominantEffect = 'average_amount'
  else if (frequencyMagnitude > 0) dominantEffect = 'balanced'
  return {
    method: 'symmetric_count_average_v1',
    frequency_effect_amount: frequencyEffect,
    average_effect_amount: averageEffect,
    net_delta: totalDelta,
    dominant_effect: dominantEffect,
    offsetting: frequencyEffect * averageEffect < 0,
  }
}

function deltaClause(delta, { positive, negative, stable, unit }) {
  if (delta > 0) return `${positive} ${Math.abs(delta)} ${unit}`
  if (delta < 0) return `${negative} ${Math.abs(delta)} ${unit}`
  return stable
}

export function generateCategoryComparisonCandidates({ records, currentRecord }) {
  const category = currentRecord?.category
  const cohort = currentRecord?.fact_contract?.comparison_cohort
  if (!category || !cohort?.startsWith('expense.category.') || parseFiniteNumber(currentRecord.amount) === null) return []

  const currentAt = new Date(currentRecord.occurred_at).getTime()
  if (!Number.isFinite(currentAt)) return []
  const currentWeekStartDate = startOfWeek(currentRecord.transaction_date)
  const currentWeekStartAt = new Date(`${currentWeekStartDate}T00:00:00${COMPARISON_TIME_ZONE_OFFSET}`).getTime()
  const previousWeekStartAt = currentWeekStartAt - 7 * 86400000
  const previousCutoffAt = currentAt - 7 * 86400000

  const sameCohort = records.filter(record => record.fact_contract?.comparison_cohort === cohort)
  const confirmed = sameCohort.filter(record => record.fact_contract?.comparison_scope === 'include')
  const pending = sameCohort.filter(record => record.fact_contract?.comparison_scope === 'pending_review')
  const currentConfirmed = confirmed.filter(record => inTimeRange(record, currentWeekStartAt, currentAt))
  const previousConfirmed = confirmed.filter(record => inTimeRange(record, previousWeekStartAt, previousCutoffAt))
  const currentRecords = currentConfirmed.filter(record => parseFiniteNumber(record.amount) !== null)
  const previousRecords = previousConfirmed.filter(record => parseFiniteNumber(record.amount) !== null)
  if (!currentRecords.length || !previousRecords.length) return []

  const currentPending = pending.filter(record => inTimeRange(record, currentWeekStartAt, currentAt))
  const previousPending = pending.filter(record => inTimeRange(record, previousWeekStartAt, previousCutoffAt))
  const currentInvalidAmountCount = currentConfirmed.length - currentRecords.length
  const baselineInvalidAmountCount = previousConfirmed.length - previousRecords.length
  const invalidAmountCount = currentInvalidAmountCount + baselineInvalidAmountCount
  const current = summarizeAmounts(currentRecords)
  const baseline = summarizeAmounts(previousRecords)
  if (!current.count || !baseline.count) return []
  current.average = average(current.total, current.count)
  baseline.average = average(baseline.total, baseline.count)
  const pendingCount = currentPending.length + previousPending.length
  const confirmedCount = current.count + baseline.count
  const unavailableCount = pendingCount + invalidAmountCount
  const dataCoverage = roundMoney(confirmedCount / (confirmedCount + unavailableCount))
  const totalMetric = metricChange(current.total, baseline.total)
  const countMetric = metricChange(current.count, baseline.count)
  const averageMetric = metricChange(current.average, baseline.average)
  const directions = {
    total: totalMetric.direction,
    count: countMetric.direction,
    average: averageMetric.direction,
  }
  const decomposition = symmetricCountAverageDecomposition(current, baseline, totalMetric.delta)
  const driver = ['record_frequency', 'average_amount'].includes(decomposition.dominant_effect)
    ? decomposition.dominant_effect
    : 'mixed'
  const changePattern = `count_${directionToken(directions.count)}_average_${directionToken(directions.average)}_total_${directionToken(directions.total)}`
  const label = categoryLabel(category)
  const currentEndAt = zonedIso(currentAt)
  const baselineEndAt = zonedIso(previousCutoffAt)
  const totalText = deltaClause(totalMetric.delta, { positive: '合计多', negative: '合计少', stable: '合计持平', unit: '元' })
  const countText = deltaClause(countMetric.delta, { positive: '笔数多', negative: '笔数少', stable: '笔数相同', unit: '笔' })
  const averageText = deltaClause(averageMetric.delta, { positive: '单笔均价高', negative: '单笔均价低', stable: '单笔均价持平', unit: '元' })

  return [comparisonCandidate({
      id: `comparison:${cohort}:week-over-week-same-time:${currentRecord.transaction_date}:${currentRecord.id}`,
    semanticKey: 'expense_category_week_to_date_vs_previous_week_same_period',
    dimension: 'category_period_comparison',
    selectionHints: {
      ...periodSummarySelectionHints(currentWeekStartDate),
      diversity_groups: {
        weekly_report: 'expense_week_to_date_comparison',
      },
      exposure_key: `expense:category:${cohort}:week_to_date:${currentWeekStartDate}`,
      dedupe_key: `expense:category:${cohort}:week_to_date:${currentWeekStartDate}`,
      period_owner: currentRecords
        .map(record => ({ record, occurredAt: new Date(record.occurred_at).getTime() }))
        .filter(item => Number.isFinite(item.occurredAt))
        .sort((left, right) => right.occurredAt - left.occurredAt)[0]?.record?.id === currentRecord.id,
      max_exposure_count: { weekly_report: 1 },
    },
    value: {
      comparison_cohort: cohort,
      category,
      comparison_window: {
        kind: 'week_to_date_same_elapsed_time',
        time_zone: COMPARISON_TIME_ZONE,
        as_of_at: currentEndAt,
        baseline_as_of_at: baselineEndAt,
      },
      current_period: { start: currentWeekStartDate, end_at: currentEndAt, ...current },
      baseline_period: { start: addDays(currentWeekStartDate, -7), end_at: baselineEndAt, ...baseline },
      metrics: { total: totalMetric, count: countMetric, average: averageMetric },
      directions,
      delta: {
        count: countMetric.delta,
        total: totalMetric.delta,
        average: averageMetric.delta,
        count_percent: countMetric.delta_percent,
        total_percent: totalMetric.delta_percent,
        average_percent: averageMetric.delta_percent,
      },
      driver,
      change_pattern: changePattern,
      decomposition,
      narrative_focus: 'current_period',
      pending_review_count: pendingCount,
      data_status: {
        current_confirmed_count: current.count,
        baseline_confirmed_count: baseline.count,
        current_pending_review_count: currentPending.length,
        baseline_pending_review_count: previousPending.length,
        current_invalid_amount_count: currentInvalidAmountCount,
        baseline_invalid_amount_count: baselineInvalidAmountCount,
        invalid_amount_count: invalidAmountCount,
        data_coverage: dataCoverage,
      },
    },
    text: `本周截至 ${cutoffLabel(currentAt)}，已确认${label}类 ${current.count} 笔、${current.total} 元；上周同期截至 ${cutoffLabel(previousCutoffAt)} 为 ${baseline.count} 笔、${baseline.total} 元。${totalText}，${countText}，${averageText}。`,
    evidence: [...recordEvidence(currentRecords), ...recordEvidence(previousRecords)],
    numbers: [
      { value: current.count, meaning: 'current_category_record_count', derivation: 'count(current_period_confirmed_category_records)' },
      { value: current.total, meaning: 'current_category_total', derivation: 'sum(current_period_confirmed_category_records.amount)' },
      { value: baseline.count, meaning: 'baseline_category_record_count', derivation: 'count(previous_period_confirmed_category_records)' },
      { value: baseline.total, meaning: 'baseline_category_total', derivation: 'sum(previous_period_confirmed_category_records.amount)' },
      { value: countMetric.delta, meaning: 'category_record_count_delta', derivation: 'current_count-baseline_count' },
      { value: totalMetric.delta, meaning: 'category_total_delta', derivation: 'current_total-baseline_total' },
      { value: averageMetric.delta, meaning: 'category_average_delta', derivation: 'current_average-baseline_average' },
      { value: decomposition.frequency_effect_amount, meaning: 'frequency_effect_amount', derivation: 'symmetric_count_average_v1' },
      { value: decomposition.average_effect_amount, meaning: 'average_effect_amount', derivation: 'symmetric_count_average_v1' },
      { value: dataCoverage, meaning: 'category_data_coverage', derivation: 'confirmed_count/(confirmed_count+pending_review_count+invalid_amount_count)' },
    ],
    quality: {
      confidence: roundMoney(0.75 + 0.2 * dataCoverage),
      sample_count: confirmedCount,
      data_coverage: dataCoverage,
      pending_review_count: pendingCount,
      invalid_amount_count: invalidAmountCount,
    },
  })]
}
