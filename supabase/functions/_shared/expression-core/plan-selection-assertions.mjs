function selectedShape(plan) {
  return plan.selected.map(({ candidate_id, semantic_key, selection_mode }) => ({
    candidate_id,
    semantic_key,
    selection_mode,
  }))
}

function excludedReasons(plan) {
  return Object.fromEntries(plan.excluded.map(item => [item.candidate_id, item.reason]))
}

export function runPlanSelectionAssertions(planSelection, vectors, assertEqual, assertDeepEqual, assertThrows) {
  for (const testCase of vectors.surface_cases) {
    const plan = planSelection.buildSurfacePlan(testCase.candidates, testCase.surface)
    assertDeepEqual(selectedShape(plan), testCase.expected.selected, `selected: ${testCase.name}`)
    assertEqual(plan.fallback_used, testCase.expected.fallback_used, `fallback: ${testCase.name}`)
    assertEqual(plan.silent, testCase.expected.silent, `silent: ${testCase.name}`)
    assertDeepEqual(excludedReasons(plan), testCase.expected.excluded_reasons, `excluded: ${testCase.name}`)
  }

  const expressionPlans = planSelection.buildExpressionPlans(vectors.expression_case.candidates)
  const summary = planSelection.summarizePlans(expressionPlans)
  assertDeepEqual(Object.keys(expressionPlans), vectors.expression_case.expected_surfaces, 'expression surfaces')
  for (const surface of vectors.expression_case.expected_surfaces) {
    assertEqual(summary[surface].selected_count, vectors.expression_case.expected_selected_count, `summary count: ${surface}`)
    assertEqual(summary[surface].selected[0].selection_mode, vectors.expression_case.expected_selection_mode, `summary mode: ${surface}`)
  }

  assertThrows(
    () => planSelection.buildSurfacePlan([], vectors.unknown_surface),
    'Unknown or invalid surface',
    'unknown surface',
  )
}
