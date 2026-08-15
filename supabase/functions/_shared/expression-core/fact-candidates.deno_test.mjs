import { runFactCandidateAssertions } from './fact-candidate-assertions.mjs'
import * as core from './fact-candidates.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-事实候选-v0.1.json', import.meta.url),
))

Deno.test('CORE-024 to CORE-030 fact candidate vectors', () => {
  runFactCandidateAssertions(core, vectors, (actual, expected, message) => {
    if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  }, (actual, expected, message) => {
    const actualText = JSON.stringify(actual)
    const expectedText = JSON.stringify(expected)
    if (actualText !== expectedText) throw new Error(`${message}: expected ${expectedText}, got ${actualText}`)
  })
})
