export function runFactCandidateAssertions(core, vectors, assertEqual, assertDeepEqual) {
  for (const testCase of vectors.cases) {
    const operation = core[testCase.operation]
    assertEqual(typeof operation, 'function', `operation: ${testCase.name}`)
    const result = operation(...testCase.args)
    const expected = testCase.expected
    assertEqual(result.length, expected.length, `length: ${testCase.name}`)
    if (expected.length === 0) continue
    const first = result[0]
    if (Object.hasOwn(expected, 'first_value')) assertDeepEqual(first.claim.structured_value, expected.first_value, `first value: ${testCase.name}`)
    if (Object.hasOwn(expected, 'second_max_amount')) assertEqual(result[1].claim.structured_value.max_amount, expected.second_max_amount, `max amount: ${testCase.name}`)
    if (Object.hasOwn(expected, 'first_count')) assertEqual(first.claim.structured_value.count, expected.first_count, `first count: ${testCase.name}`)
    if (Object.hasOwn(expected, 'semantic_key')) assertEqual(first.claim.semantic_key, expected.semantic_key, `semantic key: ${testCase.name}`)
    if (Object.hasOwn(expected, 'fact_status')) assertEqual(first.claim.structured_value.fact_status, expected.fact_status, `fact status: ${testCase.name}`)
    if (Object.hasOwn(expected, 'category_needs_review')) assertEqual(first.claim.structured_value.category_needs_review, expected.category_needs_review, `review flag: ${testCase.name}`)
    if (Object.hasOwn(expected, 'first_seen_kind')) assertEqual(first.claim.structured_value.first_seen_kind, expected.first_seen_kind, `first seen kind: ${testCase.name}`)
    if (Object.hasOwn(expected, 'exposure_key')) assertEqual(first.selection_hints.exposure_key, expected.exposure_key, `exposure key: ${testCase.name}`)
    for (const text of expected.text_contains ?? []) assertEqual(first.claim.canonical_text.includes(text), true, `text contains: ${testCase.name}/${text}`)
    if (Object.hasOwn(expected, 'text_not_contains')) assertEqual(first.claim.canonical_text.includes(expected.text_not_contains), false, `text exclusion: ${testCase.name}`)
    if (Object.hasOwn(expected, 'allowed_surfaces')) assertDeepEqual(first.selection_hints.allowed_surfaces, expected.allowed_surfaces, `allowed surfaces: ${testCase.name}`)
  }
}
