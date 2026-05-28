import { WEEK_LABELS_SHORT } from '../shared/timeBuckets'
import { formatDateTimeLabel } from '../../utils/helpers'
import { accountTitle, formatAccountCurrency, splitAccounts } from './accountAdapter'

function getWalletRecords(store) {
  return store.dataRecords.value
    .filter(item => item.domainKey === 'wallet')
    .sort((a, b) => ((b.occurredAt || b.createdAt || '').localeCompare(a.occurredAt || a.createdAt || '')))
}

function latestSnapshots(records) {
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

function isCash(record) {
  return record?.payload?.record_kind === 'cash_snapshot'
}

function isUnpaidLiability(record) {
  return record?.payload?.record_kind === 'liability_snapshot' && record?.payload?.status !== 'paid'
}

function formatCurrency(value) {
  return `¥ ${Math.round(Number(value || 0))}`
}

function getNextDueLabel(records) {
  const due = records
    .filter(isUnpaidLiability)
    .map(record => ({
      name: record.payload?.account_name || record.title || '待还款',
      amount: amountOf(record),
      dueDate: record.payload?.due_date || null,
      billDay: record.payload?.bill_day || null,
    }))
    .sort((a, b) => String(a.dueDate || '9999-99-99').localeCompare(String(b.dueDate || '9999-99-99')))
  const first = due[0]
  if (!first) return '暂无'
  if (first.dueDate) return `${first.name} ${first.dueDate}`
  if (first.billDay) return `${first.name} 每月${first.billDay}号`
  return first.name
}

export function getMetricItems(store) {
  const accounts = store.accounts?.value || []
  if (accounts.length) {
    const { assets, liabilities } = splitAccounts(accounts)
    const assetTotal = assets.reduce((sum, account) => sum + Number(account.currentBalance || 0), 0)
    const liabilityTotal = liabilities.reduce((sum, account) => sum + Number(account.currentBalance || 0), 0)
    return [
      { label: '资产合计', value: formatAccountCurrency(assetTotal), accent: true },
      { label: '负债合计', value: formatAccountCurrency(liabilityTotal) },
      { label: '净资产', value: formatAccountCurrency(assetTotal - liabilityTotal) },
      { label: '账户数', value: String(accounts.filter(account => !account.isArchived).length) },
    ]
  }

  const snapshots = latestSnapshots(getWalletRecords(store))
  const cashTotal = snapshots.filter(isCash).reduce((sum, record) => sum + amountOf(record), 0)
  const liabilityTotal = snapshots.filter(isUnpaidLiability).reduce((sum, record) => sum + amountOf(record), 0)
  return [
    { label: '可用现金', value: formatCurrency(cashTotal), accent: true },
    { label: '待还款', value: formatCurrency(liabilityTotal) },
    { label: '净额估算', value: formatCurrency(cashTotal - liabilityTotal) },
    { label: '最近还款', value: getNextDueLabel(snapshots) },
  ]
}

export function getTrend(store) {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const monday = new Date()
  const dow = monday.getDay()
  monday.setDate(monday.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)

  getWalletRecords(store).forEach(record => {
    if (!isCash(record)) return
    const ts = record.occurredAt || record.createdAt
    if (!ts) return
    const d = new Date(ts)
    if (Number.isNaN(d.getTime())) return
    d.setHours(0, 0, 0, 0)
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) result[diff] += amountOf(record)
  })

  return {
    values: result,
    labels: WEEK_LABELS_SHORT,
    scope: '本周现金快照',
    unit: '元',
    currency: true,
    isDuration: false,
  }
}

export function getTrendItems(store) {
  const trend = getTrend(store)
  const max = Math.max(...trend.values, 1)
  return trend.values.map((value, index) => ({
    label: trend.labels[index],
    value,
    pct: Math.round((value / max) * 100),
  }))
}

export function getTrendScope() {
  return '本周现金快照'
}

export function getDistribution(store) {
  const snapshots = latestSnapshots(getWalletRecords(store))
  const groups = snapshots.map(record => {
    const payload = record.payload || {}
    const name = payload.account_name || record.title || '其他'
    const value = amountOf(record)
    return {
      name,
      value,
      kind: payload.record_kind,
      display: payload.record_kind === 'liability_snapshot' ? `待还 ¥${value.toFixed(0)}` : `余额 ¥${value.toFixed(0)}`,
    }
  }).sort((a, b) => b.value - a.value).slice(0, 8)
  const max = groups[0]?.value || 1
  return groups.map(item => ({
    ...item,
    pct: Math.round((item.value / max) * 100),
  }))
}

export function getDimensionItems(store) {
  return getDistribution(store).map(item => ({
    name: item.name,
    amount: item.value,
    pct: item.pct,
    display: item.display,
  }))
}

export function getRecentRecords(store, domain, limit = 8) {
  return getWalletRecords(store).slice(0, limit).map(record => {
    const payload = record.payload || {}
    const isLiability = payload.record_kind === 'liability_snapshot'
    const due = payload.due_date ? ` · ${payload.due_date}还` : payload.bill_day ? ` · 每月${payload.bill_day}号还` : ''
    return {
      id: record.id,
      kind: 'universal',
      raw: record,
      icon: isLiability ? '还' : '钱',
      title: record.title || payload.account_name || domain.name,
      subtitle: record.summary || `${payload.account_type || 'wallet'}${due}`,
      value: `${isLiability ? '待还' : '余额'} ¥${amountOf(record).toFixed(2)}`,
      date: formatDateTimeLabel(record.occurredAt || record.createdAt),
    }
  })
}

export function getAccountSections(store) {
  const { assets, liabilities } = splitAccounts(store.accounts?.value || [])
  return [
    {
      key: 'assets',
      title: '资产账户',
      empty: '还没有资产账户，可从余额截图创建',
      items: assets.map(account => ({
        id: account.id,
        title: accountTitle(account),
        subtitle: account.institution || account.type,
        value: formatAccountCurrency(account.currentBalance),
        snapshot: account.snapshotAt ? `最近快照 ${account.snapshotAt.slice(0, 10)}` : '暂无快照',
      })),
    },
    {
      key: 'liabilities',
      title: '待还负债',
      empty: '还没有待还账户，可从花呗/白条截图创建',
      items: liabilities.map(account => ({
        id: account.id,
        title: accountTitle(account),
        subtitle: account.institution || account.type,
        value: formatAccountCurrency(account.currentBalance),
        snapshot: account.snapshotAt ? `最近快照 ${account.snapshotAt.slice(0, 10)}` : '暂无快照',
      })),
    },
  ]
}

export default {
  getMetricItems,
  getTrend,
  getTrendItems,
  getTrendScope,
  getDistribution,
  getDimensionItems,
  getRecentRecords,
  getAccountSections,
}
