export const SURFACE_RENDER_CONTRACTS = {
  shortcut_notification: {
    surface_kind: 'external_notification',
    fixed_slots: ['archive_status', 'current_record_summary', 'daily_summary'],
    visible_feedback_fields: ['icon', 'badge', 'band', 'confidence', 'emotion_line', 'utility_line'],
    expandable_feedback_fields: [],
    persisted_only_feedback_fields: ['detail_reason', 'timing_signal', 'source'],
    delivery_state_when_sent: 'returned_to_shortcut',
  },
  pwa_pending_ai_card: {
    surface_kind: 'in_app_compact_card',
    fixed_slots: ['amount_editor', 'image_preview', 'correction_fields', 'archive_action'],
    visible_feedback_fields: ['icon', 'badge', 'band', 'emotion_line', 'utility_line', 'timing_signal'],
    expandable_feedback_fields: ['detail_reason'],
    persisted_only_feedback_fields: ['confidence', 'source'],
    delivery_state_when_sent: 'client_rendered',
  },
  record_detail: {
    surface_kind: 'in_app_detail',
    fixed_slots: ['record_fields', 'domain_destination', 'account_binding', 'record_actions'],
    visible_feedback_fields: ['icon', 'badge', 'band', 'emotion_line', 'utility_line', 'detail_reason', 'timing_signal'],
    expandable_feedback_fields: ['evidence', 'numbers'],
    persisted_only_feedback_fields: ['source'],
    delivery_state_when_sent: 'client_rendered',
  },
  weekly_report: {
    surface_kind: 'periodic_report',
    fixed_slots: ['period_header', 'weekly_totals'],
    visible_feedback_fields: ['headline', 'summary', 'supporting_facts'],
    expandable_feedback_fields: ['evidence', 'numbers', 'derivation'],
    persisted_only_feedback_fields: ['source'],
    delivery_state_when_sent: 'client_rendered',
  },
}

function candidateMap(candidates) {
  return new Map(candidates.map(candidate => [candidate.candidate_id, candidate]))
}

export function buildRenderPlans(expressionPlans, candidates) {
  const byId = candidateMap(candidates)
  return Object.fromEntries(Object.entries(expressionPlans).map(([surface, expressionPlan]) => {
    const contract = SURFACE_RENDER_CONTRACTS[surface]
    if (!contract) throw new Error(`Missing render contract for surface: ${surface}`)
    const selected = expressionPlan.selected.map(selection => {
      const candidate = byId.get(selection.candidate_id)
      return {
        candidate_id: selection.candidate_id,
        semantic_key: selection.semantic_key,
        claim_type: selection.claim_type,
        dimension: selection.dimension,
        score: selection.score,
        selection_mode: selection.selection_mode,
        structured_value: candidate?.claim?.structured_value ?? null,
        canonical_text: candidate?.claim?.canonical_text ?? selection.canonical_text ?? null,
        visible_field_paths: contract.visible_feedback_fields.map(field => `rendered_feedback.${field}`),
        expandable_field_paths: contract.expandable_feedback_fields.map(field => `rendered_feedback.${field}`),
        persisted_only_field_paths: contract.persisted_only_feedback_fields.map(field => `rendered_feedback.${field}`),
      }
    })
    return [surface, {
      render_contract_version: 'surface-render-contract-v0.1',
      expression_plan_version: expressionPlan.plan_version ?? 'expression-plan-v0.1',
      surface,
      surface_kind: contract.surface_kind,
      fixed_slots: contract.fixed_slots,
      selected,
      delivery_state_when_sent: contract.delivery_state_when_sent,
      render_state: 'rendered_preview',
      simulation_only: true,
    }]
  }))
}

export function buildExposureEvents(renderPlans, { traceId, occurredAt, simulationOnly = true } = {}) {
  const timestamp = occurredAt ?? new Date().toISOString()
  const events = []
  for (const [surface, plan] of Object.entries(renderPlans)) {
    for (const selected of plan.selected) {
      events.push({
        exposure_event_version: 'expression-exposure-event-v0.1',
        event_id: `${traceId ?? 'preview'}:${surface}:${selected.candidate_id}`,
        trace_id: traceId ?? null,
        candidate_id: selected.candidate_id,
        semantic_key: selected.semantic_key,
        claim_type: selected.claim_type,
        dimension: selected.dimension,
        score: selected.score,
        selection_mode: selected.selection_mode,
        surface,
        lifecycle_state: simulationOnly ? 'rendered_preview' : plan.delivery_state_when_sent,
        expression_plan_version: plan.expression_plan_version,
        render_contract_version: plan.render_contract_version,
        simulation_only: simulationOnly,
        counts_for_novelty: !simulationOnly,
        visible_field_paths: selected.visible_field_paths,
        expandable_field_paths: selected.expandable_field_paths,
        persisted_only_field_paths: selected.persisted_only_field_paths,
        occurred_at: timestamp,
      })
    }
  }
  return events
}

export function compileExposureHistory(events) {
  const acceptedStates = new Set(['returned_to_shortcut', 'client_rendered', 'client_acknowledged', 'user_reviewed'])
  const history = {}
  for (const event of events) {
    if (event.simulation_only || !event.counts_for_novelty || !acceptedStates.has(event.lifecycle_state)) continue
    const key = event.semantic_key
    if (!key) continue
    const previous = history[key] ?? { count: 0, last_shown_at: null }
    previous.count += 1
    if (!previous.last_shown_at || new Date(event.occurred_at) > new Date(previous.last_shown_at)) {
      previous.last_shown_at = event.occurred_at
    }
    history[key] = previous
  }
  return history
}
