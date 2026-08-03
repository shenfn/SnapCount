/**
 * time-core / parse.js
 *
 * 显式时区解析：把边界层的字符串（AI 返回、DB 生成列、客户端上传）转成 Instant。
 * 每一个入口都必须显式声明 tz（IANA 名），杜绝隐式系统时区。
 */

import { toInstant } from './instant.js'

/**
 * 默认时区。海外化后应改为按用户 profile 传入。
 */
export const DEFAULT_TZ = 'Asia/Shanghai'

/**
 * 把 "YYYY-MM-DD" 或 "YYYY-MM-DD HH:MM[:SS]" 按指定 IANA 时区解析为 Instant。
 * - 无时间部分默认 12:00:00（避免落在跨日边缘引发歧义）
 * - 不接受不带日期的时间；不接受 "T00:00:00" 无 offset 结尾
 *
 * @param {string} ymdOrDatetime
 * @param {string} [tz]
 * @returns {number | null}
 */
export function parseLocalYmd(ymdOrDatetime, tz = DEFAULT_TZ) {
  if (typeof ymdOrDatetime !== 'string' || !ymdOrDatetime) return null
  const trimmed = ymdOrDatetime.trim()
  const match = trimmed.match(
    /^(\d{4})-(\d{2})-(\d{2})(?:[ T](\d{2}):(\d{2})(?::(\d{2}))?)?$/,
  )
  if (!match) return null
  const [, y, mo, d, h = '12', mi = '00', s = '00'] = match
  return zonedWallTimeToInstant(
    { year: +y, month: +mo, day: +d, hour: +h, minute: +mi, second: +s },
    tz,
  )
}

/**
 * 智能解析：优先当作带时区的 ISO；否则按 (ymdOrDatetime, tz) 走 parseLocalYmd。
 *
 * @param {string} input
 * @param {string} [tz]
 * @returns {number | null}
 */
export function parseInstant(input, tz = DEFAULT_TZ) {
  if (typeof input !== 'string' || !input) return null
  // 带时区的 ISO 直接走 toInstant
  const iso = toInstant(input)
  if (iso != null) return iso
  return parseLocalYmd(input, tz)
}

/**
 * 把 { year, month, day, hour, minute, second } 视为指定 IANA 时区的"墙上时间"，
 * 反推 UTC epochMs。
 *
 * 实现思路：先假设 UTC 就是墙上时间（记 guess），再看该 guess 在目标时区的墙上时间与
 * 期望值差多少，把这个 offset 补回去。因为夏令时会有跳变，做一次二次修正即可稳定。
 *
 * @param {{year:number,month:number,day:number,hour:number,minute:number,second:number}} parts
 * @param {string} tz IANA
 * @returns {number}
 */
export function zonedWallTimeToInstant(parts, tz) {
  const target = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second,
  )
  const offset1 = tzOffsetMs(target, tz)
  const guess1 = target - offset1
  const offset2 = tzOffsetMs(guess1, tz)
  return target - offset2
}

/**
 * 返回指定时区在指定 Instant 时相对 UTC 的偏移（毫秒）。
 * 例如 Asia/Shanghai 恒为 +8h → 28800000
 *
 * @param {number} instant
 * @param {string} tz IANA
 * @returns {number}
 */
export function tzOffsetMs(instant, tz) {
  const dtf = new Intl.DateTimeFormat('en-US', {
    timeZone: tz,
    hour12: false,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
  })
  const parts = dtf.formatToParts(new Date(instant))
  const map = {}
  for (const p of parts) {
    if (p.type !== 'literal') map[p.type] = p.value
  }
  const asUtc = Date.UTC(
    +map.year,
    +map.month - 1,
    +map.day,
    +(map.hour === '24' ? '00' : map.hour),
    +map.minute,
    +map.second,
  )
  return asUtc - instant
}
