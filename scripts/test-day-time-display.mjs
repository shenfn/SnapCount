import assert from 'node:assert/strict'
import test from 'node:test'

import { buildDayRecords } from '../src/domains/dayAdapters.js'

test('day records use the event time when it exists', () => {
  const [record] = buildDayRecords({
    dateKey: '2026-08-14',
    bills: [{ id: 'event', dateRaw: '2026-08-14', name: '商户', amount: 6.8, time: '11:36', createdAt: '2026-08-14T11:40:00+08:00' }],
  })

  assert.equal(record.time, '11:36')
})

test('day records mark upload time when the event time is unavailable', () => {
  const [record] = buildDayRecords({
    dateKey: '2026-08-14',
    bills: [{ id: 'upload', dateRaw: '2026-08-14', name: '商户', amount: 6.8, time: '', createdAt: '2026-08-14T11:36:44+08:00' }],
  })

  assert.equal(record.time, '上传 11:36')
})
