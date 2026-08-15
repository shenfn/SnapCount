import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const planner = await readFile(path.join(root, 'supabase/functions/ingest-receipt/expression-shadow-planner.ts'), 'utf8')

test('CORE-062 Edge planner owns entity rules and public alias config', () => {
  assert.match(planner, /from ["']\.\.\/_shared\/expression-core\/entity-normalizer\.mjs["']/)
  assert.match(planner, /from ["']\.\.\/_shared\/expression-config\/entity-aliases\.public\.v0\.1\.json["']/)
  assert.match(planner, /compileMerchantAliases\(merchantAliasConfig\)/)
  assert.doesNotMatch(planner, /tools\/ai-validation\/expression-planner\/(?:lib\/entity-normalizer|configs\/entity-aliases\.public\.v0\.1\.json)/)
})
