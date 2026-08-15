import { parseFiniteNumber } from './expression-core-adapter.mjs'

function timestamp(value) {
  const parsed = new Date(value).getTime()
  return Number.isFinite(parsed) ? parsed : null
}

function preciseEventTime(event) {
  return ['minute', 'second', 'exact'].includes(String(event?.event_time_precision ?? ''))
}

function dateKey(event, timeZone) {
  if (typeof event?.transaction_date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(event.transaction_date)) {
    return event.transaction_date
  }
  const eventAt = timestamp(event?.event_at)
  if (eventAt === null) return null
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(eventAt))
}

function calendarDayDifference(previousDate, currentDate) {
  if (!previousDate || !currentDate) return null
  const previous = timestamp(`${previousDate}T00:00:00Z`)
  const current = timestamp(`${currentDate}T00:00:00Z`)
  if (previous === null || current === null) return null
  return Math.round((current - previous) / 86400000)
}

function durationFromMinutes(totalMinutes) {
  const days = Math.floor(totalMinutes / 1440)
  const hours = Math.floor((totalMinutes % 1440) / 60)
  const minutes = totalMinutes % 60
  const parts = [
    days > 0 ? `${days} 天` : null,
    hours > 0 ? `${hours} 小时` : null,
    minutes > 0 ? `${minutes} 分钟` : null,
  ].filter(Boolean)
  return { days, hours, minutes, display_text: parts.join(' ') || '不足 1 分钟' }
}

function gapBetween(previous, current, timeZone) {
  const previousAt = timestamp(previous.event_at)
  const currentAt = timestamp(current.event_at)
  if (preciseEventTime(previous) && preciseEventTime(current) && previousAt !== null && currentAt !== null) {
    const elapsedMinutes = Math.round((currentAt - previousAt) / 60000)
    if (elapsedMinutes <= 0) return null
    return {
      precision: 'minute',
      elapsed_minutes: elapsedMinutes,
      elapsed_calendar_days: calendarDayDifference(dateKey(previous, timeZone), dateKey(current, timeZone)),
      duration: durationFromMinutes(elapsedMinutes),
    }
  }

  const elapsedDays = calendarDayDifference(dateKey(previous, timeZone), dateKey(current, timeZone))
  if (elapsedDays === null || elapsedDays <= 0) return null
  return {
    precision: 'calendar_day',
    elapsed_minutes: null,
    elapsed_calendar_days: elapsedDays,
    duration: { days: elapsedDays, hours: null, minutes: null, display_text: `${elapsedDays} 天` },
  }
}

function knownBefore(previous, current) {
  const previousKnownAt = timestamp(previous.known_at)
  const currentKnownAt = timestamp(current.known_at)
  if (currentKnownAt === null) return true
  return previousKnownAt !== null && previousKnownAt < currentKnownAt
}

function eventSortTime(event, timeZone) {
  const eventAt = timestamp(event.event_at)
  if (eventAt !== null) return eventAt
  const date = dateKey(event, timeZone)
  return date ? timestamp(`${date}T00:00:00Z`) ?? Number.MIN_SAFE_INTEGER : Number.MIN_SAFE_INTEGER
}

function endpointConfidence(event, precision) {
  if (precision === 'calendar_day') return 0.9
  return Math.min(1, Math.max(0, parseFiniteNumber(event.event_time_confidence) ?? 0.5))
}

function evidenceEntry(event) {
  return {
    source_type: event.source_type,
    source_id: event.event_id,
    ledger_status: event.ledger_status,
    fields: {
      record_name: event.merchant?.canonical_name ?? event.merchant?.raw_name ?? null,
      normalized_record_name: event.merchant?.normalized_key ?? null,
      amount: event.amount ?? null,
      event_at: event.event_at ?? null,
      transaction_date: event.transaction_date ?? null,
      known_at: event.known_at ?? null,
      event_time_source: event.event_time_source ?? null,
      event_time_precision: event.event_time_precision ?? null,
      event_time_confidence: event.event_time_confidence ?? null,
    },
  }
}

function sameObservation(left, right) {
  const leftGroup = String(left?.observation_group ?? "").trim()
  const rightGroup = String(right?.observation_group ?? "").trim()
  if (leftGroup && rightGroup && leftGroup === rightGroup) return true
  if (!preciseEventTime(left) || !preciseEventTime(right)) return false
  return timestamp(left.event_at) === timestamp(right.event_at)
    && parseFiniteNumber(left.amount) === parseFiniteNumber(right.amount)
    && left.merchant?.normalized_key === right.merchant?.normalized_key
}

/**
 * @param {any[]} events
 * @param {{ currentEventId?: string | null, timeZone?: string }} options
 */
export function generateRecordNameRecurrenceCandidates(events, {
  currentEventId,
  timeZone = 'Asia/Shanghai',
} = {}) {
  if (!currentEventId || !Array.isArray(events)) return []
  const current = events.find(event => event.event_id === currentEventId)
  const normalizedName = current?.merchant?.normalized_key
  if (!current?.count_in_facts || !normalizedName) return []

  const prior = events
    .filter(event => event.event_id !== currentEventId)
    .filter(event => event.count_in_facts && event.merchant?.normalized_key === normalizedName)
    .filter(event => !sameObservation(event, current))
    .filter(event => knownBefore(event, current))
    .sort((left, right) => eventSortTime(right, timeZone) - eventSortTime(left, timeZone))
  const previous = prior[0]
  if (!previous) return []
  const gap = gapBetween(previous, current, timeZone)
  if (!gap) return []

  const recordName = current.merchant?.canonical_name ?? current.merchant?.raw_name ?? normalizedName
  const precision = gap.precision
  const confidence = Math.min(endpointConfidence(current, precision), endpointConfidence(previous, precision))
  const durationText = precision === 'calendar_day'
    ? `约 ${gap.duration.display_text}`
    : gap.duration.display_text
  return [{
    candidate_id: `fact:record-name:previous-gap:${current.event_id}`,
    candidate_version: 'candidate-v0.1',
    domain_key: 'expense',
    dimension: 'repeat_interval',
    claim_type: 'fact',
    fact_subtype: 'derived',
    interaction_mode: 'inform',
    claim: {
      semantic_key: 'expense_record_name_previous_gap',
      structured_value: {
        entity_id: current.merchant?.entity_id ?? null,
        record_name: recordName,
        normalized_record_name: normalizedName,
        match_basis: 'normalized_record_name_exact',
        current_record_id: current.target_id ?? current.event_id,
        previous_record_id: previous.target_id ?? previous.event_id,
        current_event_at: current.event_at,
        previous_event_at: previous.event_at,
        current_local_date: dateKey(current, timeZone),
        previous_local_date: dateKey(previous, timeZone),
        current_amount: parseFiniteNumber(current.amount),
        previous_amount: parseFiniteNumber(previous.amount),
        elapsed_minutes: gap.elapsed_minutes,
        elapsed_calendar_days: gap.elapsed_calendar_days,
        elapsed_duration: gap.duration,
        time_precision: precision,
        history_scope: 'nearest_available_causal_same_name_record',
      },
      canonical_text: `距离上一次同名记录已经过去 ${durationText}`,
    },
    evidence: [evidenceEntry(current), evidenceEntry(previous)],
    numbers: precision === 'minute'
      ? [
          { value: gap.elapsed_minutes, meaning: 'same_record_name_elapsed_minutes', derivation: 'current_event_at-previous_same_name_event_at' },
          { value: gap.duration.days, meaning: 'same_record_name_elapsed_days_component', derivation: 'floor(elapsed_minutes/1440)' },
          { value: gap.duration.hours, meaning: 'same_record_name_elapsed_hours_component', derivation: 'floor((elapsed_minutes%1440)/60)' },
          { value: gap.duration.minutes, meaning: 'same_record_name_elapsed_minutes_component', derivation: 'elapsed_minutes%60' },
        ]
      : [{ value: gap.elapsed_calendar_days, meaning: 'same_record_name_elapsed_calendar_days', derivation: 'current_local_date-previous_same_name_local_date' }],
    quality: {
      confidence,
      sample_count: 2,
      data_coverage: 1,
    },
    selection_hints: {
      exposure_key: `expense:record_name:${normalizedName}`,
      dedupe_key: `expense:record_name:${normalizedName}`,
    },
    eligibility: { eligible: true, blocked_reasons: [] },
  }]
}
