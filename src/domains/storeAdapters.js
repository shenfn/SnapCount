import { incomeCatMap } from '../utils/helpers'
import { getSystemDomainLabel } from './registry'

export function buildTodaySummary({ bills, incomeRecords, dataRecords, stagingRecords, todayKey }) {
  const todayBills = bills.filter(b => b.status === 'done' && b.dateRaw === todayKey)
  const todayPendingBills = bills.filter(b => b.status === 'pending' && b.dateRaw === todayKey)
  const expenseByPlatform = {}

  todayBills.forEach(bill => {
    const platform = bill.platform && bill.platform !== '?' ? bill.platform : '其他'
    expenseByPlatform[platform] = (expenseByPlatform[platform] || 0) + 1
  })

  const todaySport = filterDataRecordsByDate(dataRecords, 'sport', todayKey)
  const todaySleep = filterDataRecordsByDate(dataRecords, 'sleep', todayKey)
  const todayFood = filterDataRecordsByDate(dataRecords, 'food', todayKey)
  const todayIncome = incomeRecords.filter(record => record.dateRaw === todayKey)
  const todayStaging = stagingRecords.filter(record => (record.occurredAt || record.createdAt || '').slice(0, 10) === todayKey)

  const pendingExpenseTotal = todayPendingBills.reduce((sum, bill) => sum + (bill.amount || 0), 0)
  const todayCalorieTotal = todayFood.reduce((sum, record) => sum + (Number(record.payload?.total_calorie_kcal) || 0), 0)

  return {
    expenseTotal: todayBills.reduce((sum, bill) => sum + bill.amount, 0),
    expenseCount: todayBills.length,
    expenseByPlatform,
    pendingExpenseTotal,
    pendingExpenseCount: todayPendingBills.length,
    incomeTotal: todayIncome.reduce((sum, record) => sum + record.amount, 0),
    incomeCount: todayIncome.length,
    sportItems: todaySport.map(record => ({
      title: record.title || getSystemDomainLabel('sport', '运动'),
      summary: record.summary,
      payload: record.payload,
    })),
    sleepItems: todaySleep.map(record => ({
      title: record.title || getSystemDomainLabel('sleep', '睡眠'),
      summary: record.summary,
      payload: record.payload,
    })),
    foodItems: todayFood.map(record => ({
      title: record.title || getSystemDomainLabel('food', '饮食'),
      summary: record.summary,
      payload: record.payload,
      mealType: record.payload?.meal_type,
      calories: Number(record.payload?.total_calorie_kcal) || 0,
    })),
    foodCalorieTotal: Math.round(todayCalorieTotal),
    foodCount: todayFood.length,
    stagingCount: todayStaging.length,
    isEmpty: todayBills.length === 0
      && todayPendingBills.length === 0
      && todaySport.length === 0
      && todaySleep.length === 0
      && todayFood.length === 0
      && todayIncome.length === 0
      && todayStaging.length === 0,
  }
}

export function buildHomeTimeline({ stagingRecords, bills, incomeRecords, dataRecords, domains }) {
  const stagingItems = stagingRecords.slice(0, 8).map(item => ({
    id: `staging-${item.id}`,
    kind: 'staging',
    title: item.domainName || '待处理截图',
    subtitle: item.summary,
    amountLabel: item.recordType === 'income' ? '+ 待确认' : item.recordType === 'expense' ? '- 待确认' : '待分类',
    dateLabel: item.occurredAt || item.createdAt,
    dateRaw: (item.occurredAt || item.createdAt || '').slice(0, 10),
    occurredTime: item.occurredAt,
    uploadTime: item.createdAt,
    imageUrl: item.imageUrl,
    color: item.status === 'ai_error' ? '#B91C1C' : '#B45309',
    raw: item,
  }))

  const expenseItems = bills.slice(0, 15).map(item => ({
    id: `expense-${item.id}`,
    kind: 'expense',
    title: item.name,
    subtitle: `${item.platform || '?'} · ${item.cat || '?'}`,
    amountLabel: `-¥${item.amount.toFixed(2)}`,
    dateLabel: item.createdAt,
    dateRaw: item.dateRaw,
    occurredTime: `${item.dateRaw}${item.time ? ' ' + item.time : ''}`,
    uploadTime: item.createdAt,
    imageUrl: null,
    color: '#C2410C',
    raw: item,
  }))

  const incomeItems = incomeRecords.slice(0, 15).map(item => ({
    id: `income-${item.id}`,
    kind: 'income',
    title: item.source || incomeCatMap[item.cat]?.label || '收入',
    subtitle: incomeCatMap[item.cat]?.label || getSystemDomainLabel('income'),
    amountLabel: `+¥${item.amount.toFixed(2)}`,
    dateLabel: item.createdAt,
    dateRaw: item.dateRaw,
    occurredTime: item.dateRaw,
    uploadTime: item.createdAt,
    imageUrl: null,
    color: '#1565C0',
    raw: item,
  }))

  const universalItems = dataRecords.slice(0, 12).map(item => {
    const domain = domains.find(domainItem => domainItem.id === item.domainKey)
    return {
      id: `universal-${item.id}`,
      kind: 'universal',
      title: item.title || domain?.name || '通用记录',
      subtitle: item.summary || domain?.description || '通用数据域记录',
      amountLabel: domain?.shortName || '记录',
      dateLabel: item.occurredAt || item.createdAt,
      dateRaw: (item.occurredAt || item.createdAt || '').slice(0, 10),
      occurredTime: item.occurredAt,
      uploadTime: item.createdAt,
      imageUrl: null,
      color: domain?.color || '#2D6A4F',
      raw: item,
    }
  })

  return [...stagingItems, ...expenseItems, ...incomeItems, ...universalItems]
    .sort((a, b) => (b.dateLabel || '').localeCompare(a.dateLabel || ''))
    .slice(0, 25)
}

export function buildUniversalRecordTitle(domainKey, payload, record) {
  if (domainKey === 'sport') return payload.sport_type || payload.activity_type || getSystemDomainLabel('sport')
  if (domainKey === 'sleep') return payload.quality_level || getSystemDomainLabel('sleep')
  if (domainKey === 'reading') return payload.book_name || payload.title || getSystemDomainLabel('reading')
  if (domainKey === 'food') {
    const dishes = Array.isArray(payload.dishes) ? payload.dishes : []
    return payload.title || dishes[0]?.name || getSystemDomainLabel('food')
  }
  if (domainKey === 'wallet') return payload.account_name || payload.title || getSystemDomainLabel('wallet')
  return record.domainName || '通用记录'
}

function filterDataRecordsByDate(dataRecords, domainKey, dateKey) {
  return dataRecords.filter(record => record.domainKey === domainKey && (record.occurredAt || '').slice(0, 10) === dateKey)
}
