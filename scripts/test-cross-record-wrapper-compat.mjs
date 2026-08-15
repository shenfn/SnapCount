import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/cross-record-relationships.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/cross-record-relationships.mjs'

test('CORE-055 Planner Lab wrapper re-exports production cross-record candidates', () => {
  assert.equal(plannerLab.generateCrossRecordRelationshipCandidates, core.generateCrossRecordRelationshipCandidates)
})
