import test from 'node:test'
import assert from 'node:assert/strict'
import { inferIssueAnnotations, normalizeExposureFeedback, primaryChoiceFromLegacyReview } from '../lib/exposure-feedback-contract.mjs'

const context = {
  feedbackKey: 'feedback-1', occurredAt: '2026-07-12T23:03:46+08:00',
  userId: '00000000-0000-4000-8000-000000000001', exposureEventId: 'exposure-1',
  candidateId: 'weekly-comparison', semanticKey: 'merchant_week_to_date_vs_previous_week_same_period',
  surface: 'shortcut_notification', visibleFieldPaths: ['ai_feedback.utility_line'],
}

test('keeps the public choice simple while deriving internal timing and relevance issues', () => {
  const feedback = normalizeExposureFeedback({ primaryChoice: 'not_helpful', notes: '和这笔订单没什么关系，这个原因更适合放在周报里。' }, context)
  assert.equal(feedback.primary_choice, 'not_helpful')
  assert.deepEqual(feedback.issue_annotations.map(item => item.issue_code).sort(), ['not_helpful', 'not_relevant', 'wrong_surface'])
})

test('does not allow production feedback without an exposure association', () => {
  assert.throws(() => normalizeExposureFeedback({ primaryChoice: 'other' }, { ...context, exposureEventId: null }), /exposure_event_id/)
})

test('allows legacy review imports to remain explicitly unresolved', () => {
  const feedback = normalizeExposureFeedback({ primaryChoice: 'not_helpful' }, { ...context, exposureEventId: null, legacyImport: true })
  assert.equal(feedback.exposure_resolution, 'legacy_unresolved')
})

test('maps July 12 style review text to understandable primary feedback', () => {
  const review = { ratings: { feedback_quality: 3 }, issue_tags: ['other'], notes: '这句文案没懂什么意思，而且和这笔订单没什么关系，每一次都拿消费说用户会厌倦。' }
  assert.equal(primaryChoiceFromLegacyReview(review), 'repetitive')
  const codes = inferIssueAnnotations({ primaryChoice: 'repetitive', legacyIssueTags: review.issue_tags, notes: review.notes }).map(item => item.issue_code)
  assert.deepEqual(codes.sort(), ['not_relevant', 'too_repetitive', 'too_vague'])
})

test('extracts detail-density and temporal preferences from free text', () => {
  const codes = inferIssueAnnotations({
    primaryChoice: 'other',
    notes: '还是话太少了，想从其他角度评价一下，比如时间维度。',
  }).map(item => item.issue_code)
  assert.deepEqual(codes.sort(), ['missing_dimensions', 'too_brief', 'wants_temporal_context'])
})
