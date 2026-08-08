const PLANNER_SOURCE = 'expression_planner'
const EXPRESSION_COVERAGE_VERSION = 'expression-coverage-v1'
const EXPRESSION_PLANNER_VERSION = 'expression-shadow-auto-v0.6'
export const FEEDBACK_CARD_TARGET = 'feedback_card'
export const COMPANION_MESSAGE_TARGET = 'companion_message'

function normalized(value) {
  return String(value || '').trim().toLowerCase()
}

function deliveryValue(delivery, feedback, snakeKey, camelKey) {
  return delivery?.[snakeKey]
    ?? delivery?.[camelKey]
    ?? feedback?.[snakeKey]
    ?? feedback?.[camelKey]
}

export function plannerPresentationTarget(delivery, feedback = delivery?.feedback) {
  const target = normalized(deliveryValue(
    delivery,
    feedback,
    'presentation_target',
    'presentationTarget',
  ))
  return target || FEEDBACK_CARD_TARGET
}

export function plannerRenderedPayload(delivery, feedback = delivery?.feedback) {
  const payload = deliveryValue(delivery, feedback, 'rendered_payload', 'renderedPayload')
  return payload && typeof payload === 'object' ? payload : {}
}

export function plannerRenderedTextFingerprint(delivery, feedback = delivery?.feedback) {
  return String(deliveryValue(
    delivery,
    feedback,
    'rendered_text_fingerprint',
    'renderedTextFingerprint',
  ) || '').trim().toLowerCase()
}

export function plannerClaimFingerprint(delivery, feedback = delivery?.feedback) {
  return String(deliveryValue(
    delivery,
    feedback,
    'claim_fingerprint',
    'claimFingerprint',
  ) || '').trim().toLowerCase()
}

export function plannerVisibleFieldPaths(delivery, feedback = delivery?.feedback) {
  const paths = deliveryValue(delivery, feedback, 'visible_field_paths', 'visibleFieldPaths')
  return Array.isArray(paths) ? paths.map(normalized).filter(Boolean) : []
}

export function isCompanionMessageDelivery(delivery, feedback = delivery?.feedback) {
  return plannerPresentationTarget(delivery, feedback) === COMPANION_MESSAGE_TARGET
}

export function hasExplicitPlannerPresentationTarget(delivery, feedback = delivery?.feedback) {
  return Boolean(normalized(
    delivery?.presentation_target
      ?? delivery?.presentationTarget
      ?? feedback?.presentation_target
      ?? feedback?.presentationTarget,
  ))
}

export function isPlannerDeliveryEnvelopeValid(delivery) {
  const feedback = delivery?.feedback
  const candidateId = delivery?.candidateId ?? delivery?.candidate_id
  if (!isPlannerFeedbackForCandidate(feedback, candidateId)) return false

  const envelopeTarget = normalized(delivery?.presentation_target ?? delivery?.presentationTarget)
  const feedbackTarget = normalized(feedback?.presentation_target ?? feedback?.presentationTarget)
  if (envelopeTarget && feedbackTarget && envelopeTarget !== feedbackTarget) return false

  const effectiveTarget = envelopeTarget || feedbackTarget || FEEDBACK_CARD_TARGET
  const envelopeFingerprint = normalized(
    delivery?.rendered_text_fingerprint ?? delivery?.renderedTextFingerprint,
  )
  const feedbackFingerprint = normalized(
    feedback?.rendered_text_fingerprint ?? feedback?.renderedTextFingerprint,
  )
  if (envelopeFingerprint && feedbackFingerprint && envelopeFingerprint !== feedbackFingerprint) return false
  if (effectiveTarget === COMPANION_MESSAGE_TARGET) {
    return envelopeTarget === COMPANION_MESSAGE_TARGET
      && feedbackTarget === COMPANION_MESSAGE_TARGET
      && Boolean(envelopeFingerprint)
      && envelopeFingerprint === feedbackFingerprint
      && Boolean(plannerClaimFingerprint(delivery, feedback))
  }
  return effectiveTarget === FEEDBACK_CARD_TARGET
}

export function isPlannerDeliveryReviewable(delivery) {
  if (!isPlannerDeliveryEnvelopeValid(delivery)) return false
  const exposureEventId = String(
    delivery?.feedback?.exposure_event_id
      ?? delivery?.feedback?.exposureEventId
      ?? '',
  ).trim()
  return Boolean(delivery?.acknowledged && exposureEventId)
}

/**
 * A companion-target delivery is safe to acknowledge only when the API froze
 * the exact text that is currently visible. The opaque text fingerprint is
 * then compared again with the acknowledgement response by the store.
 */
export function companionMessageMatchesDelivery({ delivery, feedback, companionMessage } = {}) {
  if (!isCompanionMessageDelivery(delivery, feedback)) return false
  if (delivery && !isPlannerDeliveryEnvelopeValid(delivery)) return false
  const candidateId = delivery?.candidateId ?? delivery?.candidate_id
  if (delivery && !isPlannerFeedbackForCandidate(feedback, candidateId)) return false
  const renderedPayload = plannerRenderedPayload(delivery, feedback)
  const expectedMessage = String(
    renderedPayload.companion_message
      ?? renderedPayload.companionMessage
      ?? feedback?.emotion_line
      ?? feedback?.emotionLine
      ?? '',
  ).trim()
  const visibleMessage = String(companionMessage || '').trim()
  return Boolean(expectedMessage)
    && expectedMessage === visibleMessage
    && Boolean(plannerRenderedTextFingerprint(delivery, feedback))
    && Boolean(plannerClaimFingerprint(delivery, feedback))
}

/**
 * Bind ACK output back to the preview that was actually rendered. Candidate,
 * claim, target and rendered text must remain stable. Legacy card deliveries
 * have no target fingerprints, so candidate identity remains their floor.
 */
export function plannerDeliveryIdentityMatches(preview, acknowledged) {
  if (!isPlannerDeliveryEnvelopeValid(preview)
    || !isPlannerDeliveryEnvelopeValid(acknowledged)) return false
  const previewFeedback = preview?.feedback
  const acknowledgedFeedback = acknowledged?.feedback
  const previewCandidateId = String(preview?.candidateId ?? preview?.candidate_id ?? '').trim()
  const acknowledgedCandidateId = String(
    acknowledged?.candidateId ?? acknowledged?.candidate_id ?? '',
  ).trim()
  if (!previewCandidateId || previewCandidateId !== acknowledgedCandidateId) return false
  if (!isPlannerFeedbackForCandidate(previewFeedback, previewCandidateId)
    || !isPlannerFeedbackForCandidate(acknowledgedFeedback, acknowledgedCandidateId)) return false

  const previewTarget = plannerPresentationTarget(preview, previewFeedback)
  const acknowledgedTarget = plannerPresentationTarget(acknowledged, acknowledgedFeedback)
  if (previewTarget !== acknowledgedTarget) return false

  const previewClaim = plannerClaimFingerprint(preview, previewFeedback)
  const acknowledgedClaim = plannerClaimFingerprint(acknowledged, acknowledgedFeedback)
  if (previewClaim && previewClaim !== acknowledgedClaim) return false

  const previewTextFingerprint = plannerRenderedTextFingerprint(preview, previewFeedback)
  const acknowledgedTextFingerprint = plannerRenderedTextFingerprint(
    acknowledged,
    acknowledgedFeedback,
  )
  if (previewTextFingerprint && previewTextFingerprint !== acknowledgedTextFingerprint) return false

  if (previewTarget === COMPANION_MESSAGE_TARGET) {
    if (!previewTextFingerprint) return false
    const previewPayload = plannerRenderedPayload(preview, previewFeedback)
    const acknowledgedPayload = plannerRenderedPayload(acknowledged, acknowledgedFeedback)
    const previewMessage = previewPayload.companion_message
      ?? previewPayload.companionMessage
      ?? previewFeedback?.emotion_line
      ?? previewFeedback?.emotionLine
    const acknowledgedMessage = acknowledgedPayload.companion_message
      ?? acknowledgedPayload.companionMessage
      ?? acknowledgedFeedback?.emotion_line
      ?? acknowledgedFeedback?.emotionLine
    if (!previewMessage || previewMessage !== acknowledgedMessage) return false
  }
  return true
}

/**
 * Planner's current-fact fallback only restates the fields already visible in
 * the companion message. It remains useful in Shadow, but should not occupy a
 * second user-facing feedback slot when the companion already exists.
 */
export function isCurrentRecordContextFeedback(feedback) {
  if (!feedback || typeof feedback !== 'object') return false
  const semanticKey = normalized(feedback.semantic_key ?? feedback.semanticKey)
  const dimension = normalized(feedback.dimension)
  const candidateId = normalized(feedback.candidate_id ?? feedback.candidateId)

  return semanticKey.endsWith('_current_record_context')
    || semanticKey.endsWith('_current_metric')
    || dimension === 'current_fact'
    || candidateId.includes('current-metric')
}

export function hasCompanionMessage(value) {
  return String(value || '').trim().length > 0
}

/**
 * The API returns the selected candidate both at the envelope level and in
 * feedback. Keep the two identities tied together before a client renders or
 * acknowledges the card. Older planner responses may not have a claim
 * fingerprint, so candidate identity is the compatibility floor here.
 */
export function isPlannerFeedbackForCandidate(feedback, candidateId) {
  if (!feedback || typeof feedback !== 'object') return false
  const expectedCandidateId = String(candidateId || '').trim()
  const actualCandidateId = String(
    feedback.candidate_id ?? feedback.candidateId ?? '',
  ).trim()
  return normalized(feedback.source) === PLANNER_SOURCE
    && Boolean(expectedCandidateId)
    && actualCandidateId === expectedCandidateId
}

export function expressedSemanticKeys(feedback, plannerFeedback) {
  const coverage = feedback?.expression_coverage ?? feedback?.expressionCoverage
  if (!coverage || typeof coverage !== 'object') return []
  const coverageVersion = normalized(coverage.coverage_version ?? coverage.coverageVersion)
  const plannerVersion = normalized(coverage.planner_version ?? coverage.plannerVersion)
  const sourceSurface = normalized(coverage.source_surface ?? coverage.sourceSurface)
  const packetFingerprint = String(coverage.packet_fingerprint ?? coverage.packetFingerprint ?? '').trim()
  const claimFingerprint = normalized(coverage.claim_fingerprint ?? coverage.claimFingerprint)
  const plannerClaimFingerprint = normalized(
    plannerFeedback?.claim_fingerprint ?? plannerFeedback?.claimFingerprint,
  )
  if (coverageVersion !== EXPRESSION_COVERAGE_VERSION
    || plannerVersion !== EXPRESSION_PLANNER_VERSION
    || sourceSurface !== 'record_detail'
    || !packetFingerprint
    || !claimFingerprint
    || (plannerFeedback && (!plannerClaimFingerprint || plannerClaimFingerprint !== claimFingerprint))) return []
  return [...new Set([
    coverage.expressed_semantic_key ?? coverage.expressedSemanticKey,
    ...(Array.isArray(coverage.expressed_semantic_keys)
      ? coverage.expressed_semantic_keys
      : Array.isArray(coverage.expressedSemanticKeys) ? coverage.expressedSemanticKeys : []),
  ].map(normalized).filter(Boolean))]
}

/**
 * Resolve the single feedback card that may accompany a companion message.
 * Legacy feedback is kept only when there is no companion, while Planner
 * feedback survives when it contributes a non-current-record angle.
 */
export function feedbackToRender({ companionMessage, feedback, companionFeedback, delivery } = {}) {
  if (!feedback || typeof feedback !== 'object') return null
  if (delivery) {
    if (!isPlannerDeliveryEnvelopeValid(delivery)) return null
    if (hasExplicitPlannerPresentationTarget(delivery, feedback)) {
      return isCompanionMessageDelivery(delivery, feedback) ? null : feedback
    }
  }
  const hasCompanion = hasCompanionMessage(companionMessage)
  const source = normalized(feedback.source)

  if (!hasCompanion) return feedback
  if (source !== PLANNER_SOURCE) return null
  const semanticKey = normalized(feedback.semantic_key ?? feedback.semanticKey)
  if (semanticKey && expressedSemanticKeys(companionFeedback, feedback).includes(semanticKey)) return null
  if (isCurrentRecordContextFeedback(feedback)) return null
  return feedback
}

export function shouldAcknowledgePlannerFeedback({
  companionMessage,
  feedback,
  companionFeedback,
  delivery,
} = {}) {
  if (!feedback || normalized(feedback.source) !== PLANNER_SOURCE) return false
  if (delivery && !isPlannerDeliveryEnvelopeValid(delivery)) return false
  if (isCompanionMessageDelivery(delivery, feedback)) {
    return companionMessageMatchesDelivery({ delivery, feedback, companionMessage })
  }
  return feedbackToRender({ companionMessage, feedback, companionFeedback, delivery }) !== null
}
