import { runComparisonAssertions } from './comparison-assertions.mjs'
import * as core from './comparison-candidates.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-比较候选-v0.1.json', import.meta.url),
))

Deno.test('CORE-040 to CORE-048 comparison vectors', () => {
  runComparisonAssertions(core, vectors, (actual, expected, message) => {
    if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  }, (actual, expected, message) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${message}: values differ`)
  })
})
