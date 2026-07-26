import assert from 'node:assert/strict'
import {
  buildPendingQueue,
  countPendingQueueByStatus,
  filterPendingQueue,
  pendingQueueItemAtPreviousIndex,
} from '../src/domains/pendingQueue.js'

const queue = buildPendingQueue({
  stagingRecords: [
    {
      id: 'review-today',
      status: 'extracted',
      occurredAt: '2026-07-26T08:10:00+08:00',
      createdAt: '2026-07-26T08:12:00+08:00',
    },
    {
      id: 'error-yesterday',
      status: 'extraction_failed',
      occurredAt: '2026-07-25T23:50:00+08:00',
      createdAt: '2026-07-26T09:00:00+08:00',
    },
    {
      id: 'unknown-occurrence',
      status: 'routing_failed',
      occurredAt: null,
      createdAt: '2026-07-26T10:00:00+08:00',
    },
    {
      id: 'already-confirmed',
      status: 'confirmed',
      occurredAt: '2026-07-26T12:00:00+08:00',
      createdAt: '2026-07-26T12:01:00+08:00',
    },
    {
      id: 'already-archived',
      status: 'archived',
      occurredAt: '2026-07-26T11:00:00+08:00',
      createdAt: '2026-07-26T11:01:00+08:00',
    },
    {
      id: 'already-discarded',
      status: 'discarded',
      occurredAt: '2026-07-26T10:00:00+08:00',
      createdAt: '2026-07-26T10:01:00+08:00',
    },
    {
      id: 'already-assigned',
      status: 'assigned',
      occurredAt: '2026-07-26T09:00:00+08:00',
      createdAt: '2026-07-26T09:01:00+08:00',
    },
  ],
  pendingBills: [
    {
      id: 'bill-today',
      status: 'pending',
      dateRaw: '2026-07-26',
      time: '08:30',
      createdAt: '2026-07-26T08:31:00+08:00',
    },
  ],
})

assert.deepEqual(
  queue.map(item => item.queueId),
  ['bill:bill-today', 'staging:review-today', 'staging:error-yesterday', 'staging:unknown-occurrence'],
  'staging 与 bill 应按发生时间混排，未知发生时间最后显示',
)

assert.deepEqual(
  queue.map(item => item.status),
  ['bill_pending', 'pending_review', 'ai_error', 'routing_failed'],
  '底层状态别名应归一到产品筛选状态',
)

assert.equal(
  queue.some(item => ['already-confirmed', 'already-archived', 'already-discarded', 'already-assigned'].includes(item.sourceId)),
  false,
  '已完成、已归档、已销毁或已分配的 staging 记录不得重新进入待处理队列',
)

const todayQueue = filterPendingQueue(queue, {
  scope: 'today',
  filter: 'all',
  todayKey: '2026-07-26',
})
assert.deepEqual(
  todayQueue.map(item => item.queueId),
  ['bill:bill-today', 'staging:review-today'],
  '今天只认发生日；今天上传的昨日或未知发生记录不得进入今天',
)

assert.deepEqual(
  filterPendingQueue(queue, {
    scope: 'all',
    filter: 'ai_error',
    todayKey: '2026-07-26',
  }).map(item => item.queueId),
  ['staging:error-yesterday'],
)

assert.deepEqual(
  countPendingQueueByStatus(queue, { scope: 'today', todayKey: '2026-07-26' }),
  {
    all: 2,
    routing_failed: 0,
    pending_review: 1,
    ai_error: 0,
    schema_failed: 0,
    bill_pending: 1,
  },
  '状态计数必须在范围筛选后计算',
)

assert.equal(
  pendingQueueItemAtPreviousIndex(queue.slice(1), 1)?.queueId,
  'staging:error-yesterday',
  '处理中间项后应停在原索引对应的下一项',
)
assert.equal(
  pendingQueueItemAtPreviousIndex(queue.slice(0, -1), 99)?.queueId,
  'staging:error-yesterday',
  '处理末项后应回退到剩余末项',
)

console.log('pending queue tests passed')
