/**
 * time-core / instant.js
 *
 * Instant = UTC epoch milliseconds (number).
 *
 * 这是 time-core 模块的"事实"单位。系统内部所有时间流转一律使用 Instant，
 * 只有在与 UI / AI / DB 边界交互时才转成本地字符串。
 *
 * 禁止在业务代码里直接 new Date(stringLikeYMD)——那会隐式吃系统时区，
 * 是 08-01 星之柠案的直接根因之一。
 */

/**
 * 判断值是否为一个合法的 Instant（有限数值）。
 * @param {unknown} value
 * @returns {value is number}
 */
export function isInstant(value) {
  return typeof value === 'number' && Number.isFinite(value)
}

/**
 * 当前 Instant。测试可注入 clock。
 * @param {{ now?: () => number }} [opts]
 * @returns {number}
 */
export function nowInstant(opts) {
  const now = opts?.now ?? Date.now
  return now()
}

/**
 * 从合法 ISO 字符串或 Date 转 Instant。
 * 拒绝无时区提示的 "YYYY-MM-DD" / "YYYY-MM-DD HH:MM:SS"（要走 parseInstant 显式带 tz）。
 * @param {string | number | Date | null | undefined} input
 * @returns {number | null}
 */
export function toInstant(input) {
  if (input == null) return null
  if (isInstant(input)) return input
  if (input instanceof Date) {
    const t = input.getTime()
    return Number.isFinite(t) ? t : null
  }
  if (typeof input === 'string') {
    // 只接受带时区的 ISO（Z 或 +hh:mm / -hh:mm）
    if (!/T.+(Z|[+-]\d{2}:?\d{2})$/.test(input)) return null
    const t = Date.parse(input)
    return Number.isFinite(t) ? t : null
  }
  return null
}

/**
 * Instant → ISO 8601 UTC 字符串。用于持久化和调试日志。
 * @param {number} instant
 * @returns {string}
 */
export function toIsoUtc(instant) {
  if (!isInstant(instant)) return ''
  return new Date(instant).toISOString()
}
