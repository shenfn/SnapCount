function assertReasons(actual, expected, message, assertEqual) {
  for (const reason of expected) assertEqual(actual.includes(reason), true, `${message}: ${reason}`)
}

export function runScoringAssertions(scoring, vectors, assertEqual) {
  for (const testCase of vectors.score_cases) {
    const result = scoring.scoreCandidate(testCase.candidate, testCase.options)
    const expected = testCase.expected
    assertEqual(result.scoring.scoring_version, expected.scoring_version ?? 'deterministic-score-v0.2', `version: ${testCase.name}`)
    for (const key of ['importance', 'relevance', 'confidence', 'novelty', 'user_preference']) {
      if (Object.hasOwn(expected, key)) assertEqual(result.scoring.components[key], expected[key], `${key}: ${testCase.name}`)
    }
    if (Object.hasOwn(expected, 'base_exposure_count')) assertEqual(result.scoring.exposure.count, expected.base_exposure_count, `base exposure: ${testCase.name}`)
    for (const [surface, surfaceExpected] of Object.entries(expected)) {
      if (!Object.hasOwn(scoring.SURFACE_THRESHOLDS, surface)) continue
      const actual = result.scoring.surfaces[surface]
      for (const key of ['score', 'passes_threshold', 'novelty']) {
        if (Object.hasOwn(surfaceExpected, key)) assertEqual(actual[key], surfaceExpected[key], `${surface}.${key}: ${testCase.name}`)
      }
      if (Object.hasOwn(surfaceExpected, 'blocked_reasons')) assertReasons(actual.blocked_reasons, surfaceExpected.blocked_reasons, `${surface}.blocked_reasons: ${testCase.name}`, assertEqual)
      if (Object.hasOwn(expected, `${surface}_exposure_count`)) assertEqual(result.scoring.exposure_by_surface[surface].count, expected[`${surface}_exposure_count`], `${surface} exposure: ${testCase.name}`)
      if (Object.hasOwn(expected, `${surface}_surface_novelty`)) assertEqual(actual.novelty, expected[`${surface}_surface_novelty`], `${surface} novelty: ${testCase.name}`)
    }
  }

  const scored = scoring.scoreCandidates(vectors.summary_case.candidates)
  const summary = scoring.summarizeScores(scored)
  for (const [surface, expected] of Object.entries(vectors.summary_case.expected)) {
    assertEqual(summary[surface].ranking[0].candidate_id, expected.ranking_first, `ranking: ${surface}`)
    assertEqual(summary[surface].passing_count, expected.passing_count, `passing count: ${surface}`)
  }
}
