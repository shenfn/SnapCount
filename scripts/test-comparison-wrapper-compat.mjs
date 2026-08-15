import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/comparison-candidates.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/comparison-candidates.mjs'

test('CORE-048 Planner Lab wrapper re-exports production comparison candidates', () => {
  assert.equal(plannerLab.generateComparisonCandidates, core.generateComparisonCandidates)
  assert.equal(plannerLab.generateCategoryComparisonCandidates, core.generateCategoryComparisonCandidates)
})
