import { parseFiniteNumber } from './index.mjs'

export function num(value) {
  return parseFiniteNumber(value)
}

export function median(values) {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2
    ? sorted[middle]
    : Math.round(((sorted[middle - 1] + sorted[middle]) / 2) * 100) / 100
}

export function localDate(value) {
  return String(value ?? '').slice(0, 10)
}

export function round(value, digits = 2) {
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

export function payloadValue(record, key) {
  return record?.payload?.[key] ?? record?.[key] ?? null
}

export function textValue(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

export function timestamp(value) {
  const parsed = new Date(value ?? '').getTime()
  return Number.isFinite(parsed) ? parsed : null
}

export function formatLocalTime(value) {
  const parsed = timestamp(value)
  if (parsed === null) return null
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: 'Asia/Shanghai',
    month: 'numeric',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  }).format(new Date(parsed))
}

function evidence(records, fields) {
  return records.map(record => ({
    source_type: record.source_type ?? 'record',
    source_id: record.id,
    ledger_status: 'confirmed_record',
    fields: Object.fromEntries(fields.map(field => [field, record[field] ?? record.payload?.[field] ?? null])),
  }))
}

export function candidate({
  id,
  domainKey,
  semanticKey,
  claimType = 'fact',
  subtype = null,
  dimension,
  value,
  text,
  records,
  numbers,
  confidence = 1,
  dataCoverage = 1,
  evidenceFields,
  selectionHints = {},
}) {
  return {
    candidate_id: id,
    candidate_version: 'candidate-v0.1',
    domain_key: domainKey,
    dimension,
    claim_type: claimType,
    fact_subtype: subtype,
    interaction_mode: 'inform',
    claim: { semantic_key: semanticKey, structured_value: value, canonical_text: text },
    evidence: evidence(records, evidenceFields ?? ['occurred_at', 'amount', 'metric_value']),
    numbers: numbers.map(item => typeof item === 'number'
      ? { value: item, meaning: 'verified_metric', derivation: 'source_record' }
      : item),
    quality: { confidence, sample_count: records.length, data_coverage: dataCoverage },
    selection_hints: selectionHints,
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}
