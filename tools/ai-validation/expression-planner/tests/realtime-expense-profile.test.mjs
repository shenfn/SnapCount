import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const bundle = await build({
  entryPoints: ['supabase/functions/ingest-receipt/realtime-expense-profile.ts'],
  bundle: true, platform: 'node', format: 'esm', write: false,
})
const mod = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64'))

test('collapses merchant spacing aliases and includes the current record', () => {
  const rows = [
    { merchant_name: 'Example API Hub', amount: 11, transaction_date: '2026-07-13' },
    { merchant_name: 'ExampleAPIHub', amount: 15, transaction_date: '2026-07-13' },
    { merchant_name: 'Example API Hub', amount: 11, transaction_date: '2026-07-13' },
    { merchant_name: 'ExampleAPIHub', amount: 11, transaction_date: '2026-07-13' },
  ]
  const stats = mod.buildRealtimeMerchantStats(rows, {
    merchant: 'Example API Hub', amount: 12, transactionDate: '2026-07-13',
  })
  assert.equal(stats.week_count, 5)
  assert.equal(stats.month_count, 5)
  assert.equal(stats.count_90d, 5)
  assert.equal(stats.avg_amount, 12)
  assert.deepEqual(stats.aliases_collapsed.sort(), ['Example API Hub', 'ExampleAPIHub'].sort())
})

test('does not merge genuinely different merchants', () => {
  const stats = mod.buildRealtimeMerchantStats([
    { merchant_name: '其他数字中心', amount: 99, transaction_date: '2026-07-13' },
  ], { merchant: 'Example API Hub', amount: 12, transactionDate: '2026-07-13' })
  assert.equal(stats.week_count, 1)
  assert.equal(stats.avg_amount, 12)
})
