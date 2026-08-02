const PRODUCTION_STATES = new Set([
  'returned_to_shortcut',
  'client_rendered',
  'client_acknowledged',
  'user_reviewed',
])

const SURFACES = new Set([
  'shortcut_notification',
  'pwa_pending_ai_card',
  'record_detail',
  'weekly_report',
])

function required(value, name) {
  if (value === null || value === undefined || value === '') throw new Error(`Missing required exposure field: ${name}`)
  return value
}

function eventKey(deliveryAttemptId, event) {
  return [deliveryAttemptId, event.surface, event.candidate_id, event.lifecycle_state].join(':')
}

export function toProductionExposureRows(events, context) {
  const userId = required(context?.userId, 'user_id')
  const deliveryAttemptId = required(context?.deliveryAttemptId, 'delivery_attempt_id')
  return events.map(event => {
    if (event.simulation_only || event.lifecycle_state === 'rendered_preview') {
      throw new Error(`Simulation exposure cannot be serialized for production: ${event.candidate_id}`)
    }
    if (!PRODUCTION_STATES.has(event.lifecycle_state)) throw new Error(`Invalid production lifecycle state: ${event.lifecycle_state}`)
    if (!SURFACES.has(event.surface)) throw new Error(`Invalid exposure surface: ${event.surface}`)
    return {
      event_key: eventKey(deliveryAttemptId, event),
      delivery_attempt_id: deliveryAttemptId,
      occurred_at: required(event.occurred_at, 'occurred_at'),
      user_id: userId,
      trace_id: context.traceId ?? event.trace_id ?? null,
      ai_log_id: context.aiLogId ?? null,
      record_id: context.recordId ?? null,
      record_type: context.recordType ?? null,
      domain_key: context.domainKey ?? null,
      entity_id: context.entityId ?? null,
      candidate_id: required(event.candidate_id, 'candidate_id'),
      semantic_key: required(event.semantic_key, 'semantic_key'),
      claim_type: required(event.claim_type, 'claim_type'),
      dimension: event.dimension ?? null,
      surface: event.surface,
      lifecycle_state: event.lifecycle_state,
      selection_mode: event.selection_mode ?? null,
      score: event.score ?? null,
      expression_plan_version: required(event.expression_plan_version, 'expression_plan_version'),
      render_contract_version: required(event.render_contract_version, 'render_contract_version'),
      scoring_version: context.scoringVersion ?? 'deterministic-score-v0.1',
      visible_field_paths: event.visible_field_paths ?? [],
      expandable_field_paths: event.expandable_field_paths ?? [],
      persisted_only_field_paths: event.persisted_only_field_paths ?? [],
      rendered_payload: context.renderedPayloadByCandidate?.[event.candidate_id] ?? {},
      metadata: {
        source: context.source ?? 'expression_planner',
        client_version: context.clientVersion ?? null,
      },
      simulation_only: false,
      counts_for_novelty: event.counts_for_novelty !== false,
    }
  })
}
