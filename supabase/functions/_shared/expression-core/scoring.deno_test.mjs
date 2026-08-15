import { runScoringAssertions } from './scoring-assertions.mjs'
import * as scoring from './deterministic-scoring.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-确定性评分-v0.1.json', import.meta.url),
))

Deno.test('CORE-018 to CORE-023 deterministic scoring vectors', () => {
  runScoringAssertions(scoring, vectors, (actual, expected, message) => {
    if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  })
})
