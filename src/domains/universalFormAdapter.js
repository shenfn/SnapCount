import { localDateKeyOf } from '../utils/helpers'

export function resetUniversalModal(modal, domainKey, meta, today) {
  modal.open = true
  modal.mode = 'create'
  modal.id = null
  modal.domainKey = domainKey

  for (const field of meta.formFields || []) {
    modal[field.model] = field.defaultValue ?? ''
  }

  // Keep compatibility with the current fixed modal state shape.
  if (!('title' in modal)) modal.title = ''
  if (!('primaryValue' in modal)) modal.primaryValue = ''
  if (!('dimension' in modal)) modal.dimension = ''
  if (!('note' in modal)) modal.note = ''

  modal.date = today
  modal.time = ''
  modal.imagePath = null
  modal.imageUrl = null
  modal.imageLoadError = false
  modal.originalPayload = null
}

function timePartOf(value) {
  if (!value || typeof value !== 'string') return ''
  return value.slice(11, 16)
}

function buildLocalDateTime(date, time) {
  if (!date || !time) return null
  return `${date}T${time}:00+08:00`
}

function normalizeSleepStartAt(startAt, wakeAt) {
  if (!startAt || !wakeAt) return startAt
  const startMs = Date.parse(startAt)
  const wakeMs = Date.parse(wakeAt)
  if (Number.isNaN(startMs) || Number.isNaN(wakeMs) || startMs <= wakeMs) return startAt
  return new Date(startMs - 24 * 60 * 60 * 1000).toISOString()
}

export function hydrateUniversalModalFromRecord(modal, record, meta) {
  const payload = record.payload || {}

  modal.open = true
  modal.mode = 'edit'
  modal.id = record.id
  modal.domainKey = record.domainKey

  for (const field of meta.formFields || []) {
    modal[field.model] = getInitialFieldValue(field, record, payload, meta)
  }

  modal.title = record.title || ''
  modal.primaryValue = readPrimaryValue(payload, meta)
  modal.dimension = payload[meta.dimensionKey] || modal.dimension || ''
  modal.note = record.summary || payload.note || ''
  modal.date = localDateKeyOf(record.occurredAt || record.createdAt || new Date())
  modal.time = (record.occurredAt || '').slice(11, 16) || ''
  modal.originalPayload = { ...payload }
  if (record.domainKey === 'sleep') {
    modal.sleepStartTime = timePartOf(payload.sleep_start_at)
    modal.wakeTime = timePartOf(payload.wake_at || record.occurredAt)
  }
  modal.imagePath = record.imagePath || null
}

// 读取主指标值；duration 类双兼容：sleep_minutes 不存在时 fallback 到 sleep_hours×60
function readPrimaryValue(payload, meta) {
  if (payload[meta.primaryKey] != null) return String(payload[meta.primaryKey])
  if (meta.primaryUnit !== 'duration') return ''
  // 时长类双兼容
  if (meta.primaryKey === 'sleep_minutes' && payload.sleep_hours != null) {
    return String(Math.round(Number(payload.sleep_hours) * 60))
  }
  return ''
}

// 各类主指标的合理上限（硬约束，超过则拒绝保存）
const PRIMARY_LIMITS = {
  duration: { max: 1440, hint: '单次时长不应超过 24 小时（1440 分钟）' },        // 1 天
  currency: { max: 1000000, hint: '单笔金额不应超过 100 万' },
  default: { max: 99999, hint: '数值过大，请检查是否填错' },
}

function getPrimaryLimit(meta) {
  return PRIMARY_LIMITS[meta.primaryUnit] || PRIMARY_LIMITS.default
}

export function validateUniversalModal(modal, meta) {
  const primary = parseFloat(modal.primaryValue)
  if (!primary || primary <= 0) {
    return `请输入有效${meta.primaryLabel || '数值'}`
  }
  const limit = getPrimaryLimit(meta)
  if (primary > limit.max) {
    return limit.hint
  }

  for (const field of meta.formFields || []) {
    if (!field.required) continue
    const value = modal[field.model]
    if (value == null || String(value).trim() === '') {
      return field.type === 'date' ? '请选择日期' : `请填写${field.label.replace('（可选）', '')}`
    }
  }

  return ''
}

export function buildUniversalRecordDraft(modal, meta) {
  const primary = parseFloat(modal.primaryValue)
  const dimensionValue = String(modal.dimension || '').trim()
  const noteValue = String(modal.note || '').trim()
  const title = String(modal.title || '').trim() || dimensionValue || meta.defaultTitle
  const wakeAt = modal.domainKey === 'sleep' ? buildLocalDateTime(modal.date, modal.wakeTime) : null
  const sleepStartAt = modal.domainKey === 'sleep' ? normalizeSleepStartAt(buildLocalDateTime(modal.date, modal.sleepStartTime), wakeAt) : null
  const occurredAt = wakeAt || `${modal.date}T${(modal.time ? modal.time + ':00' : '12:00:00')}+08:00`

  const payload = {
    ...(modal.originalPayload || {}),
    [meta.primaryKey]: primary,
    [meta.dimensionKey]: dimensionValue,
    note: noteValue || null,
    source_app: 'manual',
  }

  for (const field of meta.formFields || []) {
    if (['title', 'primaryValue', 'dimension', 'note', 'date', 'time', 'sleepStartTime', 'wakeTime'].includes(field.model)) continue
    const raw = modal[field.model]
    const value = normalizeExtraFieldValue(raw, field)
    if (value !== undefined) payload[toPayloadKey(field.model)] = value
  }

  if (modal.domainKey === 'sleep') {
    payload.sleep_minutes = Math.round(primary)
    payload.sleep_hours = Math.round((primary / 60) * 100) / 100
    payload.sleep_start_at = sleepStartAt
    payload.wake_at = wakeAt
  }

  return {
    title,
    occurredAt,
    summary: noteValue || `${meta.dimensionLabel}：${dimensionValue}`,
    payload,
  }
}

function getInitialFieldValue(field, record, payload, meta) {
  if (field.model === 'title') return record.title || ''
  if (field.model === 'primaryValue') return readPrimaryValue(payload, meta)
  if (field.model === 'dimension') return payload[meta.dimensionKey] || field.defaultValue || ''
  if (field.model === 'note') return record.summary || payload.note || ''
  if (field.model === 'date') return localDateKeyOf(record.occurredAt || record.createdAt || new Date())
  if (field.model === 'time') return (record.occurredAt || '').slice(11, 16) || ''
  const payloadValue = payload[toPayloadKey(field.model)]
  return payloadValue ?? field.defaultValue ?? ''
}

function toPayloadKey(model) {
  return String(model || '').replace(/[A-Z]/g, m => '_' + m.toLowerCase())
}

function normalizeExtraFieldValue(raw, field) {
  if (raw == null || raw === '') return field.defaultValue ?? undefined
  if (field.type === 'number') {
    const n = Number(raw)
    return Number.isFinite(n) ? n : undefined
  }
  return String(raw).trim()
}
