import { runRecurrenceAssertions } from './recurrence-assertions.mjs'
import * as core from './recurrence-candidates.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-周期复现-v0.1.json', import.meta.url),
))

Deno.test('CORE-031 to CORE-039 recurrence vectors', () => {
  runRecurrenceAssertions(core, vectors, (actual, expected, message) => {
    if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
  }, (actual, expected, message) => {
    if (JSON.stringify(actual) !== JSON.stringify(expected)) throw new Error(`${message}: values differ`)
  })
})
