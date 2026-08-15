import { candidate, localDate, num } from './generic-domain-shared.mjs'

function monthStart(date) {
  return `${date.slice(0, 7)}-01`
}

export function generateIncomeCandidates(records, currentRecordId) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  const amount = num(current.amount)
  if (amount === null) return []
  const date = localDate(current.occurred_at)
  const monthRecords = records.filter(record => (
    localDate(record.occurred_at) >= monthStart(date)
    && localDate(record.occurred_at) <= date
  ))
  const monthAmounts = monthRecords.map(record => num(record.amount)).filter(value => value !== null)
  const monthTotal = Math.round(monthAmounts.reduce((sum, value) => sum + value, 0) * 100) / 100
  const source = current.source_name || '未命名来源'
  const sourceRecords = monthRecords.filter(record => (
    String(record.source_name ?? '').trim() === String(current.source_name ?? '').trim()
  ))
  const output = [candidate({
    id: `fact:income:${current.id}`,
    domainKey: 'income',
    semanticKey: 'income_current_amount',
    subtype: 'observed',
    dimension: 'current_fact',
    value: { amount, source_name: source, date },
    text: `${source} 本次收入 ${amount} 元`,
    records: [current],
    numbers: [{ value: amount, meaning: 'current_income_amount', derivation: 'source_record.amount' }],
  }), candidate({
    id: `fact:income:month:${date}`,
    domainKey: 'income',
    semanticKey: 'income_month_total_count',
    subtype: 'aggregated',
    dimension: 'period_aggregation',
    value: { count: monthRecords.length, total_amount: monthTotal, month: date.slice(0, 7) },
    text: `${date.slice(0, 7)} 已记录 ${monthRecords.length} 笔收入，累计 ${monthTotal} 元`,
    records: monthRecords,
    numbers: [
      { value: monthRecords.length, meaning: 'current_month_income_count', role: 'count', derivation: 'count(month_records)' },
      { value: monthTotal, meaning: 'current_month_income_total_amount', derivation: 'sum(month_records.amount)' },
    ],
  })]
  if (sourceRecords.length >= 2) output.push(candidate({
    id: `pattern:income:source:${String(source).toLowerCase()}:${date}`,
    domainKey: 'income',
    semanticKey: 'income_source_month_pattern',
    claimType: 'pattern',
    dimension: 'source_pattern',
    value: { source_name: source, count: sourceRecords.length, month: date.slice(0, 7) },
    text: `${date.slice(0, 7)} 来自「${source}」的收入已出现 ${sourceRecords.length} 次`,
    records: sourceRecords,
    numbers: [{
      value: sourceRecords.length,
      meaning: 'current_month_source_occurrence_count',
      role: 'count',
      derivation: 'count(month_source_records)',
    }],
    confidence: 0.9,
  }))
  return output
}
