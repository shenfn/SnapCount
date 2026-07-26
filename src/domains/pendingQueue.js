import { localDateKeyOf } from '../utils/helpers.js'

export const PENDING_SCOPE_ALL = 'all'
export const PENDING_SCOPE_TODAY = 'today'

export const PENDING_FILTERS = [
  'all',
  'routing_failed',
  'pending_review',
  'ai_error',
  'schema_failed',
  'bill_pending',
]

const STAGING_STATUS_GROUPS = {
  routing_failed: new Set(['routing_failed', 'unrouted', 'unassigned']),
  pending_review: new Set(['pending_review', 'routed', 'extracted']),
  ai_error: new Set(['ai_error', 'failed', 'extraction_failed']),
  schema_failed: new Set(['schema_failed']),
}

const RESOLVED_STAGING_STATUSES = new Set([
  'assigned',
  'confirmed',
  'archived',
  'discarded',
])

export function pendingStatusGroup(status) {
  const normalized = String(status || '').trim()
  return Object.entries(STAGING_STATUS_GROUPS)
    .find(([, statuses]) => statuses.has(normalized))?.[0] || normalized || 'routing_failed'
}

function billOccurrenceValue(bill) {
  const date = String(bill?.dateRaw || '').trim()
  if (!date) return ''
  const time = String(bill?.time || '').trim()
  const normalizedTime = time
    ? (time.length >= 8 ? time.slice(0, 8) : `${time.slice(0, 5)}:00`)
    : '00:00:00'
  return `${date}T${normalizedTime}`
}

function timestampOf(value) {
  if (!value) return Number.NEGATIVE_INFINITY
  const timestamp = new Date(value).getTime()
  return Number.isFinite(timestamp) ? timestamp : Number.NEGATIVE_INFINITY
}

function comparePendingQueueItems(left, right) {
  const leftOccurred = timestampOf(left.occurredAt)
  const rightOccurred = timestampOf(right.occurredAt)
  if (leftOccurred !== rightOccurred) return rightOccurred > leftOccurred ? 1 : -1

  const leftCreated = timestampOf(left.createdAt)
  const rightCreated = timestampOf(right.createdAt)
  if (leftCreated !== rightCreated) return rightCreated > leftCreated ? 1 : -1

  return left.queueId.localeCompare(right.queueId)
}

export function buildPendingQueue({ stagingRecords = [], pendingBills = [] } = {}) {
  const stagingItems = stagingRecords
    .filter(record => !RESOLVED_STAGING_STATUSES.has(String(record?.status || '').trim().toLowerCase()))
    .map(record => ({
      queueId: `staging:${record.id}`,
      source: 'staging',
      sourceId: record.id,
      status: pendingStatusGroup(record.status),
      rawStatus: record.status,
      occurredAt: record.occurredAt || '',
      occurredDateKey: localDateKeyOf(record.occurredAt),
      createdAt: record.createdAt || '',
      imageUrl: record.imageUrl || '',
      record,
    }))

  const billItems = pendingBills.map(bill => {
    const occurredAt = billOccurrenceValue(bill)
    return {
      queueId: `bill:${bill.id}`,
      source: 'bill',
      sourceId: bill.id,
      status: 'bill_pending',
      rawStatus: bill.status,
      occurredAt,
      occurredDateKey: localDateKeyOf(bill.dateRaw),
      createdAt: bill.createdAt || '',
      imageUrl: bill.imageUrl || '',
      record: bill,
    }
  })

  return [...stagingItems, ...billItems].sort(comparePendingQueueItems)
}

export function filterPendingQueue(
  queue,
  { scope = PENDING_SCOPE_ALL, filter = 'all', todayKey } = {},
) {
  return queue.filter(item => {
    if (scope === PENDING_SCOPE_TODAY && item.occurredDateKey !== todayKey) return false
    return filter === 'all' || item.status === filter
  })
}

export function countPendingQueueByStatus(
  queue,
  { scope = PENDING_SCOPE_ALL, todayKey } = {},
) {
  const scoped = filterPendingQueue(queue, { scope, filter: 'all', todayKey })
  return scoped.reduce((counts, item) => {
    counts.all += 1
    if (Object.prototype.hasOwnProperty.call(counts, item.status)) counts[item.status] += 1
    return counts
  }, {
    all: 0,
    routing_failed: 0,
    pending_review: 0,
    ai_error: 0,
    schema_failed: 0,
    bill_pending: 0,
  })
}

export function pendingQueueItemAtPreviousIndex(queue, previousIndex) {
  if (!queue.length) return null
  const safeIndex = Math.min(Math.max(Number(previousIndex) || 0, 0), queue.length - 1)
  return queue[safeIndex]
}
