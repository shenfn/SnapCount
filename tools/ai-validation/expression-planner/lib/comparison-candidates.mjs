function roundMoney(value) {
  return Math.round(value * 100) / 100
}

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
  const amounts = items.map(item => Number(item.amount)).filter(Number.isFinite)
  return {
    count: amounts.length,
    total: roundMoney(amounts.reduce((sum, amount) => sum + amount, 0)),
  }
}

function signedPercent(current, baseline) {
  if (!baseline) return null
  return roundMoney(((current - baseline) / baseline) * 100)
}

function recordEvidence(records) {
  return records.map(record => ({
    source_type: 'transaction',
    source_id: record.id,
    fields: {
      amount: Number(record.amount),
      transaction_date: record.transaction_date,
      occurred_at: record.occurred_at,
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

function comparisonCandidate({ id, semanticKey, dimension, value, text, evidence, numbers, quality }) {
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
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

export function generateComparisonCandidates({ records, currentDayEvents, entityId, localDate }) {
  const historicalRecords = records
    .filter(record => !entityId || record.merchant?.entity_id === entityId)
    .filter(record => record.transaction_date < localDate)
  const trustedCurrentEvents = currentDayEvents
    .filter(event => event.count_in_facts && event.amount !== null)
    .filter(event => !entityId || event.merchant?.entity_id === entityId)
  const currentDay = summarizeAmounts(trustedCurrentEvents)
  const candidates = []

  const byDate = new Map()
  for (const record of historicalRecords) {
    if (!byDate.has(record.transaction_date)) byDate.set(record.transaction_date, [])
    byDate.get(record.transaction_date).push(record)
  }
  const activeDays = [...byDate.entries()].map(([date, dayRecords]) => ({ date, records: dayRecords, ...summarizeAmounts(dayRecords) }))
  if (currentDay.count > 0 && activeDays.length >= 3) {
    const medianCount = median(activeDays.map(day => day.count))
    const medianTotal = median(activeDays.map(day => day.total))
    const countDelta = currentDay.count - medianCount
    const totalDelta = roundMoney(currentDay.total - medianTotal)
    candidates.push(comparisonCandidate({
      id: `comparison:${entityId}:daily-active-median:${localDate}`,
      semanticKey: 'merchant_daily_vs_active_day_median',
      dimension: 'personal_baseline',
      value: {
        entity_id: entityId,
        current_date: localDate,
        current: currentDay,
        baseline: { kind: 'historical_active_day_median', sample_days: activeDays.length, count: medianCount, total: medianTotal },
        delta: { count: countDelta, total: totalDelta, count_percent: signedPercent(currentDay.count, medianCount), total_percent: signedPercent(currentDay.total, medianTotal) },
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
  const currentWeek = summarizeAmounts([...currentPriorRecords, ...trustedCurrentEvents])
  const previousWeek = summarizeAmounts(previousPeriodRecords)
  if (currentWeek.count > 0 && previousWeek.count > 0) {
    candidates.push(comparisonCandidate({
      id: `comparison:${entityId}:week-over-week-to-date:${localDate}`,
      semanticKey: 'merchant_week_to_date_vs_previous_week_same_period',
      dimension: 'period_comparison',
      value: {
        entity_id: entityId,
        current_period: { start: currentWeekStart, end: localDate, ...currentWeek },
        baseline_period: { start: previousWeekStart, end: previousWeekEnd, ...previousWeek },
        delta: {
          count: currentWeek.count - previousWeek.count,
          total: roundMoney(currentWeek.total - previousWeek.total),
          count_percent: signedPercent(currentWeek.count, previousWeek.count),
          total_percent: signedPercent(currentWeek.total, previousWeek.total),
        },
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
