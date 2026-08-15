import { parseFiniteNumber } from './index.mjs'
import { candidate, median, num, payloadValue, textValue, timestamp } from './generic-domain-shared.mjs'
import { generateFoodCandidates } from './food-candidates.mjs'
import { generateIncomeCandidates } from './income-candidates.mjs'
import { generateSleepCandidates } from './sleep-candidates.mjs'
import { generateWalletCandidates } from './wallet-candidates.mjs'

export { parseFiniteNumber, generateIncomeCandidates }

function domainRecordKnownAt(record) {
  return timestamp(record?.created_at) ?? timestamp(record?.occurred_at)
}

function canonicalTimestamp(value) {
  const parsed = timestamp(value)
  return parsed === null ? null : new Date(parsed).toISOString()
}

function sleepEventKey(record) {
  const start = canonicalTimestamp(payloadValue(record, 'sleep_start_at'))
  const wake = canonicalTimestamp(payloadValue(record, 'wake_at'))
  if (!start || !wake) return null
  return JSON.stringify({
    start,
    wake,
    sleep_minutes: num(payloadValue(record, 'sleep_minutes')),
    sleep_hours: num(payloadValue(record, 'sleep_hours')),
    deep_sleep_minutes: num(payloadValue(record, 'deep_sleep_minutes')),
    light_sleep_minutes: num(payloadValue(record, 'light_sleep_minutes')),
    rem_minutes: num(payloadValue(record, 'rem_minutes')),
    awake_minutes: num(payloadValue(record, 'awake_minutes')),
  })
}

export function prepareDomainRecords(domainKey, records, currentRecordId) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  const currentKnownAt = domainRecordKnownAt(current)
  const causal = records.filter(record => {
    if (record.id === currentRecordId) return true
    const knownAt = domainRecordKnownAt(record)
    return currentKnownAt !== null && knownAt !== null && knownAt < currentKnownAt
  })
  if (domainKey !== 'sleep') return causal

  const ordered = [...causal].sort((left, right) => {
    if (left.id === currentRecordId) return -1
    if (right.id === currentRecordId) return 1
    return (domainRecordKnownAt(right) ?? 0) - (domainRecordKnownAt(left) ?? 0)
  })
  const seen = new Set()
  return ordered.filter(record => {
    const key = sleepEventKey(record)
    if (!key) return true
    if (seen.has(key)) return false
    seen.add(key)
    return true
  })
}

function domainMetric(domainKey, record) {
  const payload = record?.payload ?? {}
  if (domainKey === 'sleep') {
    const hours = num(payload.sleep_hours)
      ?? (num(payload.sleep_minutes) !== null
        ? Math.round((num(payload.sleep_minutes) / 60) * 100) / 100
        : null)
    return hours === null ? null : { value: hours, label: '睡眠', unit: '小时' }
  }
  if (domainKey === 'sport') {
    const minutes = num(payload.duration_min) ?? num(payload.duration_minutes) ?? num(payload.duration)
    return minutes === null ? null : { value: minutes, label: '运动', unit: '分钟' }
  }
  if (domainKey === 'food') {
    const calories = num(payload.total_calorie_kcal)
      ?? num(payload.total_calories)
      ?? num(payload.calorie_kcal)
      ?? num(payload.calories)
    return calories === null ? null : { value: calories, label: '饮食热量', unit: '千卡' }
  }
  if (domainKey === 'reading') {
    const minutes = num(payload.reading_minutes) ?? num(payload.duration_minutes) ?? num(payload.duration_min)
    return minutes === null ? null : { value: minutes, label: '阅读', unit: '分钟' }
  }
  return null
}

export function generateBuiltinDomainCandidates(
  domainKey,
  records,
  currentRecordId,
  domainProfile = {},
) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  if (domainKey === 'wallet') return generateWalletCandidates(current, records)

  const currentMetric = domainMetric(domainKey, current)
  const prior = records
    .filter(record => record.id !== currentRecordId)
    .map(record => ({ record, metric: domainMetric(domainKey, record) }))
    .filter(item => item.metric)
  const output = []
  if (currentMetric) output.push(candidate({
    id: `fact:${domainKey}:${current.id}`,
    domainKey,
    semanticKey: `${domainKey}_current_metric`,
    subtype: 'observed',
    dimension: 'current_fact',
    value: {
      domain_key: domainKey,
      value: currentMetric.value,
      unit: currentMetric.unit,
      occurred_at: current.occurred_at,
    },
    text: `本次${currentMetric.label}为 ${currentMetric.value} ${currentMetric.unit}`,
    records: [current],
    numbers: [{
      value: currentMetric.value,
      meaning: `current_${domainKey}_metric`,
      derivation: 'source_record.metric',
    }],
  }))
  if (currentMetric
    && prior.length >= 3
    && !(domainKey === 'food' && textValue(payloadValue(current, 'meal_type')))) {
    const baseline = median(prior.map(item => item.metric.value))
    const delta = Math.round((currentMetric.value - baseline) * 100) / 100
    output.push(candidate({
      id: `comparison:${domainKey}:median:${current.id}`,
      domainKey,
      semanticKey: `${domainKey}_vs_personal_median`,
      claimType: 'comparison',
      dimension: 'personal_baseline',
      value: {
        current: currentMetric.value,
        median: baseline,
        delta,
        unit: currentMetric.unit,
        sample_count: prior.length,
      },
      text: `本次${currentMetric.label} ${currentMetric.value} ${currentMetric.unit}，历史中位数 ${baseline} ${currentMetric.unit}`,
      records: [current, ...prior.map(item => item.record)],
      numbers: [
        { value: currentMetric.value, meaning: `current_${domainKey}_metric`, derivation: 'source_record.metric' },
        { value: baseline, meaning: `historical_median_${domainKey}_metric`, derivation: 'median(prior.metric)' },
      ],
      confidence: prior.length >= 7 ? 0.92 : 0.82,
    }))
  }
  const historicalRecords = records.filter(record => record.id !== currentRecordId)
  if (domainKey === 'food') output.push(...generateFoodCandidates(current, historicalRecords, domainProfile))
  if (domainKey === 'sleep') output.push(...generateSleepCandidates(current, historicalRecords, domainProfile))
  return output
}
