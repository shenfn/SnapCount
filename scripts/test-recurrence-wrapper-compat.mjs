import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/recurrence-candidates.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/recurrence-candidates.mjs'

test('CORE-039 Planner Lab wrapper re-exports production recurrence candidate', () => {
  assert.equal(plannerLab.generateRecordNameRecurrenceCandidates, core.generateRecordNameRecurrenceCandidates)
})
