function getPath(value, path) {
  return path.split('.').reduce((current, key) => current?.[key], value)
}

export function runComparisonAssertions(core, vectors, assertEqual, assertDeepEqual) {
  for (const testCase of vectors.cases) {
    const operation = core[testCase.operation]
    assertEqual(typeof operation, 'function', `operation: ${testCase.name}`)
    const args = Array.isArray(testCase.args) ? testCase.args : [testCase.args]
    const result = operation(...args)
    assertEqual(result.length, testCase.expected.length, `length: ${testCase.name}`)
    if (result.length === 0) continue
    const candidate = result[testCase.expected.candidate_index ?? 0]
    for (const [path, expected] of Object.entries(testCase.expected.checks ?? {})) {
      const actual = getPath(candidate, path)
      if (Array.isArray(expected) || (expected && typeof expected === 'object')) {
        assertDeepEqual(actual, expected, `${path}: ${testCase.name}`)
      } else {
        assertEqual(actual, expected, `${path}: ${testCase.name}`)
      }
    }
  }
}
