import test from 'node:test'
import assert from 'node:assert/strict'
import {
  parseInstant,
  parseLocalYmd,
  tzOffsetMs,
  zonedWallTimeToInstant,
} from '../parse.js'

test('parseInstant accepts ISO with explicit offset', () => {
  const t = parseInstant('2026-08-01T07:46:31+08:00')
  assert.equal(t, Date.UTC(2026, 6, 31, 23, 46, 31))
})

test('parseInstant accepts ISO with Z', () => {
  const t = parseInstant('2026-07-31T23:46:31Z')
  assert.equal(t, Date.UTC(2026, 6, 31, 23, 46, 31))
})

test('parseInstant rejects bare YMD when treated as ISO fallback and reparses via tz', () => {
  const t = parseInstant('2026-08-01', 'Asia/Shanghai')
  // 默认 12:00 本地时间
  assert.equal(t, Date.UTC(2026, 7, 1, 4, 0, 0))
})

test('parseLocalYmd handles "YYYY-MM-DD HH:MM:SS" in Asia/Shanghai', () => {
  const t = parseLocalYmd('2026-08-01 07:46:31', 'Asia/Shanghai')
  assert.equal(t, Date.UTC(2026, 6, 31, 23, 46, 31))
})

test('parseLocalYmd handles LA daylight-saving forward jump', () => {
  // 2026-03-08 02:00 LA 不存在（跳到 03:00），我们至少要求解析出的 instant 落回一个合法瞬间
  const t = parseLocalYmd('2026-03-08 02:30', 'America/Los_Angeles')
  assert.ok(typeof t === 'number' && Number.isFinite(t))
})

test('tzOffsetMs for Asia/Shanghai is +8h year-round', () => {
  const jan = Date.UTC(2026, 0, 15, 0, 0, 0)
  const jul = Date.UTC(2026, 6, 15, 0, 0, 0)
  assert.equal(tzOffsetMs(jan, 'Asia/Shanghai'), 8 * 3600 * 1000)
  assert.equal(tzOffsetMs(jul, 'Asia/Shanghai'), 8 * 3600 * 1000)
})

test('zonedWallTimeToInstant round-trips a wall clock', () => {
  const t = zonedWallTimeToInstant(
    { year: 2026, month: 8, day: 1, hour: 7, minute: 46, second: 31 },
    'Asia/Shanghai',
  )
  assert.equal(t, Date.UTC(2026, 6, 31, 23, 46, 31))
})

test('parseInstant returns null for garbage', () => {
  assert.equal(parseInstant('not a date'), null)
  assert.equal(parseInstant(''), null)
  assert.equal(parseInstant(null), null)
})
