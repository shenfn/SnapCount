import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runRenderContractAssertions } from './render-contract-assertions.mjs'
import * as core from './render-contract.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-渲染契约-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-077 to CORE-084 render contract vectors', () => {
  runRenderContractAssertions(core, vectors, {
    equal: (actual, expected, message) => assert.equal(actual, expected, message),
    deepEqual: (actual, expected, message) => assert.deepEqual(actual, expected, message),
  })
})
