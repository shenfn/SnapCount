import { runCrossRecordAssertions } from './cross-record-assertions.mjs'
import * as core from './cross-record-relationships.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-跨记录关系-v0.1.json', import.meta.url),
))

Deno.test('CORE-049 to CORE-055 cross-record vectors', () => {
  runCrossRecordAssertions(
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
