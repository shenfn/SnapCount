function timestamp(value) {
  const parsed = new Date(value ?? '').getTime()
  return Number.isFinite(parsed) ? parsed : null
}

function text(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

function normalizeTerm(value) {
  return String(value ?? '')
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[\s「」『』（）()【】\[\]，。、“”"'：:·•/\\_-]+/g, '')
    .trim()
}

function addTerms(value, output, depth = 0) {
  if (depth > 3 || value === null || value === undefined) return
  if (typeof value === 'string') {
    const normalized = normalizeTerm(value)
    if (normalized.length >= 2) output.add(normalized)
    return
  }
  if (Array.isArray(value)) {
    for (const item of value) addTerms(item, output, depth + 1)
    return
  }
  if (typeof value === 'object') {
    for (const [key, item] of Object.entries(value)) {
      if (/^(name|title|item|product|dish|food|merchant|subject|book|sport|type|label)$/i.test(key)) {
        addTerms(item, output, depth + 1)
      }
    }
  }
}

function objectTerms(record) {
  const terms = new Set()
  addTerms(record?.title, terms)
  addTerms(record?.summary, terms)
  addTerms(record?.merchant_name, terms)
  addTerms(record?.source_name, terms)
  addTerms(record?.note, terms)
  addTerms(record?.payload, terms)
  return [...terms].filter(term => !['外卖订单', '订单', '记录', '消费', '食品', '食物'].includes(term))
}

function evidence(record, terms) {
  return {
    source_type: record?.source_type ?? 'record',
    source_id: String(record?.id ?? ''),
    ledger_status: record?.status ?? 'confirmed_record',
    fields: {
      domain_key: record?.domain_key ?? null,
      title: record?.title ?? null,
      summary: record?.summary ?? null,
      merchant_name: record?.merchant_name ?? null,
      occurred_at: record?.occurred_at ?? null,
      created_at: record?.created_at ?? null,
      matched_terms: terms,
    },
  }
}

function candidateId(current, related) {
  return `hypothesis:cross-record:life-chain:${current.id}:${related.id}`
}

/**
 * Produce only high-signal, still-unconfirmed relationships. The caller may
 * provide records from any domain; this function never infers a beneficiary
 * or a completed causal chain.
 */
export function generateCrossRecordRelationshipCandidates({
  currentRecord,
  relatedRecords = [],
  maxGapMinutes = 180,
} = {}) {
  const currentAt = timestamp(currentRecord?.occurred_at)
  if (!currentRecord?.id || currentAt === null) return []
  const currentTerms = objectTerms(currentRecord)
  if (!currentTerms.length) return []

  return relatedRecords.flatMap(related => {
    if (!related?.id || related.id === currentRecord.id) return []
    if (/^(pending|pending_review|failed|deleted|discarded|rejected)$/i.test(String(related.status ?? ''))) return []
    const relatedAt = timestamp(related.occurred_at)
    if (relatedAt === null || relatedAt > currentAt) return []
    const currentKnownAt = timestamp(currentRecord.created_at)
    const relatedKnownAt = timestamp(related.created_at)
    if (currentKnownAt !== null && relatedKnownAt !== null && relatedKnownAt > currentKnownAt) return []
    const elapsedMinutes = Math.round((currentAt - relatedAt) / 60000)
    if (elapsedMinutes < 0 || elapsedMinutes > maxGapMinutes) return []
    const relatedTerms = objectTerms(related)
    const overlap = currentTerms.filter(term => relatedTerms.some(other => term === other || term.includes(other) || other.includes(term)))
    if (!overlap.length) return []
    const domainTransition = currentRecord.domain_key && related.domain_key && currentRecord.domain_key !== related.domain_key
    const temporalScore = Math.max(0, 1 - elapsedMinutes / maxGapMinutes)
    const confidence = Math.round(Math.min(0.99, 0.58 + (domainTransition ? 0.16 : 0.08) + Math.min(0.18, overlap.length * 0.09) + temporalScore * 0.08) * 100) / 100
    if (confidence < 0.75) return []

    const value = {
      relation_status: 'hypothesis',
      current_record_id: currentRecord.id,
      related_record_id: related.id,
      current_domain_key: currentRecord.domain_key ?? null,
      related_domain_key: related.domain_key ?? null,
      object_overlap: true,
      matched_terms: overlap,
      elapsed_minutes: elapsedMinutes,
      event_order: 'related_before_current',
      beneficiary: null,
    }
    return [{
      candidate_id: candidateId(currentRecord, related),
      candidate_version: 'candidate-v0.1',
      domain_key: currentRecord.domain_key ?? 'unknown',
      dimension: 'cross_record_relationship',
      claim_type: 'hypothesis',
      fact_subtype: 'derived',
      interaction_mode: 'inform',
      claim: {
        semantic_key: 'cross_record_possible_life_chain',
        structured_value: value,
        canonical_text: '两条记录可能属于同一条生活安排',
      },
      evidence: [evidence(related, overlap), evidence(currentRecord, overlap)],
      numbers: [{ value: elapsedMinutes, meaning: 'cross_record_elapsed_minutes', derivation: 'current.occurred_at-related.occurred_at' }],
      quality: { confidence, sample_count: 2, data_coverage: 1 },
      selection_hints: {
        allowed_surfaces: ['pwa_pending_ai_card', 'record_detail', 'shortcut_notification'],
        exposure_key: `cross-record:${currentRecord.id}:${related.id}`,
        dedupe_key: `cross-record:${currentRecord.id}:${related.id}`,
      },
      eligibility: { eligible: true, blocked_reasons: [] },
    }]
  })
}
