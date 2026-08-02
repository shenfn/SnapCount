import test from 'node:test'
import assert from 'node:assert/strict'
import { baselineSemanticKey } from '../lib/semantic-taxonomy.mjs'

test('uses controlled semantic identities instead of badge text', () => {
  assert.equal(baselineSemanticKey('food', '结构扎实'), 'food_composition')
  assert.equal(baselineSemanticKey('expense', '理性消费'), 'legacy_expense_feedback')
  assert.equal(baselineSemanticKey('food', '理智消费'), 'legacy_food_feedback')
})
