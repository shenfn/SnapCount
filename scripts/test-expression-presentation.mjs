import assert from 'node:assert/strict'
import test from 'node:test'
import {
  companionMessageMatchesDelivery,
  expressedSemanticKeys,
  feedbackForCompanion,
  feedbackToRender,
  isCompanionMessageDelivery,
  isPlannerDeliveryEnvelopeValid,
  isPlannerDeliveryReviewable,
  isPlannerFeedbackForCandidate,
  isCurrentRecordContextFeedback,
  plannerDeliveryIdentityMatches,
  plannerFeedbackSurfaceState,
  recordExpressionPlanForDetail,
  shouldAcknowledgePlannerFeedback,
} from '../src/utils/expressionPresentation.js'
import {
  isRetryableDeliveryError,
  retryWithBackoff,
  waitForVisibleElement,
} from '../src/utils/expressionDelivery.js'

const planner = (overrides = {}) => ({
  source: 'expression_planner',
  semantic_key: 'expense_current_record_context',
  dimension: 'record_context',
  emotion_line: '8/5 10:20 已记录一笔 6.28 元支出。',
  ...overrides,
})

test('suppresses the expense current-record fallback beside a companion message', () => {
  const feedback = planner()
  assert.equal(isCurrentRecordContextFeedback(feedback), true)
  assert.equal(feedbackToRender({ companionMessage: '青禾茶饮这笔已经记下。', feedback }), null)
  assert.equal(shouldAcknowledgePlannerFeedback({ companionMessage: '青禾茶饮这笔已经记下。', feedback }), false)
})

test('keeps current facts when there is no companion message', () => {
  const feedback = planner()
  assert.equal(feedbackToRender({ companionMessage: '', feedback }), feedback)
  assert.equal(shouldAcknowledgePlannerFeedback({ companionMessage: '', feedback }), true)
})

test('keeps a first-seen or comparison angle beside a companion message', () => {
  for (const semanticKey of ['expense_merchant_first_seen', 'expense_vs_personal_median']) {
    const feedback = planner({
      semantic_key: semanticKey,
      dimension: semanticKey.includes('first') ? 'novelty' : 'personal_baseline',
    })
    assert.equal(isCurrentRecordContextFeedback(feedback), false)
    assert.equal(feedbackToRender({ companionMessage: '这一笔已经记下。', feedback }), feedback)
    assert.equal(shouldAcknowledgePlannerFeedback({ companionMessage: '这一笔已经记下。', feedback }), true)
  }
})

test('suppresses the exact Planner semantic angle already expressed by Voice provenance', () => {
  const feedback = planner({
    semantic_key: 'expense_merchant_first_occurrence',
    dimension: 'first_occurrence',
    emotion_line: '第一次记录「青禾茶饮」',
    claim_fingerprint: 'fnv1a64:first-occurrence',
  })
  const companionFeedback = {
    source: 'hybrid',
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: 'expense_merchant_first_occurrence',
      expressed_semantic_keys: ['expense_merchant_first_occurrence'],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'fnv1a32:test',
      claim_fingerprint: 'fnv1a64:first-occurrence',
    },
  }

  assert.deepEqual(expressedSemanticKeys(companionFeedback, feedback), ['expense_merchant_first_occurrence'])
  assert.equal(feedbackToRender({
    companionMessage: '第一次记下青禾茶饮，像是碰上了小惊喜。',
    feedback,
    companionFeedback,
  }), null)
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage: '第一次记下青禾茶饮，像是碰上了小惊喜。',
    feedback,
    companionFeedback,
  }), false)
})

test('fails open when companion coverage is stale or incomplete', () => {
  const feedback = planner({
    semantic_key: 'expense_merchant_first_occurrence',
    dimension: 'first_occurrence',
    claim_fingerprint: 'fnv1a64:current',
  })
  const stale = {
    source: 'hybrid',
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: 'expense_merchant_first_occurrence',
      expressed_semantic_keys: ['expense_merchant_first_occurrence'],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.5',
      packet_fingerprint: 'fnv1a32:stale',
      claim_fingerprint: 'fnv1a64:stale',
    },
  }

  assert.deepEqual(expressedSemanticKeys(stale, feedback), [])
  assert.equal(feedbackToRender({
    companionMessage: '这笔已经记下。',
    feedback,
    companionFeedback: stale,
  }), feedback)
})

test('fails open when coverage belongs to an edited version of the same semantic claim', () => {
  const feedback = planner({
    semantic_key: 'expense_merchant_first_occurrence',
    dimension: 'first_occurrence',
    claim_fingerprint: 'fnv1a64:after-edit',
  })
  const companionFeedback = {
    source: 'hybrid',
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: 'expense_merchant_first_occurrence',
      expressed_semantic_keys: ['expense_merchant_first_occurrence'],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'fnv1a32:before-edit',
      claim_fingerprint: 'fnv1a64:before-edit',
    },
  }

  assert.deepEqual(expressedSemanticKeys(companionFeedback, feedback), [])
  assert.equal(feedbackToRender({
    companionMessage: '第一次记下新的商户。',
    feedback,
    companionFeedback,
  }), feedback)
})

test('keeps food record context because it adds meal or dish context', () => {
  const feedback = planner({
    semantic_key: 'food_record_context',
    dimension: 'record_context',
    candidate_id: 'fact:food:context:record-1',
  })
  assert.equal(isCurrentRecordContextFeedback(feedback), false)
  assert.equal(feedbackToRender({ companionMessage: '早餐已经记下。', feedback }), feedback)
})

test('hides legacy feedback when a companion message already exists', () => {
  const feedback = { source: 'legacy_voice', emotion_line: '已记录这笔支出。' }
  assert.equal(feedbackToRender({ companionMessage: '这笔已记下。', feedback }), null)
})

test('keeps hybrid supporting copy inside the companion surface', () => {
  const feedback = {
    source: 'hybrid',
    badge: '生活新记',
    emotion_line: '初次遇见的小确幸，值得被温柔记录。',
    utility_line: '标记为首次光顾，方便日后回顾变化。',
    detail_reason: '候选明确显示这是第一次记录青集便利店。',
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      planner_version: 'expression-shadow-auto-v0.6',
      source_surface: 'record_detail',
      packet_fingerprint: 'packet-first-shop',
      claim_fingerprint: 'claim-first-shop',
      presentation_target: 'companion_message',
    },
  }
  const companionMessage = '第一次见青集便利店，8元买份踏实。'

  assert.equal(feedbackForCompanion({ companionMessage, feedback }), feedback)
  assert.equal(feedbackToRender({ companionMessage, feedback }), null)
})

test('does not move an explicit feedback card into the companion surface', () => {
  const feedback = {
    source: 'expression_planner',
    presentation_target: 'feedback_card',
    emotion_line: '这是一个独立的新角度。',
  }
  assert.equal(feedbackForCompanion({ companionMessage: '主陪伴文案', feedback }), null)
})

test('requires the feedback candidate identity to match the API envelope', () => {
  assert.equal(isPlannerFeedbackForCandidate({
    source: 'expression_planner',
    candidate_id: 'candidate-a',
    emotion_line: '旧版响应仍可兼容。',
  }, 'candidate-a'), true)
  assert.equal(isPlannerFeedbackForCandidate({
    source: 'expression_planner',
    candidate_id: 'candidate-b',
  }, 'candidate-a'), false)
  assert.equal(isPlannerFeedbackForCandidate({
    source: 'legacy_voice',
    candidate_id: 'candidate-a',
  }, 'candidate-a'), false)
  assert.equal(isPlannerFeedbackForCandidate({
    source: 'expression_planner',
    candidateId: 'candidate-a',
  }, 'candidate-a'), true)
})

const visibleCompanionMessage = '这周第 4 次点沙县，熟悉的味道又出现了。'

const companionDelivery = (overrides = {}) => ({
  candidateId: 'candidate-voice',
  presentationTarget: 'companion_message',
  renderedTextFingerprint: 'fnv1a64:voice-text',
  claimFingerprint: 'fnv1a64:merchant-repeat',
  feedback: planner({
    candidate_id: 'candidate-voice',
    semantic_key: 'merchant_weekly_repeat',
    claim_fingerprint: 'fnv1a64:merchant-repeat',
    presentation_target: 'companion_message',
    rendered_text_fingerprint: 'fnv1a64:voice-text',
    emotion_line: visibleCompanionMessage,
  }),
  ...overrides,
})

test('companion target acknowledges the visible companion container without rendering a second body', () => {
  const delivery = companionDelivery()
  const companionMessage = visibleCompanionMessage

  assert.equal(isCompanionMessageDelivery(delivery), true)
  assert.equal(isPlannerDeliveryEnvelopeValid(delivery), true)
  assert.equal(companionMessageMatchesDelivery({
    delivery,
    feedback: delivery.feedback,
    companionMessage,
  }), true)
  assert.equal(feedbackToRender({
    companionMessage,
    feedback: delivery.feedback,
    delivery,
  }), null)
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage,
    feedback: delivery.feedback,
    delivery,
  }), true)
})

test('companion target refuses acknowledgement when visible text or candidate identity drifted', () => {
  const delivery = companionDelivery()
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage: '这周第 11 次点沙县。',
    feedback: delivery.feedback,
    delivery,
  }), false)
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage: visibleCompanionMessage,
    feedback: { ...delivery.feedback, candidate_id: 'candidate-other' },
    delivery,
  }), false)
  assert.equal(companionMessageMatchesDelivery({
    delivery: { ...delivery, renderedTextFingerprint: '' },
    feedback: delivery.feedback,
    companionMessage: visibleCompanionMessage,
  }), false)
})

test('acknowledgement must retain companion candidate, claim and rendered text fingerprints', () => {
  const preview = companionDelivery()
  const acknowledged = companionDelivery({
    acknowledged: true,
    candidate_id: 'candidate-voice',
    candidateId: undefined,
    feedback: {
      ...preview.feedback,
      exposure_event_id: 'exposure-voice',
    },
  })
  assert.equal(plannerDeliveryIdentityMatches(preview, acknowledged), true)
  assert.equal(isPlannerDeliveryReviewable(preview), false)
  assert.equal(isPlannerDeliveryReviewable(acknowledged), true)
  assert.equal(plannerDeliveryIdentityMatches(preview, {
    ...acknowledged,
    renderedTextFingerprint: 'fnv1a64:different-text',
  }), false)
  assert.equal(plannerDeliveryIdentityMatches(preview, {
    ...acknowledged,
    claimFingerprint: 'fnv1a64:different-claim',
  }), false)
  assert.equal(plannerDeliveryIdentityMatches(preview, {
    ...acknowledged,
    candidate_id: 'candidate-other',
  }), false)
})

test('companion envelope rejects nested target and fingerprint mismatches before ACK', () => {
  const delivery = companionDelivery()
  assert.equal(isPlannerDeliveryEnvelopeValid({
    ...delivery,
    feedback: { ...delivery.feedback, presentation_target: 'feedback_card' },
  }), false)
  assert.equal(isPlannerDeliveryEnvelopeValid({
    ...delivery,
    feedback: { ...delivery.feedback, rendered_text_fingerprint: 'fnv1a64:other-text' },
  }), false)
})

test('authoritative feedback-card delivery is not hidden by legacy coverage or current-fact heuristics', () => {
  const feedback = planner({
    candidate_id: 'candidate-card',
    semantic_key: 'expense_current_record_context',
    dimension: 'current_fact',
    claim_fingerprint: 'fnv1a64:current-record',
    presentation_target: 'feedback_card',
    rendered_text_fingerprint: 'fnv1a64:card-text',
  })
  const delivery = {
    candidateId: 'candidate-card',
    presentationTarget: 'feedback_card',
    renderedTextFingerprint: 'fnv1a64:card-text',
    feedback,
  }
  const staleCompanionFeedback = {
    source: 'hybrid',
    expression_coverage: {
      coverage_version: 'expression-coverage-v1',
      expressed_semantic_key: 'expense_current_record_context',
      expressed_semantic_keys: ['expense_current_record_context'],
      source_surface: 'record_detail',
      planner_version: 'expression-shadow-auto-v0.6',
      packet_fingerprint: 'fnv1a32:legacy',
      claim_fingerprint: 'fnv1a64:current-record',
    },
  }

  assert.equal(isPlannerDeliveryEnvelopeValid(delivery), true)
  assert.equal(feedbackToRender({
    companionMessage: '这笔已经由 AI 陪伴说过一次。',
    feedback,
    companionFeedback: staleCompanionFeedback,
    delivery,
  }), feedback)
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage: '这笔已经由 AI 陪伴说过一次。',
    feedback,
    companionFeedback: staleCompanionFeedback,
    delivery,
  }), true)
  const acknowledged = {
    ...delivery,
    feedback: { ...feedback, exposure_event_id: 'exposure-card' },
  }
  assert.equal(plannerDeliveryIdentityMatches(delivery, acknowledged), true)
  assert.equal(plannerDeliveryIdentityMatches(delivery, {
    ...acknowledged,
    renderedTextFingerprint: 'fnv1a64:rewritten-card',
    feedback: {
      ...acknowledged.feedback,
      emotion_line: '确认时被改写的卡片文案。',
      rendered_text_fingerprint: 'fnv1a64:rewritten-card',
    },
  }), false)
})

test('legacy planner delivery without an explicit target still uses composition heuristics', () => {
  const feedback = planner({
    candidate_id: 'candidate-legacy-card',
    semantic_key: 'expense_current_record_context',
    dimension: 'current_fact',
  })
  const delivery = {
    candidateId: 'candidate-legacy-card',
    feedback,
  }
  assert.equal(isPlannerDeliveryEnvelopeValid(delivery), true)
  assert.equal(feedbackToRender({
    companionMessage: '这笔已经由 AI 陪伴说过一次。',
    feedback,
    delivery,
  }), null)
  assert.equal(shouldAcknowledgePlannerFeedback({
    companionMessage: '这笔已经由 AI 陪伴说过一次。',
    feedback,
    delivery,
  }), false)
})

test('resolves a universal-domain plan by record identity instead of UI record-kind vocabulary', () => {
  const sleepPlan = {
    status: 'ready',
    available: true,
    recordId: 'sleep-record-1',
    recordKind: 'data',
  }
  const cache = { 'sleep-record-1': sleepPlan }

  assert.equal(recordExpressionPlanForDetail(cache, 'sleep-record-1'), sleepPlan)
  assert.equal(recordExpressionPlanForDetail({
    'sleep-record-1': { ...sleepPlan, recordId: 'food-record-1' },
  }, 'sleep-record-1'), null)
})

test('reports Planner loading before a multi-domain feedback card arrives', () => {
  assert.deepEqual(plannerFeedbackSurfaceState({
    delivery: {
      status: 'loading',
      available: false,
      recordId: 'sleep-record-1',
      recordKind: 'data',
    },
  }), {
    state: 'loading',
    feedback: null,
    error: '',
  })
})

test('renders authoritative sleep and food feedback-card deliveries beside Voice', () => {
  for (const domain of ['sleep', 'food']) {
    const candidateId = `fact:${domain}:current-metric:record-1`
    const feedback = planner({
      candidate_id: candidateId,
      semantic_key: `${domain}_current_metric`,
      dimension: 'current_fact',
      presentation_target: 'feedback_card',
      rendered_text_fingerprint: `fnv1a64:${domain}-card`,
    })
    const delivery = {
      status: 'ready',
      available: true,
      candidateId,
      presentationTarget: 'feedback_card',
      renderedTextFingerprint: `fnv1a64:${domain}-card`,
      feedback,
    }

    assert.deepEqual(plannerFeedbackSurfaceState({
      delivery,
      companionMessage: `${domain} Voice support copy`,
    }), {
      state: 'ready',
      feedback,
      error: '',
    })
  }
})

test('retries transient Planner transport failures but not authorization or business errors', async () => {
  const failedFetch = new TypeError('Failed to fetch')
  const overloaded = Object.assign(new Error('服务暂时繁忙'), { status: 503 })
  const unauthorized = Object.assign(new Error('未授权'), { status: 401 })
  const businessError = new Error('表达计划响应不完整')

  assert.equal(isRetryableDeliveryError(failedFetch), true)
  assert.equal(isRetryableDeliveryError(overloaded), true)
  assert.equal(isRetryableDeliveryError(unauthorized), false)
  assert.equal(isRetryableDeliveryError(businessError), false)

  let attempts = 0
  const result = await retryWithBackoff(async () => {
    attempts += 1
    if (attempts === 1) throw failedFetch
    return { available: true }
  }, {
    delays: [0],
    shouldRetryError: isRetryableDeliveryError,
  })
  assert.deepEqual(result, { available: true })
  assert.equal(attempts, 2)
})

test('companion exposure waits until its container enters the visible viewport', async () => {
  const element = { id: 'companion-container' }
  const listeners = new Map()
  const documentRef = {
    visibilityState: 'visible',
    addEventListener(type, callback) { listeners.set(type, callback) },
    removeEventListener(type) { listeners.delete(type) },
  }
  let observerCallback
  class IntersectionObserverStub {
    constructor(callback) { observerCallback = callback }
    observe() {}
    disconnect() {}
  }
  let acknowledgementCount = 0
  const delivery = (async () => {
    await waitForVisibleElement(element, {
      documentRef,
      IntersectionObserverCtor: IntersectionObserverStub,
    })
    acknowledgementCount += 1
  })()

  await Promise.resolve()
  assert.equal(acknowledgementCount, 0)
  observerCallback([{ target: element, isIntersecting: false, intersectionRatio: 0 }])
  await Promise.resolve()
  assert.equal(acknowledgementCount, 0)
  observerCallback([{ target: element, isIntersecting: true, intersectionRatio: 0.01 }])
  await delivery
  assert.equal(acknowledgementCount, 1)
})
