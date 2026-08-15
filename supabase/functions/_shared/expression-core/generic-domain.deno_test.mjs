import { runGenericDomainAssertions } from './generic-domain-assertions.mjs'
import * as core from './generic-domain-candidates.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-通用域-v0.1.json', import.meta.url),
))

Deno.test('CORE-063 to CORE-074 generic domain vectors', () => {
  runGenericDomainAssertions(core, vectors, {
    equal: (actual, expected, message) => {
      if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
    },
    deepEqual: (actual, expected, message) => {
      if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${message}: values differ`)
    },
    match: (actual, pattern, message) => {
      if (!new RegExp(pattern).test(actual)) throw new Error(`${message}: pattern ${pattern} did not match`)
    },
    doesNotMatch: (actual, pattern, message) => {
      if (new RegExp(pattern).test(actual)) throw new Error(`${message}: pattern ${pattern} unexpectedly matched`)
    },
  })
})
