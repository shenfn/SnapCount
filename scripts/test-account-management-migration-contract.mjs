import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const migrationPath = 'supabase/migrations/20260816160000_account_management_atomic_contract.sql'
const migration = await readFile(migrationPath, 'utf8')
const workflow = await readFile('.github/workflows/release-validation.yml', 'utf8')

assert.match(migration, /create or replace function public\.normalize_account_management_write\(\)/i)
assert.match(migration, /create trigger tr_normalize_account_management_write/i)
assert.match(migration, /pg_advisory_xact_lock/i)
assert.match(migration, /create unique index if not exists uq_accounts_active_default_expense/i)
assert.match(migration, /create unique index if not exists uq_accounts_active_default_income/i)
assert.match(migration, /constraint accounts_archived_not_default/i)
assert.match(migration, /create or replace function public\.save_account\(/i)
assert.match(migration, /create or replace function public\.set_account_archived\(/i)
assert.match(migration, /account_type_transition_blocked/i)
assert.match(migration, /auth\.uid\(\)/i)
assert.match(migration, /security definer/i)
assert.match(migration, /revoke all on function public\.save_account/i)
assert.match(migration, /revoke all on function public\.set_account_archived/i)

const migrationCommand = `-f ${migrationPath}`
assert.equal(
  workflow.split(migrationCommand).length - 1,
  2,
  'release validation must execute the account management migration twice',
)
assert.match(workflow, /test-account-management-contract-fixture\.sql/i)
assert.match(workflow, /test-account-management-contract\.sql/i)

console.log('Account management migration contracts validated.')
