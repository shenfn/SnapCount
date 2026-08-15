import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runEligibilityAssertions } from './eligibility-assertions.mjs'
import * as eligibility from './eligibility-gates.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-资格门禁-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-013 to CORE-017 eligibility vectors', () => {
  runEligibilityAssertions(
    eligibility,
    vectors,
    (actual, expected, message) => assert.equal(actual, expected, message),
    (actual, expected, message) => assert.deepEqual(actual, expected, message),
  )
})
