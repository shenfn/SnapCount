function getPath(value, path) {
  return path.split('.').reduce((current, key) => current?.[key], value)
}

function invoke(core, testCase) {
  const args = testCase.args ?? {}
  if (testCase.operation === 'surfaceContracts') return core.SURFACE_RENDER_CONTRACTS
  if (testCase.operation === 'buildRenderPlans') {
    return core.buildRenderPlans(args.expressionPlans ?? {}, args.candidates ?? [])
  }
  if (testCase.operation === 'buildExposureEvents') {
    return core.buildExposureEvents(args.renderPlans ?? {}, args.options ?? {})
  }
  if (testCase.operation === 'compileExposureHistory') {
    return core.compileExposureHistory(args.events ?? [])
  }
  if (testCase.operation === 'version') return core.SURFACE_RENDER_CONTRACT_VERSION
  throw new Error(`unknown operation: ${testCase.operation}`)
}

export function runRenderContractAssertions(core, vectors, assertions) {
  for (const testCase of vectors.cases) {
    const label = `${testCase.id}: ${testCase.name}`
    if (testCase.expected_error) {
      let thrown = null
      try {
        invoke(core, testCase)
      } catch (error) {
        thrown = error
      }
      assertions.equal(thrown instanceof Error, true, `throws: ${label}`)
      assertions.equal(thrown?.message, testCase.expected_error, `error message: ${label}`)
      continue
    }

    const result = invoke(core, testCase)
    if (Object.hasOwn(testCase.expected ?? {}, 'value')) {
      assertions.deepEqual(result, testCase.expected.value, `value: ${label}`)
    }
    for (const check of testCase.expected?.checks ?? []) {
      const actual = getPath(result, check.path)
      if (Array.isArray(check.value) || (check.value && typeof check.value === 'object')) {
        assertions.deepEqual(actual, check.value, `${check.path}: ${label}`)
      } else {
        assertions.equal(actual, check.value, `${check.path}: ${label}`)
      }
    }
  }
}
