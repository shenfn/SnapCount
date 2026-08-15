import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runComparisonAssertions } from './comparison-assertions.mjs'
import * as core from './comparison-candidates.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-比较候选-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-040 to CORE-048 comparison vectors', () => {
  runComparisonAssertions(core, vectors, (actual, expected, message) => assert.equal(actual, expected, message), (actual, expected, message) => assert.deepEqual(actual, expected, message))
})
