// ════════════════════════════════════════════════════════════════════
// expenseAdapter：消费记账域的特化 adapter
// 数据源：store.doneBills（来自 transactions 表）
// 保留特化字段映射逻辑，但接口对齐 universalAdapter 协议
// ════════════════════════════════════════════════════════════════════
import { computeWeekData, formatDateTimeLabel } from '../../utils/helpers'
import { WEEK_LABELS_SHORT, getTodayIndex } from '../shared/timeBuckets'
import { formatPlainNumber } from '../shared/aggregations'

function getRecords(store) {
  return store.doneBills.value || []
}

// ──────────────────────────────────────────────────────────────────
export function getMetricItems(store, domain) {
  const records = getRecords(store)
  const total = store.totalExpense.value
  const today = store.todayExpense.value
  const max = records.reduce((m, item) => Math.max(m, item.amount), 0)

  return [
    { label: '本月总额', value: `¥${total.toFixed(0)}`, accent: true },
    { label: '记录数', value: `${records.length}` },
    { label: '今日支出', value: `¥${today.toFixed(0)}` },
    { label: '最高单笔', value: `¥${max.toFixed(0)}` },
  ]
}

export function getTrendItems(store, domain) {
  const values = computeWeekData(store.doneBills.value)
  const max = Math.max(...values, 1)
  return values.map((value, index) => ({
    label: WEEK_LABELS_SHORT[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
}

export function getTrendScope(store, domain) {
  return store.doneBills.value.length ? '本周' : '模板预览'
}

export function getDimensionItems(store, domain) {
  const list = store.doneBills.value.map(item => ({
    name: item.cat && item.cat !== '?' ? item.cat : '其他',
    amount: item.amount,
  }))
  return buildAmountDimension(list, true)
}

export function getRecentRecords(store, domain) {
  return store.doneBills.value.slice(0, 8).map(item => ({
    id: item.id,
    kind: 'expense',
    raw: item,
    icon: '支',
    title: item.name,
    subtitle: `${item.platform || '其他'} · ${item.cat || '其他'}`,
    value: `-¥${item.amount.toFixed(2)}`,
    date: item.createdAt ? formatDateTimeLabel(item.createdAt) : item.date,
  }))
}

// 共享工具：金额维度构建（按金额从大到小，币种格式化）
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
    display: currency ? `¥${Math.round(amount)}` : `${formatPlainNumber(amount)} 条`,
  }))
}

export default {
  getMetricItems,
  getTrendItems,
  getTrendScope,
  getDimensionItems,
  getRecentRecords,
}
