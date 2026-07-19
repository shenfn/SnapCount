function num(value) {
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

function median(values) {
  if (!values.length) return null
  const sorted = [...values].sort((a, b) => a - b)
  const middle = Math.floor(sorted.length / 2)
  return sorted.length % 2 ? sorted[middle] : Math.round(((sorted[middle - 1] + sorted[middle]) / 2) * 100) / 100
}

function localDate(value) {
  return String(value ?? "").slice(0, 10)
}

function monthStart(date) {
  return `${date.slice(0, 7)}-01`
}

function evidence(records, fields) {
  return records.map(record => ({
    source_type: record.source_type ?? "record",
    source_id: record.id,
    ledger_status: "confirmed_record",
    fields: Object.fromEntries(fields.map(field => [field, record[field] ?? record.payload?.[field] ?? null])),
  }))
}

function candidate({ id, domainKey, semanticKey, claimType = "fact", subtype = null, dimension, value, text, records, numbers, confidence = 1 }) {
  return {
    candidate_id: id, candidate_version: "candidate-v0.1", domain_key: domainKey, dimension,
    claim_type: claimType, fact_subtype: subtype, interaction_mode: "inform",
    claim: { semantic_key: semanticKey, structured_value: value, canonical_text: text },
    evidence: evidence(records, ["occurred_at", "amount", "metric_value"]),
    numbers: numbers.map(item => typeof item === "number" ? { value: item, meaning: "verified_metric", derivation: "source_record" } : item),
    quality: { confidence, sample_count: records.length, data_coverage: 1 },
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

function domainMetric(domainKey, payload) {
  if (domainKey === "sleep") {
    const hours = num(payload.sleep_hours) ?? (num(payload.sleep_minutes) !== null ? Math.round((num(payload.sleep_minutes) / 60) * 100) / 100 : null)
    return hours === null ? null : { value: hours, label: "睡眠", unit: "小时" }
  }
  if (domainKey === "sport") {
    const minutes = num(payload.duration_min) ?? num(payload.duration_minutes) ?? num(payload.duration)
    return minutes === null ? null : { value: minutes, label: "运动", unit: "分钟" }
  }
  if (domainKey === "food") {
    const calories = num(payload.total_calorie_kcal) ?? num(payload.total_calories) ?? num(payload.calorie_kcal) ?? num(payload.calories)
    return calories === null ? null : { value: calories, label: "饮食热量", unit: "千卡" }
  }
  if (domainKey === "reading") {
    const minutes = num(payload.reading_minutes) ?? num(payload.duration_minutes) ?? num(payload.duration_min)
    return minutes === null ? null : { value: minutes, label: "阅读", unit: "分钟" }
  }
  if (domainKey === "wallet") {
    const amount = num(payload.amount) ?? num(payload.balance) ?? num(payload.wallet_amount) ?? num(payload.liability_amount)
    return amount === null ? null : { value: amount, label: "账户金额", unit: "元" }
  }
  return null
}

export function generateIncomeCandidates(records, currentRecordId) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  const amount = num(current.amount)
  if (amount === null) return []
  const date = localDate(current.occurred_at)
  const monthRecords = records.filter(record => localDate(record.occurred_at) >= monthStart(date) && localDate(record.occurred_at) <= date)
  const monthAmounts = monthRecords.map(record => num(record.amount)).filter(value => value !== null)
  const monthTotal = Math.round(monthAmounts.reduce((sum, value) => sum + value, 0) * 100) / 100
  const source = current.source_name || "未命名来源"
  const sourceRecords = monthRecords.filter(record => String(record.source_name ?? "").trim() === String(current.source_name ?? "").trim())
  const output = [candidate({
    id: `fact:income:${current.id}`, domainKey: "income", semanticKey: "income_current_amount",
    subtype: "observed", dimension: "current_fact", value: { amount, source_name: source, date },
    text: `${source} 本次收入 ${amount} 元`, records: [current], numbers: [amount],
  }), candidate({
    id: `fact:income:month:${date}`, domainKey: "income", semanticKey: "income_month_total_count",
    subtype: "aggregated", dimension: "period_aggregation", value: { count: monthRecords.length, total_amount: monthTotal, month: date.slice(0, 7) },
    text: `${date.slice(0, 7)} 已记录 ${monthRecords.length} 笔收入，累计 ${monthTotal} 元`, records: monthRecords, numbers: [monthRecords.length, monthTotal],
  })]
  if (sourceRecords.length >= 2) output.push(candidate({
    id: `pattern:income:source:${String(source).toLowerCase()}:${date}`, domainKey: "income", semanticKey: "income_source_month_pattern",
    claimType: "pattern", dimension: "source_pattern", value: { source_name: source, count: sourceRecords.length, month: date.slice(0, 7) },
    text: `本月来自「${source}」的收入已出现 ${sourceRecords.length} 次`, records: sourceRecords, numbers: [sourceRecords.length], confidence: 0.9,
  }))
  return output
}

export function generateBuiltinDomainCandidates(domainKey, records, currentRecordId) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  const currentMetric = domainMetric(domainKey, current.payload ?? {})
  if (!currentMetric) return []
  const prior = records.filter(record => record.id !== currentRecordId).map(record => ({ record, metric: domainMetric(domainKey, record.payload ?? {}) })).filter(item => item.metric)
  const output = [candidate({
    id: `fact:${domainKey}:${current.id}`, domainKey, semanticKey: `${domainKey}_current_metric`, subtype: "observed", dimension: "current_fact",
    value: { value: currentMetric.value, unit: currentMetric.unit, occurred_at: current.occurred_at },
    text: `本次${currentMetric.label}为 ${currentMetric.value} ${currentMetric.unit}`, records: [current], numbers: [currentMetric.value],
  })]
  if (prior.length >= 3) {
    const baseline = median(prior.map(item => item.metric.value))
    const delta = Math.round((currentMetric.value - baseline) * 100) / 100
    output.push(candidate({
      id: `comparison:${domainKey}:median:${current.id}`, domainKey, semanticKey: `${domainKey}_vs_personal_median`, claimType: "comparison", dimension: "personal_baseline",
      value: { current: currentMetric.value, median: baseline, delta, unit: currentMetric.unit, sample_count: prior.length },
      text: `本次${currentMetric.label} ${currentMetric.value} ${currentMetric.unit}，历史中位数 ${baseline} ${currentMetric.unit}`,
      records: [current, ...prior.map(item => item.record)], numbers: [currentMetric.value, baseline], confidence: prior.length >= 7 ? 0.92 : 0.82,
    }))
  }
  if (domainKey === "wallet" && prior.length) {
    const previous = prior.sort((a, b) => new Date(b.record.occurred_at) - new Date(a.record.occurred_at))[0]
    const delta = Math.round((currentMetric.value - previous.metric.value) * 100) / 100
    output.push(candidate({
      id: `comparison:wallet:previous:${current.id}`, domainKey, semanticKey: "wallet_change_previous", claimType: "comparison", dimension: "state_change",
      value: { current: currentMetric.value, previous: previous.metric.value, delta, unit: "元" },
      text: `账户金额较上次变化 ${delta} 元，当前 ${currentMetric.value} 元`, records: [current, previous.record], numbers: [delta, currentMetric.value, previous.metric.value], confidence: 0.9,
    }))
  }
  return output
}
