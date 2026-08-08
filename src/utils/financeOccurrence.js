import {
  DEFAULT_TZ,
  formatDateKey,
  parseInstant,
  toIsoUtc,
  zonedParts,
  zonedWallTimeToInstant,
} from '../lib/time-core/index.js'

function normalizeDate(value) {
  const text = String(value || '').trim()
  if (!/^\d{4}-\d{2}-\d{2}$/.test(text)) return null
  const instant = parseInstant(text, DEFAULT_TZ)
  return instant != null && formatDateKey(instant, DEFAULT_TZ) === text ? text : null
}

function normalizeTime(value) {
  const text = String(value || '').trim()
  const match = text.match(/^(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?$/)
  if (!match) return null
  const hour = Number(match[1])
  const minute = Number(match[2])
  const second = Number(match[3] || 0)
  if (hour > 23 || minute > 59 || second > 59) return null
  return `${match[1]}:${match[2]}:${String(second).padStart(2, '0')}`
}

function exactInstant(value) {
  const text = String(value || '').trim()
  if (!/[ T]\d{2}:\d{2}/.test(text)) return null
  return parseInstant(text, DEFAULT_TZ)
}

function wallParts(instant) {
  const parts = zonedParts(instant, DEFAULT_TZ)
  if (!parts) return null
  return {
    occurredAt: toIsoUtc(instant),
    date: `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`,
    time: `${String(parts.hour).padStart(2, '0')}:${String(parts.minute).padStart(2, '0')}:${String(parts.second).padStart(2, '0')}`,
    hasExactTime: true,
  }
}

export function buildShanghaiOccurredAt(date, time) {
  const normalizedDate = normalizeDate(date)
  const normalizedTime = normalizeTime(time)
  if (!normalizedDate || !normalizedTime) return null
  const [year, month, day] = normalizedDate.split('-').map(Number)
  const [hour, minute, second] = normalizedTime.split(':').map(Number)
  return toIsoUtc(zonedWallTimeToInstant({ year, month, day, hour, minute, second }, DEFAULT_TZ))
}

export function resolveFinanceOccurrence({
  occurredAt = null,
  date = null,
  time = null,
  fallbackInstant = null,
} = {}) {
  const explicitInstant = exactInstant(occurredAt)
  if (explicitInstant != null) return wallParts(explicitInstant)

  const normalizedDate = normalizeDate(date) || normalizeDate(occurredAt)
  const normalizedTime = normalizeTime(time)
  if (normalizedDate && normalizedTime) {
    const combined = buildShanghaiOccurredAt(normalizedDate, normalizedTime)
    return wallParts(parseInstant(combined, DEFAULT_TZ))
  }

  let fallbackDate = normalizedDate
  if (!fallbackDate) {
    const fallback = exactInstant(fallbackInstant)
    if (fallback != null) fallbackDate = formatDateKey(fallback, DEFAULT_TZ)
  }

  return {
    occurredAt: null,
    date: fallbackDate,
    time: null,
    hasExactTime: false,
  }
}
