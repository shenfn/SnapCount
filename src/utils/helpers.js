/**
 * src/utils/helpers.js
 *
 * 时间相关函数已迁移到 src/lib/time-core/，本文件保留旧签名作为薄壳，
 * 内部走 time-core，禁止再出现裸 new Date(str + 'T00:00:00') 之类的隐式时区代码。
 *
 * 迁移背景：08-01 星之柠案，UTC 时分被拼到北京日期上（详见 docs/time-and-companion-refactor-prd-v0.1.md）。
 */

import {
  DEFAULT_TZ,
  formatDateKey as tcFormatDateKey,
  formatDisplay as tcFormatDisplay,
  formatRelativeDate as tcFormatRelativeDate,
  parseInstant,
  parseLocalYmd,
  toInstant,
  zonedParts,
} from '../lib/time-core/index.js'

/**
 * 获取本地日期键（YYYY-MM-DD）。
 * 兼容旧签名：无参数 = 当前时刻；传 Date = 该 Date 对应本地日期键。
 * 内部走 time-core，用 DEFAULT_TZ 保证一致性。
 */
export function getLocalDateKey(date = new Date()) {
  const instant = date instanceof Date ? date.getTime() : toInstant(date)
  if (instant == null) return ''
  return tcFormatDateKey(instant, DEFAULT_TZ)
}

/**
 * 各种输入 → YYYY-MM-DD 日期键（DEFAULT_TZ 视角）。
 */
export function localDateKeyOf(value) {
  if (!value) return ''
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? '' : getLocalDateKey(value)
  }
  const text = String(value)
  if (/^\d{4}-\d{2}-\d{2}$/.test(text)) return text
  const instant = parseInstant(text, DEFAULT_TZ)
  if (instant == null) return text.slice(0, 10)
  return tcFormatDateKey(instant, DEFAULT_TZ)
}

export function buildScopedDayKey(year, month, day = zonedParts(Date.now(), DEFAULT_TZ)?.day ?? 1) {
  const daysInMonth = new Date(year, month, 0).getDate() // 纯日历计算，无时区含义
  const safeDay = Math.min(day, daysInMonth)
  return `${year}-${String(month).padStart(2, '0')}-${String(safeDay).padStart(2, '0')}`
}

export function formatDateKeyLabel(dateKey) {
  const [, month, day] = String(dateKey).split('-')
  return `${Number(month)}月${Number(day)}日`
}

export const incomeCatMap = {
  salary:        { label: '工资',     icon: '💼' },
  bonus:         { label: '奖金',     icon: '🎁' },
  freelance:     { label: '兼职',     icon: '💻' },
  investment:    { label: '投资收益', icon: '📈' },
  reimbursement: { label: '报销',     icon: '🧾' },
  other:         { label: '其他',     icon: '💰' },
}

export const catCodeMap = {
  food: '餐饮', shopping: '购物', transport: '出行',
  entertainment: '娱乐', life: '生活', health: '健康',
  education: '教育', other: '其他',
}

export const payAliasMap = {
  '拼多多先用后付': '先用后付',
  '花呗（先用后付）': '先用后付',
}

/**
 * 旧签名：入参是 "YYYY-MM-DD" 字符串（DB transaction_date）。
 * 返回 "今天/昨天/M月D日"。
 *
 * 内部：把 YMD 按 DEFAULT_TZ 解析为 Instant，再交给 time-core 的 formatRelativeDate。
 * 语义与旧实现等价（旧实现的 `new Date(str + 'T00:00:00')` 隐式吃系统 tz，
 * 在国内环境下和 DEFAULT_TZ=Asia/Shanghai 一致；出海后旧代码会漂移，本版本不会）。
 */
export function formatDate(dateStr) {
  if (!dateStr) return ''
  const instant = parseLocalYmd(String(dateStr), DEFAULT_TZ)
  if (instant == null) return String(dateStr)
  return tcFormatRelativeDate(instant, DEFAULT_TZ)
}

export function formatMonthLabel(y, m) {
  return `${y}年${m}月`
}

export function platformIcon(p) {
  const m = { 美团: '🛵', 微信: '💬', 京东: '📦', 拼多多: '🛍', 淘宝: '🧡', 抖音: '🎵', 支付宝: '💙', 滴滴: '🚗', 线下消费: '🏪', 其他: '💰' }
  return m[p] || '💰'
}

export function platformBg(p) {
  const m = { 美团: '#FFF7ED', 微信: '#ECFDF5', 京东: '#EFF6FF', 拼多多: '#FFF7ED', 淘宝: '#FFF7ED', 抖音: '#F5F3FF', 支付宝: '#EFF6FF', 线下消费: '#F0FDF4', 其他: '#F0EEE9' }
  return m[p] || '#F0EEE9'
}

export function mapTransaction(t) {
  return {
    id: t.id,
    name: t.merchant_name || '未识别商家',
    platform: t.platform || '?',
    payment: t.payment_method || '?',
    cat: t.category || '?',
    amount: Number(t.amount),
    createdAt: t.created_at,
    date: formatDate(t.transaction_date),
    dateRaw: t.transaction_date,
    time: t.transaction_time ? String(t.transaction_time).slice(0, 5) : '',
    status: t.status,
    type: t.type,
    icon: platformIcon(t.platform),
    iconBg: platformBg(t.platform),
    image_url: t.image_url,
    image_path: t.image_url,
    image_hash: t.image_hash,
    transport_type: t.transport_type,
    note: t.note || '',
    source: t.source || 'manual',
    companionMessage: t.companion_message || '',
    aiFeedback: t.ai_feedback || null,
    accountId: t.account_id || null,
    accountConfidence: t.account_confidence ?? null,
    accountInference: t.account_inference || null,
    paymentChannel: t.payment_channel || null,
    fundingSourceLabel: t.funding_source_label || null,
    merchantPlatform: t.merchant_platform || null,
  }
}

/**
 * 按 DEFAULT_TZ 计算本周（周一起）7 天累计消费。
 * dateRaw = "YYYY-MM-DD"，视为 DEFAULT_TZ 本地日期。
 * 原实现用 `new Date(dateRaw + 'T00:00:00')` 隐式取系统 tz；本版本改用日历日 key 比对，
 * 消除时区依赖并保持语义。
 */
export function computeWeekData(bills) {
  const todayKey = getLocalDateKey()
  const [y, m, d] = todayKey.split('-').map(Number)
  // 计算本周一的日历日 key（用日历运算，不涉及 wall-clock 时间转换）
  const jsDate = new Date(y, m - 1, d)
  const dow = jsDate.getDay()
  const mondayOffset = dow === 0 ? -6 : 1 - dow
  const monday = new Date(y, m - 1, d + mondayOffset)
  const weekKeys = []
  for (let i = 0; i < 7; i++) {
    const day = new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)
    weekKeys.push(
      `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`,
    )
  }
  const data = [0, 0, 0, 0, 0, 0, 0]
  bills.forEach(b => {
    if (b.status !== 'done' || !b.dateRaw) return
    const idx = weekKeys.indexOf(b.dateRaw)
    if (idx >= 0) data[idx] += b.amount
  })
  return data
}

/**
 * 旧签名：入参是 timestamp（带 tz 的 ISO 或 epoch）；返回 "M月D日 HH:MM"（DEFAULT_TZ 视角）。
 *
 * 这一次修复对齐 08-01 星之柠案：以前 `new Date(value)` 展示时使用系统 tz，
 * 现在统一走 DEFAULT_TZ；后续接入用户 tz profile 时只需替换 DEFAULT_TZ。
 */
export function formatDateTimeLabel(value) {
  if (!value) return ''
  const instant = toInstant(value) ?? parseInstant(String(value), DEFAULT_TZ)
  if (instant == null) return ''
  return tcFormatDisplay(instant, DEFAULT_TZ)
}
