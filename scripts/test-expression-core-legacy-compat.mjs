import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { buildSurfacePlan } from '../tools/ai-validation/expression-planner/lib/expression-plan.mjs'
import * as core from '../supabase/functions/_shared/expression-core/index.mjs'

const fixture = JSON.parse(await readFile(
  new URL('../supabase/functions/_shared/contracts/表达核心-旧行为对比-v0.1.json', import.meta.url),
  'utf8',
))

function selectedShape(plan) {
  return plan.selected.map(({ candidate_id, semantic_key, claim_type, selection_mode }) => ({
    candidate_id,
    semantic_key,
    claim_type,
    selection_mode,
  }))
}

for (const testCase of fixture.core_cases) {
  test(`CORE-compat ${testCase.name}`, () => {
    const operation = core[testCase.operation]
    assert.equal(typeof operation, 'function', `unknown core operation: ${testCase.operation}`)
    const actual = operation(...testCase.args)
    if (testCase.expected && typeof testCase.expected === 'object') {
      const selectedKeys = Object.keys(testCase.expected)
      assert.deepEqual(
        Object.fromEntries(selectedKeys.map(key => [key, actual[key]])),
        testCase.expected,
      )
      return
    }
    assert.deepEqual(actual, testCase.expected)
  })
}

for (const testCase of fixture.fallback_cases) {
  test(`CORE-fallback ${testCase.name}`, () => {
    const plan = buildSurfacePlan(testCase.candidates, testCase.surface)
    assert.deepEqual(selectedShape(plan), testCase.expected.selected)
    assert.equal(plan.fallback_used, testCase.expected.fallback_used)
    assert.equal(plan.silent, testCase.expected.silent)
  })
}
