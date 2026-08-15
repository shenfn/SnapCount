function getPath(value, path) {
  return path.split('.').reduce((current, key) => current?.[key], value)
}

function invoke(core, testCase) {
  const args = testCase.args ?? {}
  if (testCase.operation === 'normalizeEntityText') return core.normalizeEntityText(args.value)
  if (testCase.operation === 'resolveMerchant') {
    return core.resolveMerchant(args.value, core.compileMerchantAliases(args.config))
  }
  if (testCase.operation === 'summarizeMerchantObservation') {
    return core.summarizeMerchantObservation(args.current, args.prior)
  }
  throw new Error(`unknown operation: ${testCase.operation}`)
}

export function runEntityNormalizerAssertions(core, vectors, assertEqual, assertDeepEqual) {
  for (const testCase of vectors.cases) {
    const result = invoke(core, testCase)
    if (Object.prototype.hasOwnProperty.call(testCase.expected, 'value')) {
      assertEqual(result, testCase.expected.value, `value: ${testCase.name}`)
      continue
    }
    for (const [path, expected] of Object.entries(testCase.expected.checks ?? {})) {
      const actual = getPath(result, path)
      if (Array.isArray(expected) || (expected && typeof expected === 'object')) {
        assertDeepEqual(actual, expected, `${path}: ${testCase.name}`)
      } else {
        assertEqual(actual, expected, `${path}: ${testCase.name}`)
      }
    }
  }
}
