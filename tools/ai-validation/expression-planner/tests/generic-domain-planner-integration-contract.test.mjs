import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const planner = await readFile(
  path.join(root, 'supabase/functions/ingest-receipt/expression-shadow-planner.ts'),
  'utf8',
)

test('CORE-075 Edge planner owns generic domain rules', () => {
  assert.match(planner, /from ["']\.\.\/_shared\/expression-core\/generic-domain-candidates\.mjs["']/)
  assert.match(planner, /prepareDomainRecords\(input\.domainKey, input\.records, input\.currentRecordId\)/)
  assert.match(planner, /generateIncomeCandidates\(planningRecords, input\.currentRecordId\)/)
  assert.match(planner, /generateBuiltinDomainCandidates\(input\.domainKey, planningRecords, input\.currentRecordId, input\.domainProfile \?\? \{\}\)/)
  assert.doesNotMatch(planner, /tools\/ai-validation\/expression-planner\/lib\/generic-domain-candidates\.mjs/)
})
