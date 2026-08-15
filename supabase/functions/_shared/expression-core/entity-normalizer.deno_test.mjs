import { runEntityNormalizerAssertions } from './entity-normalizer-assertions.mjs'
import * as core from './entity-normalizer.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-实体归一化-v0.1.json', import.meta.url),
))

Deno.test('CORE-056 to CORE-061 entity normalizer vectors', () => {
  runEntityNormalizerAssertions(
    core,
    vectors,
    (actual, expected, message) => {
      if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
    },
    (actual, expected, message) => {
      if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${message}: values differ`)
    },
  )
})
