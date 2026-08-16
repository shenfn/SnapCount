import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const migrationPath = 'supabase/migrations/20260816210000_wallet_snapshot_atomic_contract.sql'
const migration = await readFile(migrationPath, 'utf8')
const workflow = await readFile('.github/workflows/release-validation.yml', 'utf8')

assert.match(migration, /create or replace function public\.apply_wallet_snapshot\(/i)
assert.match(migration, /returns jsonb/i)
assert.match(migration, /auth\.uid\(\)/i)
assert.match(migration, /for update/i)
assert.match(migration, /wallet_snapshot_not_found/i)
assert.match(migration, /snapshot_link_conflict/i)
assert.match(migration, /account_kind_mismatch/i)
assert.match(migration, /needs_confirmation/i)
assert.match(migration, /balance_scope/i)
assert.match(migration, /evidence_record_id/i)
assert.match(migration, /snapshot_initialization/i)
assert.match(migration, /set_repayment_cycle_paid_amount/i)
assert.match(migration, /revoke all on function public\.apply_wallet_snapshot/i)

const migrationCommand = `-f ${migrationPath}`
assert.equal(
  workflow.split(migrationCommand).length - 1,
  2,
  'release validation must execute the wallet snapshot migration twice',
)
assert.match(workflow, /test-wallet-snapshot-contract-fixture\.sql/i)
assert.match(workflow, /test-wallet-snapshot-contract\.sql/i)

console.log('Wallet snapshot migration contracts validated.')
