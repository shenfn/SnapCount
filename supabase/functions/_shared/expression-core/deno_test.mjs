import { runExpressionCoreFeatureAssertions } from './feature-assertions.mjs'
import * as core from './index.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-v0.1.json', import.meta.url),
))

const assertEqual = (actual, expected, message) => {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
}

const assertDeepEqual = (actual, expected, message) => {
  const actualText = JSON.stringify(actual)
  const expectedText = JSON.stringify(expected)
  if (actualText !== expectedText) throw new Error(`${message}: expected ${expectedText}, got ${actualText}`)
}

Deno.test('CORE-001 to CORE-004 shared vectors', () => {
  runExpressionCoreFeatureAssertions(core, vectors, assertEqual, assertDeepEqual)
})
