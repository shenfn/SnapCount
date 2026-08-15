import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runScoringAssertions } from './scoring-assertions.mjs'
import * as scoring from './deterministic-scoring.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-确定性评分-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-018 to CORE-023 deterministic scoring vectors', () => {
  runScoringAssertions(scoring, vectors, (actual, expected, message) => assert.equal(actual, expected, message))
})
