import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')
const ingestPath = path.join(root, 'supabase/functions/ingest-receipt/index.ts')
const shadowPath = path.join(root, 'supabase/functions/ingest-receipt/expression-shadow.ts')

test('credit payment method alone cannot trigger repayment feedback', async () => {
  const source = await readFile(ingestPath, 'utf8')
  const repaymentLine = source.split('\n').find(line => line.includes('const repaymentText ='))
  assert.ok(repaymentLine)
  assert.doesNotMatch(repaymentLine, /payment_method|funding_source/)
  assert.match(source, /includesAny\(repaymentText, \["还款", "待还", "应还", "最低还款", "账单还款", "欠款"\]\)/)
})

test('food expense is handled before generic small-spend framing', async () => {
  const source = await readFile(ingestPath, 'utf8')
  const expenseStart = source.indexOf('function buildExpenseAIFeedback')
  const foodBranch = source.indexOf('if (isFoodExpense)', expenseStart)
  const smallBranch = source.indexOf('if (amount <= 20)', expenseStart)
  assert.ok(foodBranch > expenseStart)
  assert.ok(smallBranch > foodBranch)
  assert.match(source, /badge: "餐饮入账"/)
  assert.match(source, /不从支付工具推断还款行为/)
})

test('unsupported meal-frequency claims are rejected', async () => {
  const source = await readFile(ingestPath, 'utf8')
  assert.match(source, /第几\(\?:笔\|顿\|次\|单\)/)
})

test('normal expense response and shadow fallback retain expense identity', async () => {
  const ingest = await readFile(ingestPath, 'utf8')
  const shadow = await readFile(shadowPath, 'utf8')
  assert.match(ingest, /status: row\.status,\s+record_type: "expense",/)
  assert.match(shadow, /data\?\.transaction_date \|\| data\?\.merchant_name \? "expense"/)
})
