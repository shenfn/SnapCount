import test from 'node:test'
import assert from 'node:assert/strict'
import {
  formatDateKey,
  formatDisplay,
  formatRelativeDate,
  formatIsoZoned,
  zonedParts,
} from '../format.js'

/**
 * Golden case: 星之柠 6.80 元
 * 数据库 created_at = 2026-07-31T23:46:31Z （UTC）
 * 用户在北京时间 2026-08-01 07:46 记录
 */
const XINGZHILIN_UTC = Date.UTC(2026, 6, 31, 23, 46, 31)

test('formatDateKey — 星之柠 UTC 23:46 应显示为北京日历日 08-01', () => {
  assert.equal(formatDateKey(XINGZHILIN_UTC, 'Asia/Shanghai'), '2026-08-01')
})

test('formatDateKey — 同一 Instant 在 LA 应显示 07-31', () => {
  assert.equal(formatDateKey(XINGZHILIN_UTC, 'America/Los_Angeles'), '2026-07-31')
})

test('formatDisplay — 星之柠案在北京时间显示为 08 月 01 日 07:46', () => {
  assert.equal(formatDisplay(XINGZHILIN_UTC, 'Asia/Shanghai'), '8月1日 07:46')
})

test('formatDisplay 支持秒精度', () => {
  assert.equal(
    formatDisplay(XINGZHILIN_UTC, 'Asia/Shanghai', { withSeconds: true }),
    '8月1日 07:46:31',
  )
})

test('formatRelativeDate — 当天返回"今天"', () => {
  const now = XINGZHILIN_UTC + 30 * 60 * 1000 // 30 分钟后
  assert.equal(formatRelativeDate(XINGZHILIN_UTC, 'Asia/Shanghai', now), '今天')
})

test('formatRelativeDate — 昨天返回"昨天"', () => {
  const now = XINGZHILIN_UTC + 24 * 3600 * 1000 + 3 * 3600 * 1000 // 次日下午
  assert.equal(formatRelativeDate(XINGZHILIN_UTC, 'Asia/Shanghai', now), '昨天')
})

test('formatRelativeDate — 早于昨天返回 M月D日', () => {
  const now = XINGZHILIN_UTC + 10 * 24 * 3600 * 1000
  assert.equal(formatRelativeDate(XINGZHILIN_UTC, 'Asia/Shanghai', now), '8月1日')
})

test('formatIsoZoned — 北京时区应显示 +08:00 offset', () => {
  assert.equal(
    formatIsoZoned(XINGZHILIN_UTC, 'Asia/Shanghai'),
    '2026-08-01T07:46:31+08:00',
  )
})

test('zonedParts — 拆解 LA 时区的墙上时间', () => {
  const p = zonedParts(XINGZHILIN_UTC, 'America/Los_Angeles')
  assert.equal(p.year, 2026)
  assert.equal(p.month, 7)
  assert.equal(p.day, 31)
  // LA 相对 UTC -7h（夏令时）
  assert.equal(p.hour, 16)
  assert.equal(p.minute, 46)
})

test('formatDisplay — null / 无效输入返回空串', () => {
  assert.equal(formatDisplay(null), '')
  assert.equal(formatDisplay('bad'), '')
})

test('formatDisplay — 跨日边界（本地 23:59 vs 00:01）', () => {
  // 北京 2026-08-01 23:59 = UTC 2026-08-01 15:59
  const a = Date.UTC(2026, 7, 1, 15, 59, 0)
  // 北京 2026-08-02 00:01 = UTC 2026-08-01 16:01
  const b = Date.UTC(2026, 7, 1, 16, 1, 0)
  assert.equal(formatDateKey(a, 'Asia/Shanghai'), '2026-08-01')
  assert.equal(formatDateKey(b, 'Asia/Shanghai'), '2026-08-02')
})
