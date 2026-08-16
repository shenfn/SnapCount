import test from 'node:test'
import assert from 'node:assert/strict'

import { createAccountRepository, mapRepaymentCycleRow } from '../accountRepository.js'

function createRpcClient(responses = {}) {
  const calls = []
  const queues = Object.fromEntries(
    Object.entries(responses).map(([name, value]) => [name, Array.isArray(value) ? [...value] : [value]]),
  )
  return {
    calls,
    client: {
      async rpc(name, params) {
        calls.push({ name, params })
        return queues[name]?.shift() || { data: null, error: null }
      },
    },
  }
}

const cycleRow = {
  id: 'cycle-1',
  user_id: 'user-1',
  account_id: 'liability-1',
  cycle_month: '2026-08',
  statement_start_date: '2026-07-01',
  statement_end_date: '2026-07-31',
  due_date: '2026-08-20',
  statement_amount: '100.00',
  paid_amount: '40.00',
  remaining_amount: '60.00',
  carried_over_amount: '0.00',
  original_statement_amount: '100.00',
  min_payment_amount: '20.00',
  refund_applied_amount: '0.00',
  status: 'partial_paid',
  auto_debit_account_id: 'debit-1',
  auto_confirm_repayment: false,
  source: 'manual',
  evidence_record_id: null,
  confidence: '0.98',
  statement_source_priority: 30,
  note: '部分还款',
  confirmed_at: '2026-08-16T08:00:00Z',
  created_at: '2026-08-01T00:00:00Z',
  updated_at: '2026-08-16T08:00:00Z',
}

test('PWA-064B maps the canonical repayment cycle DTO once', () => {
  const cycle = mapRepaymentCycleRow(cycleRow)

  assert.equal(cycle.id, 'cycle-1')
  assert.equal(cycle.accountId, 'liability-1')
  assert.equal(cycle.statementAmount, 100)
  assert.equal(cycle.paidAmount, 40)
  assert.equal(cycle.remainingAmount, 60)
  assert.equal(cycle.minPaymentAmount, 20)
  assert.equal(cycle.confidence, 0.98)
  assert.equal(cycle.autoDebitAccountId, 'debit-1')
})

test('PWA-064B confirmation owns RPC params without accepting a user id', async () => {
  const { client, calls } = createRpcClient({
    set_repayment_cycle_paid_amount: { data: cycleRow, error: null },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.confirmRepayment({
    cycleId: 'cycle-1',
    paidAmount: 40,
    paidAt: '2026-08-16T08:00:00Z',
    debitAccountId: 'debit-1',
    status: 'partial_paid',
    note: '部分还款',
    userId: 'must-not-cross-transport',
  })

  assert.equal(result.status, 'accepted')
  assert.equal(result.reason, 'confirmed')
  assert.equal(result.cycle.id, 'cycle-1')
  assert.deepEqual(calls, [{
    name: 'set_repayment_cycle_paid_amount',
    params: {
      p_cycle_id: 'cycle-1',
      p_paid_amount: 40,
      p_paid_at: '2026-08-16T08:00:00Z',
      p_debit_account_id: 'debit-1',
      p_status: 'partial_paid',
      p_note: '部分还款',
    },
  }])
  assert.equal(Object.hasOwn(calls[0].params, 'user_id'), false)
})

test('PWA-064B revocation preserves a null canonical cycle and service failures', async () => {
  const { client, calls } = createRpcClient({
    revoke_liability_payment: [
      { data: null, error: null },
      { data: null, error: { message: '撤销失败' } },
    ],
  })
  const repository = createAccountRepository({ client })

  const accepted = await repository.revokePayment({ paymentId: 'payment-1', reason: '用户撤销还款' })
  const failed = await repository.revokePayment({ paymentId: 'payment-2', reason: '用户撤销还款' })

  assert.deepEqual(accepted, { status: 'accepted', reason: 'revoked', cycle: null })
  assert.equal(failed.status, 'failed')
  assert.equal(failed.reason, 'service_error')
  assert.equal(failed.error, '撤销失败')
  assert.deepEqual(calls[0], {
    name: 'revoke_liability_payment',
    params: { p_payment_id: 'payment-1', p_reason: '用户撤销还款' },
  })
})

test('PWA-064B invalid canonical responses are not reported as accepted', async () => {
  const { client } = createRpcClient({
    set_repayment_cycle_paid_amount: { data: null, error: null },
  })
  const repository = createAccountRepository({ client })

  const result = await repository.confirmRepayment({ cycleId: 'cycle-1', paidAmount: 40 })

  assert.equal(result.status, 'failed')
  assert.equal(result.reason, 'invalid_response')
  assert.equal(result.cycle, null)
})
