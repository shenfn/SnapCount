export function parseFiniteNumber(value) {
  if (typeof value === "number") return Number.isFinite(value) ? value : null
  if (typeof value !== "string") return null
  const trimmed = value.trim()
  if (!trimmed) return null
  const number = Number(trimmed)
  return Number.isFinite(number) ? number : null
}

function num(value) {
  return parseFiniteNumber(value)
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

function round(value, digits = 2) {
  const factor = 10 ** digits
  return Math.round(value * factor) / factor
}

function payloadValue(record, key) {
  return record?.payload?.[key] ?? record?.[key] ?? null
}

function textValue(value) {
  return typeof value === "string" && value.trim() ? value.trim() : null
}

function timestamp(value) {
  const parsed = new Date(value ?? "").getTime()
  return Number.isFinite(parsed) ? parsed : null
}

function domainRecordKnownAt(record) {
  return timestamp(record?.created_at) ?? timestamp(record?.occurred_at)
}

function canonicalTimestamp(value) {
  const parsed = timestamp(value)
  return parsed === null ? null : new Date(parsed).toISOString()
}

function sleepEventKey(record) {
  const start = canonicalTimestamp(payloadValue(record, "sleep_start_at"))
  const wake = canonicalTimestamp(payloadValue(record, "wake_at"))
  if (!start || !wake) return null
  return JSON.stringify({
    start,
    wake,
    sleep_minutes: num(payloadValue(record, "sleep_minutes")),
    sleep_hours: num(payloadValue(record, "sleep_hours")),
    deep_sleep_minutes: num(payloadValue(record, "deep_sleep_minutes")),
    light_sleep_minutes: num(payloadValue(record, "light_sleep_minutes")),
    rem_minutes: num(payloadValue(record, "rem_minutes")),
    awake_minutes: num(payloadValue(record, "awake_minutes")),
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
  if (domainKey !== "sleep") return causal

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

function formatLocalTime(value) {
  const parsed = timestamp(value)
  if (parsed === null) return null
  return new Intl.DateTimeFormat("zh-CN", {
    timeZone: "Asia/Shanghai", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit",
  }).format(new Date(parsed))
}

function dishItems(record) {
  const dishes = payloadValue(record, "dishes")
  return Array.isArray(dishes) ? dishes.filter(item => item && typeof item === "object") : []
}

function dishNames(record) {
  return dishItems(record).map(item => textValue(item.name)).filter(Boolean)
}

function numericDishTotal(record, key) {
  const values = dishItems(record).map(item => num(item[key]))
  if (!values.length || values.some(value => value === null)) return null
  return round(values.reduce((sum, value) => sum + value, 0))
}

function mealTypeLabel(value) {
  return ({ breakfast: "早餐", lunch: "午餐", dinner: "晚餐", snack: "加餐" })[value] ?? value ?? "未标注餐次"
}

function rawRecordValue(record, key) {
  if (record && record[key] !== null && record[key] !== undefined) return record[key]
  return record?.payload?.[key]
}

function hasRawValue(value) {
  return value !== null && value !== undefined && !(typeof value === "string" && !value.trim())
}

function walletAmountState(record) {
  const sources = [
    ["snapshot_balance", record?.snapshot_balance],
    ["payload.snapshot_balance", record?.payload?.snapshot_balance],
    ["payload.amount", record?.payload?.amount],
    ["amount", record?.amount],
    ["payload.balance", record?.payload?.balance],
    ["balance", record?.balance],
    ["payload.wallet_amount", record?.payload?.wallet_amount],
    ["wallet_amount", record?.wallet_amount],
    ["payload.liability_amount", record?.payload?.liability_amount],
    ["liability_amount", record?.liability_amount],
  ].filter(([, value]) => hasRawValue(value))
  const parsed = sources.map(([source, raw]) => ({ source, raw, value: num(raw) }))
  const valid = parsed.filter(item => item.value !== null)
  const first = valid[0]?.value ?? null
  const conflict = parsed.some(item => item.value === null)
    || valid.some(item => item.value !== first)
  return { value: first, source: valid[0]?.source ?? null, conflict }
}

function normalizeWalletKind(value) {
  const normalized = textValue(value)?.toLowerCase()
  if (normalized === "asset" || normalized === "cash_snapshot") return "asset"
  if (normalized === "liability" || normalized === "liability_snapshot") return "liability"
  return null
}

function walletKindState(record) {
  const sources = [
    ["account_snapshot_kind", record?.account_snapshot_kind],
    ["payload.account_snapshot_kind", record?.payload?.account_snapshot_kind],
    ["record_kind", record?.record_kind],
    ["payload.record_kind", record?.payload?.record_kind],
  ].filter(([, value]) => hasRawValue(value))
  const parsed = sources.map(([source, raw]) => ({ source, raw, kind: normalizeWalletKind(raw) }))
  const valid = parsed.filter(item => item.kind !== null)
  const uniqueKinds = [...new Set(valid.map(item => item.kind))]
  const conflict = parsed.some(item => item.kind === null) || uniqueKinds.length > 1
  return { kind: valid[0]?.kind ?? null, source: valid[0]?.source ?? null, conflict }
}

function normalizeAccountName(value) {
  return textValue(value)?.toLocaleLowerCase().replace(/\s+/g, " ") ?? null
}

function walletIdentityState(record) {
  const linkedAccountId = textValue(rawRecordValue(record, "linked_account_id"))
  const accountName = normalizeAccountName(
    rawRecordValue(record, "account_name") ?? record?.title,
  )
  const genericNames = new Set(["账户", "未知账户", "余额", "钱包", "银行卡"])
  return {
    linkedAccountId,
    accountName,
    accountNameSpecific: Boolean(accountName && accountName.length >= 2 && !genericNames.has(accountName)),
  }
}

function walletSnapshotTime(record) {
  const snapshotRaw = rawRecordValue(record, "snapshot_at")
  const raw = hasRawValue(snapshotRaw) ? snapshotRaw : record?.occurred_at
  const value = new Date(raw ?? "").getTime()
  return Number.isFinite(value) ? value : null
}

function walletComparisonAllowed(current, previous, currentMetric, previousMetric) {
  const currentUser = textValue(current?.user_id)
  const previousUser = textValue(previous?.user_id)
  if (currentUser || previousUser) {
    if (!currentUser || !previousUser || currentUser !== previousUser) return false
  }
  const currentWallet = currentMetric.wallet
  const previousWallet = previousMetric.wallet
  if (currentWallet.amountConflict || previousWallet.amountConflict) return false
  if (currentWallet.kindConflict || previousWallet.kindConflict) return false
  if (!currentWallet.kind || currentWallet.kind !== previousWallet.kind) return false

  const currentIdentity = currentWallet.identity
  const previousIdentity = previousWallet.identity
  if (currentIdentity.accountName && previousIdentity.accountName
    && currentIdentity.accountName !== previousIdentity.accountName) return false
  if (currentIdentity.linkedAccountId || previousIdentity.linkedAccountId) {
    if (!currentIdentity.linkedAccountId || !previousIdentity.linkedAccountId
      || currentIdentity.linkedAccountId !== previousIdentity.linkedAccountId) return false
  } else if (!currentIdentity.accountNameSpecific || !previousIdentity.accountNameSpecific
    || currentIdentity.accountName !== previousIdentity.accountName) {
    return false
  }

  const currentTime = walletSnapshotTime(current)
  const previousTime = walletSnapshotTime(previous)
  return currentTime !== null && previousTime !== null && previousTime < currentTime
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

function candidate({ id, domainKey, semanticKey, claimType = "fact", subtype = null, dimension, value, text, records, numbers, confidence = 1, dataCoverage = 1, evidenceFields, selectionHints = {} }) {
  return {
    candidate_id: id, candidate_version: "candidate-v0.1", domain_key: domainKey, dimension,
    claim_type: claimType, fact_subtype: subtype, interaction_mode: "inform",
    claim: { semantic_key: semanticKey, structured_value: value, canonical_text: text },
    evidence: evidence(records, evidenceFields ?? ["occurred_at", "amount", "metric_value"]),
    numbers: numbers.map(item => typeof item === "number" ? { value: item, meaning: "verified_metric", derivation: "source_record" } : item),
    quality: { confidence, sample_count: records.length, data_coverage: dataCoverage },
    selection_hints: selectionHints,
    eligibility: { eligible: true, blocked_reasons: [] },
  }
}

function domainMetric(domainKey, record) {
  const payload = record?.payload ?? {}
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
    const amount = walletAmountState(record)
    if (amount.value === null) return null
    const kind = walletKindState(record)
    const identity = walletIdentityState(record)
    return {
      value: amount.value,
      label: kind.kind === "liability" ? "待还金额" : kind.kind === "asset" ? "账户余额" : "账户金额",
      unit: "元",
      wallet: {
        amountSource: amount.source,
        amountConflict: amount.conflict,
        kind: kind.kind,
        kindSource: kind.source,
        kindConflict: kind.conflict,
        identity,
        snapshotAt: rawRecordValue(record, "snapshot_at") ?? record?.occurred_at ?? null,
      },
    }
  }
  return null
}

function generateFoodCandidates(current, prior, domainProfile = {}) {
  const mealType = textValue(payloadValue(current, "meal_type"))
  const names = dishNames(current)
  const currentKcal = num(payloadValue(current, "total_calorie_kcal"))
  const output = []

  if (mealType || names.length || current.occurred_at) {
    const time = formatLocalTime(current.occurred_at)
    output.push(candidate({
      id: `fact:food:context:${current.id}`, domainKey: "food", semanticKey: "food_record_context", subtype: "observed", dimension: "record_context",
      value: { domain_key: "food", occurred_at: current.occurred_at, meal_type: mealType, dish_names: names, dish_count: names.length },
      text: `记录于${time ?? "当前时间"}，${mealTypeLabel(mealType)}${names.length ? `，${names.slice(0, 3).join("、")}${names.length > 3 ? "等" : ""}` : ""}`,
      records: [current], numbers: [{ value: names.length, meaning: "recognized_dish_count", derivation: "count(payload.dishes)" }], evidenceFields: ["occurred_at", "meal_type", "dishes", "time_context"],
      selectionHints: { allowed_surfaces: ["pwa_pending_ai_card", "record_detail"] },
    }))
  }

  const macroValues = {
    protein_g: numericDishTotal(current, "protein_g"),
    carb_g: numericDishTotal(current, "carb_g"),
    fat_g: numericDishTotal(current, "fat_g"),
  }
  if (names.length && Object.values(macroValues).some(value => value !== null && value > 0)) {
    const macroText = Object.entries(macroValues)
      .filter(([, value]) => value !== null && value > 0)
      .map(([key, value]) => `${{ protein_g: "蛋白质", carb_g: "碳水", fat_g: "脂肪" }[key]} ${value} 克`)
      .join("，")
    output.push(candidate({
      id: `fact:food:composition:${current.id}`, domainKey: "food", semanticKey: "food_composition", subtype: "derived", dimension: "record_composition",
      value: { dish_names: names, dish_count: names.length, macros: macroValues, estimated: payloadValue(current, "is_estimated") ?? null },
      text: `记录了${names.length}道菜：${names.slice(0, 3).join("、")}${names.length > 3 ? "等" : ""}；${macroText}`,
      records: [current], numbers: [names.length, ...Object.values(macroValues).filter(value => value !== null && value > 0)], confidence: 0.86,
      evidenceFields: ["occurred_at", "dishes", "is_estimated", "confidence_note"],
      selectionHints: { allowed_surfaces: ["pwa_pending_ai_card", "record_detail"] },
    }))
  }

  if (mealType && currentKcal !== null) {
    const mealPrior = prior.filter(record => textValue(payloadValue(record, "meal_type")) === mealType)
      .map(record => num(payloadValue(record, "total_calorie_kcal"))).filter(value => value !== null)
    const profileMeal = domainProfile?.meal_baseline?.[mealType]
    const profileMedian = num(profileMeal?.median_kcal)
    const profileN = num(profileMeal?.n)
    if (mealPrior.length >= 3 || (profileMedian !== null && profileN !== null && profileN >= 5)) {
      const useProfile = profileMedian !== null && profileN !== null && profileN >= 5
      const baseline = useProfile ? profileMedian : median(mealPrior)
      const sampleCount = useProfile ? profileN : mealPrior.length
      output.push(candidate({
        id: `comparison:food:meal-median:${current.id}`, domainKey: "food", semanticKey: "food_meal_vs_personal_median", claimType: "comparison", dimension: "meal_baseline",
        value: { meal_type: mealType, current: currentKcal, median: baseline, delta: round(currentKcal - baseline), unit: "千卡", sample_count: sampleCount, baseline_source: useProfile ? "domain_profile" : "record_history" },
        text: `这顿${mealTypeLabel(mealType)}约 ${round(currentKcal)} 千卡；你历史同餐次中位数为 ${baseline} 千卡`,
        records: [current, ...prior.filter(record => textValue(payloadValue(record, "meal_type")) === mealType)], numbers: [currentKcal, baseline, sampleCount], confidence: sampleCount >= 7 ? 0.92 : 0.82,
        evidenceFields: ["occurred_at", "meal_type", "total_calorie_kcal"],
      }))
    }
  }

  const priorDishCounts = new Map()
  for (const record of prior) {
    for (const name of dishNames(record)) priorDishCounts.set(name, (priorDishCounts.get(name) ?? 0) + 1)
  }
  const recurring = names.find(name => (priorDishCounts.get(name) ?? 0) >= 3)
  if (recurring) {
    output.push(candidate({
      id: `pattern:food:recurring-dish:${current.id}`, domainKey: "food", semanticKey: "food_recurring_dish", claimType: "pattern", dimension: "recurrence",
      value: { dish_name: recurring, prior_count: priorDishCounts.get(recurring), window: "available_history" },
      text: `「${recurring}」在你的历史饮食中已出现 ${priorDishCounts.get(recurring)} 次`, records: [current, ...prior.filter(record => dishNames(record).includes(recurring))], numbers: [priorDishCounts.get(recurring)], confidence: 0.9,
      evidenceFields: ["occurred_at", "meal_type", "dishes"],
    }))
  }

  return output
}

function sleepClock(value) {
  const parsed = timestamp(value)
  if (parsed === null) return null
  return new Intl.DateTimeFormat("zh-CN", { timeZone: "Asia/Shanghai", hour: "2-digit", minute: "2-digit" }).format(new Date(parsed))
}

function clockMinutes(value) {
  const match = String(value ?? "").match(/(?:T|\s|^)(\d{1,2}):(\d{2})/)
  if (!match) return null
  const minutes = Number(match[1]) * 60 + Number(match[2])
  return Number.isFinite(minutes) ? minutes : null
}

function signedClockDelta(current, baseline) {
  if (current === null || baseline === null) return null
  let delta = current - baseline
  if (delta > 720) delta -= 1440
  if (delta < -720) delta += 1440
  return delta
}

function generateSleepCandidates(current, prior, domainProfile = {}) {
  const output = []
  const start = payloadValue(current, "sleep_start_at")
  const wake = payloadValue(current, "wake_at")
  const score = num(payloadValue(current, "quality_score"))
  const deep = num(payloadValue(current, "deep_sleep_minutes"))
  const light = num(payloadValue(current, "light_sleep_minutes"))
  const rem = num(payloadValue(current, "rem_minutes"))
  if (start || wake) {
    const timingNumbers = [
      { value: clockMinutes(start), meaning: "sleep_start_clock_minutes", derivation: "source_record.sleep_start_at" },
      { value: clockMinutes(wake), meaning: "wake_clock_minutes", derivation: "source_record.wake_at" },
    ].filter(item => item.value !== null)
    output.push(candidate({
      id: `fact:sleep:timing:${current.id}`, domainKey: "sleep", semanticKey: "sleep_timing", subtype: "observed", dimension: "temporal_rhythm",
      value: { occurred_at: current.occurred_at, sleep_start_at: start, wake_at: wake },
      text: `入睡 ${sleepClock(start) ?? "未知"}，醒来 ${sleepClock(wake) ?? "未知"}`,
      records: [current], numbers: timingNumbers, confidence: timingNumbers.length === 2 ? 0.9 : 0.8,
      dataCoverage: timingNumbers.length / 2, evidenceFields: ["occurred_at", "sleep_start_at", "wake_at", "time_context"],
      selectionHints: { allowed_surfaces: ["pwa_pending_ai_card", "record_detail"] },
    }))
    const typicalStart = clockMinutes(domainProfile?.chronotype?.typical_sleep_start)
    const typicalWake = clockMinutes(domainProfile?.chronotype?.typical_wake)
    const startDelta = signedClockDelta(clockMinutes(start), typicalStart)
    const wakeDelta = signedClockDelta(clockMinutes(wake), typicalWake)
    if (startDelta !== null || wakeDelta !== null) {
      const describeDelta = value => value === null ? null : `${Math.abs(value)} 分钟${value >= 0 ? "晚" : "早"}`
      output.push(candidate({
        id: `comparison:sleep:timing-baseline:${current.id}`, domainKey: "sleep", semanticKey: "sleep_timing_vs_typical", claimType: "comparison", dimension: "timing_baseline",
        value: { sleep_start_delta_minutes: startDelta, wake_delta_minutes: wakeDelta, baseline: domainProfile.chronotype },
        text: `入睡${describeDelta(startDelta) ?? "时间未知"}，醒来${describeDelta(wakeDelta) ?? "时间未知"}（相对你的典型作息）`,
        records: [current], numbers: [startDelta, wakeDelta].filter(value => value !== null), confidence: 0.86, evidenceFields: ["occurred_at", "sleep_start_at", "wake_at"],
      }))
    }
  }
  if (score !== null) {
    const priorScores = prior.map(record => num(payloadValue(record, "quality_score"))).filter(value => value !== null)
    const baseline = priorScores.length >= 3 ? median(priorScores) : null
    output.push(candidate({
      id: `fact:sleep:quality:${current.id}`, domainKey: "sleep", semanticKey: "sleep_quality_current", subtype: baseline === null ? "observed" : "comparison", dimension: "quality",
      value: { current: score, median: baseline, sample_count: priorScores.length },
      text: baseline === null ? `设备睡眠评分 ${score}` : `设备睡眠评分 ${score}，历史中位数 ${baseline}`,
      records: [current, ...prior.filter(record => num(payloadValue(record, "quality_score")) !== null)], numbers: baseline === null ? [score] : [score, baseline, priorScores.length], confidence: baseline === null ? 0.82 : 0.86,
      evidenceFields: ["occurred_at", "quality_score", "quality_level"],
    }))
  }
  if (deep !== null || light !== null || rem !== null) {
    const known = [deep, light, rem].filter(value => value !== null)
    const total = known.reduce((sum, value) => sum + value, 0)
    const stages = { deep_minutes: deep, light_minutes: light, rem_minutes: rem, observed_total_minutes: total }
    output.push(candidate({
      id: `fact:sleep:stages:${current.id}`, domainKey: "sleep", semanticKey: "sleep_stage_composition", subtype: "derived", dimension: "sleep_structure",
      value: stages,
      text: `睡眠阶段：深睡 ${deep ?? "未知"} 分钟、浅睡 ${light ?? "未知"} 分钟、REM ${rem ?? "未知"} 分钟（设备估算）`,
      records: [current], numbers: [total, ...known], confidence: 0.74, dataCoverage: known.length / 3, evidenceFields: ["occurred_at", "deep_sleep_minutes", "light_sleep_minutes", "rem_minutes", "awake_minutes"],
      selectionHints: { allowed_surfaces: ["pwa_pending_ai_card", "record_detail"] },
    }))
  }
  return output
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

export function generateBuiltinDomainCandidates(domainKey, records, currentRecordId, domainProfile = {}) {
  const current = records.find(record => record.id === currentRecordId)
  if (!current) return []
  const currentMetric = domainMetric(domainKey, current)
  const prior = records.filter(record => record.id !== currentRecordId)
    .map(record => ({ record, metric: domainMetric(domainKey, record) }))
    .filter(item => item.metric)
  const output = []
  if (currentMetric) output.push(candidate({
    id: `fact:${domainKey}:${current.id}`, domainKey, semanticKey: `${domainKey}_current_metric`, subtype: "observed", dimension: "current_fact",
    value: {
      domain_key: domainKey,
      value: currentMetric.value,
      unit: currentMetric.unit,
      occurred_at: current.occurred_at,
      ...(currentMetric.wallet ? {
        account_name: currentMetric.wallet.identity.accountName,
        linked_account_id: currentMetric.wallet.identity.linkedAccountId,
        account_snapshot_kind: currentMetric.wallet.kind,
        snapshot_at: currentMetric.wallet.snapshotAt,
        amount_source: currentMetric.wallet.amountSource,
        amount_conflict: currentMetric.wallet.amountConflict,
        kind_conflict: currentMetric.wallet.kindConflict,
      } : {}),
    },
    text: `本次${currentMetric.label}为 ${currentMetric.value} ${currentMetric.unit}`, records: [current], numbers: [currentMetric.value],
  }))
  if (currentMetric && domainKey !== "wallet" && prior.length >= 3 && !(domainKey === "food" && textValue(payloadValue(current, "meal_type")))) {
    const baseline = median(prior.map(item => item.metric.value))
    const delta = Math.round((currentMetric.value - baseline) * 100) / 100
    output.push(candidate({
      id: `comparison:${domainKey}:median:${current.id}`, domainKey, semanticKey: `${domainKey}_vs_personal_median`, claimType: "comparison", dimension: "personal_baseline",
      value: { current: currentMetric.value, median: baseline, delta, unit: currentMetric.unit, sample_count: prior.length },
      text: `本次${currentMetric.label} ${currentMetric.value} ${currentMetric.unit}，历史中位数 ${baseline} ${currentMetric.unit}`,
      records: [current, ...prior.map(item => item.record)], numbers: [currentMetric.value, baseline], confidence: prior.length >= 7 ? 0.92 : 0.82,
    }))
  }
  if (domainKey === "food") output.push(...generateFoodCandidates(current, records.filter(record => record.id !== currentRecordId), domainProfile))
  if (domainKey === "sleep") output.push(...generateSleepCandidates(current, records.filter(record => record.id !== currentRecordId), domainProfile))
  if (domainKey === "wallet" && currentMetric) {
    const previous = prior
      .filter(item => walletComparisonAllowed(current, item.record, currentMetric, item.metric))
      .sort((a, b) => walletSnapshotTime(b.record) - walletSnapshotTime(a.record))[0]
    if (!previous) return output
    const delta = Math.round((currentMetric.value - previous.metric.value) * 100) / 100
    if (delta === 0) return output
    const amountLabel = currentMetric.wallet.kind === "liability" ? "待还金额" : "账户余额"
    const deltaText = delta > 0 ? `+${delta}` : String(delta)
    output.push(candidate({
      id: `comparison:wallet:previous:${current.id}`, domainKey, semanticKey: "wallet_change_previous", claimType: "comparison", dimension: "state_change",
      value: {
        current: currentMetric.value,
        previous: previous.metric.value,
        delta,
        unit: "元",
        account_snapshot_kind: currentMetric.wallet.kind,
        account_name: currentMetric.wallet.identity.accountName,
        linked_account_id: currentMetric.wallet.identity.linkedAccountId,
        previous_account_name: previous.metric.wallet.identity.accountName,
        previous_linked_account_id: previous.metric.wallet.identity.linkedAccountId,
      },
      text: `${amountLabel}较上次变化 ${deltaText} 元，当前 ${currentMetric.value} 元`, records: [current, previous.record], numbers: [delta, currentMetric.value, previous.metric.value], confidence: 0.9,
    }))
  }
  return output
}
