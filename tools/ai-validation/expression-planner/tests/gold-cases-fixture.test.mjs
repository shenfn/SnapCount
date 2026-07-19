import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const fixtureUrl = new URL('../fixtures/gold-cases.public.v0.1.json', import.meta.url)
const fixtureText = await readFile(fixtureUrl, 'utf8')
const fixture = JSON.parse(fixtureText)

test('public gold cases contain seven synthetic regression scenarios', () => {
  assert.equal(fixture.schema_version, 'expression-planner-public-gold-cases-v0.1')
  assert.equal(fixture.privacy.classification, 'public_synthetic')
  assert.equal(fixture.privacy.contains_real_user_data, false)
  assert.equal(fixture.cases.length, 7)
})

test('every public gold case defines an input and expected layer', () => {
  for (const item of fixture.cases) {
    assert.ok(item.case_id.startsWith('synthetic-'))
    assert.ok(item.source_case.startsWith('gold-'))
    assert.equal(typeof item.input, 'object')
    assert.ok(['fact', 'candidate', 'selection'].includes(item.expected.root_layer))
  }
})

test('public gold cases do not contain database identifiers or private fields', () => {
  assert.doesNotMatch(fixtureText, /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i)
  for (const field of ['user_id', 'record_id', 'ai_log_id', 'notification_text']) {
    assert.equal(fixtureText.includes(`"${field}"`), false, field)
  }
})

test('gold cases keep fact, candidate, and selection failures separate', () => {
  const layers = new Set(fixture.cases.map(item => item.expected.root_layer))
  assert.deepEqual([...layers].sort(), ['candidate', 'fact', 'selection'])
})
