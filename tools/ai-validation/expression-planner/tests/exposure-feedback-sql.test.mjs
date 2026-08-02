import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const sqlPath = path.resolve(here, '../sql/069_expression_feedback_events.draft.sql')

test('feedback SQL requires a real exposure and service-role writes', async () => {
  const sql = await readFile(sqlPath, 'utf8')
  assert.match(sql, /exposure_event_id uuid not null references public\.expression_exposure_events/)
  assert.match(sql, /primary_choice in \('incorrect', 'not_helpful', 'repetitive', 'style_dislike', 'other'\)/)
  assert.match(sql, /revoke insert, update, delete/)
  assert.match(sql, /grant all on table public\.expression_feedback_events to service_role/)
  assert.doesNotMatch(sql, /legacy_unresolved/)
})
