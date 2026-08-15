import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { runGenericDomainAssertions } from './generic-domain-assertions.mjs'
import * as core from './generic-domain-candidates.mjs'

const vectors = JSON.parse(await readFile(
  new URL('../contracts/表达核心-通用域-v0.1.json', import.meta.url),
  'utf8',
))

test('CORE-063 to CORE-074 generic domain vectors', () => {
  runGenericDomainAssertions(core, vectors, {
    equal: (actual, expected, message) => assert.equal(actual, expected, message),
    deepEqual: (actual, expected, message) => assert.deepEqual(actual, expected, message),
    match: (actual, pattern, message) => assert.match(actual, new RegExp(pattern), message),
    doesNotMatch: (actual, pattern, message) => assert.doesNotMatch(actual, new RegExp(pattern), message),
  })
})
