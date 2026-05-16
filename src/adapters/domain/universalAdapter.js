// ════════════════════════════════════════════════════════════════════
// universalAdapter：协议驱动的通用域 adapter
// 核心：完全从 getDomainSchema/getDomainDisplay 读取协议，零硬编码字段名
// 只要 schema_json 里有 facts/dimensions，就能自动产出 metrics/trend/distribution
// ════════════════════════════════════════════════════════════════════
import { getDomainSchema, getDomainDisplay } from '../../domains/registry'
import {
  sumByPayloadKey,
  maxByPayloadKey,
  avgByPayloadKey,
  groupSumByPayloadKey,
  groupByPayloadKey,
  toDistributionItems,
  formatWithUnit,
  formatPlainNumber,
  pickPayloadValue,
  safeNumber,
} from '../shared/aggregations'
import {
  bucketByWeek,
  getTodayIndex,
  WEEK_LABELS_SHORT,
} from '../shared/timeBuckets'
import { formatDateTimeLabel } from '../../utils/helpers'
import { formatDuration, isDurationFact, readDurationAsMinutes } from '../../utils/format'

// ──────────────────────────────────────────────────────────────────
// 时长类 fact 的统一处理（双兼容：sleep_hours / sleep_minutes 都能读）
// ──────────────────────────────────────────────────────────────────

/** 从 records 数组取出 fact 值的列表，时长类自动统一为分钟 */
function extractFactValues(records, fact) {
  if (!fact) return []
  if (isDurationFact(fact)) {
    return records.map(r => readDurationAsMinutes(r, fact))
  }
  return records.map(r => safeNumber(pickPayloadValue(r, fact.key, 0)))
}

/** 单条 record 取 fact 值（时长类返回分钟） */
function extractFactValue(record, fact) {
  if (!fact) return 0
  if (isDurationFact(fact)) return readDurationAsMinutes(record, fact)
  return safeNumber(pickPayloadValue(record, fact.key, 0))
}

/** 格式化 fact 值（时长类用 formatDuration，否则用 formatWithUnit） */
function formatFactValue(value, fact, { short = false } = {}) {
  if (!fact) return formatPlainNumber(value)
  if (isDurationFact(fact)) return formatDuration(value, { short })
  return formatWithUnit(value, fact.unit)
}

/**
 * 取域内的所有 records（按时间倒序）
 */
function getDomainRecords(store, domain) {
  return store.dataRecords.value
    .filter(item => item.domainKey === domain.id)
    .sort((a, b) => ((b.occurredAt || b.createdAt || '').localeCompare(a.occurredAt || a.createdAt || '')))
}

/** 取主 fact（display.primary_fact 或 facts[0]） */
function getPrimaryFact(schema, display) {
  if (!schema?.facts?.length) return null
  const key = display?.primary_fact
  return schema.facts.find(f => f.key === key) || schema.facts[0]
}

/** 取主 dimension（display.primary_dimension 或 dimensions[0]） */
function getPrimaryDimension(schema, display) {
  if (!schema?.dimensions?.length) return null
  const key = display?.primary_dimension
  return schema.dimensions.find(d => d.key === key) || schema.dimensions[0]
}

// ──────────────────────────────────────────────────────────────────
// getMetricItems
// ──────────────────────────────────────────────────────────────────
export function getMetricItems(store, domain) {
  const schema = getDomainSchema(domain.id)
  const display = getDomainDisplay(domain.id)
  const records = getDomainRecords(store, domain)
  const primary = getPrimaryFact(schema, display)

  // 没有协议时返回兜底
  if (!primary || !records.length) {
    return [
      { label: '记录数', value: `${records.length}`, accent: true },
      { label: '模板状态', value: domain.recordCount ? '运行中' : '预留' },
      { label: '入库链路', value: domain.recordCount ? '已接入' : '待接入' },
      { label: '展示组件', value: '已就绪' },
    ]
  }

  // 时长类 fact 走分钟聚合（兼容 sleep_hours/sleep_minutes 双数据状态）
  const values = extractFactValues(records, primary)
  const total = values.reduce((sum, v) => sum + v, 0)
  const max = values.reduce((m, v) => Math.max(m, v), 0)
  const avg = records.length ? total / records.length : 0

  return [
    {
      label: `本月总${primary.label}`,
      value: formatFactValue(total, primary),
      accent: true,
    },
    { label: '记录数', value: `${records.length}` },
    { label: `最高单次`, value: formatFactValue(max, primary) },
    { label: `平均`, value: formatFactValue(avg, primary) },
  ]
}

// ──────────────────────────────────────────────────────────────────
// getTrend
// 时长类 fact 在每条 record 上换算为分钟后再分桶；其他 fact 走 bucketByWeek
// ──────────────────────────────────────────────────────────────────
export function getTrend(store, domain) {
  const schema = getDomainSchema(domain.id)
  const display = getDomainDisplay(domain.id)
  const records = getDomainRecords(store, domain)
  const primary = getPrimaryFact(schema, display)

  let values
  if (!primary) {
    values = bucketByWeek(records, { timeField: 'occurredAt' })
  } else if (isDurationFact(primary)) {
    // 时长类：先把每条记录换算为分钟挂在临时字段上，再分桶
    const enriched = records.map(r => ({
      ...r,
      payload: { ...(r.payload || {}), __duration_minutes__: extractFactValue(r, primary) },
    }))
    values = bucketByWeek(enriched, { timeField: 'occurredAt', factKey: '__duration_minutes__' })
  } else {
    values = bucketByWeek(records, { timeField: 'occurredAt', factKey: primary.key })
  }

  return {
    values,
    labels: WEEK_LABELS_SHORT,
    todayIndex: getTodayIndex(),
    scope: records.length ? '本周' : '模板预览',
    unit: primary?.unit || '条',
    currency: false,
    isDuration: isDurationFact(primary),
  }
}

// 兼容旧 API：返回 [{ label, value, pct }]，方便 detailAdapters 透传
export function getTrendItems(store, domain) {
  const trend = getTrend(store, domain)
  const max = Math.max(...trend.values, 1)
  return trend.values.map((value, index) => ({
    label: trend.labels[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
}

export function getTrendScope(store, domain) {
  const records = getDomainRecords(store, domain)
  return records.length ? '本周' : '模板预览'
}

// ──────────────────────────────────────────────────────────────────
// getDistribution
// ──────────────────────────────────────────────────────────────────
export function getDistribution(store, domain) {
  const schema = getDomainSchema(domain.id)
  const display = getDomainDisplay(domain.id)
  const records = getDomainRecords(store, domain)
  const primary = getPrimaryFact(schema, display)
  const dim = getPrimaryDimension(schema, display)

  if (!dim) return []

  // 优先按主 fact 求和（更有信息量），其次按数量
  if (primary) {
    // 时长类：先把每条记录的 fact 值统一为分钟，再 groupSum
    if (isDurationFact(primary)) {
      const grouped = new Map()
      records.forEach(r => {
        const dimVal = pickPayloadValue(r, dim.key, '其他') || '其他'
        const name = String(dimVal)
        if (!grouped.has(name)) grouped.set(name, { name, sum: 0, count: 0 })
        const bucket = grouped.get(name)
        bucket.sum += extractFactValue(r, primary)
        bucket.count += 1
      })
      const sorted = Array.from(grouped.values()).sort((a, b) => b.sum - a.sum).slice(0, 6)
      const max = sorted[0]?.sum || 1
      return sorted.map(g => ({
        name: g.name,
        value: g.sum,
        pct: Math.round((g.sum / max) * 100),
        display: formatDuration(g.sum),
      }))
    }

    const groups = groupSumByPayloadKey(records, dim.key, primary.key)
    return toDistributionItems(groups, 'sum', { unit: primary.unit, maxCount: 6 })
  }

  const groups = groupByPayloadKey(records, dim.key)
  return toDistributionItems(groups, 'count', { unit: '条', maxCount: 6 })
}

// 兼容旧 API：返回 [{ name, amount, pct, display }]
export function getDimensionItems(store, domain) {
  return getDistribution(store, domain).map(item => ({
    name: item.name,
    amount: item.value,
    pct: item.pct,
    display: item.display,
  }))
}

// ──────────────────────────────────────────────────────────────────
// getRecentRecords
// ──────────────────────────────────────────────────────────────────
export function getRecentRecords(store, domain, limit = 8) {
  const schema = getDomainSchema(domain.id)
  const display = getDomainDisplay(domain.id)
  const records = getDomainRecords(store, domain)
  const primary = getPrimaryFact(schema, display)
  const dim = getPrimaryDimension(schema, display)

  return records.slice(0, limit).map(item => {
    const primaryVal = primary ? extractFactValue(item, primary) : null
    const dimVal = dim ? pickPayloadValue(item, dim.key, '') : ''

    // 标题：title > display.title_field > primary_dimension > 域名
    let title = item.title
    if (!title && display?.title_field) title = pickPayloadValue(item, display.title_field, '')
    if (!title) title = dimVal
    if (!title) title = domain.name

    // 副标题：summary > "维度·主指标"
    let subtitle = item.summary
    if (!subtitle) {
      const parts = []
      if (dimVal) parts.push(String(dimVal))
      if (primary && primaryVal) parts.push(formatFactValue(primaryVal, primary))
      subtitle = parts.join(' · ') || '已记录'
    }

    // 值：主 fact 数值
    let value = '已记录'
    if (primary && primaryVal) {
      value = formatFactValue(primaryVal, primary)
    }

    return {
      id: item.id,
      kind: 'universal',
      raw: item,
      icon: domain.shortName?.slice(0, 1) || '·',
      title,
      subtitle,
      value,
      date: formatDateTimeLabel(item.occurredAt || item.createdAt),
    }
  })
}

// ──────────────────────────────────────────────────────────────────
// 默认导出：聚合接口
// ──────────────────────────────────────────────────────────────────
export default {
  getMetricItems,
  getTrend,
  getTrendItems,
  getTrendScope,
  getDistribution,
  getDimensionItems,
  getRecentRecords,
}
