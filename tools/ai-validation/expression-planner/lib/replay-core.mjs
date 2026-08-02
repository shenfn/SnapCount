function numberOrNull(value) {
  const number = Number(value)
  return Number.isFinite(number) ? number : null
}

export function buildOccurredAt(row, timezoneOffset = '+08:00') {
  if (!row?.transaction_date) return row?.created_at ?? null
  return `${row.transaction_date}T${row.transaction_time || '12:00:00'}${timezoneOffset}`
}

export function summarizeTransactions(transactions, currentRecordId = null) {
  const sorted = [...transactions].sort((left, right) => new Date(left.occurred_at) - new Date(right.occurred_at))
  const amounts = sorted.map(row => numberOrNull(row.amount)).filter(value => value !== null)
  const first = sorted[0] ?? null
  const last = sorted.at(-1) ?? null
  const currentIndex = currentRecordId ? sorted.findIndex(row => row.id === currentRecordId) : -1
  return {
    count: sorted.length,
    total: Math.round(amounts.reduce((sum, value) => sum + value, 0) * 100) / 100,
    min_amount: amounts.length ? Math.min(...amounts) : null,
    max_amount: amounts.length ? Math.max(...amounts) : null,
    first_occurred_at: first?.occurred_at ?? null,
    last_occurred_at: last?.occurred_at ?? null,
    span_minutes: first && last ? Math.round((new Date(last.occurred_at) - new Date(first.occurred_at)) / 60000) : null,
    current_sequence: currentIndex >= 0 ? currentIndex + 1 : null,
  }
}

export function auditTransactions(transactions) {
  const grouped = new Map()
  for (const row of transactions) {
    const key = row.merchant?.entity_id ?? 'merchant_missing'
    if (!grouped.has(key)) grouped.set(key, [])
    grouped.get(key).push(row)
  }
  const merchant_entities = [...grouped.entries()].map(([entity_id, rows]) => {
    const categories = [...new Set(rows.map(row => row.category).filter(Boolean))].sort()
    return {
      entity_id,
      entity_type: rows[0]?.merchant?.entity_type ?? 'unknown',
      canonical_name: rows[0]?.merchant?.canonical_name ?? null,
      raw_names: [...new Set(rows.map(row => row.merchant?.raw_name).filter(Boolean))].sort(),
      categories,
      count: rows.length,
      total: Math.round(rows.reduce((sum, row) => sum + (numberOrNull(row.amount) ?? 0), 0) * 100) / 100,
      category_conflict: categories.length > 1,
    }
  }).sort((left, right) => right.count - left.count)
  return {
    merchant_entities,
    category_conflicts: merchant_entities.filter(item => item.category_conflict),
    duplicate_flags: transactions
      .filter(row => row.source_log?.duplicate_kind || row.source_log?.status === 'duplicate')
      .map(row => ({
        transaction_id: row.id,
        ai_log_id: row.source_log?.id ?? null,
        status: row.source_log?.status ?? null,
        duplicate_kind: row.source_log?.duplicate_kind ?? null,
      })),
  }
}
