import test from 'node:test'
import assert from 'node:assert/strict'
import * as eligibility from '../supabase/functions/_shared/expression-core/eligibility-gates.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/eligibility-gates.mjs'

test('CORE-017 Planner Lab wrapper re-exports production eligibility gates', () => {
  assert.equal(plannerLab.SURFACE_RULES, eligibility.SURFACE_RULES)
  assert.equal(plannerLab.evaluateCandidateEligibility, eligibility.evaluateCandidateEligibility)
  assert.equal(plannerLab.evaluateCandidates, eligibility.evaluateCandidates)
  assert.equal(plannerLab.summarizeEligibility, eligibility.summarizeEligibility)
})
