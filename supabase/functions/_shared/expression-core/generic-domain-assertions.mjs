function getPath(value, path) {
  return path.split('.').reduce((current, key) => current?.[key], value)
}

function invoke(core, testCase) {
  const args = testCase.args ?? {}
  if (testCase.operation === 'prepareDomainRecords') {
    return core.prepareDomainRecords(args.domainKey, args.records ?? [], args.currentRecordId)
  }
  if (testCase.operation === 'generateIncomeCandidates') {
    return core.generateIncomeCandidates(args.records ?? [], args.currentRecordId)
  }
  if (testCase.operation === 'generateBuiltinDomainCandidates') {
    return core.generateBuiltinDomainCandidates(
      args.domainKey,
      args.records ?? [],
      args.currentRecordId,
      args.domainProfile ?? {},
    )
  }
  throw new Error(`unknown operation: ${testCase.operation}`)
}

function semanticKeys(candidates) {
  return candidates.map(candidate => candidate?.claim?.semantic_key)
}

function findCandidate(candidates, semanticKey) {
  return candidates.find(candidate => candidate?.claim?.semantic_key === semanticKey)
}

export function runGenericDomainAssertions(core, vectors, assertions) {
  for (const testCase of vectors.cases) {
    const result = invoke(core, testCase)
    const expected = testCase.expected ?? {}
    const label = `${testCase.id}: ${testCase.name}`

    if (expected.record_ids) {
      assertions.deepEqual(result.map(record => record.id), expected.record_ids, `record ids: ${label}`)
      continue
    }

    const keys = semanticKeys(result)
    if (expected.candidate_keys) assertions.deepEqual(keys, expected.candidate_keys, `candidate keys: ${label}`)
    for (const key of expected.candidate_keys_include ?? []) {
      assertions.equal(keys.includes(key), true, `includes ${key}: ${label}`)
    }
    for (const key of expected.candidate_keys_exclude ?? []) {
      assertions.equal(keys.includes(key), false, `excludes ${key}: ${label}`)
    }
    for (const check of expected.checks ?? []) {
      const candidate = findCandidate(result, check.semantic_key)
      assertions.equal(Boolean(candidate), true, `candidate ${check.semantic_key}: ${label}`)
      const actual = getPath(candidate, check.path)
      if (Array.isArray(check.value) || (check.value && typeof check.value === 'object')) {
        assertions.deepEqual(actual, check.value, `${check.path}: ${label}`)
      } else {
        assertions.equal(actual, check.value, `${check.path}: ${label}`)
      }
    }
    for (const check of expected.text_matches ?? []) {
      const candidate = findCandidate(result, check.semantic_key)
      assertions.equal(Boolean(candidate), true, `candidate ${check.semantic_key}: ${label}`)
      assertions.match(candidate.claim.canonical_text, check.pattern, `text matches: ${label}`)
    }
    for (const check of expected.text_excludes ?? []) {
      const candidate = findCandidate(result, check.semantic_key)
      assertions.equal(Boolean(candidate), true, `candidate ${check.semantic_key}: ${label}`)
      assertions.doesNotMatch(candidate.claim.canonical_text, check.pattern, `text excludes: ${label}`)
    }
  }
}
