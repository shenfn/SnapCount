import { runEligibilityAssertions } from './eligibility-assertions.mjs'
import * as eligibility from './eligibility-gates.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-资格门禁-v0.1.json', import.meta.url),
))

const assertEqual = (actual, expected, message) => {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
}

const assertDeepEqual = (actual, expected, message) => {
  const actualText = JSON.stringify(actual)
  const expectedText = JSON.stringify(expected)
  if (actualText !== expectedText) throw new Error(`${message}: expected ${expectedText}, got ${actualText}`)
}

Deno.test('CORE-013 to CORE-017 eligibility vectors', () => {
  runEligibilityAssertions(eligibility, vectors, assertEqual, assertDeepEqual)
})
