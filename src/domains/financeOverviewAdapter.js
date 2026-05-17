import { formatCurrency } from '../utils/format'

const DAY_LABELS = ['一', '二', '三', '四', '五', '六', '日']

export function buildFinanceOverview({ bills = [], incomeRecords = [], dataRecords = [], todayKey = localDateKey(new Date()) }) {
  const walletSnapshots = latestWalletSnapshots(dataRecords.filter(item => item.domainKey === 'wallet'))
  const cashSnapshots = walletSnapshots.filter(item => item.payload?.record_kind === 'cash_snapshot')
  const liabilitySnapshots = walletSnapshots.filter(item => item.payload?.record_kind === 'liability_snapshot' && item.payload?.status !== 'paid')

  const availableCash = cashSnapshots.reduce((sum, item) => sum + amountOf(item), 0)
  const liabilityTotal = liabilitySnapshots.reduce((sum, item) => sum + amountOf(item), 0)
  const netWorthEstimate = availableCash - liabilityTotal
  const nearestLiability = pickNearestLiability(liabilitySnapshots)

  const todayExpense = bills
    .filter(item => item.status === 'done' && item.dateRaw === todayKey)
    .reduce((sum, item) => sum + Number(item.amount || 0), 0)
  const todayIncome = incomeRecords
    .filter(item => item.dateRaw === todayKey)
    .reduce((sum, item) => sum + Number(item.amount || 0), 0)
  const todayNet = todayIncome - todayExpense
  const sevenDayExpenseTrend = buildSevenDayExpenseTrend(bills, todayKey)
  const sevenDayTotal = sevenDayExpenseTrend.reduce((sum, item) => sum + item.amount, 0)
  const maxExpense = Math.max(...sevenDayExpenseTrend.map(item => item.amount), 1)
  const todayTrend = sevenDayExpenseTrend[sevenDayExpenseTrend.length - 1]
  const todayExpenseShare = sevenDayTotal > 0 ? Math.round(todayExpense / sevenDayTotal * 100) : 0

  return {
    availableCash,
    liabilityTotal,
    netWorthEstimate,
    nearestLiability,
    todayExpense,
    todayIncome,
    todayNet,
    todayExpenseShare,
    sevenDayExpenseTrend: sevenDayExpenseTrend.map(item => ({
      ...item,
      pct: Math.max(Math.round(item.amount / maxExpense * 100), item.amount > 0 ? 8 : 3),
    })),
    maxExpenseDay: sevenDayExpenseTrend.reduce((max, item) => item.amount > max.amount ? item : max, { amount: 0, label: '--', dateKey: '' }),
    todayTrend,
    statusLabel: buildStatusLabel({ availableCash, liabilityTotal, netWorthEstimate, nearestLiability }),
    hasWalletSnapshot: walletSnapshots.length > 0,
    display: {
      availableCash: formatCurrency(availableCash, { fractionDigits: 0 }),
      liabilityTotal: formatCurrency(liabilityTotal, { fractionDigits: 0 }),
      netWorthEstimate: formatCurrency(netWorthEstimate, { fractionDigits: 0 }),
      todayExpense: formatCurrency(todayExpense, { fractionDigits: 0 }),
      todayIncome: formatCurrency(todayIncome, { fractionDigits: 0 }),
      todayNet: `${todayNet >= 0 ? '+' : '-'}${formatCurrency(Math.abs(todayNet), { fractionDigits: 0 })}`,
    },
  }
}

function latestWalletSnapshots(records) {
  const map = new Map()
  records.forEach(record => {
    const payload = record.payload || {}
    const key = `${payload.record_kind || ''}:${payload.account_name || ''}:${payload.account_type || ''}`
    const prev = map.get(key)
    const ts = record.occurredAt || record.createdAt || ''
    const prevTs = prev?.occurredAt || prev?.createdAt || ''
    if (!prev || ts >= prevTs) map.set(key, record)
  })
  return Array.from(map.values())
}

function amountOf(record) {
  return Number(record?.payload?.amount || 0)
}

function pickNearestLiability(records) {
  const today = localDateKey(new Date())
  const enriched = records.map(record => {
    const payload = record.payload || {}
    const dueDate = normalizeDueDate(payload.due_date, payload.bill_day, today)
    return {
      id: record.id,
      accountName: payload.account_name || record.title || '待还款',
      amount: amountOf(record),
      dueDate,
      billDay: payload.bill_day || null,
      status: payload.status || 'unpaid',
      raw: record,
    }
  })
  return enriched.sort((a, b) => String(a.dueDate || '9999-99-99').localeCompare(String(b.dueDate || '9999-99-99')))[0] || null
}

function normalizeDueDate(dueDate, billDay, todayKey) {
  if (dueDate && /^\d{4}-\d{2}-\d{2}$/.test(String(dueDate))) return dueDate
  const day = Number(billDay)
  if (!Number.isFinite(day) || day <= 0) return null
  const today = new Date(`${todayKey}T00:00:00`)
  const currentMonthDue = makeDate(today.getFullYear(), today.getMonth() + 1, day)
  if (currentMonthDue >= today) return localDateKey(currentMonthDue)
  return localDateKey(makeDate(today.getFullYear(), today.getMonth() + 2, day))
}

function makeDate(year, month, day) {
  return new Date(year, month - 1, Math.min(day, new Date(year, month, 0).getDate()))
}

function buildSevenDayExpenseTrend(bills, todayKey) {
  const today = new Date(`${todayKey}T00:00:00`)
  return Array.from({ length: 7 }, (_, index) => {
    const d = new Date(today)
    d.setDate(today.getDate() - (6 - index))
    const key = localDateKey(d)
    const amount = bills
      .filter(item => item.status === 'done' && item.dateRaw === key)
      .reduce((sum, item) => sum + Number(item.amount || 0), 0)
    const dayIndex = d.getDay() === 0 ? 6 : d.getDay() - 1
    return { dateKey: key, label: DAY_LABELS[dayIndex], amount }
  })
}

function buildStatusLabel({ availableCash, liabilityTotal, netWorthEstimate, nearestLiability }) {
  if (!availableCash && !liabilityTotal) return '缺少钱包快照'
  if (netWorthEstimate < 0) return '待还压力偏高'
  if (nearestLiability && liabilityTotal > availableCash * 0.5) return '近期需预留还款'
  return '短期现金安全'
}

function localDateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}
