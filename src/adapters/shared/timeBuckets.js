// ════════════════════════════════════════════════════════════════════
// 时间分桶工具
// 把 records 按周分桶（周一~周日 = 7 个桶）
// 按 fact 求和（如总时长）或按数量计数
// ════════════════════════════════════════════════════════════════════
import { safeNumber, pickPayloadValue } from './aggregations'

/** 取本周一 00:00 */
function getCurrentMonday() {
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)
  return monday
}

/** 当前是周几（周一=0，周日=6） */
export function getTodayIndex() {
  const today = new Date()
  return today.getDay() === 0 ? 6 : today.getDay() - 1
}

/**
 * 把 records 按周分桶
 * @param {Array} records 数据记录
 * @param {Object} options
 * @param {String} options.timeField  时间字段名，默认 'occurredAt'
 * @param {String} options.factKey    要累加的 fact key；不传则计数
 * @returns {Array<number>} 7 个桶 [周一, 周二, ..., 周日]
 */
export function bucketByWeek(records, { timeField = 'occurredAt', factKey = null } = {}) {
  const result = [0, 0, 0, 0, 0, 0, 0]
  const monday = getCurrentMonday()

  records.forEach(item => {
    const tsRaw = item[timeField] || item.occurredAt || item.createdAt || item.dateRaw
    if (!tsRaw) return
    const d = parseDate(tsRaw)
    if (!d || Number.isNaN(d.getTime())) return
    d.setHours(0, 0, 0, 0)
    const diff = Math.round((d - monday) / 86400000)
    if (diff < 0 || diff >= 7) return

    if (factKey) {
      result[diff] += safeNumber(pickPayloadValue(item, factKey, 0))
    } else {
      result[diff] += 1
    }
  })

  return result
}

function parseDate(input) {
  if (!input) return null
  if (input instanceof Date) return input
  // ISO datetime
  if (typeof input === 'string') {
    if (input.includes('T') || input.includes(' ')) return new Date(input)
    // 纯日期 'YYYY-MM-DD'
    return new Date(input + 'T00:00:00')
  }
  return new Date(input)
}

/** 标准周标签（细短版，用于柱状图） */
export const WEEK_LABELS_SHORT = ['一', '二', '三', '四', '五', '六', '日']

/** 标准周标签（带'周'前缀，用于 tooltip） */
export const WEEK_LABELS_FULL = ['周一', '周二', '周三', '周四', '周五', '周六', '周日']

/** 生成本周每天的"周X M/D"完整标签，用于 tooltip */
export function makeCurrentWeekFullLabels() {
  const monday = getCurrentMonday()
  return Array.from({ length: 7 }, (_, i) => {
    const d = new Date(monday)
    d.setDate(monday.getDate() + i)
    return `${WEEK_LABELS_FULL[i]} ${d.getMonth() + 1}/${d.getDate()}`
  })
}
