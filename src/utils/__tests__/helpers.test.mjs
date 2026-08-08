import test from 'node:test'
import assert from 'node:assert/strict'
import {
  buildScopedDayKey,
  computeWeekData,
  formatDate,
  formatDateKeyLabel,
  formatDateTimeLabel,
  formatMonthLabel,
  getLocalDateKey,
  localDateKeyOf,
  mapTransaction,
} from '../helpers.js'

test('getLocalDateKey(new Date()) 返回 YYYY-MM-DD', () => {
  const key = getLocalDateKey(new Date())
  assert.match(key, /^\d{4}-\d{2}-\d{2}$/)
})

test('localDateKeyOf 接受 ISO / YMD / Date', () => {
  assert.equal(localDateKeyOf('2026-08-01'), '2026-08-01')
  assert.equal(localDateKeyOf('2026-07-31T23:46:31Z'), '2026-08-01') // 星之柠案
})

test('buildScopedDayKey 处理月份天数溢出', () => {
  assert.equal(buildScopedDayKey(2026, 2, 31), '2026-02-28')
})

test('formatDateKeyLabel 显示 M月D日', () => {
  assert.equal(formatDateKeyLabel('2026-08-01'), '8月1日')
})

test('formatDate "M月D日" 用于非今天/昨天', () => {
  // 距今 10 天前的日期一定不是今天/昨天
  const past = new Date(Date.now() - 10 * 86400000)
  const key = getLocalDateKey(past)
  const label = formatDate(key)
  assert.match(label, /^\d+月\d+日$/)
})

test('formatDate("今天日期") 返回"今天"', () => {
  const today = getLocalDateKey()
  assert.equal(formatDate(today), '今天')
})

test('formatDateTimeLabel — 星之柠 UTC 23:46 显示为北京 8月1日 07:46', () => {
  assert.equal(formatDateTimeLabel('2026-07-31T23:46:31Z'), '8月1日 07:46')
})

test('formatDateTimeLabel 拒绝无效值', () => {
  assert.equal(formatDateTimeLabel(null), '')
  assert.equal(formatDateTimeLabel(''), '')
  assert.equal(formatDateTimeLabel('bad'), '')
})

test('formatMonthLabel', () => {
  assert.equal(formatMonthLabel(2026, 8), '2026年8月')
})

test('mapTransaction 保留旧字段形状', () => {
  const t = mapTransaction({
    id: 'x',
    merchant_name: '星之柠',
    amount: 6.8,
    transaction_date: getLocalDateKey(),
    transaction_time: '07:46:31',
    source: 'manual',
    status: 'done',
    type: 'expense',
    created_at: '2026-07-31T23:46:31Z',
  })
  assert.equal(t.name, '星之柠')
  assert.equal(t.amount, 6.8)
  assert.equal(t.date, '今天')
  assert.equal(t.time, '07:46')
})

test('mapTransaction 不把 AI 旧 transaction_time 冒充可信发生时间', () => {
  const t = mapTransaction({
    id: 'ai-x',
    merchant_name: '星之柠',
    amount: 6.8,
    transaction_date: '2026-08-08',
    transaction_time: '02:41:00',
    source: 'ai_scan',
    created_at: '2026-08-07T22:42:00Z',
  })

  assert.equal(t.occurredAt, null)
  assert.equal(t.dateRaw, '2026-08-08')
  assert.equal(t.time, '')
})

test('mapTransaction 使用 canonical occurred_at 转换北京时间', () => {
  const t = mapTransaction({
    id: 'canonical-x',
    merchant_name: '星之柠',
    amount: 6.8,
    occurred_at: '2026-08-07T22:41:00Z',
    transaction_date: '2026-08-08',
    transaction_time: '02:41:00',
    source: 'ai_scan',
    created_at: '2026-08-07T22:42:00Z',
  })

  assert.equal(t.occurredAt, '2026-08-07T22:41:00Z')
  assert.equal(t.dateRaw, '2026-08-08')
  assert.equal(t.time, '06:41')
})

test('computeWeekData 按本周 7 天累加 done 记录', () => {
  const todayKey = getLocalDateKey()
  const bills = [
    { status: 'done', dateRaw: todayKey, amount: 10 },
    { status: 'done', dateRaw: todayKey, amount: 5 },
    { status: 'pending', dateRaw: todayKey, amount: 999 }, // 不算
    { status: 'done', dateRaw: '1970-01-01', amount: 999 }, // 不在本周
  ]
  const data = computeWeekData(bills)
  assert.equal(data.length, 7)
  const total = data.reduce((a, b) => a + b, 0)
  assert.equal(total, 15)
})
