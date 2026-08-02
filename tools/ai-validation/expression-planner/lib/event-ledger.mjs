function numericValue(value) {
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function responseOf(log) {
  if (!log?.ai_response) return {}
  if (typeof log.ai_response === 'object') return log.ai_response
  try { return JSON.parse(log.ai_response) } catch { return {} }
}

export function compileEventOverrides(config) {
  return new Map((config?.overrides ?? []).map(item => [item.ai_log_id, item]))
}

export function buildRecognitionLedger(logs, { aliasMap, resolveMerchant, overrideMap }) {
  return logs.map(log => {
    const ai = responseOf(log)
    const override = overrideMap.get(log.id) ?? null
    let ledger_status = 'unclassified'
    let count_in_facts = false
    let trust_level = 'untrusted'

    if (override) {
      ledger_status = override.ledger_status
      count_in_facts = Boolean(override.count_in_facts)
      trust_level = 'user_confirmed'
    } else if (log.status === 'duplicate') {
      ledger_status = 'duplicate_candidate'
      trust_level = 'disputed'
    } else if (log.staging_record_id || log.status === 'pending') {
      ledger_status = 'pending_record'
      trust_level = 'pending'
    } else if (log.status === 'success' && log.target_table === 'transactions' && log.target_id) {
      ledger_status = 'confirmed_transaction'
      count_in_facts = true
      trust_level = 'confirmed'
    }

    const event_at = log.order_finished_at || log.occurred_at || log.created_at
    const event_time_source = log.order_finished_at
      ? 'order_finished_at'
      : log.occurred_at
        ? 'occurred_at'
        : 'known_at_proxy'

    return {
      event_id: log.id,
      source_type: 'ai_recognition_log',
      ledger_status,
      trust_level,
      count_in_facts,
      event_at,
      event_time_source,
      event_time_confidence: event_time_source === 'known_at_proxy' ? 0.55 : 0.95,
      known_at: log.created_at,
      record_type: log.record_type,
      image_type: log.image_type,
      amount: numericValue(ai.amount),
      merchant: resolveMerchant(ai.merchant_name, aliasMap),
      category: ai.category ?? null,
      platform: ai.platform ?? null,
      payment_method: ai.payment_method ?? null,
      target_table: log.target_table ?? null,
      target_id: log.target_id ?? null,
      staging_record_id: log.staging_record_id ?? null,
      duplicate: {
        kind: log.duplicate_kind ?? null,
        ref_id: log.duplicate_ref_id ?? null,
      },
      override,
    }
  })
}

export function summarizeLedger(ledger) {
  const counts = {}
  for (const event of ledger) counts[event.ledger_status] = (counts[event.ledger_status] ?? 0) + 1
  const trusted = ledger.filter(event => event.count_in_facts)
  return {
    total_events: ledger.length,
    status_counts: counts,
    fact_eligible_events: trusted.length,
    disputed_events: ledger.filter(event => event.trust_level === 'disputed').length,
    pending_events: ledger.filter(event => event.trust_level === 'pending').length,
  }
}
