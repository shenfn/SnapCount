// ════════════════════════════════════════════════════════════════════
// 通用 formatter 工具
// 重点：formatDuration 把分钟整数转成 "6 小时 30 分钟" 自然格式
// ════════════════════════════════════════════════════════════════════

/**
 * 把分钟数格式化成人类可读的时长
 * 20         → '20 分钟'
 * 60         → '1 小时'
 * 90         → '1 小时 30 分钟'
 * 480        → '8 小时'
 * 0 / null   → '0 分钟'
 *
 * @param {number} minutes 分钟数（整数或浮点）
 * @param {Object} options
 * @param {boolean} options.short 紧凑模式 → '6h30m'，用于柱顶等空间紧张场景
 */
export function formatDuration(minutes, { short = false } = {}) {
  const m = Math.round(Number(minutes) || 0)
  if (m <= 0) return short ? '0m' : '0 分钟'

  const h = Math.floor(m / 60)
  const mm = m % 60

  if (short) {
    if (h === 0) return `${mm}m`
    if (mm === 0) return `${h}h`
    return `${h}h${mm}m`
  }

  if (h === 0) return `${mm} 分钟`
  if (mm === 0) return `${h} 小时`
  return `${h} 小时 ${mm} 分钟`
}

/**
 * 通用数字格式（万级缩写）
 * 1234   → '1234'
 * 12345  → '1.2万'
 */
export function formatPlainNumber(value) {
  const n = Number(value) || 0
  if (n >= 10000) return `${(n / 10000).toFixed(1)}万`
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

/**
 * 人民币金额格式：默认 2 位小数
 * 900.39 → '¥900.39'
 * 12345.6 → '¥12,345.60'
 * @param {number} amount
 * @param {Object} options
 * @param {number} options.fractionDigits 小数位数，默认 2
 * @param {boolean} options.thousands 是否显示千分位，默认 true
 * @param {boolean} options.short 紧凑模式：大额缩写为 '¥1.2万'
 */
export function formatCurrency(amount, { fractionDigits = 2, thousands = true, short = false } = {}) {
  const n = Number(amount) || 0

  if (short && Math.abs(n) >= 10000) {
    return `¥${(n / 10000).toFixed(1)}万`
  }

  const formatted = thousands
    ? n.toLocaleString('zh-CN', {
        minimumFractionDigits: fractionDigits,
        maximumFractionDigits: fractionDigits,
      })
    : n.toFixed(fractionDigits)

  return `¥${formatted}`
}

/**
 * 判断 schema fact 是否是时长类（用于自动应用 formatDuration）
 * unit 是 '小时' 或 '分钟' 都算
 */
export function isDurationFact(fact) {
  if (!fact) return false
  if (fact.input === 'duration') return true
  return fact.unit === '分钟' || fact.unit === '小时'
}

/**
 * 从 payload 读取 fact 值，统一返回分钟数
 * 兼容历史数据：fact.key='sleep_hours' 时读出小时 ×60；fact.key='sleep_minutes' 时直接读
 *
 * 双兼容核心：无论 schema 是 sleep_hours 还是 sleep_minutes，都能正确读取
 *  - 015 未跑：schema.fact.key='sleep_hours', payload.sleep_hours=6.67 → 返回 400
 *  - 015 已跑：schema.fact.key='sleep_minutes', payload.sleep_minutes=400 → 返回 400
 *  - 极端情况：schema=minutes 但 payload 还存 sleep_hours → 也能 fallback
 */
export function readDurationAsMinutes(record, fact) {
  if (!record?.payload || !fact) return 0
  const payload = record.payload

  // 候选字段：fact.key 优先，sleep 域考虑互为 fallback
  const candidates = [fact.key]
  if (fact.key === 'sleep_minutes') candidates.push('sleep_hours')
  if (fact.key === 'sleep_hours') candidates.push('sleep_minutes')

  for (const key of candidates) {
    const raw = payload[key]
    if (raw == null) continue
    const n = Number(raw)
    if (!Number.isFinite(n)) continue
    // 按字段名后缀推断单位：以 _hours 结尾视为小时数 ×60，否则视为分钟
    if (key.endsWith('_hours')) return n * 60
    return n
  }
  return 0
}
