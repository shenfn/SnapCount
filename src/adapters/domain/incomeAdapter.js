// ════════════════════════════════════════════════════════════════════
// incomeAdapter：收入记录域的特化 adapter
// 数据源：store.incomeRecords / store.recentIncomeRecords（来自 income_records 表）
// 保留特化字段映射，但接口对齐 universalAdapter 协议
// ════════════════════════════════════════════════════════════════════
import { formatDateTimeLabel, incomeCatMap } from '../../utils/helpers'
import { WEEK_LABELS_SHORT } from '../shared/timeBuckets'
import { formatPlainNumber } from '../shared/aggregations'

function getRecords(store) {
  return store.incomeRecords.value || []
}

// ──────────────────────────────────────────────────────────────────
export function getMetricItems(store, domain) {
  const records = getRecords(store)
  const total = store.totalIncome.value
  const net = store.netBalance.value
  const max = records.reduce((m, item) => Math.max(m, item.amount), 0)

  return [
    { label: '本月总额', value: `¥${total.toFixed(2)}`, accent: true },
    { label: '记录数', value: `${records.length}` },
    { label: '月度结余', value: `¥${net.toFixed(2)}` },
    { label: '最高单笔', value: `¥${max.toFixed(2)}` },
  ]
}

export function getTrendItems(store, domain) {
  const values = computeIncomeWeekData(store.incomeRecords.value)
  const max = Math.max(...values, 1)
  return values.map((value, index) => ({
    label: WEEK_LABELS_SHORT[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
}

export function getTrendScope(store, domain) {
  return store.incomeRecords.value.length ? '本周' : '模板预览'
}

export function getDimensionItems(store, domain) {
  const list = store.incomeRecords.value.map(item => ({
    name: incomeCatMap[item.cat]?.label || '其他',
    amount: item.amount,
  }))
  return buildAmountDimension(list, true)
}

export function getRecentRecords(store, domain) {
  return store.recentIncomeRecords.value.slice(0, 8).map(item => ({
    id: item.id,
    kind: 'income',
    raw: item,
    icon: '收',
    title: item.source || incomeCatMap[item.cat]?.label || '收入',
    subtitle: incomeCatMap[item.cat]?.label || '收入记录',
    value: `+¥${item.amount.toFixed(2)}`,
    date: item.createdAt ? formatDateTimeLabel(item.createdAt) : item.date,
  }))
}

// ──────────────────────────────────────────────────────────────────
function computeIncomeWeekData(records) {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)

  records.forEach(item => {
    if (!item.dateRaw) return
    const d = new Date(item.dateRaw + 'T00:00:00')
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += item.amount
  })
  return result
}

function buildAmountDimension(list, currency = true) {
  const grouped = {}
  list.forEach(item => {
    grouped[item.name] = (grouped[item.name] || 0) + Number(item.amount || 0)
  })
  const entries = Object.entries(grouped).sort((a, b) => b[1] - a[1]).slice(0, 6)
  const max = entries[0]?.[1] || 1
  return entries.map(([name, amount]) => ({
    name,
    amount,
    pct: Math.round((amount / max) * 100),
    display: currency ? `¥${amount.toFixed(2)}` : `${formatPlainNumber(amount)} 条`,
  }))
}

export default {
  getMetricItems,
  getTrendItems,
  getTrendScope,
  getDimensionItems,
  getRecentRecords,
}
