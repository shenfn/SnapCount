function roundMoney(value) {
  return Math.round(value * 100) / 100
}

function localDateOf(value, timeZone) {
  if (!timeZone) return value.slice(0, 10)
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(value))
}

function evidenceOf(events, fields) {
  return events.map(event => ({
    source_type: event.source_type,
    source_id: event.event_id,
    ledger_status: event.ledger_status,
    fields: Object.fromEntries(fields.map(field => [field, event[field] ?? null])),
  }))
}

function candidate({ id, semanticKey, subtype, dimension, value, text, evidence, numbers, quality = {} }) {
  return {
    candidate_id: id,
    candidate_version: 'candidate-v0.1',
    domain_key: 'expense',
    dimension,
    claim_type: 'fact',
    fact_subtype: subtype,
    interaction_mode: 'inform',
    claim: {
      semantic_key: semanticKey,
      structured_value: value,
      canonical_text: text,
    },
    evidence,
    numbers,
    quality: {
      confidence: 1,
      sample_count: evidence.length,
      data_coverage: 1,
      ...quality,
    },
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

export function generateFactCandidates(events, { entityId, localDate, timeZone }) {
  const trusted = events
    .filter(event => event.count_in_facts && event.amount !== null)
    .filter(event => !entityId || event.merchant.entity_id === entityId)
    .filter(event => !localDate || localDateOf(event.event_at, timeZone) === localDate)
    .sort((left, right) => new Date(left.event_at) - new Date(right.event_at))

  if (!trusted.length) return []
  const total = roundMoney(trusted.reduce((sum, event) => sum + event.amount, 0))
  const amounts = trusted.map(event => event.amount)
  const first = trusted[0]
  const last = trusted.at(-1)
  const spanMinutes = Math.round((new Date(last.event_at) - new Date(first.event_at)) / 60000)
  const entityName = first.merchant.canonical_name
  const commonEvidence = evidenceOf(trusted, ['amount', 'event_at', 'known_at'])

  return [
    candidate({
      id: `fact:${entityId}:daily-count-total:${localDate}`,
      semanticKey: 'merchant_daily_count_total',
      subtype: 'aggregated',
      dimension: 'daily_aggregation',
      value: { entity_id: entityId, date: localDate, count: trusted.length, total_amount: total },
      text: `${localDate} 在「${entityName}」共 ${trusted.length} 笔，累计 ${total} 元`,
      evidence: commonEvidence,
      numbers: [
        { value: trusted.length, meaning: 'transaction_count', derivation: 'count(fact_eligible_events)' },
        { value: total, meaning: 'daily_total_amount', derivation: 'sum(amount)' },
      ],
    }),
    candidate({
      id: `fact:${entityId}:amount-structure:${localDate}`,
      semanticKey: 'merchant_daily_amount_structure',
      subtype: 'aggregated',
      dimension: 'amount_structure',
      value: { amounts, min_amount: Math.min(...amounts), max_amount: Math.max(...amounts) },
      text: `金额分布为 ${amounts.join('、')} 元，最高单笔 ${Math.max(...amounts)} 元`,
      evidence: commonEvidence,
      numbers: amounts.map(value => ({ value, meaning: 'transaction_amount', derivation: 'source_event.amount' })),
    }),
    candidate({
      id: `fact:${entityId}:time-span:${localDate}`,
      semanticKey: 'merchant_daily_activity_span',
      subtype: 'derived',
      dimension: 'temporal_rhythm',
      value: { first_event_at: first.event_at, last_event_at: last.event_at, span_minutes: spanMinutes },
      text: `首笔到末笔相隔 ${spanMinutes} 分钟`,
      evidence: evidenceOf([first, last], ['event_at', 'known_at']),
      numbers: [{ value: spanMinutes, meaning: 'activity_span_minutes', derivation: 'last_event_at-first_event_at' }],
      quality: {
        confidence: Math.min(first.event_time_confidence, last.event_time_confidence),
        data_coverage: trusted.filter(event => event.event_time_source !== 'known_at_proxy').length / trusted.length,
      },
    }),
  ]
}
