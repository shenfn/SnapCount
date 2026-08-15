export function runRecurrenceAssertions(core, vectors, assertEqual, assertDeepEqual) {
  for (const testCase of vectors.cases) {
    const operation = core[testCase.operation]
    assertEqual(typeof operation, 'function', `operation: ${testCase.name}`)
    const result = operation(...testCase.args)
    assertEqual(result.length, testCase.expected.length, `length: ${testCase.name}`)
    if (result.length === 0) continue
    const value = result[0].claim.structured_value
    const expected = testCase.expected
    for (const field of ['previous_record_id', 'elapsed_minutes', 'elapsed_calendar_days', 'time_precision']) {
      if (Object.hasOwn(expected, field)) assertEqual(value[field], expected[field], `${field}: ${testCase.name}`)
    }
    if (Object.hasOwn(expected, 'candidate_id')) assertEqual(result[0].candidate_id, expected.candidate_id, `candidate id: ${testCase.name}`)
    if (Object.hasOwn(expected, 'text_contains')) assertEqual(result[0].claim.canonical_text.includes(expected.text_contains), true, `text: ${testCase.name}`)
    if (Object.hasOwn(expected, 'elapsed_duration')) assertDeepEqual(value.elapsed_duration, expected.elapsed_duration, `duration: ${testCase.name}`)
  }
}
