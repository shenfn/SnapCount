/**
 * time-core / diff.js
 *
 * 事实层时间差：由代码算好，交给 LLM 使用（禁止 LLM 生成"3 分钟内"这类词）。
 * 覆盖 08-01 星之柠案里 detail_reason 硬编码"3 分钟内"的场景。
 */

import { toInstant } from './instant.js'
import { formatDateKey, formatDisplay } from './format.js'
import { DEFAULT_TZ } from './parse.js'

const MINUTE = 60_000
const HOUR = 60 * MINUTE
const DAY = 24 * HOUR

/**
 * 两个 Instant 的差值（毫秒）。b - a。
 *
 * @param {number | string | Date} a
 * @param {number | string | Date} b
 * @returns {number | null}
 */
export function diffMs(a, b) {
  const ai = toInstant(a)
  const bi = toInstant(b)
  if (ai == null || bi == null) return null
  return bi - ai
}

/**
 * 把 (historical, now) 差距渲染成给用户/LLM 的短语。
 *
 * 规则：
 *  - 未来 → "即将 / 未来 X 分钟"
 *  - < 60s → "刚刚"
 *  - < 60min → "X 分钟前"
 *  - 同一日历日 → "今天 HH:MM"
 *  - 昨天 → "昨天 HH:MM"
 *  - < 7 天 → "N 天前"
 *  - 其它 → "M月D日 HH:MM"
 *
 * @param {number | string | Date} historical
 * @param {number | string | Date} [now]
 * @param {string} [tz]
 * @returns {string}
 */
export function diffHuman(historical, now = Date.now(), tz = DEFAULT_TZ) {
  const h = toInstant(historical)
  const n = toInstant(now)
  if (h == null || n == null) return ''
  const delta = n - h

  if (delta < 0) {
    const abs = -delta
    if (abs < MINUTE) return '即将'
    if (abs < HOUR) return `${Math.round(abs / MINUTE)} 分钟后`
    return `未来 ${Math.round(abs / HOUR)} 小时`
  }

  if (delta < MINUTE) return '刚刚'
  if (delta < HOUR) return `${Math.floor(delta / MINUTE)} 分钟前`

  const hKey = formatDateKey(h, tz)
  const nKey = formatDateKey(n, tz)
  if (hKey === nKey) {
    return `今天 ${formatDisplay(h, tz).split(' ')[1] ?? ''}`.trim()
  }
  const yesterdayKey = formatDateKey(n - DAY, tz)
  if (hKey === yesterdayKey) {
    return `昨天 ${formatDisplay(h, tz).split(' ')[1] ?? ''}`.trim()
  }
  if (delta < 7 * DAY) return `${Math.floor(delta / DAY)} 天前`
  return formatDisplay(h, tz)
}

/**
 * 结构化差值，供规则/契约层使用（例如判断是否满足"3 分钟内"这类阈值）。
 *
 * @param {number | string | Date} a
 * @param {number | string | Date} b
 * @returns {{ ms:number, minutes:number, hours:number, days:number, sameDayInTz:(tz:string)=>boolean } | null}
 */
export function diffStructured(a, b) {
  const ai = toInstant(a)
  const bi = toInstant(b)
  if (ai == null || bi == null) return null
  const ms = Math.abs(bi - ai)
  return {
    ms,
    minutes: ms / MINUTE,
    hours: ms / HOUR,
    days: ms / DAY,
    sameDayInTz(tz = DEFAULT_TZ) {
      return formatDateKey(ai, tz) === formatDateKey(bi, tz)
    },
  }
}
