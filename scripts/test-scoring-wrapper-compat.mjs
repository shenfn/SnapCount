import test from 'node:test'
import assert from 'node:assert/strict'
import * as scoring from '../supabase/functions/_shared/expression-core/deterministic-scoring.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/deterministic-scoring.mjs'

test('CORE-023 Planner Lab wrapper re-exports production deterministic scoring', () => {
  assert.equal(plannerLab.SURFACE_THRESHOLDS, scoring.SURFACE_THRESHOLDS)
  assert.equal(plannerLab.INTERRUPTION_COSTS, scoring.INTERRUPTION_COSTS)
  assert.equal(plannerLab.DEFAULT_IMPORTANCE, scoring.DEFAULT_IMPORTANCE)
  assert.equal(plannerLab.scoreCandidate, scoring.scoreCandidate)
  assert.equal(plannerLab.scoreCandidates, scoring.scoreCandidates)
  assert.equal(plannerLab.summarizeScores, scoring.summarizeScores)
})
