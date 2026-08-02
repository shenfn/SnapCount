import test from 'node:test'
import assert from 'node:assert/strict'
import { aggregatePreferenceSignals, toScoringPreferenceProfile } from '../lib/preference-signal-aggregator.mjs'

function signal(overrides = {}) {
  return {
    signal_key: 'signal-1', feedback_key: 'feedback-1',
    occurred_at: '2026-07-12T12:00:00+08:00',
    semantic_key: 'merchant_week_velocity', surface: 'shortcut_notification',
    preference_dimension: 'semantic_preference', direction: 'decrease', strength: 0.4,
    ...overrides,
  }
}

test('keeps one feedback provisional and attenuated', () => {
  const snapshot = aggregatePreferenceSignals([signal()], { asOf: '2026-07-13T12:00:00+08:00' })
  assert.equal(snapshot.evidence[0].support_count, 1)
  assert.equal(snapshot.evidence[0].maturity, 'provisional')
  assert.ok(snapshot.semantic_key_weights.merchant_week_velocity > 0.85)
  assert.ok(snapshot.semantic_key_weights.merchant_week_velocity < 1)
})

test('strengthens repeated independent feedback without exceeding bounds', () => {
  const signals = [
    signal(),
    signal({ signal_key: 'signal-2', feedback_key: 'feedback-2', strength: 0.5 }),
    signal({ signal_key: 'signal-3', feedback_key: 'feedback-3', strength: 0.6 }),
  ]
  const snapshot = aggregatePreferenceSignals(signals, { asOf: '2026-07-13T12:00:00+08:00' })
  assert.equal(snapshot.evidence[0].maturity, 'active')
  assert.equal(snapshot.semantic_key_weights.merchant_week_velocity, 0.7)
})

test('applies time decay and opposing corrections', () => {
  const snapshot = aggregatePreferenceSignals([
    signal({ occurred_at: '2026-05-13T12:00:00+08:00', strength: 0.5 }),
    signal({ signal_key: 'signal-2', feedback_key: 'feedback-2', direction: 'increase', strength: 0.3 }),
  ], { asOf: '2026-07-13T12:00:00+08:00', halfLifeDays: 60 })
  assert.ok(snapshot.semantic_key_weights.merchant_week_velocity > 0.95)
  assert.ok(snapshot.semantic_key_weights.merchant_week_velocity < 1.05)
})

test('separates surface scoring preferences from rendering preferences', () => {
  const snapshot = aggregatePreferenceSignals([
    signal({ preference_dimension: 'surface_preference' }),
    signal({ signal_key: 'signal-2', feedback_key: 'feedback-2', preference_dimension: 'expression_style' }),
  ], { asOf: '2026-07-13T12:00:00+08:00' })
  assert.ok(snapshot.surface_semantic_weights.shortcut_notification.merchant_week_velocity < 1)
  assert.ok(snapshot.rendering_preferences.shortcut_notification.expression_style < 1)
  const profile = toScoringPreferenceProfile(snapshot)
  assert.equal(profile.rendering_preferences, undefined)
})

test('does not guess semantic targets for unresolved legacy signals', () => {
  const snapshot = aggregatePreferenceSignals([
    signal({ semantic_key: null }),
  ], { asOf: '2026-07-13T12:00:00+08:00' })
  assert.equal(snapshot.unresolved_signals.length, 1)
  assert.deepEqual(snapshot.semantic_key_weights, {})
})

test('counts repeated reviews of one exposure as one support item', () => {
  const snapshot = aggregatePreferenceSignals([
    signal({
      signal_key: 'signal-1', feedback_key: 'feedback-1', exposure_event_id: 'exposure-1',
      preference_dimension: 'verbosity_preference', direction: 'increase', strength: 0.1,
    }),
    signal({
      signal_key: 'signal-2', feedback_key: 'feedback-2', exposure_event_id: 'exposure-1',
      occurred_at: '2026-07-12T13:00:00+08:00', preference_dimension: 'verbosity_preference',
      direction: 'increase', strength: 0.2,
    }),
  ], { asOf: '2026-07-13T12:00:00+08:00' })
  assert.equal(snapshot.evidence[0].support_count, 1)
  assert.equal(snapshot.evidence[0].contributions.length, 1)
  assert.equal(snapshot.evidence[0].contributions[0].signal_key, 'signal-2')
})
