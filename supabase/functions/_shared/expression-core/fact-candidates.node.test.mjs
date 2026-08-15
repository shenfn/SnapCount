import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runFactCandidateAssertions } from './fact-candidate-assertions.mjs'
import * as core from './fact-candidates.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-事实候选-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-024 to CORE-030 fact candidate vectors', () => {
  runFactCandidateAssertions(core, vectors, (actual, expected, message) => assert.equal(actual, expected, message), (actual, expected, message) => assert.deepEqual(actual, expected, message))
})
