import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runExpressionCoreFeatureAssertions } from './feature-assertions.mjs'
import * as core from './index.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-001 to CORE-004 shared vectors', () => {
  runExpressionCoreFeatureAssertions(
    core,
    vectors,
    (actual, expected, message) => assert.equal(actual, expected, message),
    (actual, expected, message) => assert.deepEqual(actual, expected, message),
  )
})
