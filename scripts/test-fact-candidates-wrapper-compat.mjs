import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/fact-candidates.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/fact-candidates.mjs'

test('CORE-030 Planner Lab wrapper re-exports production fact candidates', () => {
  assert.equal(plannerLab.generateCurrentExpenseRecordCandidate, core.generateCurrentExpenseRecordCandidate)
  assert.equal(plannerLab.generateFactCandidates, core.generateFactCandidates)
  assert.equal(plannerLab.generateMerchantFirstOccurrenceCandidate, core.generateMerchantFirstOccurrenceCandidate)
})
