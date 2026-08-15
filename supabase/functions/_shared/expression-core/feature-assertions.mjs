export function runExpressionCoreFeatureAssertions(core, vectors, assertEqual, assertDeepEqual) {
  for (const testCase of vectors.number_cases) {
    assertEqual(
      core.parseFiniteNumber(testCase.input),
      testCase.expected,
      `number: ${testCase.name}`,
    )
  }

  for (const testCase of vectors.money_cases) {
    assertEqual(
      core.roundMoney(testCase.input, testCase.digits),
      testCase.expected,
      `money: ${testCase.name}`,
    )
  }

  for (const testCase of vectors.entity_cases) {
    assertEqual(
      core.normalizeEntityText(testCase.input),
      testCase.expected,
      `entity: ${testCase.name}`,
    )
  }

  for (const testCase of vectors.fact_contract_cases) {
    const actual = core.buildExpenseFactContract(testCase.record)
    const selected = Object.fromEntries(
      Object.keys(testCase.expected).map(key => [key, actual[key]]),
    )
    assertDeepEqual(selected, testCase.expected, `fact contract: ${testCase.name}`)
  }
}
