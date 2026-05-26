import { incomeCatMap, localDateKeyOf } from '../utils/helpers'
import { formatDuration, readDurationAsMinutes } from '../utils/format'

export function getRecordDetailFields(store, detailRecord) {
  if (!detailRecord?.raw) return []

  const raw = detailRecord.raw
  if (detailRecord.kind === 'income') {
    return [
      { label: '金额', value: `+¥${Number(raw.amount || 0).toFixed(2)}`, numeric: true },
      { label: '收入类型', value: incomeCatMap[raw.cat]?.label || '其他' },
      { label: '来源名称', value: raw.source || '未填写' },
      { label: '到账日期', value: fmtAbsoluteDate(raw.dateRaw) || raw.date || '--' },
      { label: '备注', value: raw.note || '无', multiline: true },
    ]
  }

  if (detailRecord.kind === 'universal') {
    const payload = raw.payload || {}
    const meta = store.getUniversalDomainMeta(raw.domainKey)
    if (raw.domainKey === 'food') {
      const mealLabelMap = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '加餐' }
      return [
        { label: '标题', value: raw.title || meta.defaultTitle },
        { label: '餐次', value: mealLabelMap[payload.meal_type] || '未分类' },
        { label: '总热量', value: payload.total_calorie_kcal != null ? `${payload.total_calorie_kcal} 千卡（估算）` : '--', numeric: true },
        { label: '菜品数', value: `${Array.isArray(payload.dishes) ? payload.dishes.length : 0} 道` },
        { label: '记录日期', value: fmtAbsoluteDate(raw.occurredAt) || '--' },
        { label: '来源类型', value: raw.source === 'staging' ? '中转站归档' : '截图识别' },
        { label: '估算依据', value: payload.confidence_note || '无', multiline: true },
        { label: '备注', value: payload.note || raw.summary || '无', multiline: true },
      ]
    }

    if (raw.domainKey === 'sleep') {
      const minutes = readDurationAsMinutes({ payload }, { key: 'sleep_minutes' })
      return [
        { label: '标题', value: raw.title || meta.defaultTitle },
        { label: '质量等级', value: payload.quality_level || '未填写' },
        { label: '睡眠时长', value: minutes > 0 ? formatDuration(minutes) : '--', numeric: true },
        { label: '睡眠评分', value: payload.quality_score != null ? `${Math.round(Number(payload.quality_score))}` : '--', numeric: true },
        { label: '入睡时间', value: formatDateTimeShort(payload.sleep_start_at) || '--' },
        { label: '醒来时间', value: formatDateTimeShort(payload.wake_at) || '--' },
        { label: '发生日期', value: fmtAbsoluteDate(raw.occurredAt) || '--' },
        { label: '模板版本', value: raw.domainVersion || '1.0' },
        { label: '来源类型', value: raw.source === 'staging' ? '中转站归档' : '截图识别' },
        { label: '备注', value: payload.note || raw.summary || '无', multiline: true },
      ]
    }

    return [
      { label: '标题', value: raw.title || meta.defaultTitle },
      { label: meta.dimensionLabel, value: payload[meta.dimensionKey] || '未填写' },
      { label: meta.primaryLabel, value: `${Number(payload[meta.primaryKey] || 0).toFixed(2)}`, numeric: true },
      { label: '发生日期', value: fmtAbsoluteDate(raw.occurredAt) || '--' },
      { label: '模板版本', value: raw.domainVersion || '1.0' },
      { label: '来源类型', value: raw.source === 'staging' ? '中转站归档' : '手动录入' },
      { label: '备注', value: payload.note || raw.summary || '无', multiline: true },
    ]
  }

  return [
    { label: '金额', value: `-¥${Number(raw.amount || 0).toFixed(2)}`, numeric: true },
    { label: '商家名称', value: raw.name || '未识别商家' },
    { label: '消费渠道', value: raw.platform || '其他' },
    { label: '消费分类', value: raw.cat || '其他' },
    { label: '支付方式', value: raw.payment || '其他' },
    { label: '消费日期', value: fmtAbsoluteDate(raw.dateRaw) || raw.date || '--' },
    { label: '备注', value: raw.note || '无', multiline: true },
  ]
}

export function getRecordFoodDishes(detailRecord) {
  if (!detailRecord?.raw) return []
  const raw = detailRecord.raw
  if (detailRecord.kind !== 'universal' || raw.domainKey !== 'food') return []
  const dishes = raw.payload?.dishes
  return Array.isArray(dishes) ? dishes : []
}

export function getRecordAiSummary(store, detailRecord, domainLabel) {
  if (!detailRecord?.raw) return '暂无摘要'

  const raw = detailRecord.raw
  if (detailRecord.kind === 'income') {
    const source = raw.source || '未命名来源'
    const cat = incomeCatMap[raw.cat]?.label || '其他收入'
    return `系统记录了一笔${cat}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，来源为 ${source}。`
  }

  if (detailRecord.kind === 'universal') {
    if (raw.domainKey === 'food') {
      return raw.summary || `饮食记录：${raw.title}。`
    }

    const meta = store.getUniversalDomainMeta(raw.domainKey)
    const payload = raw.payload || {}
    if (raw.domainKey === 'sleep') {
      const minutes = readDurationAsMinutes({ payload }, { key: 'sleep_minutes' })
      const score = Number(payload.quality_score || payload.score || 0)
      return `${domainLabel}中记录了“${payload.quality_level || raw.title || domainLabel}”，睡眠时长为 ${minutes > 0 ? formatDuration(minutes) : '--'}。${score ? `评分 ${Math.round(score)}。` : ''}${raw.summary || ''}`
    }
    const dimension = payload[meta.dimensionKey] || raw.title || domainLabel
    const primary = Number(payload[meta.primaryKey] || 0)
    return `${domainLabel}中记录了“${dimension}”，${meta.primaryLabel}为 ${primary.toFixed(2)}。${raw.summary || ''}`
  }

  return `系统记录了一笔支出，商家为 ${raw.name || '未识别商家'}，金额 ${Number(raw.amount || 0).toFixed(2)} 元，渠道 ${raw.platform || '未知'}，分类 ${raw.cat || '未知'}。`
}

function fmtAbsoluteDate(value) {
  if (!value) return null
  const s = localDateKeyOf(value)
  const d = new Date(s + 'T00:00:00+08:00')
  if (Number.isNaN(d.getTime())) return null
  return `${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日`
}

function formatDateTimeShort(value) {
  if (!value) return null
  const d = new Date(value)
  if (Number.isNaN(d.getTime())) return String(value).slice(0, 16)
  return `${d.getMonth() + 1}月${d.getDate()}日 ${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

