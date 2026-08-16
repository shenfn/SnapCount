import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

import {
  buildShanghaiOccurredAt,
  resolveFinanceOccurrence,
} from '../src/utils/financeOccurrence.js'
import { mapTransaction } from '../src/utils/helpers.js'

const migration = await readFile(
  'supabase/migrations/20260808120000_finance_occurred_at_contract.sql',
  'utf8',
)
const canonicalExpenseStart = migration.indexOf(
  'create or replace function public.save_transaction_with_account(',
)
const legacyExpenseStart = migration.indexOf(
  'create or replace function public.save_transaction_with_account(',
  canonicalExpenseStart + 1,
)
const canonicalExpense = migration.slice(canonicalExpenseStart, legacyExpenseStart)
const accountEntryStart = migration.indexOf(
  'create or replace function public.create_account_entry_for_record(',
)
const canonicalExpenseEnd = migration.indexOf(
  'create or replace function public.save_income_with_account(',
  canonicalExpenseStart,
)
const accountEntryFunction = migration.slice(accountEntryStart, canonicalExpenseStart)
const storeSource = await readFile('src/composables/useStore.js', 'utf8')
const stagingArchiveFeatureSource = await readFile(
  'src/features/staging/createStagingArchiveFeature.js',
  'utf8',
)
const stagingRepositorySource = await readFile('src/repositories/stagingRepository.js', 'utf8')
const recordRepositorySource = await readFile('src/repositories/recordRepository.js', 'utf8')
const helpersSource = await readFile('src/utils/helpers.js', 'utf8')
const ingestSource = await readFile(
  'supabase/functions/ingest-receipt/index.ts',
  'utf8',
)
const shadowSource = await readFile(
  'supabase/functions/ingest-receipt/expression-shadow.ts',
  'utf8',
)

assert.notEqual(canonicalExpenseStart, -1, 'canonical expense RPC must exist')
assert.notEqual(legacyExpenseStart, -1, 'legacy expense RPC must exist')
assert.notEqual(canonicalExpenseEnd, -1, 'canonical expense RPC must have a bounded body')
assert.notEqual(accountEntryStart, -1, 'account entry helper must exist')

assert.match(
  migration,
  /alter table public\.transactions\s+add column if not exists occurred_at timestamptz/i,
)
assert.match(
  migration,
  /alter table public\.income_records\s+add column if not exists occurred_at timestamptz/i,
)
assert.match(migration, /p_occurred_at timestamptz default null/i)
assert.match(migration, /Compatibility shell for the original 16-argument expense RPC/i)
assert.match(migration, /Compatibility shell for the original 11-argument income RPC/i)
assert.doesNotMatch(migration, /drop function if exists public\.save_transaction_with_account/i)
assert.doesNotMatch(migration, /drop function if exists public\.save_income_with_account/i)
assert.equal(
  (migration.match(/create or replace function public\.save_transaction_with_account\(/gi) || []).length,
  2,
  'expense RPC must expose one canonical overload and one legacy compatibility shell',
)
assert.equal(
  (migration.match(/create or replace function public\.save_income_with_account\(/gi) || []).length,
  2,
  'income RPC must expose one canonical overload and one legacy compatibility shell',
)
assert.match(migration, /timezone\('Asia\/Shanghai'/i)
assert.match(migration, /make_timestamptz\([\s\S]*'Asia\/Shanghai'/i)
assert.doesNotMatch(migration, /localtime\s*\(/i)
assert.match(
  migration,
  /finance_explicit_occurred_at_from_payload\(extracted_json\)/i,
  'staging backfill must parse explicit payload evidence instead of trusting the storage column',
)
assert.match(migration, /transaction\.staging_record_id\s*=\s*evidence\.id/i)
assert.match(migration, /target_table\s*=\s*'transactions'/i)
assert.match(migration, /target_table\s*=\s*'income_records'/i)
assert.match(migration, /finance_explicit_occurred_at_from_payload\(ai_response\)/i)
assert.match(migration, /source_table\s*=\s*'income_records'/i)
assert.match(migration, /entry\.user_id\s*=\s*transaction\.user_id/i)
assert.match(migration, /entry\.user_id\s*=\s*income\.user_id/i)
assert.doesNotMatch(
  migration,
  /set occurred_at\s*=\s*public\.finance_occurred_at_from_shanghai_wall_time\([\s\S]{0,200}transaction_time/i,
  'legacy transaction_time alone must not be treated as authoritative evidence',
)
assert.doesNotMatch(
  canonicalExpense,
  /finance_occurred_at_from_shanghai_wall_time\(/i,
  'canonical expense RPC must not derive a canonical instant from legacy date/time',
)
assert.doesNotMatch(
  accountEntryFunction,
  /coalesce\(\s*p_occurred_at\s*,\s*now\(\)\s*\)/i,
  'account entry helper must preserve an unknown occurrence as null',
)
assert.doesNotMatch(
  accountEntryFunction,
  /p_occurred_at\s+timestamptz\s+default\s+now\(\)/i,
  'account entry helper must not default an unknown occurrence to the ledger write time',
)
assert.doesNotMatch(
  migration,
  /coalesce\(\s*v_row\.occurred_at,\s*public\.finance_occurred_at_from_shanghai_wall_time\([\s\S]{0,100}'12:00:00'/i,
  'date-only income must not invent a noon occurrence instant',
)
assert.match(
  migration,
  /alter table public\.account_entries\s+alter column occurred_at drop not null/i,
  'source-backed ledger entries must represent unknown occurrence as null',
)
assert.match(
  migration,
  /p_source_table,[\s\S]{0,300}p_source_id,[\s\S]{0,300}p_occurred_at,[\s\S]{0,100}p_note/i,
  'account entry helper must persist the supplied canonical value without a now fallback',
)
assert.match(
  migration,
  /coalesce\(p_source, 'manual'\) = 'manual'[\s\S]{0,180}p_transaction_date is not null[\s\S]{0,180}p_transaction_time is not null/i,
  'legacy expense shell must convert only explicit manual date and time evidence',
)
assert.match(
  migration,
  /revoke all on function public\.save_transaction_with_account\(uuid, numeric, text, text, text, text, date, time, text, boolean, text, text, text, text, text, uuid\) from public, anon/i,
  'legacy expense RPC must explicitly revoke PUBLIC and anon execution',
)
assert.match(
  migration,
  /p_occurred_at\s*=>\s*p_occurred_at/i,
  'archive RPC must pass the explicit occurrence timestamp into finance save RPCs',
)
assert.match(
  migration,
  /p_occurred_at\s*=>\s*v_pending\.occurred_at/i,
  'pending confirmation must preserve the source occurrence timestamp',
)
assert.doesNotMatch(
  migration,
  /coalesce\(\s*p_occurred_at\s*,\s*now\(\)\s*\)/i,
  'archive and source-backed account paths must not replace unknown occurrence with write time',
)
assert.match(
  migration,
  /insert into public\.data_records[\s\S]{0,900}\bp_occurred_at\s*,/i,
  'generic staging archive must persist the explicit occurrence value, including null',
)

const utcOccurrence = resolveFinanceOccurrence({
  occurredAt: '2026-08-07T22:41:00Z',
})
assert.deepEqual(utcOccurrence, {
  occurredAt: '2026-08-07T22:41:00.000Z',
  date: '2026-08-08',
  time: '06:41:00',
  hasExactTime: true,
})

assert.deepEqual(
  resolveFinanceOccurrence({ occurredAt: '2026-08-08T06:41:00+08:00' }),
  utcOccurrence,
)

const wallOccurrence = resolveFinanceOccurrence({
  date: '2026-08-08',
  time: '06:41',
})
assert.equal(wallOccurrence.occurredAt, '2026-08-07T22:41:00.000Z')
assert.equal(wallOccurrence.date, '2026-08-08')
assert.equal(wallOccurrence.time, '06:41:00')
assert.equal(wallOccurrence.hasExactTime, true)

const dateOnly = resolveFinanceOccurrence({
  occurredAt: '2026-08-08',
  fallbackInstant: '2026-08-08T07:00:00+08:00',
})
assert.deepEqual(dateOnly, {
  occurredAt: null,
  date: '2026-08-08',
  time: null,
  hasExactTime: false,
})

const uploadFallback = resolveFinanceOccurrence({
  fallbackInstant: '2026-08-07T22:41:00Z',
})
assert.deepEqual(uploadFallback, {
  occurredAt: null,
  date: '2026-08-08',
  time: null,
  hasExactTime: false,
})

assert.equal(
  buildShanghaiOccurredAt('2026-08-08', '06:41'),
  '2026-08-07T22:41:00.000Z',
)
assert.equal(buildShanghaiOccurredAt('2026-08-08', ''), null)

const legacyAiTransaction = mapTransaction({
  id: 'legacy-ai',
  merchant_name: '星之柠',
  amount: 6.8,
  transaction_date: '2026-08-08',
  transaction_time: '02:41:00',
  source: 'ai_scan',
})
assert.equal(
  legacyAiTransaction.time,
  '',
  'AI legacy transaction_time must not be presented as a trusted local occurrence time',
)

const canonicalAiTransaction = mapTransaction({
  id: 'canonical-ai',
  merchant_name: '星之柠',
  amount: 6.8,
  occurred_at: '2026-08-07T22:41:00Z',
  transaction_date: '2026-08-08',
  transaction_time: '02:41:00',
  source: 'ai_scan',
})
assert.equal(canonicalAiTransaction.dateRaw, '2026-08-08')
assert.equal(canonicalAiTransaction.time, '06:41')

assert.match(
  storeSource,
  /recordTime:\s*financeOccurrence\.time/,
  'staging archive facade must pass the recognized wall time to the feature',
)
assert.match(
  storeSource,
  /occurredAt:\s*financeOccurrence\.occurredAt/,
  'staging archive facade must pass the exact occurrence timestamp to the feature',
)
assert.match(
  stagingArchiveFeatureSource,
  /recordTime:\s*options\.recordTime[\s\S]{0,400}occurredAt:\s*options\.occurredAt/,
  'staging archive feature must preserve explicit occurrence fields',
)
assert.match(
  stagingRepositorySource,
  /p_record_time:\s*input\.recordTime[\s\S]{0,200}p_occurred_at:\s*input\.occurredAt/,
  'staging repository must map occurrence fields to the atomic RPC',
)
assert.match(helpersSource, /occurredAt:\s*t\.occurred_at\s*\|\|\s*null/)
assert.match(recordRepositorySource, /occurredAt:\s*row\.occurred_at\s*\|\|\s*null/)
assert.match(
  storeSource,
  /async function bindRecordToAccount[\s\S]*p_occurred_at:\s*record\.occurredAt\s*\|\|\s*null/,
  'account binding must preserve the record canonical occurrence timestamp',
)
assert.match(
  ingestSource,
  /async function createAutoAccountEntry[\s\S]{0,1200}occurred_at:\s*payload\.occurredAt/,
  'automatic account binding must preserve unknown source occurrence as null',
)
assert.doesNotMatch(
  ingestSource,
  /async function createAutoAccountEntry[\s\S]{0,1200}payload\.occurredAt\s*\?\?\s*new Date\(\)\.toISOString\(\)/,
  'automatic account binding must not substitute its write timestamp',
)
assert.match(
  ingestSource,
  /select\("id,perceptual_hash,amount,merchant_name,platform,payment_method,occurred_at,transaction_date,transaction_time,created_at"\)/,
  'financial duplicate lookup must fetch the canonical transaction occurrence',
)
assert.match(
  ingestSource,
  /occurredAt:\s*row\.occurred_at,[\s\S]{0,120}timePrecision:\s*row\.occurred_at\s*\?\s*"datetime"/,
  'financial duplicate lookup must not reconstruct an instant from legacy transaction_time',
)
assert.doesNotMatch(
  shadowSource,
  /processExpenseShadow\([\s\S]{0,3000}occurredAt:\s*input\.occurredAt\s*\?\?\s*new Date\(\)\.toISOString\(\)/,
  'Planner current-record context must not use the shadow processing timestamp as event time',
)

console.log('finance occurred_at contract: ok')
