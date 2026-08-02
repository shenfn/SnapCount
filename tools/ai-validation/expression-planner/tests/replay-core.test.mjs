import test from 'node:test'
import assert from 'node:assert/strict'
import { summarizeTransactions } from '../lib/replay-core.mjs'

test('summarizes four developer transactions', () => {
  const rows = [
    { id: '1', amount: 10, occurred_at: '2026-07-12T14:10:00+08:00' },
    { id: '2', amount: 10, occurred_at: '2026-07-12T15:02:00+08:00' },
    { id: '3', amount: 10, occurred_at: '2026-07-12T18:40:00+08:00' },
    { id: '4', amount: 15, occurred_at: '2026-07-12T22:15:00+08:00' },
  ]
  assert.deepEqual(summarizeTransactions(rows, '4'), {
    count: 4,
    total: 45,
    min_amount: 10,
    max_amount: 15,
    first_occurred_at: '2026-07-12T14:10:00+08:00',
    last_occurred_at: '2026-07-12T22:15:00+08:00',
    span_minutes: 485,
    current_sequence: 4,
  })
})
