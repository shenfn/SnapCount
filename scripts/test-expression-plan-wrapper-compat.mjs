import test from 'node:test'
import assert from 'node:assert/strict'
import * as planSelection from '../supabase/functions/_shared/expression-core/plan-selection.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/expression-plan.mjs'

test('CORE-012 Planner Lab wrapper re-exports production selectors', () => {
  assert.equal(plannerLab.SURFACE_CAPACITY, planSelection.SURFACE_CAPACITY)
  assert.equal(plannerLab.buildSurfacePlan, planSelection.buildSurfacePlan)
  assert.equal(plannerLab.buildExpressionPlans, planSelection.buildExpressionPlans)
  assert.equal(plannerLab.summarizePlans, planSelection.summarizePlans)
})
