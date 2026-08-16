import { formatDate, incomeCatMap, mapTransaction } from '../utils/helpers.js'
import { buildShanghaiOccurredAt, resolveFinanceOccurrence } from '../utils/financeOccurrence.js'

const DEFAULT_PENDING_LIMIT = 1000
const DEFAULT_RECENT_INCOME_LIMIT = 10
const DEFAULT_UNIVERSAL_LIMIT = 120
const DEFAULT_UNBOUND_LIMIT = 100

function errorMessage(error) {
  return error?.message || String(error || '正式记录读取失败')
}

function normalizeLimit(value, fallback) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback
  return Math.min(parsed, 1000)
}

function financeMonthFilter(legacyDateColumn, start, end) {
  const startTimestamp = buildShanghaiOccurredAt(start, '00:00:00')
  const endTimestamp = buildShanghaiOccurredAt(end, '23:59:59')
  return `and(occurred_at.gte.${startTimestamp},occurred_at.lte.${endTimestamp}),and(occurred_at.is.null,${legacyDateColumn}.gte.${start},${legacyDateColumn}.lte.${end})`
}

function universalMonthFilter(start, end) {
  const startTimestamp = buildShanghaiOccurredAt(start, '00:00:00')
  const endTimestamp = buildShanghaiOccurredAt(end, '23:59:59')
  return `and(occurred_at.gte.${startTimestamp},occurred_at.lte.${endTimestamp}),and(occurred_at.is.null,created_at.gte.${startTimestamp},created_at.lte.${endTimestamp})`
}

function readFailure(error) {
  return {
    status: 'failed',
    reason: 'service_error',
    rows: [],
    error: errorMessage(error),
  }
}

async function readRows(query, mapper) {
  try {
    const { data, error } = await query
    if (error) return readFailure(error)
    return {
      status: 'accepted',
      reason: 'loaded',
      rows: (data || []).map(mapper),
    }
  } catch (error) {
    return readFailure(error)
  }
}

async function readSingle(query, mapper, kind) {
  try {
    const { data, error } = await query
    if (error) return { status: 'failed', reason: 'service_error', kind, record: null, error: errorMessage(error) }
    if (!data) return { status: 'accepted', reason: 'not_found', kind, record: null }
    return { status: 'accepted', reason: 'loaded', kind, record: mapper(data) }
  } catch (error) {
    return { status: 'failed', reason: 'service_error', kind, record: null, error: errorMessage(error) }
  }
}

export function mapIncomeRow(row = {}) {
  const occurrence = resolveFinanceOccurrence({ occurredAt: row.occurred_at, date: row.income_date })
  return {
    id: row.id,
    cat: row.category,
    source: row.source_name,
    amount: Number(row.amount),
    date: occurrence.date ? formatDate(occurrence.date) : '',
    dateRaw: occurrence.date || row.income_date,
    createdAt: row.created_at,
    occurredAt: row.occurred_at || null,
    time: occurrence.time?.slice(0, 5) || '',
    icon: incomeCatMap[row.category]?.icon || '💰',
    note: row.note,
    image_url: row.image_url,
    image_path: row.image_url,
    sourceType: row.source || 'manual',
    companionMessage: row.companion_message || '',
    aiFeedback: row.ai_feedback || null,
    accountId: row.account_id || null,
    accountConfidence: row.account_confidence ?? null,
    accountInference: row.account_inference || null,
  }
}

export function mapDataRecordRow(row = {}) {
  const payload = row.payload_jsonb || {}
  return {
    id: row.id,
    domainId: row.domain_id,
    domainKey: row.domain_key,
    domainVersion: row.domain_version || '1.0',
    occurredAt: row.occurred_at,
    createdAt: row.created_at,
    title: row.title,
    summary: row.summary,
    payload: {
      ...payload,
      linked_account_id: row.linked_account_id || payload.linked_account_id || null,
      account_snapshot_kind: row.account_snapshot_kind || payload.account_snapshot_kind || null,
      snapshot_balance: row.snapshot_balance ?? payload.snapshot_balance ?? null,
    },
    companionMessage: payload?.companion_message || '',
    aiFeedback: payload?.ai_feedback || null,
    imagePath: row.source_image_path,
    imageHash: row.source_image_hash,
    stagingRecordId: row.staging_record_id,
    source: row.source || 'staging',
  }
}

export function createRecordRepository({ client }) {
  if (!client?.from) throw new Error('正式记录服务缺少数据库客户端')

  function listExpenses({ start, end }) {
    return readRows(
      client.from('transactions')
        .select('*')
        .or(financeMonthFilter('transaction_date', start, end))
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('transaction_date', { ascending: false })
        .order('created_at', { ascending: false }),
      mapTransaction,
    )
  }

  function listPendingExpenses({ limit = DEFAULT_PENDING_LIMIT } = {}) {
    return readRows(
      client.from('transactions')
        .select('*')
        .eq('status', 'pending')
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('transaction_date', { ascending: false })
        .order('created_at', { ascending: false })
        .limit(normalizeLimit(limit, DEFAULT_PENDING_LIMIT)),
      mapTransaction,
    )
  }

  function listIncomes({ start, end }) {
    return readRows(
      client.from('income_records')
        .select('*')
        .or(financeMonthFilter('income_date', start, end))
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('income_date', { ascending: false })
        .order('created_at', { ascending: false }),
      mapIncomeRow,
    )
  }

  function listRecentIncomes({ limit = DEFAULT_RECENT_INCOME_LIMIT } = {}) {
    return readRows(
      client.from('income_records')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(normalizeLimit(limit, DEFAULT_RECENT_INCOME_LIMIT)),
      mapIncomeRow,
    )
  }

  function listUniversalRecords({ start, end, limit = DEFAULT_UNIVERSAL_LIMIT }) {
    return readRows(
      client.from('data_records')
        .select('*')
        .or(universalMonthFilter(start, end))
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(normalizeLimit(limit, DEFAULT_UNIVERSAL_LIMIT)),
      mapDataRecordRow,
    )
  }

  async function listUnboundRecords({ start, end, limit = DEFAULT_UNBOUND_LIMIT }) {
    const normalizedLimit = normalizeLimit(limit, DEFAULT_UNBOUND_LIMIT)
    const [expenseResult, incomeResult] = await Promise.all([
      readRows(
        client.from('transactions')
          .select('*')
          .eq('status', 'done')
          .is('account_id', null)
          .or(financeMonthFilter('transaction_date', start, end))
          .order('occurred_at', { ascending: false, nullsFirst: false })
          .order('transaction_date', { ascending: false })
          .limit(normalizedLimit),
        mapTransaction,
      ),
      readRows(
        client.from('income_records')
          .select('*')
          .is('account_id', null)
          .or(financeMonthFilter('income_date', start, end))
          .order('occurred_at', { ascending: false, nullsFirst: false })
          .order('income_date', { ascending: false })
          .limit(normalizedLimit),
        mapIncomeRow,
      ),
    ])

    if (expenseResult.status !== 'accepted' || incomeResult.status !== 'accepted') {
      return {
        status: 'failed',
        reason: 'service_error',
        expenses: [],
        incomes: [],
        error: expenseResult.error || incomeResult.error || '未绑定记录读取失败',
      }
    }
    return {
      status: 'accepted',
      reason: 'loaded',
      expenses: expenseResult.rows,
      incomes: incomeResult.rows,
    }
  }

  async function getRecordByTarget({ targetKind, targetRecordId } = {}) {
    const normalizedKind = String(targetKind || '').trim()
    const normalizedId = String(targetRecordId || '').trim()
    const targetReaders = {
      expense: ['transactions', mapTransaction],
      income: ['income_records', mapIncomeRow],
      data: ['data_records', mapDataRecordRow],
    }
    const targetReader = targetReaders[normalizedKind]
    if (!targetReader || !normalizedId) {
      return {
        status: 'rejected',
        reason: 'invalid_target',
        kind: targetReader ? normalizedKind : null,
        record: null,
        error: '归档目标类型未知或目标编号缺失',
      }
    }

    const [table, mapper] = targetReader
    return readSingle(
      client.from(table)
        .select('*')
        .eq('id', normalizedId)
        .maybeSingle(),
      mapper,
      normalizedKind,
    )
  }

  return {
    listExpenses,
    listPendingExpenses,
    listIncomes,
    listRecentIncomes,
    listUniversalRecords,
    listUnboundRecords,
    getRecordByTarget,
  }
}
