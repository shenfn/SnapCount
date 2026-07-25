import test from 'node:test'
import assert from 'node:assert/strict'
import { generateRecordNameRecurrenceCandidates } from '../lib/recurrence-candidates.mjs'

function event(id, name, normalizedName, eventAt, options = {}) {
  return {
    event_id: `transaction:${id}`,
    target_id: id,
    source_type: 'transaction',
    ledger_status: 'confirmed_transaction',
    count_in_facts: options.countInFacts ?? true,
    amount: options.amount ?? 10,
    event_at: eventAt,
    transaction_date: eventAt.slice(0, 10),
    known_at: options.knownAt ?? eventAt,
    event_time_source: options.precision === 'date_only' ? 'date_noon_proxy' : 'transaction_time',
    event_time_precision: options.precision ?? 'second',
    event_time_confidence: options.precision === 'date_only' ? 0.35 : 0.95,
    merchant: {
      entity_id: `merchant_unmapped_${normalizedName}`,
      canonical_name: name,
      raw_name: name,
      normalized_key: normalizedName,
    },
  }
}

test('selects the nearest earlier same-name record and formats the exact interval', () => {
  const current = event('current', 'Example Digital Center', 'exampledigitalcenter', '2026-07-12T18:42:00+08:00', {
    knownAt: '2026-07-12T18:43:00+08:00',
    amount: 25,
  })
  const candidates = generateRecordNameRecurrenceCandidates([
    current,
    event('old', 'Example Digital Center', 'exampledigitalcenter', '2026-07-01T09:00:00+08:00'),
    event('nearest', 'Example Digital Center', 'exampledigitalcenter', '2026-07-12T09:05:00+08:00', {
      knownAt: '2026-07-12T09:06:00+08:00',
      amount: 18,
    }),
  ], { currentEventId: current.event_id })

  assert.equal(candidates.length, 1)
  const candidate = candidates[0]
  assert.equal(candidate.claim.structured_value.previous_record_id, 'nearest')
  assert.equal(candidate.claim.structured_value.elapsed_minutes, 577)
  assert.deepEqual(candidate.claim.structured_value.elapsed_duration, {
    days: 0, hours: 9, minutes: 37, display_text: '9 小时 37 分钟',
  })
  assert.equal(candidate.claim.structured_value.current_amount, 25)
  assert.equal(candidate.claim.structured_value.previous_amount, 18)
  assert.equal(candidate.candidate_id, 'fact:record-name:previous-gap:transaction:current')
  assert.equal(candidate.claim.canonical_text, '距离上一次同名记录已经过去 9 小时 37 分钟')
})

test('does not substitute a different record name or a later-known record', () => {
  const current = event('current', 'Coffee A', 'coffeea', '2026-07-12T12:00:00+08:00', {
    knownAt: '2026-07-12T12:01:00+08:00',
  })
  const candidates = generateRecordNameRecurrenceCandidates([
    event('different', 'Coffee B', 'coffeeb', '2026-07-12T09:00:00+08:00'),
    event('late-known', 'Coffee A', 'coffeea', '2026-07-12T10:00:00+08:00', {
      knownAt: '2026-07-12T13:00:00+08:00',
    }),
    current,
  ], { currentEventId: current.event_id })

  assert.deepEqual(candidates, [])
})

test('uses calendar-day precision when either record lacks a transaction time', () => {
  const previous = event('previous', 'Monthly Service', 'monthlyservice', '2026-06-20T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-06-20T13:00:00+08:00',
  })
  const current = event('current', 'Monthly Service', 'monthlyservice', '2026-07-02T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-07-02T13:00:00+08:00',
  })
  const candidate = generateRecordNameRecurrenceCandidates([current, previous], {
    currentEventId: current.event_id,
  })[0]

  assert.equal(candidate.claim.structured_value.elapsed_minutes, null)
  assert.equal(candidate.claim.structured_value.elapsed_calendar_days, 12)
  assert.equal(candidate.claim.structured_value.time_precision, 'calendar_day')
  assert.match(candidate.claim.canonical_text, /约 12 天/)
})

test('does not invent a minute interval for same-day date-only records', () => {
  const previous = event('previous', 'Date Only', 'dateonly', '2026-07-02T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-07-02T08:00:00+08:00',
  })
  const current = event('current', 'Date Only', 'dateonly', '2026-07-02T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-07-02T09:00:00+08:00',
  })
  assert.deepEqual(generateRecordNameRecurrenceCandidates([previous, current], {
    currentEventId: current.event_id,
  }), [])
})

test('does not skip an unorderable nearest same-name record to call an older record previous', () => {
  const current = event('current', 'Nearest Name', 'nearestname', '2026-07-12T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-07-12T10:00:00+08:00',
  })
  const nearest = event('nearest', 'Nearest Name', 'nearestname', '2026-07-12T12:00:00+08:00', {
    precision: 'date_only',
    knownAt: '2026-07-12T09:00:00+08:00',
  })
  const older = event('older', 'Nearest Name', 'nearestname', '2026-07-01T08:00:00+08:00', {
    knownAt: '2026-07-01T08:01:00+08:00',
  })

  assert.deepEqual(generateRecordNameRecurrenceCandidates([older, nearest, current], {
    currentEventId: current.event_id,
  }), [])
})

test('does not use pending or otherwise fact-ineligible records as the previous record', () => {
  const current = event('current', 'Eligible Name', 'eligiblename', '2026-07-12T12:00:00+08:00')
  const previous = event('previous', 'Eligible Name', 'eligiblename', '2026-07-11T12:00:00+08:00', {
    countInFacts: false,
  })
  assert.deepEqual(generateRecordNameRecurrenceCandidates([previous, current], {
    currentEventId: current.event_id,
  }), [])
})
