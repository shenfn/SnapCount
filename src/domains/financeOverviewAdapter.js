import { formatCurrency } from '../utils/format'

const DAY_LABELS = ['一', '二', '三', '四', '五', '六', '日']

export function buildFinanceOverview({ bills = [], incomeRecords = [], dataRecords = [], accounts = [], repaymentCycles = [], todayKey = localDateKey(new Date()) }) {
  const walletSnapshots = latestWalletSnapshots(dataRecords.filter(item => item.domainKey === 'wallet'))
  const cashSnapshots = walletSnapshots.filter(item => item.payload?.record_kind === 'cash_snapshot')
  const liabilitySnapshots = walletSnapshots.filter(item => item.payload?.record_kind === 'liability_snapshot' && item.payload?.status !== 'paid')

  const activeAccounts = accounts.filter(item => !item.isArchived)
  const assetAccounts = activeAccounts.filter(item => !isLiabilityAccount(item))
  const liabilityAccounts = activeAccounts.filter(isLiabilityAccount)
  const accountAvailableCash = assetAccounts.reduce((sum, item) => sum + Number(item.currentBalance || 0), 0)
  const accountLiabilityTotal = liabilityAccounts.reduce((sum, item) => sum + Number(item.currentBalance || 0), 0)

  const availableCash = activeAccounts.length
    ? accountAvailableCash
    : cashSnapshots.reduce((sum, item) => sum + amountOf(item), 0)
  const liabilityTotal = activeAccounts.length
    ? accountLiabilityTotal
    : liabilitySnapshots.reduce((sum, item) => sum + amountOf(item), 0)
  const netWorthEstimate = availableCash - liabilityTotal
  const nearestLiability = pickNearestRepaymentCycle(repaymentCycles, liabilityAccounts, todayKey)
    || pickNearestLiability(liabilitySnapshots, todayKey)

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
    hasWalletSnapshot: walletSnapshots.length > 0 || activeAccounts.length > 0,
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

function pickNearestRepaymentCycle(cycles, accounts, todayKey) {
  const accountMap = new Map((accounts || []).map(account => [account.id, account]))
  const openStatuses = new Set(['pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'minimum_paid'])
  const enriched = (cycles || [])
    .filter(cycle => openStatuses.has(cycle.status))
    .filter(cycle => {
      if (cycle.status === 'historical_unconfirmed' || cycle.status === 'carried_over') return false
      if (cycle.status === 'partial_paid' || cycle.status === 'minimum_paid') return true
      if (!cycle.dueDate) return false
      return cycle.dueDate >= todayKey
    })
    .map(cycle => {
      const account = accountMap.get(cycle.accountId)
      const amount = Number(cycle.remainingAmount || cycle.statementAmount || account?.currentBalance || 0)
      return {
        id: cycle.id,
        accountName: account?.name || '待还款',
        amount,
        dueDate: cycle.dueDate || null,
        billDay: account?.paymentDueDay || null,
        statementDay: account?.billDay || null,
        cycleMonth: cycle.cycleMonth || null,
        status: normalizeCycleStatus(cycle, cycle.dueDate),
        autoDebitAccountId: cycle.autoDebitAccountId || account?.autoDebitAccountId || null,
        autoDebitAccountName: accountNameById(accounts, cycle.autoDebitAccountId || account?.autoDebitAccountId),
        autoDebitPrompt: shouldPromptAutoDebit(cycle, account, todayKey),
        raw: cycle,
        rawType: 'repayment_cycle',
        account,
      }
    })
    .filter(item => item.amount > 0)
    .sort((a, b) => String(a.dueDate || '9999-99-99').localeCompare(String(b.dueDate || '9999-99-99')) || b.amount - a.amount)
  return enriched[0] || null
}

function accountNameById(accounts, id) {
  if (!id) return ''
  const account = (accounts || []).find(item => item.id === id)
  return account?.name || account?.institution || '扣款账户'
}

function shouldPromptAutoDebit(cycle, account, todayKey) {
  const autoDebitAccountId = cycle?.autoDebitAccountId || account?.autoDebitAccountId
  if (!autoDebitAccountId || !cycle?.dueDate) return false
  if (!['pending', 'due_today', 'overdue_unconfirmed', 'partial_paid', 'minimum_paid'].includes(cycle.status)) return false
  const days = daysBetween(todayKey, cycle.dueDate)
  return days === 0 || days === 1
}

function daysBetween(todayKey, targetKey) {
  const today = new Date(`${todayKey}T00:00:00`)
  const target = new Date(`${targetKey}T00:00:00`)
  return Math.round((today - target) / 86400000)
}

function normalizeCycleStatus(cycle, dueDate) {
  if (['partial_paid', 'minimum_paid', 'carried_over', 'historical_unconfirmed'].includes(cycle.status)) return cycle.status
  if (cycle.status === 'paid' || cycle.status === 'ignored' || cycle.status === 'reconciled') return cycle.status
  return buildDueStatus(dueDate)
}

function isLiabilityAccount(account) {
  return account?.type === 'credit_card' || account?.type === 'credit_line'
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

function pickNearestLiability(records, today = localDateKey(new Date())) {
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
  return enriched
    .filter(item => item.dueDate && item.dueDate >= today)
    .sort((a, b) => String(a.dueDate || '9999-99-99').localeCompare(String(b.dueDate || '9999-99-99')))[0] || null
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

function buildDueStatus(dueDate) {
  if (!dueDate) return 'missing_due_day'
  const today = localDateKey(new Date())
  if (dueDate < today) return 'overdue_unconfirmed'
  if (dueDate === today) return 'due_today'
  return 'upcoming'
}

function localDateKey(date) {
  return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`
}
