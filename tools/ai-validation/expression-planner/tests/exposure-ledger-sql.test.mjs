import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const sqlUrl = new URL('../sql/068_expression_exposure_events.draft.sql', import.meta.url)

test('draft ledger is append-only for authenticated clients', async () => {
  const sql = await readFile(sqlUrl, 'utf8')
  assert.match(sql, /for select\s+to authenticated/i)
  assert.match(sql, /revoke insert, update, delete/i)
  assert.doesNotMatch(sql, /for insert\s+to authenticated/i)
  assert.doesNotMatch(sql, /for update\s+to authenticated/i)
})

test('draft ledger rejects simulation rows', async () => {
  const sql = await readFile(sqlUrl, 'utf8')
  assert.match(sql, /simulation_only boolean not null default false check \(simulation_only = false\)/i)
})

test('draft ledger indexes novelty lookup dimensions', async () => {
  const sql = await readFile(sqlUrl, 'utf8')
  assert.match(sql, /\(user_id, semantic_key, occurred_at desc\)/i)
  assert.match(sql, /\(user_id, surface, occurred_at desc\)/i)
})

test('draft ledger rejects local dry-run preview sources', async () => {
  const sql = await readFile(sqlUrl, 'utf8')
  assert.match(sql, /metadata ->> 'source'.*local_dry_run_preview/i)
})
