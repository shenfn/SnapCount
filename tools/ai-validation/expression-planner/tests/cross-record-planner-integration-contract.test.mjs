import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const planner = await readFile(path.join(root, 'supabase/functions/ingest-receipt/expression-shadow-planner.ts'), 'utf8')
const shadow = await readFile(path.join(root, 'supabase/functions/ingest-receipt/expression-shadow.ts'), 'utf8')
const delivery = await readFile(path.join(root, 'supabase/functions/ingest-receipt/expression-delivery.ts'), 'utf8')

test('EXP-007 planner and both Edge paths receive cross-domain source records', () => {
  assert.match(planner, /generateCrossRecordRelationshipCandidates/)
  assert.match(planner, /from ["']\.\.\/_shared\/expression-core\/cross-record-relationships\.mjs["']/)
  assert.doesNotMatch(planner, /tools\/ai-validation\/expression-planner\/lib\/cross-record-relationships\.mjs/)
  assert.match(planner, /relatedRecords: input\.relatedRecords \?\? \[\]/)
  assert.match(planner, /source_table: "transactions" \| "income_records" \| "data_records"/)
  assert.match(shadow, /loadCrossDomainRecords/)
  assert.match(shadow, /relatedRecords[\s\S]{0,80}\.\.\.personalization/)
  assert.match(delivery, /loadCrossDomainRecords/)
  assert.match(delivery, /relatedRecords[\s\S]{0,120}\.\.\.personalization/)
})
