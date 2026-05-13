import { computeWeekData, formatDateTimeLabel, incomeCatMap } from '../utils/helpers'

export function getDomainMetricItems(store, domain) {
  if (domain.id === 'expense') {
    const maxBill = store.doneBills.value.reduce((max, item) => Math.max(max, item.amount), 0)
    return [
      { label: '本月总额', value: `¥${store.totalExpense.value.toFixed(0)}` },
      { label: '记录数', value: `${store.doneBills.value.length}` },
      { label: '今日支出', value: `¥${store.todayExpense.value.toFixed(0)}` },
      { label: '最高单笔', value: `¥${maxBill.toFixed(0)}` },
    ]
  }

  if (domain.id === 'income') {
    const maxIncome = store.incomeRecords.value.reduce((max, item) => Math.max(max, item.amount), 0)
    return [
      { label: '本月总额', value: `¥${store.totalIncome.value.toFixed(0)}` },
      { label: '记录数', value: `${store.incomeRecords.value.length}` },
      { label: '月度结余', value: `¥${store.netBalance.value.toFixed(0)}` },
      { label: '最高单笔', value: `¥${maxIncome.toFixed(0)}` },
    ]
  }

  const records = getUniversalRecords(store, domain)
  return [
    { label: '记录数', value: `${records.length}` },
    { label: '模板状态', value: domain.recordCount ? '运行中' : '预留' },
    { label: '入库链路', value: domain.recordCount ? '已接入' : '待接入' },
    { label: '展示组件', value: '已就绪' },
  ]
}

export function getDomainTrendScope(domain) {
  return domain.recordCount ? '本周' : '模板预览'
}

export function getDomainTrendItems(store, domain) {
  const labels = ['一', '二', '三', '四', '五', '六', '日']
  let values = [0, 0, 0, 0, 0, 0, 0]

  if (domain.id === 'expense') values = computeWeekData(store.doneBills.value)
  if (domain.id === 'income') values = computeIncomeWeekData(store)
  if (!['expense', 'income'].includes(domain.id)) values = computeUniversalWeekData(store, domain)

  const max = Math.max(...values, 1)
  return values.map((value, index) => ({
    label: labels[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
}

export function getDomainDimensionItems(store, domain) {
  if (domain.id === 'expense') {
    return buildDimension(store.doneBills.value.map(item => ({
      name: item.cat && item.cat !== '?' ? item.cat : '其他',
      amount: item.amount,
    })))
  }

  if (domain.id === 'income') {
    return buildDimension(store.incomeRecords.value.map(item => ({
      name: incomeCatMap[item.cat]?.label || '其他',
      amount: item.amount,
    })))
  }

  return buildDimension(getUniversalRecords(store, domain).map(item => ({
    name: getUniversalDimensionName(item, domain),
    amount: 1,
  })), false)
}

export function getDomainRecentRecords(store, domain) {
  if (domain.id === 'expense') {
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

  if (domain.id === 'income') {
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

  return getUniversalRecords(store, domain).slice(0, 8).map(item => ({
    id: item.id,
    kind: 'universal',
    raw: item,
    icon: domain.shortName.slice(0, 1),
    title: item.title || domain.name,
    subtitle: item.summary || getUniversalDimensionName(item, domain),
    value: item.occurredAt ? '已归档' : '已记录',
    date: formatDateTimeLabel(item.occurredAt || item.createdAt),
  }))
}

export function getDomainCapabilities(domain) {
  if (domain.recordCount) return ['SummaryMetric', 'TrendLine', 'DimensionBars', 'RecentRecords', 'RecordDetail']
  return ['模板元数据', '空状态展示', '默认指标位', '最近记录位']
}

function getUniversalRecords(store, domain) {
  return store.dataRecords.value
    .filter(item => item.domainKey === domain.id)
    .sort((a, b) => ((b.occurredAt || b.createdAt || '').localeCompare(a.occurredAt || a.createdAt || '')))
}

function computeIncomeWeekData(store) {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)

  store.incomeRecords.value.forEach(item => {
    if (!item.dateRaw) return
    const d = new Date(item.dateRaw + 'T00:00:00')
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += item.amount
  })

  return result
}

function buildDimension(list, currency = true) {
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
    display: currency ? `¥${amount.toFixed(0)}` : `${amount.toFixed(0)} 条`,
  }))
}

function computeUniversalWeekData(store, domain) {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)

  getUniversalRecords(store, domain).forEach(item => {
    const d = new Date(item.occurredAt || item.createdAt)
    if (Number.isNaN(d.getTime())) return
    d.setHours(0, 0, 0, 0)
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += 1
  })

  return result
}

function getUniversalDimensionName(item, domain) {
  const payload = item.payload || {}
  if (domain.id === 'sport') return payload.sport_type || payload.activity_type || payload.source_app || '运动记录'
  if (domain.id === 'sleep') return payload.quality_level || payload.source_app || '睡眠记录'
  if (domain.id === 'reading') return payload.book_name || payload.source_app || '阅读记录'
  return item.title || domain.name
}
