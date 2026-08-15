import { runPlanSelectionAssertions } from './plan-selection-assertions.mjs'
import * as planSelection from './plan-selection.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-降级选择-v0.1.json', import.meta.url),
))

const assertEqual = (actual, expected, message) => {
  if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
}

const assertDeepEqual = (actual, expected, message) => {
  const actualText = JSON.stringify(actual)
  const expectedText = JSON.stringify(expected)
  if (actualText !== expectedText) throw new Error(`${message}: expected ${expectedText}, got ${actualText}`)
}

const assertThrows = (operation, expectedMessage, message) => {
  try {
    operation()
  } catch (error) {
    if (String(error?.message ?? error).includes(expectedMessage)) return
    throw new Error(`${message}: unexpected error ${String(error?.message ?? error)}`)
  }
  throw new Error(`${message}: expected operation to throw`)
}

Deno.test('CORE-008 to CORE-012 plan selection vectors', () => {
  runPlanSelectionAssertions(planSelection, vectors, assertEqual, assertDeepEqual, assertThrows)
})
