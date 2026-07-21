import { payAliasMap, platformIcon } from '../utils/helpers.js'
import {
  EXPENSE_CATEGORY_DEFINITIONS,
  expenseCategoryLabel,
  normalizeExpenseCategory,
} from './expenseCategories.js'

// Starter values are fallback suggestions for new users, never validation allowlists.
const STARTER_PLATFORM_VALUES = Object.freeze([
  '美团', '微信', '线下消费', '京东', '拼多多', '淘宝', '抖音', '支付宝',
])

const STARTER_PAYMENT_VALUES = Object.freeze([
  '微信支付', '花呗', '支付宝', '银行卡', '京东白条', '美团月付', '先用后付',
])

const PAYMENT_ICONS = Object.freeze({
  微信支付: '💚',
  花呗: '🔵',
  支付宝: '🔷',
  银行卡: '💳',
  京东白条: '🟡',
  美团月付: '🔴',
  先用后付: '⚡',
})

const CATEGORY_ICONS = new Map(
  EXPENSE_CATEGORY_DEFINITIONS.map(item => [item.label, item.icon]),
)

const STARTER_VALUES = Object.freeze({
  platform: STARTER_PLATFORM_VALUES,
  category: Object.freeze(EXPENSE_CATEGORY_DEFINITIONS.map(item => item.label)),
  payment: STARTER_PAYMENT_VALUES,
})

function cleanText(value) {
  const text = String(value ?? '').trim()
  return !text || text === '?' ? '' : text
}

export function normalizeFinanceOptionValue(kind, rawValue) {
  const value = cleanText(rawValue)
  if (!value) return ''
  if (kind === 'category') {
    const code = normalizeExpenseCategory(value)
    return code ? expenseCategoryLabel(code, '') : ''
  }
  if (kind === 'payment') return payAliasMap[value] || value
  return value
}

function optionIcon(kind, value) {
  if (kind === 'platform') {
    const icon = platformIcon(value)
    return icon === '💰' && value !== '其他' ? '' : icon
  }
  if (kind === 'category') return CATEGORY_ICONS.get(value) || ''
  return PAYMENT_ICONS[value] || ''
}

export function buildAdaptiveFinanceOptions({
  kind,
  currentValue,
  vocabulary = [],
  limit = 12,
}) {
  const stats = new Map()

  function register(rawValue, source, recency = 0, usageCount = 0) {
    const value = normalizeFinanceOptionValue(kind, rawValue)
    if (!value) return
    const existing = stats.get(value) || {
      value,
      count: 0,
      recency: 0,
      isCurrent: false,
      starterOrder: Number.MAX_SAFE_INTEGER,
    }
    if (source === 'vocabulary') {
      existing.count = Math.max(existing.count, Math.max(0, Number(usageCount || 0)))
      existing.recency = Math.max(existing.recency, recency)
    } else if (source === 'current') {
      existing.isCurrent = true
    } else if (source === 'starter') {
      existing.starterOrder = Math.min(existing.starterOrder, recency)
    }
    stats.set(value, existing)
  }

  register(currentValue, 'current')
  vocabulary
    .filter(item => item?.kind === kind && (item.status || 'active') === 'active')
    .forEach(item => {
      register(
        item.displayName || item.display_name,
        'vocabulary',
        Date.parse(item.lastUsedAt || item.last_used_at || '') || 0,
        item.usageCount ?? item.usage_count,
      )
    })
  ;(STARTER_VALUES[kind] || []).forEach((value, index) => register(value, 'starter', index))

  const frequentValues = new Set(
    [...stats.values()]
      .filter(item => item.count >= 2)
      .sort((left, right) => right.count - left.count || right.recency - left.recency)
      .slice(0, 3)
      .map(item => item.value),
  )

  return [...stats.values()]
    .sort((left, right) => {
      if (left.isCurrent !== right.isCurrent) return left.isCurrent ? -1 : 1
      if (left.count !== right.count) return right.count - left.count
      if (left.recency !== right.recency) return right.recency - left.recency
      return left.starterOrder - right.starterOrder
    })
    .slice(0, Math.max(1, limit))
    .map(item => {
      const icon = optionIcon(kind, item.value)
      return {
        val: item.value,
        label: icon ? `${icon} ${item.value}` : item.value,
        hot: frequentValues.has(item.value),
      }
    })
}
