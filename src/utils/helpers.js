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
  entertainment: '娱乐', life: '生活', health: '生活',
  education: '其他', other: '其他',
}

export const payAliasMap = {
  '拼多多先用后付': '先用后付',
  '花呗（先用后付）': '先用后付',
}

export function formatDate(dateStr) {
  const today = new Date().toISOString().slice(0, 10)
  const yesterday = new Date(Date.now() - 86400000).toISOString().slice(0, 10)
  if (dateStr === today) return '今天'
  if (dateStr === yesterday) return '昨天'
  const d = new Date(dateStr + 'T00:00:00')
  return `${d.getMonth() + 1}月${d.getDate()}日`
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
    date: formatDate(t.transaction_date),
    dateRaw: t.transaction_date,
    time: t.transaction_time ? t.transaction_time.slice(0, 5) : '',
    status: t.status,
    icon: platformIcon(t.platform),
    iconBg: platformBg(t.platform),
    image_url: t.image_url,
    image_path: t.image_url,
    transport_type: t.transport_type,
  }
}

export function computeWeekData(bills) {
  const today = new Date()
  const dow = today.getDay()
  const monday = new Date(today)
  monday.setDate(today.getDate() - (dow === 0 ? 6 : dow - 1))
  monday.setHours(0, 0, 0, 0)
  const data = [0, 0, 0, 0, 0, 0, 0]
  bills.forEach(b => {
    if (b.status !== 'done' || !b.dateRaw) return
    const d = new Date(b.dateRaw + 'T00:00:00')
    const diff = Math.round((d - monday) / 86400000)
    if (diff >= 0 && diff < 7) data[diff] += b.amount
  })
  return data
}
