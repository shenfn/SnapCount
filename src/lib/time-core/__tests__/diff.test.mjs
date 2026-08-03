import test from 'node:test'
import assert from 'node:assert/strict'
import { diffHuman, diffMs, diffStructured } from '../diff.js'

const XINGZHILIN_UTC = Date.UTC(2026, 6, 31, 23, 46, 31)

test('diffMs 正差与负差', () => {
  assert.equal(diffMs(1000, 2500), 1500)
  assert.equal(diffMs(2500, 1000), -1500)
})

test('diffHuman — 刚刚', () => {
  assert.equal(diffHuman(XINGZHILIN_UTC, XINGZHILIN_UTC + 30 * 1000), '刚刚')
})

test('diffHuman — 分钟前', () => {
  assert.equal(diffHuman(XINGZHILIN_UTC, XINGZHILIN_UTC + 15 * 60 * 1000), '15 分钟前')
})

test('diffHuman — 今天 HH:MM', () => {
  const now = XINGZHILIN_UTC + 5 * 3600 * 1000 // 同天下午
  assert.equal(diffHuman(XINGZHILIN_UTC, now, 'Asia/Shanghai'), '今天 07:46')
})

test('diffHuman — 昨天 HH:MM', () => {
  const now = XINGZHILIN_UTC + 25 * 3600 * 1000
  assert.equal(diffHuman(XINGZHILIN_UTC, now, 'Asia/Shanghai'), '昨天 07:46')
})

test('diffHuman — N 天前', () => {
  const now = XINGZHILIN_UTC + 3 * 24 * 3600 * 1000
  assert.equal(diffHuman(XINGZHILIN_UTC, now, 'Asia/Shanghai'), '3 天前')
})

test('diffHuman — 星之柠案关键断言：16h32m 差绝不能被称为"3 分钟内"', () => {
  // 历史记录：2026-07-31 15:14 北京
  const historical = Date.UTC(2026, 6, 31, 7, 14, 0)
  // 当前：2026-08-01 07:46 北京 (= UTC 07-31 23:46)
  const now = XINGZHILIN_UTC
  const text = diffHuman(historical, now, 'Asia/Shanghai')
  assert.ok(!text.includes('分钟'), `expected no 分钟, got "${text}"`)
  assert.ok(!text.includes('刚刚'), `expected no 刚刚, got "${text}"`)
  assert.equal(text, '昨天 15:14')
})

test('diffHuman — 未来时间显示"即将"或"未来"', () => {
  assert.equal(diffHuman(1000, 500), '即将')
  const past = XINGZHILIN_UTC
  const future = past - 2 * 3600 * 1000
  assert.equal(diffHuman(past, future), '未来 2 小时')
})

test('diffStructured — 提供分钟/小时/天精度', () => {
  const s = diffStructured(XINGZHILIN_UTC, XINGZHILIN_UTC + 3 * 3600 * 1000)
  assert.equal(s.hours, 3)
  assert.equal(s.minutes, 180)
})

test('diffStructured — sameDayInTz', () => {
  // 北京 08-01 23:59 vs 北京 08-02 00:01
  const a = Date.UTC(2026, 7, 1, 15, 59, 0)
  const b = Date.UTC(2026, 7, 1, 16, 1, 0)
  const s = diffStructured(a, b)
  assert.equal(s.sameDayInTz('Asia/Shanghai'), false)
  assert.equal(s.sameDayInTz('UTC'), true)
})
