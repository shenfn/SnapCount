import test from 'node:test'
import assert from 'node:assert/strict'
import * as core from '../supabase/functions/_shared/expression-core/entity-normalizer.mjs'
import * as plannerLab from '../tools/ai-validation/expression-planner/lib/entity-normalizer.mjs'

test('CORE-062 Planner Lab wrapper re-exports production entity normalizer', () => {
  assert.equal(plannerLab.compileMerchantAliases, core.compileMerchantAliases)
  assert.equal(plannerLab.normalizeEntityText, core.normalizeEntityText)
  assert.equal(plannerLab.resolveMerchant, core.resolveMerchant)
  assert.equal(plannerLab.summarizeMerchantObservation, core.summarizeMerchantObservation)
})
