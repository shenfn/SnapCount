import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runCrossRecordAssertions } from './cross-record-assertions.mjs'
import * as core from './cross-record-relationships.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-跨记录关系-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-049 to CORE-055 cross-record vectors', () => {
  runCrossRecordAssertions(
    core,
    vectors,
    (actual, expected, message) => assert.equal(actual, expected, message),
    (actual, expected, message) => assert.deepEqual(actual, expected, message),
  )
})
