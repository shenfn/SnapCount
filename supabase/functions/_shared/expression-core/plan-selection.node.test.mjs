import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runPlanSelectionAssertions } from './plan-selection-assertions.mjs'
import * as planSelection from './plan-selection.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-降级选择-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-008 to CORE-012 plan selection vectors', () => {
  runPlanSelectionAssertions(
    planSelection,
    vectors,
    (actual, expected, message) => assert.equal(actual, expected, message),
    (actual, expected, message) => assert.deepEqual(actual, expected, message),
    (operation, expectedMessage, message) => assert.throws(operation, { message: new RegExp(expectedMessage) }, message),
  )
})
