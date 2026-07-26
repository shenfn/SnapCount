import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import {
  retryWithBackoff,
  waitForVisibleElement,
} from '../../../../src/utils/expressionDelivery.js'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')

test('PWA binds feedback to the rendered exposure when its id is available', async () => {
  const [card, detail, store] = await Promise.all([
    readFile(path.join(root, 'src/components/AiFeedbackCard.vue'), 'utf8'),
    readFile(path.join(root, 'src/components/pages/PageRecordDetail.vue'), 'utf8'),
    readFile(path.join(root, 'src/composables/useStore.js'), 'utf8'),
  ])

  assert.match(card, /exposureEventId:\s*\{\s*type:\s*String/)
  assert.match(card, /exposureEventId:\s*props\.exposureEventId/)
  assert.match(detail, /:exposure-event-id="aiFeedbackExposureEventId"/)
  assert.match(detail, /aiFeedback\.value\?\.exposure_event_id/)
  assert.match(detail, /submitExpressionFeedback\(\{\s*recordId,\s*choice,\s*freeText,\s*exposureEventId\s*\}\)/)
  assert.match(store, /submitExpressionFeedback\(\{\s*recordId,\s*choice,\s*freeText\s*=\s*"",\s*exposureEventId\s*=\s*""\s*\}\)/)
  assert.match(store, /\.\.\.\(exposureEventId\s*\?\s*\{\s*exposure_event_id:\s*exposureEventId\s*\}\s*:\s*\{\}\)/)
})

test('PWA success copy describes future selection without claiming immediate effect', async () => {
  const [card, detail] = await Promise.all([
    readFile(path.join(root, 'src/components/AiFeedbackCard.vue'), 'utf8'),
    readFile(path.join(root, 'src/components/pages/PageRecordDetail.vue'), 'utf8'),
  ])

  assert.match(card, /已记录，将用于后续选择/)
  assert.match(detail, /已记录，将用于后续选择/)
  assert.doesNotMatch(detail, /点评已生效/)
})

test('PWA can edit a submitted review without changing its exposure binding', async () => {
  const card = await readFile(path.join(root, 'src/components/AiFeedbackCard.vue'), 'utf8')

  assert.match(card, /reviewState === 'submitted' && !editingReview/)
  assert.match(card, /class="ai-feedback-review-edit" @click="startReviewEdit">修改点评<\/button>/)
  assert.match(card, /function startReviewEdit\(\)\s*\{\s*editingReview\.value = true\s*\}/)
  assert.match(card, /nextState === 'submitted' && previousState === 'syncing'/)

  const choices = [...card.matchAll(/\{ value: '([^']+)', label: '[^']+' \}/g)].map(match => match[1])
  assert.deepEqual(choices, [
    'helpful',
    'good_angle',
    'just_what_i_wanted',
    'no_change_needed',
    'incorrect',
    'not_helpful',
    'repetitive',
    'style_dislike',
    'other',
  ])
  assert.match(card, /aria-pressed="selectedChoice === choice\.value"/)
  assert.match(card, /exposureEventId:\s*props\.exposureEventId \|\| ''/)
})

test('PWA renders owner planner feedback before acknowledging its exposure', async () => {
  const [card, detail, store, delivery] = await Promise.all([
    readFile(path.join(root, 'src/components/AiFeedbackCard.vue'), 'utf8'),
    readFile(path.join(root, 'src/components/pages/PageRecordDetail.vue'), 'utf8'),
    readFile(path.join(root, 'src/composables/useStore.js'), 'utf8'),
    readFile(path.join(root, 'src/utils/expressionDelivery.js'), 'utf8'),
  ])

  assert.match(store, /recordExpressionPlanCache\s*=\s*ref\(\{\}\)/)
  assert.match(store, /get_record_expression_plan/)
  assert.match(store, /ack_record_expression_plan/)
  assert.match(store, /plan_token:\s*planToken/)
  assert.match(store, /candidate_id:\s*candidateId/)
  assert.match(store, /recordExpressionPlanCache\.value\s*=\s*\{\}/)
  assert.match(store, /cached\.reason\s*===\s*'plan_not_ready'/)
  assert.match(detail, /plan\?\.recordKind\s*===\s*expectedExpressionRecordKind\.value/)
  assert.match(detail, /plannerAiFeedback\.value\s*\|\|\s*legacyAiFeedback\.value/)
  assert.match(detail, /:reviewable="aiFeedbackReviewable"/)
  assert.match(detail, /recordExpressionPlan\.value\?\.acknowledged\s*&&\s*aiFeedbackExposureEventId\.value/)
  assert.match(detail, /!aiFeedbackReviewable\.value/)
  assert.match(detail, /onCleanup\(\(\)\s*=>\s*\{/)
  assert.match(detail, /controller\.abort\(\)/)
  assert.match(detail, /waitForVisibleElement\(feedbackCardElement\(\)/)
  assert.match(detail, /globalThis\.document\?\.visibilityState\s*!==\s*'visible'/)
  assert.match(delivery, /documentRef\.visibilityState\s*===\s*'visible'/)
  assert.match(card, /暂时无法点评/)
  assert.match(card, /emit\('retry-review'\)/)

  const loadIndex = detail.indexOf('store.loadRecordExpressionPlan(recordId')
  const nextTickIndex = detail.indexOf('await nextTick()', loadIndex)
  const visibleIndex = detail.indexOf('await waitForVisibleElement(', nextTickIndex)
  const ackIndex = detail.indexOf('store.ackRecordExpressionPlan(recordId', nextTickIndex)
  assert.ok(loadIndex >= 0, 'detail must load the selected record plan')
  assert.ok(nextTickIndex > loadIndex, 'detail must render the planner feedback before acknowledgement')
  assert.ok(visibleIndex > nextTickIndex, 'detail must wait until the rendered card enters the viewport')
  assert.ok(ackIndex > visibleIndex, 'detail must acknowledge only after visibility is confirmed')
})

test('PWA pending records expose the same visible acknowledgement and review loop', async () => {
  const pending = await readFile(path.join(root, 'src/components/ModalPending.vue'), 'utf8')

  assert.match(pending, /store\.loadRecordExpressionPlan\(recordId,\s*\{\s*recordKind,\s*signal\s*\}\)/)
  assert.match(pending, /waitForVisibleElement\(pendingFeedbackCardElement\(\)/)
  assert.match(pending, /store\.ackRecordExpressionPlan\(recordId,\s*\{\s*signal:/)
  assert.match(pending, /:reviewable="aiFeedbackReviewable"/)
  assert.match(pending, /:exposure-event-id="aiFeedbackExposureEventId"/)
  assert.match(pending, /@submit-review="submitFeedbackReview"/)
  assert.match(pending, /submitExpressionFeedback\(\{\s*recordId,\s*choice,\s*freeText,\s*exposureEventId\s*\}\)/)
  assert.match(pending, /onCleanup\(\(\)\s*=>\s*\{\s*controller\.abort\(\)/)

  const loadIndex = pending.indexOf('store.loadRecordExpressionPlan(recordId')
  const nextTickIndex = pending.indexOf('await nextTick()', loadIndex)
  const visibleIndex = pending.indexOf('await waitForVisibleElement(', nextTickIndex)
  const ackIndex = pending.indexOf('store.ackRecordExpressionPlan(recordId', nextTickIndex)
  assert.ok(loadIndex >= 0)
  assert.ok(nextTickIndex > loadIndex)
  assert.ok(visibleIndex > nextTickIndex)
  assert.ok(ackIndex > visibleIndex)
})

test('bounded backoff retries plan_not_ready and stops after cancellation', async () => {
  let attempts = 0
  const ready = await retryWithBackoff(
    async () => {
      attempts += 1
      return attempts < 3 ? { available: false, reason: 'plan_not_ready' } : { available: true }
    },
    {
      delays: [0, 0, 0],
      shouldRetryResult: result => result.reason === 'plan_not_ready',
    },
  )
  assert.equal(ready.available, true)
  assert.equal(attempts, 3)

  let boundedAttempts = 0
  const unavailable = await retryWithBackoff(
    async () => {
      boundedAttempts += 1
      return { available: false, reason: 'plan_not_ready' }
    },
    {
      delays: [0, 0],
      shouldRetryResult: result => result.reason === 'plan_not_ready',
    },
  )
  assert.equal(unavailable.available, false)
  assert.equal(boundedAttempts, 3)

  const controller = new AbortController()
  let cancelledAttempts = 0
  const pending = retryWithBackoff(
    async () => {
      cancelledAttempts += 1
      return { available: false, reason: 'plan_not_ready' }
    },
    {
      delays: [1000, 1000],
      signal: controller.signal,
      shouldRetryResult: result => result.reason === 'plan_not_ready',
    },
  )
  await Promise.resolve()
  controller.abort()
  await assert.rejects(pending, error => error?.name === 'AbortError')
  assert.equal(cancelledAttempts, 1)
})

test('acknowledgement retries errors only for the configured attempts', async () => {
  let attempts = 0
  await assert.rejects(
    retryWithBackoff(
      async () => {
        attempts += 1
        throw new Error('ack failed')
      },
      {
        delays: [0, 0],
        shouldRetryError: () => true,
      },
    ),
    /ack failed/,
  )
  assert.equal(attempts, 3)
})

test('visibility gate requires both viewport intersection and a visible document', async () => {
  const listeners = new Set()
  const documentRef = {
    visibilityState: 'hidden',
    addEventListener(type, listener) {
      if (type === 'visibilitychange') listeners.add(listener)
    },
    removeEventListener(type, listener) {
      if (type === 'visibilitychange') listeners.delete(listener)
    },
  }
  let observerCallback = null
  let disconnected = false
  class FakeIntersectionObserver {
    constructor(callback) {
      observerCallback = callback
    }
    observe() {}
    disconnect() {
      disconnected = true
    }
  }
  const element = {}
  let resolved = false
  const visible = waitForVisibleElement(element, {
    documentRef,
    IntersectionObserverCtor: FakeIntersectionObserver,
  }).then(() => {
    resolved = true
  })

  observerCallback([{ target: element, isIntersecting: true, intersectionRatio: 0.5 }])
  await Promise.resolve()
  assert.equal(resolved, false, 'hidden documents must not acknowledge an exposure')

  documentRef.visibilityState = 'visible'
  for (const listener of [...listeners]) listener()
  await visible
  assert.equal(resolved, true)
  assert.equal(disconnected, true)
  assert.equal(listeners.size, 0)

  disconnected = false
  const controller = new AbortController()
  const cancelled = waitForVisibleElement(element, {
    signal: controller.signal,
    documentRef,
    IntersectionObserverCtor: FakeIntersectionObserver,
  })
  controller.abort()
  await assert.rejects(cancelled, error => error?.name === 'AbortError')
  assert.equal(disconnected, true)
  assert.equal(listeners.size, 0)
})

test('direct SIGNED_IN user switches clear cached state before assigning the new user', async () => {
  const app = await readFile(path.join(root, 'src/App.vue'), 'utf8')
  const sessionStart = app.indexOf('async function applySession(session)')
  const resetIndex = app.indexOf('store.resetUserData()', sessionStart)
  const assignIndex = app.indexOf('store.currentUserId.value = session.user.id', sessionStart)

  assert.match(app, /store\.currentUserId\.value\s*&&\s*store\.currentUserId\.value\s*!==\s*session\.user\.id/)
  assert.ok(sessionStart >= 0)
  assert.ok(resetIndex > sessionStart, 'user switching must clear the previous account cache')
  assert.ok(assignIndex > resetIndex, 'the cache must be cleared before assigning the new user id')
})
