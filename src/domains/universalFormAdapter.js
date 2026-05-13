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
  modal.primaryValue = payload[meta.primaryKey] != null ? String(payload[meta.primaryKey]) : ''
  modal.dimension = payload[meta.dimensionKey] || modal.dimension || ''
  modal.note = record.summary || payload.note || ''
  modal.date = (record.occurredAt || record.createdAt || new Date().toISOString()).slice(0, 10)
  modal.time = (record.occurredAt || '').slice(11, 16) || ''
  modal.imagePath = record.imagePath || null
}

export function validateUniversalModal(modal, meta) {
  const primary = parseFloat(modal.primaryValue)
  if (!primary || primary <= 0 || primary > 99999) {
    return '请输入有效数值'
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
  const occurredAt = `${modal.date}T${(modal.time ? modal.time + ':00' : '12:00:00')}+08:00`

  const payload = {
    [meta.primaryKey]: primary,
    [meta.dimensionKey]: dimensionValue,
    note: noteValue || null,
    source_app: 'manual',
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
  if (field.model === 'primaryValue') return payload[meta.primaryKey] != null ? String(payload[meta.primaryKey]) : ''
  if (field.model === 'dimension') return payload[meta.dimensionKey] || field.defaultValue || ''
  if (field.model === 'note') return record.summary || payload.note || ''
  if (field.model === 'date') return (record.occurredAt || record.createdAt || new Date().toISOString()).slice(0, 10)
  if (field.model === 'time') return (record.occurredAt || '').slice(11, 16) || ''
  return field.defaultValue ?? ''
}
