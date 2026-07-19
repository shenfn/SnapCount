import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const shadowModulePath = path.join(root, 'supabase/functions/ingest-receipt/expression-shadow.ts')
const ingestPath = path.join(root, 'supabase/functions/ingest-receipt/index.ts')
const sqlPath = path.resolve(here, '../sql/070_expression_shadow_runs.draft.sql')

test('shadow collector defaults off and never changes user output', async () => {
  const source = await readFile(shadowModulePath, 'utf8')
  assert.match(source, /value \?\? "off"/)
  assert.match(source, /if \(mode === "off"\) return/)
  assert.match(source, /changes_user_output: false/)
  assert.match(source, /waitUntil/)
  assert.match(source, /\.catch\(\(error\) =>/)
})

test('shadow collector distinguishes visible notification from persisted AI feedback', async () => {
  const source = await readFile(shadowModulePath, 'utf8')
  assert.match(source, /return \["notification"\]/)
  assert.match(source, /persisted_only_field_paths/)
  assert.match(source, /normalizeString\(data\?\.domain_key\)/)
})

test('all traced success responses use the shadow wrapper', async () => {
  const source = await readFile(ingestPath, 'utf8')
  const wrapped = source.match(/return respondWithExpressionShadow\(withTraceMeta/g) ?? []
  const bypassed = source.match(/return respondShortcut\(withTraceMeta/g) ?? []
  assert.equal(wrapped.length, 12)
  assert.equal(bypassed.length, 0)
  assert.match(source, /scheduleExpressionShadowCapture/)
})

test('shadow SQL is service-role written, append-only for clients, and output-neutral', async () => {
  const sql = await readFile(sqlPath, 'utf8')
  assert.match(sql, /event_key text not null unique/)
  assert.match(sql, /changes_user_output boolean not null default false check \(changes_user_output = false\)/)
  assert.match(sql, /persisted_only_field_paths text\[\]/)
  assert.match(sql, /revoke insert, update, delete/)
  assert.match(sql, /grant all on table public\.expression_shadow_runs to service_role/)
})
test('shadow capture automatically invokes the shared deterministic planner', async () => {
  const source = await readFile(shadowModulePath, 'utf8')
  assert.match(source, /buildExpressionShadowPlan/)
  assert.match(source, /processExpenseShadow/)
  assert.match(source, /shared_expression_planner_completed/)
  assert.match(source, /proposed_score_summary: scoreSummary/)
  assert.match(source, /processing_error: null/)
})
