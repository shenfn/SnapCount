import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const feedbackPath = path.join(root, 'supabase/functions/ingest-receipt/expression-feedback.ts')
const migrationPath = path.join(root, 'supabase/migrations/20260725120000_expression_feedback_positive_choices.sql')
const atomicMigrationPath = path.join(root, 'supabase/migrations/20260725123000_expression_feedback_atomic_bundle.sql')
const deleteCleanupMigrationPath = path.join(root, 'supabase/migrations/20260725124000_expression_record_delete_cleanup.sql')
const signalKeyHotfixMigrationPath = path.join(root, 'supabase/migrations/20260726121000_fix_expression_feedback_signal_key_precedence.sql')

test('feedback contract accepts positive and corrective choices and emits scorer profile keys', async () => {
  const source = await readFile(feedbackPath, 'utf8')
  for (const choice of ['helpful', 'good_angle', 'just_what_i_wanted', 'no_change_needed', 'incorrect']) {
    assert.match(source, new RegExp(`"${choice}"`))
  }
  for (const key of ['surface_semantic_weights', 'surface_weights', 'repetition_tolerance']) {
    assert.match(source, new RegExp(key))
  }
  assert.match(source, /if \(!exposureId\)/)
  assert.match(source, /createPersistedRecordExposure\(supabase, userId, recordId\)/)
  assert.match(source, /const feedbackKey = `feedback:\$\{userId\}:\$\{exposure\.id\}`/)
})

test('database constraint is migrated with positive feedback choices', async () => {
  const migration = await readFile(migrationPath, 'utf8')
  assert.match(migration, /drop constraint if exists expression_feedback_events_primary_choice_check/)
  assert.match(migration, /'helpful'/)
  assert.match(migration, /'no_change_needed'/)
})

test('feedback, signals, and snapshot revisions use service-only transactional contracts', async () => {
  const migration = await readFile(atomicMigrationPath, 'utf8')
  assert.match(migration, /unique \(exposure_event_id\)/)
  assert.match(migration, /pg_advisory_xact_lock/)
  assert.match(migration, /replace_expression_feedback_bundle/)
  assert.match(migration, /source_revision bigint/)
  assert.match(migration, /upsert_expression_preference_snapshot_if_newer/)
  assert.match(migration, /expires_at timestamptz not null default \(now\(\) \+ interval '1 hour'\)/)
  assert.match(migration, /shadow_run_id uuid references public\.expression_shadow_runs\(id\) on delete set null/)
  assert.match(migration, /cleanup_expression_delivery_snapshots/)
  assert.match(migration, /v_feedback_key \|\| ':' \|\| \(signal\.value ->> 'issue_code'\)/)
  assert.match(migration, /'decision_id', nullif\(v_exposure\.metadata ->> 'decision_id', ''\)/)
  assert.match(migration, /'selection_probability',[\s\S]*v_exposure\.metadata -> 'selection_probability'/)
  assert.match(migration, /revoke all on function public\.replace_expression_feedback_bundle[\s\S]*from public, anon, authenticated/)
  assert.match(migration, /grant execute on function public\.replace_expression_feedback_bundle[\s\S]*to service_role/)

  const hotfixMigration = await readFile(signalKeyHotfixMigrationPath, 'utf8')
  assert.match(hotfixMigration, /pg_get_functiondef\(v_signature::oid\)/)
  assert.match(hotfixMigration, /execute replace\(v_definition, v_buggy, v_fixed\)/)
  assert.match(hotfixMigration, /v_feedback_key \|\| ':' \|\| \(signal\.value ->> 'issue_code'\)/)
})

test('record deletion purges expression artifacts and invalidates preference snapshots', async () => {
  const migration = await readFile(deleteCleanupMigrationPath, 'utf8')
  assert.match(migration, /purge_expression_artifacts_after_record_delete/)
  assert.match(migration, /expression_exposure_source_records/)
  assert.doesNotMatch(migration, /\bposition\s*\(/i)
  assert.match(migration, /delete from public\.expression_preference_signals/)
  assert.match(migration, /delete from public\.expression_feedback_events/)
  assert.match(migration, /delete from public\.expression_exposure_events/)
  assert.match(migration, /delete from public\.expression_delivery_snapshots/)
  assert.match(migration, /delete from public\.expression_shadow_runs/)
  for (const table of ['transactions', 'income_records', 'data_records']) {
    assert.match(migration, new RegExp(`after delete on public\\.${table}`))
  }
  assert.match(migration, /expression_preference_revisions\.revision \+ 1/)

  const accountDelete = migration.match(
    /create or replace function public\.delete_user_account_data\(p_user_id uuid\)[\s\S]*?\$\$;/,
  )?.[0] ?? ''
  assert.ok(accountDelete, 'delete_user_account_data must be present')
  for (const table of [
    'expression_exposure_source_records',
    'expression_delivery_snapshots',
    'expression_preference_snapshots',
    'expression_preference_revisions',
    'expression_shadow_runs',
  ]) {
    assert.match(accountDelete, new RegExp(`delete from public\\.${table}`))
  }
})
