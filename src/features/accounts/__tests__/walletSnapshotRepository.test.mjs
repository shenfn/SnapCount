import test from 'node:test'
import assert from 'node:assert/strict'

import { createAccountRepository } from '../../../repositories/accountRepository.js'

function rpcClient(responses) {
  const calls = []
  const queue = Array.isArray(responses) ? [...responses] : [responses]
  return {
    calls,
    client: {
      async rpc(name, params) {
        calls.push({ name, params })
        return queue.shift() || { data: null, error: null }
      },
    },
  }
}

const accountRow = {
  id: 'account-1', user_id: 'user-1', name: '花呗', type: 'credit_line',
  initial_balance: '100.00', current_balance: '60.00', snapshot_balance: '100.00',
  snapshot_at: '2026-08-16T08:00:00Z', is_archived: false,
}

const cycleRow = {
  id: 'cycle-1', user_id: 'user-1', account_id: 'account-1', cycle_month: '2026-08',
  statement_amount: '100.00', paid_amount: '40.00', remaining_amount: '60.00',
  carried_over_amount: '0.00', status: 'partial_paid', source: 'screenshot',
  evidence_record_id: 'record-1', statement_source_priority: 90,
}

const paymentRow = {
  id: 'payment-1', account_id: 'account-1', statement_id: 'cycle-1',
  amount: '40.00', overpayment_amount: '0.00', paid_at: '2026-08-16T08:00:00Z',
  source: 'screenshot', evidence_record_id: 'record-1', status: 'confirmed',
}

test('PWA-068G repository owns the canonical RPC and maps nested account facts', async () => {
  const { client, calls } = rpcClient({
    data: {
      outcome: 'linked', record_id: 'record-1', linked_account_id: 'account-1',
      account: accountRow, cycle: cycleRow, payment: paymentRow,
      balance_changed: true, review_required: false,
    },
    error: null,
  })
  const repository = createAccountRepository({ client })

  const result = await repository.applyWalletSnapshot({
    recordId: 'record-1', accountId: 'account-1', userId: 'must-not-cross',
    amount: 999, status: 'paid',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'linked')
  assert.equal(result.account.currentBalance, 60)
  assert.equal(result.cycle.remainingAmount, 60)
  assert.equal(result.payment.evidenceRecordId, 'record-1')
  assert.equal(result.balanceChanged, true)
  assert.deepEqual(calls, [{
    name: 'apply_wallet_snapshot',
    params: { p_record_id: 'record-1', p_account_id: 'account-1' },
  }])
})

test('PWA-068G needs-confirmation is accepted without inventing cycle or payment', async () => {
  const { client } = rpcClient({
    data: {
      outcome: 'needs_confirmation', record_id: 'record-2', linked_account_id: 'account-1',
      account: accountRow, cycle: null, payment: null,
      balance_changed: false, review_required: true,
    },
    error: null,
  })
  const repository = createAccountRepository({ client })

  const result = await repository.applyWalletSnapshot({ recordId: 'record-2', accountId: 'account-1' })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'needs_confirmation')
  assert.equal(result.reviewRequired, true)
  assert.equal(result.cycle, null)
  assert.equal(result.payment, null)
})

test('PWA-068G invalid responses and stable database reasons remain failures', async () => {
  const { client } = rpcClient([
    { data: null, error: null },
    { data: { outcome: 'linked', record_id: 'record-1', linked_account_id: 'account-1', account: null }, error: null },
    { data: null, error: { message: 'snapshot_link_conflict' } },
    { data: null, error: { message: 'account_kind_mismatch' } },
  ])
  const repository = createAccountRepository({ client })

  assert.equal((await repository.applyWalletSnapshot({ recordId: 'record-1' })).reason, 'invalid_response')
  assert.equal((await repository.applyWalletSnapshot({ recordId: 'record-1' })).reason, 'invalid_response')
  assert.equal((await repository.applyWalletSnapshot({ recordId: 'record-1' })).reason, 'snapshot_link_conflict')
  assert.equal((await repository.applyWalletSnapshot({ recordId: 'record-1' })).reason, 'account_kind_mismatch')
})
