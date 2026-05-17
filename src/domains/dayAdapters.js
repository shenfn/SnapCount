import { incomeCatMap } from '../utils/helpers'
import { formatCurrency, formatDuration } from '../utils/format'
import { getSystemDomainLabel } from './registry'

const DAY_NAMES = ['周日', '周一', '周二', '周三', '周四', '周五', '周六']
const DOMAIN_COLORS = {
  expense: '#d45a4c',
  income: '#62b783',
  sleep: '#7460f2',
  sport: '#5b9fe6',
  food: '#df7b86',
  reading: '#b07a43',
  wallet: '#7c3aed',
  staging: '#b45309',
}

export function buildDailyCards({ bills = [], incomeRecords = [], dataRecords = [], stagingRecords = [], year, month }) {
  const days = getMonthDateKeys(year, month)
  return days.map(dateKey => buildDailyCard({ dateKey, bills, incomeRecords, dataRecords, stagingRecords }))
}

export function buildDayRecords({ dateKey, bills = [], incomeRecords = [], dataRecords = [], stagingRecords = [], domains = [] }) {
  const domainMap = new Map(domains.map(domain => [domain.id, domain]))
  const expenseItems = bills
    .filter(item => item.dateRaw === dateKey)
    .map(item => ({
      id: `expense-${item.id}`,
      kind: 'expense',
      domainKey: 'expense',
      icon: '支',
      title: item.name || '支出',
      subtitle: `${item.platform || '其他'} · ${item.cat || '其他'}`,
      value: `-${formatCurrency(item.amount || 0)}`,
      time: item.time || '',
      color: DOMAIN_COLORS.expense,
      raw: item,
    }))

  const incomeItems = incomeRecords
    .filter(item => item.dateRaw === dateKey)
    .map(item => ({
      id: `income-${item.id}`,
      kind: 'income',
      domainKey: 'income',
      icon: '收',
      title: item.source || incomeCatMap[item.cat]?.label || '收入',
      subtitle: incomeCatMap[item.cat]?.label || getSystemDomainLabel('income'),
      value: `+${formatCurrency(item.amount || 0)}`,
      time: item.time || '',
      color: DOMAIN_COLORS.income,
      raw: item,
    }))

  const universalItems = dataRecords
    .filter(item => datePart(item.occurredAt || item.createdAt) === dateKey)
    .map(item => {
      const domain = domainMap.get(item.domainKey)
      const info = universalRecordInfo(item, domain)
      return {
        id: `universal-${item.id}`,
        kind: 'universal',
        domainKey: item.domainKey,
        icon: domain?.shortName?.slice(0, 1) || info.label.slice(0, 1),
        title: item.title || info.title || domain?.name || '记录',
        subtitle: item.summary || info.subtitle || domain?.description || '通用记录',
        value: info.value || domain?.shortName || '已记录',
        time: timePart(item.occurredAt || item.createdAt),
        color: domain?.color || DOMAIN_COLORS[item.domainKey] || '#2d6a4f',
        raw: item,
      }
    })

  const stagingItems = stagingRecords
    .filter(item => datePart(item.occurredAt || item.createdAt) === dateKey)
    .map(item => ({
      id: `staging-${item.id}`,
      kind: 'staging',
      domainKey: 'staging',
      icon: '待',
      title: item.domainName || '待处理截图',
      subtitle: item.summary || '等待处理',
      value: item.recordType === 'income' ? '+ 待确认' : item.recordType === 'expense' ? '- 待确认' : '待分类',
      time: timePart(item.occurredAt || item.createdAt),
      color: item.status === 'ai_error' ? '#b91c1c' : DOMAIN_COLORS.staging,
      raw: item,
    }))

  return [...expenseItems, ...incomeItems, ...universalItems, ...stagingItems]
    .sort((a, b) => timeSortValue(b).localeCompare(timeSortValue(a)))
}

function buildDailyCard({ dateKey, bills, incomeRecords, dataRecords, stagingRecords }) {
  const doneBills = bills.filter(item => item.status === 'done' && item.dateRaw === dateKey)
  const allBills = bills.filter(item => item.dateRaw === dateKey)
  const incomes = incomeRecords.filter(item => item.dateRaw === dateKey)
  const records = dataRecords.filter(item => datePart(item.occurredAt || item.createdAt) === dateKey)
  const staging = stagingRecords.filter(item => datePart(item.occurredAt || item.createdAt) === dateKey)

  const rows = []
  const expenseTotal = doneBills.reduce((sum, item) => sum + Number(item.amount || 0), 0)
  const incomeTotal = incomes.reduce((sum, item) => sum + Number(item.amount || 0), 0)
  if (doneBills.length || allBills.length) rows.push(row('expense', '支出', formatCurrency(expenseTotal, { fractionDigits: 0 })))
  if (incomes.length) rows.push(row('income', '收入', formatCurrency(incomeTotal, { fractionDigits: 0 })))

  const sleepRows = records.filter(item => item.domainKey === 'sleep')
  const sleepMinutes = sleepRows.reduce((sum, item) => sum + readMinutes(item.payload, ['sleep_minutes', 'duration_minutes'], ['sleep_hours']), 0)
  const sleepScore = latestNumber(sleepRows, ['quality_score', 'score'])
  if (sleepRows.length) rows.push(row('sleep', '睡眠', `${formatDuration(sleepMinutes)}${sleepScore ? ` · ${Math.round(sleepScore)}分` : ''}`))

  const sportRows = records.filter(item => item.domainKey === 'sport')
  const sportMinutes = sportRows.reduce((sum, item) => sum + readMinutes(item.payload, ['duration_minutes'], ['duration_hours']), 0)
  if (sportRows.length) rows.push(row('sport', '运动', formatDuration(sportMinutes || sportRows.length)))

  const foodRows = records.filter(item => item.domainKey === 'food')
  const calories = foodRows.reduce((sum, item) => sum + Number(item.payload?.total_calorie_kcal || 0), 0)
  if (foodRows.length) rows.push(row('food', '饮食', `${Math.round(calories)}千卡 · ${foodRows.length}餐`))

  const readingRows = records.filter(item => item.domainKey === 'reading')
  const readingMinutes = readingRows.reduce((sum, item) => sum + readMinutes(item.payload, ['reading_minutes', 'duration_minutes'], ['reading_hours']), 0)
  if (readingRows.length) rows.push(row('reading', '阅读', formatDuration(readingMinutes || readingRows.length)))

  const walletRows = records.filter(item => item.domainKey === 'wallet')
  if (walletRows.length) rows.push(row('wallet', '钱包', `${walletRows.length} 条快照`))
  if (staging.length) rows.push(row('staging', '待处理', `${staging.length} 条`))

  const date = parseDateKey(dateKey)
  return {
    key: dateKey,
    dateKey,
    monthDay: dateKey.slice(5),
    weekday: DAY_NAMES[date.getDay()],
    rows,
    count: doneBills.length + incomes.length + records.length + staging.length,
    isEmpty: rows.length === 0,
  }
}

function row(kind, label, value) {
  return { kind, label, value, color: DOMAIN_COLORS[kind] || '#2d6a4f' }
}

function universalRecordInfo(item, domain) {
  const payload = item.payload || {}
  if (item.domainKey === 'sleep') {
    const minutes = readMinutes(payload, ['sleep_minutes', 'duration_minutes'], ['sleep_hours'])
    const score = Number(payload.quality_score || payload.score || 0)
    return { label: '睡眠', title: item.title || '睡眠记录', subtitle: payload.quality_level || '', value: `${formatDuration(minutes)}${score ? ` · ${Math.round(score)}分` : ''}` }
  }
  if (item.domainKey === 'sport') {
    const minutes = readMinutes(payload, ['duration_minutes'], ['duration_hours'])
    return { label: '运动', title: item.title || payload.sport_type || '运动记录', subtitle: payload.sport_type || '', value: formatDuration(minutes) }
  }
  if (item.domainKey === 'food') {
    const calories = Number(payload.total_calorie_kcal || 0)
    return { label: '饮食', title: item.title || payload.meal_type || '饮食记录', subtitle: payload.meal_type || '', value: calories ? `${Math.round(calories)}千卡` : '已记录' }
  }
  if (item.domainKey === 'reading') {
    const minutes = readMinutes(payload, ['reading_minutes', 'duration_minutes'], ['reading_hours'])
    return { label: '阅读', title: item.title || payload.book_name || '阅读记录', subtitle: payload.book_name || '', value: formatDuration(minutes) }
  }
  if (item.domainKey === 'wallet') {
    const isLiability = payload.record_kind === 'liability_snapshot'
    const amount = Number(payload.amount || 0)
    return { label: '钱包', title: item.title || payload.account_name || '钱包快照', subtitle: payload.account_type || '', value: `${isLiability ? '待还' : '余额'} ${formatCurrency(amount)}` }
  }
  return { label: domain?.shortName || '记录', title: item.title || domain?.name || '记录', subtitle: item.summary || '', value: domain?.shortName || '已记录' }
}

function getMonthDateKeys(year, month) {
  const lastDay = new Date(year, month, 0).getDate()
  const todayKey = localDateKey(new Date())
  const result = []
  for (let day = lastDay; day >= 1; day -= 1) {
    const key = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    if (key <= todayKey || !isCurrentMonth(year, month)) result.push(key)
  }
  return result
}

function isCurrentMonth(year, month) {
  const now = new Date()
  return now.getFullYear() === year && now.getMonth() + 1 === month
}

function localDateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}

function parseDateKey(dateKey) {
  const d = new Date(`${dateKey}T00:00:00`)
  return Number.isNaN(d.getTime()) ? new Date() : d
}

function datePart(value) {
  return value ? String(value).slice(0, 10) : ''
}

function timePart(value) {
  if (!value) return ''
  const text = String(value)
  if (text.includes('T')) return text.split('T')[1].slice(0, 5)
  if (/^\d{2}:\d{2}/.test(text)) return text.slice(0, 5)
  return ''
}

function timeSortValue(item) {
  return item.time || '12:00'
}

function readMinutes(payload, minuteKeys, hourKeys = []) {
  if (!payload) return 0
  for (const key of minuteKeys) {
    const n = Number(payload[key])
    if (Number.isFinite(n) && n > 0) return n
  }
  for (const key of hourKeys) {
    const n = Number(payload[key])
    if (Number.isFinite(n) && n > 0) return n * 60
  }
  return 0
}

function latestNumber(records, keys) {
  for (const record of records) {
    for (const key of keys) {
      const n = Number(record.payload?.[key])
      if (Number.isFinite(n) && n > 0) return n
    }
  }
  return 0
}
