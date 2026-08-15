import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runRecurrenceAssertions } from './recurrence-assertions.mjs'
import * as core from './recurrence-candidates.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-周期复现-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-031 to CORE-039 recurrence vectors', () => {
  runRecurrenceAssertions(core, vectors, (actual, expected, message) => assert.equal(actual, expected, message), (actual, expected, message) => assert.deepEqual(actual, expected, message))
})
