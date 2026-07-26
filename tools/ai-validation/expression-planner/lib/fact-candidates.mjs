function roundMoney(value) {
  return Math.round(value * 100) / 100
}

function parseFiniteNumber(value) {
  if (typeof value === 'number') return Number.isFinite(value) ? value : null
  if (typeof value !== 'string' || !value.trim()) return null
  const parsed = Number(value.trim())
  return Number.isFinite(parsed) ? parsed : null
}

function localDateOf(value, timeZone) {
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return null
  if (!timeZone) return date.toISOString().slice(0, 10)
  return new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(date)
}

function localEventTime(value, precision, timeZone) {
  const date = new Date(value)
  if (!Number.isFinite(date.getTime())) return null
  return new Intl.DateTimeFormat('zh-CN', {
    timeZone: timeZone || 'Asia/Shanghai',
    month: 'numeric',
    day: 'numeric',
    ...(precision === 'date_only' ? {} : { hour: '2-digit', minute: '2-digit', hour12: false }),
  }).format(date)
}

function eventTime(event) {
  const time = new Date(event.event_at).getTime()
  return Number.isFinite(time) ? time : null
}

function evidenceOf(events, fields) {
  return events.map(event => ({
    source_type: event.source_type,
    source_id: event.event_id,
    ledger_status: event.ledger_status,
    fields: Object.fromEntries(fields.map(field => [field, event[field] ?? null])),
  }))
}

function candidate({ id, semanticKey, subtype, dimension, value, text, evidence, numbers, quality = {}, selectionHints = {} }) {
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
    selection_hints: selectionHints,
    quality: {
      confidence: 1,
      sample_count: evidence.length,
      data_coverage: 1,
      ...quality,
    },
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

export function generateCurrentExpenseRecordCandidate(event, { timeZone = 'Asia/Shanghai' } = {}) {
  const amount = parseFiniteNumber(event?.amount)
  if (!event?.event_id || amount === null) return []
  const factContract = event.fact_contract ?? {}
  const pendingReview = factContract.fact_status === 'pending_review'
  const categoryNeedsReview = pendingReview || factContract.comparison_scope === 'pending_review' || !event.category
  const timeLabel = localEventTime(event.event_at, event.event_time_precision, timeZone)
  const action = pendingReview ? '已识别到' : '已记录'
  const canonicalText = `${timeLabel ? `${timeLabel} ` : ''}${action}一笔 ${roundMoney(amount)} 元支出${categoryNeedsReview ? '；分类仍待确认' : ''}`
  const recordName = event.merchant?.canonical_name ?? event.merchant?.raw_name ?? null
  const sourceEvidence = evidenceOf([event], [
    'amount', 'event_at', 'event_time_precision', 'category', 'platform', 'payment_method', 'fact_contract',
  ])
  const recordId = event.target_id ?? event.event_id
  return [candidate({
    id: `fact:expense:record-context:${recordId}`,
    semanticKey: 'expense_current_record_context',
    subtype: 'observed',
    dimension: 'record_context',
    value: {
      record_id: recordId,
      amount: roundMoney(amount),
      unit: '元',
      occurred_at: event.event_at ?? null,
      time_precision: event.event_time_precision ?? null,
      record_name: recordName,
      category: event.category ?? null,
      platform: event.platform ?? null,
      payment_method: event.payment_method ?? null,
      fact_status: factContract.fact_status ?? null,
      category_needs_review: categoryNeedsReview,
    },
    text: canonicalText,
    evidence: sourceEvidence,
    numbers: [{ value: roundMoney(amount), meaning: 'current_record_amount', derivation: 'source_event.amount' }],
    quality: { confidence: pendingReview ? 0.9 : 1 },
    selectionHints: {
      allowed_surfaces: ['pwa_pending_ai_card', 'record_detail'],
      exposure_key: `expense:record:${recordId}:context`,
      dedupe_key: `expense:record:${recordId}:context`,
    },
  })]
}

/**
 * @param {any[]} events
 * @param {{
 *   entityId?: string | null,
 *   localDate?: string | null,
 *   timeZone?: string,
 *   currentRecordId?: string | null,
 * }} options
 */
export function generateFactCandidates(events, { entityId, localDate, timeZone, currentRecordId = null } = {}) {
  const trusted = events
    .map(event => ({ event, amount: parseFiniteNumber(event.amount) }))
    .filter(item => item.event.count_in_facts && item.amount !== null)
    .filter(item => !entityId || item.event.merchant?.entity_id === entityId)
    .map(item => ({ ...item.event, amount: item.amount }))
    .filter(event => !localDate || localDateOf(event.event_at, timeZone) === localDate)
    .sort((left, right) => (eventTime(left) ?? Number.MAX_SAFE_INTEGER) - (eventTime(right) ?? Number.MAX_SAFE_INTEGER))

  if (!trusted.length) return []
  const total = roundMoney(trusted.reduce((sum, event) => sum + event.amount, 0))
  const amounts = trusted.map(event => event.amount)
  const entityName = trusted[0].merchant?.canonical_name ?? entityId
  const commonEvidence = evidenceOf(trusted, ['amount', 'event_at', 'known_at'])
  const output = [
    candidate({
      id: `fact:${entityId}:daily-count-total:${localDate}:${currentRecordId ?? trusted[trusted.length - 1].event_id}`,
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
      selectionHints: {
        exposure_key: `expense:merchant:${entityId}:day:${localDate}`,
        dedupe_key: `expense:merchant:${entityId}:day:${localDate}`,
      },
    }),
    candidate({
      id: `fact:${entityId}:amount-structure:${localDate}:${currentRecordId ?? trusted[trusted.length - 1].event_id}`,
      semanticKey: 'merchant_daily_amount_structure',
      subtype: 'aggregated',
      dimension: 'amount_structure',
      value: { amounts, min_amount: Math.min(...amounts), max_amount: Math.max(...amounts) },
      text: `金额分布为 ${amounts.join('、')} 元，最高单笔 ${Math.max(...amounts)} 元`,
      evidence: commonEvidence,
      numbers: amounts.map(value => ({ value, meaning: 'transaction_amount', derivation: 'source_event.amount' })),
      selectionHints: {
        exposure_key: `expense:merchant:${entityId}:day:${localDate}:amounts`,
        dedupe_key: `expense:merchant:${entityId}:day:${localDate}:amounts`,
      },
    }),
  ]

  return output
}
