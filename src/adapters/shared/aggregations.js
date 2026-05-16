// ════════════════════════════════════════════════════════════════════
// adapter 共享聚合工具
// 不依赖任何域，纯函数，所有 adapter 复用
// ════════════════════════════════════════════════════════════════════

/** 安全取数字 */
export function safeNumber(value, fallback = 0) {
  const n = Number(value)
  return Number.isFinite(n) ? n : fallback
}

/** 从 payload 取字段值（支持嵌套，如 'dishes.length' → record.payload.dishes.length） */
export function pickPayloadValue(record, key, fallback) {
  if (!record || !key) return fallback
  const payload = record.payload || {}
  if (!key.includes('.')) return payload[key] ?? fallback
  return key.split('.').reduce((obj, k) => (obj == null ? obj : obj[k]), payload) ?? fallback
}

/** 求和：records 中某个 fact 的总和 */
export function sumByPayloadKey(records, key) {
  return records.reduce((sum, r) => sum + safeNumber(pickPayloadValue(r, key, 0)), 0)
}

/** 最大值 */
export function maxByPayloadKey(records, key) {
  if (!records.length) return 0
  return records.reduce((max, r) => Math.max(max, safeNumber(pickPayloadValue(r, key, 0))), 0)
}

/** 平均值 */
export function avgByPayloadKey(records, key) {
  if (!records.length) return 0
  return sumByPayloadKey(records, key) / records.length
}

/** 按 payload key 分组（dimension 维度） */
export function groupByPayloadKey(records, key, fallbackName = '其他') {
  const result = new Map()
  records.forEach(r => {
    const raw = pickPayloadValue(r, key, null)
    const name = (raw == null || raw === '') ? fallbackName : String(raw)
    if (!result.has(name)) result.set(name, { name, count: 0, sum: 0, records: [] })
    const bucket = result.get(name)
    bucket.count += 1
    bucket.records.push(r)
  })
  return Array.from(result.values())
}

/** 按 payload key 分组并对某个 fact 求和 */
export function groupSumByPayloadKey(records, dimensionKey, factKey, fallbackName = '其他') {
  const result = new Map()
  records.forEach(r => {
    const raw = pickPayloadValue(r, dimensionKey, null)
    const name = (raw == null || raw === '') ? fallbackName : String(raw)
    if (!result.has(name)) result.set(name, { name, sum: 0, count: 0 })
    const bucket = result.get(name)
    bucket.count += 1
    bucket.sum += safeNumber(pickPayloadValue(r, factKey, 0))
  })
  return Array.from(result.values())
}

/** Top N 排序 */
export function topN(items, key, n = 6) {
  return [...items].sort((a, b) => (b[key] || 0) - (a[key] || 0)).slice(0, n)
}

/** 把分组结果转换成 DistributionPanel 期望的格式 */
export function toDistributionItems(groups, valueKey = 'sum', { currency = false, unit = '条', maxCount = 6 } = {}) {
  if (!groups.length) return []
  const sorted = topN(groups, valueKey, maxCount)
  const max = sorted[0]?.[valueKey] || 1
  return sorted.map(g => ({
    name: g.name,
    value: g[valueKey],
    pct: Math.round(((g[valueKey] || 0) / max) * 100),
    display: currency
      ? `¥${Math.round(g[valueKey] || 0)}`
      : `${formatPlainNumber(g[valueKey])}${unit ? ' ' + unit : ''}`,
  }))
}

/** 通用数字格式化（无单位） */
export function formatPlainNumber(value) {
  const n = safeNumber(value)
  if (n >= 10000) return `${(n / 10000).toFixed(1)}万`
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

/** 带单位的数字格式化（运动 32 分钟、阅读 1.5 小时） */
export function formatWithUnit(value, unit, { currency = false } = {}) {
  if (currency) {
    const n = safeNumber(value)
    if (n >= 10000) return `¥${(n / 10000).toFixed(2)}万`
    return `¥${Math.round(n)}`
  }
  return `${formatPlainNumber(value)}${unit ? ' ' + unit : ''}`
}
