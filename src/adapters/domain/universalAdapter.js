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
} from '../shared/aggregations'
import {
  bucketByWeek,
  getTodayIndex,
  WEEK_LABELS_SHORT,
} from '../shared/timeBuckets'
import { formatDateTimeLabel } from '../../utils/helpers'

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

  const total = sumByPayloadKey(records, primary.key)
  const max = maxByPayloadKey(records, primary.key)
  const avg = avgByPayloadKey(records, primary.key)

  return [
    {
      label: `本月总${primary.label}`,
      value: formatWithUnit(total, primary.unit),
      accent: true,
    },
    { label: '记录数', value: `${records.length}` },
    { label: `最高单次`, value: formatWithUnit(max, primary.unit) },
    { label: `平均`, value: formatWithUnit(avg, primary.unit) },
  ]
}

// ──────────────────────────────────────────────────────────────────
// getTrend
// ──────────────────────────────────────────────────────────────────
export function getTrend(store, domain) {
  const schema = getDomainSchema(domain.id)
  const display = getDomainDisplay(domain.id)
  const records = getDomainRecords(store, domain)
  const primary = getPrimaryFact(schema, display)

  // 累加主 fact；如无主 fact 则按记录数计数
  const values = primary
    ? bucketByWeek(records, { timeField: 'occurredAt', factKey: primary.key })
    : bucketByWeek(records, { timeField: 'occurredAt' })

  return {
    values,
    labels: WEEK_LABELS_SHORT,
    todayIndex: getTodayIndex(),
    scope: records.length ? '本周' : '模板预览',
    unit: primary?.unit || '条',
    currency: false,
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
    const primaryVal = primary ? pickPayloadValue(item, primary.key, 0) : null
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
      if (primary && primaryVal) parts.push(`${formatPlainNumber(primaryVal)}${primary.unit ? primary.unit : ''}`)
      subtitle = parts.join(' · ') || '已记录'
    }

    // 值：主 fact 数值
    let value = '已记录'
    if (primary && primaryVal) {
      value = formatWithUnit(primaryVal, primary.unit)
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
