function assertIncludedReasons(actual, expected, message, assertEqual) {
  for (const reason of expected) {
    assertEqual(actual.includes(reason), true, `${message}: ${reason}`)
  }
}

export function runEligibilityAssertions(eligibility, vectors, assertEqual, assertDeepEqual) {
  const evaluatedByName = new Map()

  for (const testCase of vectors.eligibility_cases) {
    const result = eligibility.evaluateCandidateEligibility(testCase.candidate, testCase.options)
    evaluatedByName.set(testCase.name, result)

    assertEqual(result.eligibility.eligible, testCase.expected.claim_eligible, `claim eligible: ${testCase.name}`)
    assertDeepEqual(result.eligibility.blocked_reasons, testCase.expected.claim_blocked_reasons, `claim reasons: ${testCase.name}`)
    if (Object.hasOwn(testCase.expected, 'materiality')) {
      assertDeepEqual(result.eligibility.materiality, testCase.expected.materiality, `materiality: ${testCase.name}`)
    }

    for (const [surface, expected] of Object.entries(testCase.expected.surfaces)) {
      const actual = result.eligibility.surface_eligibility[surface]
      assertEqual(actual.eligible, expected.eligible, `surface eligible: ${testCase.name}/${surface}`)
      assertIncludedReasons(actual.blocked_reasons, expected.blocked_reasons, `surface reason: ${testCase.name}/${surface}`, assertEqual)
    }
  }

  const summaryCandidates = vectors.summary_case.candidate_names.map(name => evaluatedByName.get(name))
  assertDeepEqual(
    eligibility.summarizeEligibility(summaryCandidates),
    vectors.summary_case.expected,
    'eligibility summary',
  )
}
