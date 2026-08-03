/**
 * time-core / format.js
 *
 * 边界展示层：Instant + tz → 用户可读字符串。
 * 所有分页、详情、卡片、prompt 拼接都只能走这里，禁止业务代码自己 new Date().toString()。
 */

import { toInstant } from './instant.js'
import { DEFAULT_TZ, tzOffsetMs } from './parse.js'

const WEEK_LABELS = ['日', '一', '二', '三', '四', '五', '六']

/**
 * 拆出目标时区下的墙上时间。
 *
 * @param {number | string | Date} input
 * @param {string} [tz]
 * @returns {{
 *   year:number, month:number, day:number,
 *   hour:number, minute:number, second:number,
 *   weekday:number
 * } | null}
 */
export function zonedParts(input, tz = DEFAULT_TZ) {
  const instant = toInstant(input)
  if (instant == null) return null
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    weekday: 'short',
  })
  const map = {}
  for (const p of dtf.formatToParts(new Date(instant))) {
    if (p.type !== 'literal') map[p.type] = p.value
  }
  const weekdayShort = map.weekday // Sun/Mon/...
  const weekdayIdx = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].indexOf(weekdayShort)
  const hour = map.hour === '24' ? 0 : +map.hour
  return {
    year: +map.year,
    month: +map.month,
    day: +map.day,
    hour,
    minute: +map.minute,
    second: +map.second,
    weekday: weekdayIdx,
  }
}

/**
 * 目标时区下的日历日 key，格式 "YYYY-MM-DD"。
 * 替代旧的 getLocalDateKey(new Date())。
 *
 * @param {number | string | Date} input
 * @param {string} [tz]
 * @returns {string}
 */
export function formatDateKey(input, tz = DEFAULT_TZ) {
  const p = zonedParts(input, tz)
  if (!p) return ''
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}`
}

/**
 * 目标时区下的可读时间标签。默认精度到分钟。
 *
 * @param {number | string | Date} input
 * @param {string} [tz]
 * @param {object} [opts]
 * @param {boolean} [opts.withSeconds=false]
 * @returns {string} "8月1日 07:46"
 */
export function formatDisplay(input, tz = DEFAULT_TZ, opts = {}) {
  const p = zonedParts(input, tz)
  if (!p) return ''
  const base = `${p.month}月${p.day}日 ${pad2(p.hour)}:${pad2(p.minute)}`
  if (opts.withSeconds) return `${base}:${pad2(p.second)}`
  return base
}

/**
 * "今天 / 昨天 / M月D日" 的日期标签（不含时间）。
 * 替代旧的 formatDate(dateStr)——但输入是 Instant，而不是 "YYYY-MM-DD"。
 *
 * @param {number | string | Date} input
 * @param {string} [tz]
 * @param {number | string | Date} [nowRef] 用于测试注入当前时刻
 * @returns {string}
 */
export function formatRelativeDate(input, tz = DEFAULT_TZ, nowRef = Date.now()) {
  const key = formatDateKey(input, tz)
  if (!key) return ''
  const todayKey = formatDateKey(nowRef, tz)
  if (key === todayKey) return '今天'
  const yesterdayKey = formatDateKey(toInstant(nowRef) - 86_400_000, tz)
  if (key === yesterdayKey) return '昨天'
  const p = zonedParts(input, tz)
  return `${p.month}月${p.day}日`
}

/**
 * 内部工具：目标时区下的 ISO 字符串，附带 offset。用于日志与断言，不给业务展示。
 * 例如 "2026-08-01T07:46:31+08:00"
 *
 * @param {number | string | Date} input
 * @param {string} [tz]
 * @returns {string}
 */
export function formatIsoZoned(input, tz = DEFAULT_TZ) {
  const p = zonedParts(input, tz)
  if (!p) return ''
  const instant = toInstant(input)
  const offsetMin = tzOffsetMs(instant, tz) / 60000
  const sign = offsetMin >= 0 ? '+' : '-'
  const absMin = Math.abs(offsetMin)
  const offH = pad2(Math.floor(absMin / 60))
  const offM = pad2(absMin % 60)
  return `${p.year}-${pad2(p.month)}-${pad2(p.day)}T${pad2(p.hour)}:${pad2(p.minute)}:${pad2(p.second)}${sign}${offH}:${offM}`
}

function pad2(n) {
  const s = String(n)
  return s.length >= 2 ? s : `0${s}`
}

export { WEEK_LABELS }
