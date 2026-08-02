const KNOWN_BASELINE_SEMANTICS = Object.freeze({
  "高频日常": "merchant_daily_count_total",
  "重复商户": "merchant_daily_count_total",
  "开发充值": "merchant_daily_count_total",
  "消费加速": "merchant_week_to_date_vs_previous_week_same_period",
  "收入入账": "income_current_amount",
  "工资到账": "income_current_amount",
  "结构扎实": "food_composition",
})

const KNOWN_DOMAINS = new Set(["expense", "income", "sleep", "sport", "food", "reading", "wallet"])

export function normalizedDomainKey(value) {
  const normalized = String(value ?? "").trim().toLowerCase()
  return KNOWN_DOMAINS.has(normalized) ? normalized : "unknown"
}

export function baselineSemanticKey(recordType, badge) {
  const known = KNOWN_BASELINE_SEMANTICS[String(badge ?? "").trim()]
  if (known) return known
  return `legacy_${normalizedDomainKey(recordType)}_feedback`
}
