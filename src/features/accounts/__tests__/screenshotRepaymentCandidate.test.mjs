import test from 'node:test'
import assert from 'node:assert/strict'

import { buildScreenshotRepaymentCandidate } from '../buildScreenshotRepaymentCandidate.js'

const record = {
  id: 'staging-1',
  domainKey: 'wallet',
  occurredAt: '2026-08-15T10:00:00Z',
  summary: '支付宝花呗还款',
  extracted: { payload_jsonb: { record_kind: 'liability_snapshot', status: 'paid', account_name: '支付宝花呗', amount: 100 } },
}
const account = { id: 'account-1', name: '支付宝花呗', institution: '支付宝', type: 'credit_line', isArchived: false }
const cycle = { id: 'cycle-1', accountId: 'account-1', cycleMonth: '2026-08', dueDate: '2026-08-16', remainingAmount: 100, statementAmount: 100, status: 'pending' }

test('PWA-067A builds a deterministic candidate from active liability evidence', () => {
  const candidate = buildScreenshotRepaymentCandidate(record, [account], [cycle])
  assert.equal(candidate.cycle.id, 'cycle-1')
  assert.equal(candidate.account.id, 'account-1')
  assert.equal(candidate.amount, 100)
  assert.ok(candidate.score >= 0.9)
})

test('PWA-067A rejects non-wallet evidence, archived accounts, and closed cycles', () => {
  assert.equal(buildScreenshotRepaymentCandidate({ ...record, domainKey: 'food' }, [account], [cycle]), null)
  assert.equal(buildScreenshotRepaymentCandidate(record, [{ ...account, isArchived: true }], [cycle]), null)
  assert.equal(buildScreenshotRepaymentCandidate(record, [account], [{ ...cycle, status: 'paid' }]), null)
})

test('PWA-067A falls back to remaining amount and uses a stable tie break', () => {
  const noAmount = { ...record, extracted: { payload_jsonb: { record_kind: 'liability_snapshot', status: 'paid', account_name: '支付宝花呗' } } }
  const later = { ...cycle, id: 'cycle-z', dueDate: '2026-08-18' }
  const earlier = { ...cycle, id: 'cycle-a', dueDate: '2026-08-16' }
  const candidate = buildScreenshotRepaymentCandidate(noAmount, [account], [later, earlier])
  assert.equal(candidate.cycle.id, 'cycle-a')
  assert.equal(candidate.amount, 100)
})

test('PWA-067A preserves extracted summary as an account matching signal', () => {
  const summaryOnly = {
    ...record,
    occurredAt: '2026-07-01T10:00:00Z',
    summary: '',
    extracted: {
      summary: '支付宝花呗支付宝还款完成',
      payload_jsonb: { record_kind: 'liability_snapshot', status: 'paid', amount: 37 },
    },
  }
  const candidate = buildScreenshotRepaymentCandidate(summaryOnly, [account], [cycle])
  assert.equal(candidate?.cycle.id, 'cycle-1')
  assert.match(candidate.reason, /账户匹配/)
})
