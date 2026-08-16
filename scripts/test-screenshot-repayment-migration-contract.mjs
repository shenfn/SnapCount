import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const migrationPath = 'supabase/migrations/20260816190000_screenshot_repayment_atomic_contract.sql'
const migration = await readFile(migrationPath, 'utf8')
const workflow = await readFile('.github/workflows/release-validation.yml', 'utf8')

assert.match(migration, /create or replace function public\.confirm_staging_repayment\(/i)
assert.match(migration, /repayment_cycle/i)
assert.match(migration, /resolved_domain_key\s*=\s*'wallet'/i)
assert.match(migration, /resolved_action\s*=\s*'liability_repayment_confirmed'/i)
assert.match(migration, /p_status\s*=>\s*null/i)
assert.match(migration, /auth\.uid\(\)/i)
assert.match(migration, /for update/i)
assert.match(migration, /revoke all on function public\.confirm_staging_repayment/i)

assert.equal(workflow.split(`-f ${migrationPath}`).length - 1, 2)
assert.match(workflow, /test-screenshot-repayment-contract-fixture\.sql/i)
assert.match(workflow, /test-screenshot-repayment-contract\.sql/i)

console.log('Screenshot repayment migration contracts validated.')
