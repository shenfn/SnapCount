import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/generic-domain-candidates.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/generic-domain-candidates.mjs'

test('CORE-075 Planner Lab wrapper re-exports production generic domain candidates', () => {
  assert.equal(plannerLab.generateBuiltinDomainCandidates, core.generateBuiltinDomainCandidates)
  assert.equal(plannerLab.generateIncomeCandidates, core.generateIncomeCandidates)
  assert.equal(plannerLab.parseFiniteNumber, core.parseFiniteNumber)
  assert.equal(plannerLab.prepareDomainRecords, core.prepareDomainRecords)
})
