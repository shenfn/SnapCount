import { runRenderContractAssertions } from './render-contract-assertions.mjs'
import * as core from './render-contract.mjs'

const vectors = JSON.parse(await Deno.readTextFile(
  new URL('../contracts/表达核心-渲染契约-v0.1.json', import.meta.url),
))

Deno.test('CORE-077 to CORE-084 render contract vectors', () => {
  runRenderContractAssertions(core, vectors, {
    equal: (actual, expected, message) => {
      if (actual !== expected) throw new Error(`${message}: expected ${expected}, got ${actual}`)
    },
    deepEqual: (actual, expected, message) => {
      const actualText = JSON.stringify(actual)
      const expectedText = JSON.stringify(expected)
      if (actualText !== expectedText) throw new Error(`${message}: expected ${expectedText}, got ${actualText}`)
    },
  })
})
