import test from 'node:test'
import assert from 'node:assert/strict'
import { normalizeExposureFeedback } from '../lib/exposure-feedback-contract.mjs'
import { derivePreferenceSignals } from '../lib/preference-signal-deriver.mjs'

const context = { feedbackKey: 'feedback-1', occurredAt: '2026-07-12T23:03:46+08:00', userId: 'user-1', exposureEventId: 'exposure-1', candidateId: 'candidate-1', semanticKey: 'merchant_week_velocity', surface: 'shortcut_notification' }

test('derives weak preference evidence instead of permanently changing a profile', () => {
  const feedback = normalizeExposureFeedback({ primaryChoice: 'repetitive', explicitIssueCodes: ['bad_timing'] }, context)
  const result = derivePreferenceSignals(feedback)
  assert.equal(result.signals.length, 2)
  assert.equal(result.signals[0].aggregation_policy, 'decay_and_repeat_required')
  assert.ok(result.signals.every(signal => signal.strength > 0 && signal.strength < 1))
})

test('keeps factual and recognition errors out of preference memory', () => {
  const feedback = normalizeExposureFeedback({ primaryChoice: 'incorrect', explicitIssueCodes: ['number_wrong', 'presentation_format_wrong', 'recognition_wrong'] }, context)
  const result = derivePreferenceSignals(feedback)
  assert.equal(result.signals.length, 0)
  assert.deepEqual(result.quality_issues.sort(), ['content_wrong_unspecified', 'number_wrong', 'presentation_format_wrong', 'recognition_wrong'])
})
test('suppresses ambiguous not-helpful preference when a specific quality defect explains it', () => {
  const feedback = normalizeExposureFeedback({
    primaryChoice: 'not_helpful',
    notes: '记录时长不要用百进制，应该转成小时和分钟。',
  }, context)
  const result = derivePreferenceSignals(feedback)
  assert.equal(result.signals.length, 0)
  assert.deepEqual(result.quality_issues, ['presentation_format_wrong'])
  assert.deepEqual(result.suppressed_signals, [{
    issue_code: 'not_helpful', reason: 'specific_quality_issue_present',
  }])
})

test('turns concise-output feedback into bounded rendering preferences', () => {
  const feedback = normalizeExposureFeedback({
    primaryChoice: 'other',
    notes: '字有点少，希望增加其他角度，比如时间维度。',
  }, context)
  const result = derivePreferenceSignals(feedback)
  assert.deepEqual(result.signals.map(item => item.preference_dimension).sort(), [
    'detail_breadth_preference', 'temporal_context_preference', 'verbosity_preference',
  ])
  assert.ok(result.signals.every(signal => signal.direction === 'increase'))
})
