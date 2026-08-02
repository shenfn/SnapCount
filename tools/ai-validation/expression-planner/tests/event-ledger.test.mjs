import test from 'node:test'
import assert from 'node:assert/strict'
import { compileMerchantAliases, resolveMerchant } from '../lib/entity-normalizer.mjs'
import { buildRecognitionLedger, compileEventOverrides, summarizeLedger } from '../lib/event-ledger.mjs'

const aliasMap = compileMerchantAliases({ merchants: [{ entity_id: 'merchant_example_api_hub', canonical_name: 'Example API Hub', aliases: ['ExampleAPIHub'] }] })
const overrideMap = compileEventOverrides({ overrides: [{ ai_log_id: 'dup-1', ledger_status: 'user_confirmed_distinct', count_in_facts: true }] })

const logs = [
  { id: 'dup-1', created_at: '2026-07-12T12:46:00+08:00', status: 'duplicate', duplicate_kind: 'perceptual_hash', target_table: 'transactions', target_id: 'tx-1', ai_response: { amount: 10, merchant_name: 'ExampleAPIHub' } },
  { id: 'success-1', created_at: '2026-07-12T20:18:00+08:00', status: 'success', target_table: 'transactions', target_id: 'tx-2', ai_response: { amount: 15, merchant_name: 'Example API Hub' } },
]

test('user override promotes duplicate candidate into fact ledger', () => {
  const ledger = buildRecognitionLedger(logs, { aliasMap, resolveMerchant, overrideMap })
  assert.equal(ledger[0].ledger_status, 'user_confirmed_distinct')
  assert.equal(ledger[0].count_in_facts, true)
  assert.deepEqual(summarizeLedger(ledger), {
    total_events: 2,
    status_counts: { user_confirmed_distinct: 1, confirmed_transaction: 1 },
    fact_eligible_events: 2,
    disputed_events: 0,
    pending_events: 0,
  })
})
