function errorMessage(error) {
  return error?.message || String(error || '中转服务请求失败')
}

async function readPayload(response) {
  try {
    return await response.json()
  } catch {
    const text = await response.text().catch(() => '')
    return text ? { error: text } : {}
  }
}

function isRetryLimitError(payload) {
  return /retry limit exceeded|max 3|重试上限/i.test(String(payload?.error || payload?.message || ''))
}

const OPEN_STAGING_LIMIT = 1000
const PROCESSED_STAGING_LIMIT = 30

function normalizeListLimit(value, fallback) {
  const parsed = Number(value)
  if (!Number.isInteger(parsed) || parsed <= 0) return fallback
  return Math.min(parsed, 1000)
}

function mapStagingRow(row = {}, { processed = false } = {}) {
  const allowedTargetKinds = new Set(['expense', 'income', 'data', 'repayment_cycle'])
  const targetKind = allowedTargetKinds.has(row.target_kind) ? row.target_kind : null
  const resolvedDomainKey = typeof row.resolved_domain_key === 'string' && row.resolved_domain_key.trim()
    ? row.resolved_domain_key.trim()
    : null
  const targetRecordId = row.target_record_id || null
  return {
    id: row.id,
    status: row.status,
    occurredAt: row.occurred_at,
    createdAt: row.created_at,
    imagePath: row.image_path,
    imageUrl: null,
    imageLoadError: false,
    imageHash: row.image_hash,
    imageType: row.image_type,
    recordType: row.record_type || 'uncertain',
    domainKey: resolvedDomainKey || row.detected_domain_key,
    detectedDomainKey: row.detected_domain_key || null,
    resolvedDomainKey,
    domainName: row.detected_domain_name,
    targetDomainId: row.target_domain_id,
    confidence: Number(row.confidence || 0),
    summary: row.ai_summary || row.failure_reason || (processed ? '' : '等待处理的截图'),
    failureReason: row.failure_reason,
    lastErrorType: row.last_error_type,
    lastErrorMessage: row.last_error_message,
    extracted: row.extracted_json && typeof row.extracted_json === 'object' ? row.extracted_json : {},
    companionMessage: row.companion_message || row.extracted_json?.companion_message || '',
    retryCount: row.retry_count || 0,
    targetKind,
    targetRecordId,
    targetReference: targetKind && targetRecordId ? `${targetKind}/${targetRecordId}` : null,
    resolvedAction: row.resolved_action,
    resolvedAt: row.resolved_at,
    discardReason: row.discard_reason,
  }
}

function readFailure(error) {
  return {
    status: 'failed',
    reason: 'service_error',
    rows: [],
    error: errorMessage(error),
  }
}

export function createStagingRepository({
  client,
  baseUrl,
  anonKey,
  fetchImpl = globalThis.fetch,
}) {
  if (!client?.auth?.getSession) throw new Error('中转服务缺少认证客户端')
  if (typeof fetchImpl !== 'function') throw new Error('中转服务缺少网络客户端')

  async function retry(recordId) {
    const normalizedId = String(recordId || '').trim()
    if (!normalizedId) throw new Error('缺少中转记录编号')

    const { data, error } = await client.auth.getSession()
    if (error) throw new Error(errorMessage(error))
    const token = String(data?.session?.access_token || '').trim()
    if (!token) throw new Error('登录状态已失效，请重新登录')

    const formData = new FormData()
    formData.append('staging_record_id', normalizedId)
    let response
    try {
      response = await fetchImpl(`${String(baseUrl || '').replace(/\/$/, '')}/functions/v1/ingest-receipt`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${token}`,
          ...(anonKey ? { apikey: anonKey } : {}),
        },
        body: formData,
      })
    } catch (error) {
      return {
        status: 'failed',
        reason: 'network',
        recordId: normalizedId,
        recordStillVisible: true,
        error: errorMessage(error),
      }
    }

    const payload = await readPayload(response)
    if (!response.ok) {
      return {
        status: response.status === 400 && isRetryLimitError(payload) ? 'rejected' : 'failed',
        reason: response.status === 400 && isRetryLimitError(payload)
          ? 'retry_limit_exceeded'
          : 'service_error',
        httpStatus: response.status,
        recordId: normalizedId,
        recordStillVisible: true,
        error: String(payload?.error || payload?.message || `中转服务请求失败（${response.status}）`),
        payload,
      }
    }

    if (payload?.status === 'done') {
      return {
        status: 'accepted',
        reason: 'archived',
        recordId: normalizedId,
        targetRecordId: payload.id || null,
        recordStillVisible: false,
        payload,
      }
    }

    if (payload?.status === 'staging') {
      return {
        status: 'failed',
        reason: 'retry_failed',
        attempted: true,
        recordId: normalizedId,
        recordStillVisible: true,
        error: String(payload.message || payload.error || '重试后仍未确定'),
        payload,
      }
    }

    return {
      status: 'failed',
      reason: 'unexpected_response',
      recordId: normalizedId,
      recordStillVisible: true,
      error: '中转服务返回了无法识别的结果',
      payload,
    }
  }

  async function archive(input = {}) {
    const stagingId = String(input.stagingId || '').trim()
    const domainKey = String(input.domainKey || '').trim()
    if (!stagingId) throw new Error('缺少中转记录编号')
    if (!domainKey) throw new Error('缺少归档数据域')

    let data
    let error
    try {
      ({ data, error } = await client.rpc('archive_staging_record', {
        p_staging_id: stagingId,
        p_domain_key: domainKey,
        p_amount: input.amount ?? null,
        p_title: input.title ?? null,
        p_platform: input.platform ?? null,
        p_category: input.category ?? null,
        p_payment_method: input.paymentMethod ?? null,
        p_income_category: input.incomeCategory ?? null,
        p_record_date: input.recordDate ?? null,
        p_record_time: input.recordTime ?? null,
        p_occurred_at: input.occurredAt ?? null,
        p_summary: input.summary ?? null,
        p_payload: input.payload && typeof input.payload === 'object' ? input.payload : {},
        p_account_id: input.accountId ?? null,
      }))
    } catch (caught) {
      return {
        status: 'failed',
        reason: 'network',
        recordId: stagingId,
        recordStillVisible: true,
        error: errorMessage(caught),
      }
    }

    if (error) {
      return {
        status: 'failed',
        reason: 'service_error',
        recordId: stagingId,
        recordStillVisible: true,
        error: errorMessage(error),
      }
    }

    const targetRecordId = data?.target_record_id || null
    if (!targetRecordId) {
      return {
        status: 'failed',
        reason: 'unexpected_response',
        recordId: stagingId,
        recordStillVisible: true,
        error: '归档服务未返回目标记录',
        payload: data,
      }
    }

    return {
      status: 'accepted',
      reason: 'archived',
      recordId: stagingId,
      targetRecordId,
      targetKind: ['expense', 'income', 'data'].includes(data?.target_kind) ? data.target_kind : null,
      resolvedDomainKey: data?.resolved_domain_key || null,
      targetReference: data.target_reference || null,
      idempotentRetry: data.idempotent_retry === true,
      recordStillVisible: false,
      payload: data,
    }
  }

  async function discard(input = {}) {
    const stagingId = String(input.stagingId || '').trim()
    const reason = String(input.reason || 'user_discarded').trim() || 'user_discarded'
    if (!stagingId) throw new Error('缺少中转记录编号')

    let data
    let error
    try {
      ({ data, error } = await client.rpc('discard_staging_record', {
        p_staging_id: stagingId,
        p_reason: reason,
      }))
    } catch (caught) {
      return {
        status: 'failed',
        reason: 'network',
        recordId: stagingId,
        recordStillVisible: true,
        error: errorMessage(caught),
      }
    }

    if (error) {
      return {
        status: 'failed',
        reason: 'service_error',
        recordId: stagingId,
        recordStillVisible: true,
        error: errorMessage(error),
      }
    }

    if (data?.status !== 'discarded') {
      return {
        status: 'failed',
        reason: 'unexpected_response',
        recordId: stagingId,
        recordStillVisible: true,
        error: '丢弃服务未返回完成状态',
        payload: data,
      }
    }

    return {
      status: 'accepted',
      reason: 'discarded',
      recordId: data.staging_id || stagingId,
      cleanupStatus: data.cleanup_status || null,
      cleanupQueued: data.cleanup_queued === true,
      bucketPath: data.bucket_path || null,
      recordStillVisible: false,
      payload: data,
    }
  }

  async function listOpen({ limit = OPEN_STAGING_LIMIT } = {}) {
    try {
      const { data, error } = await client.from('staging_records')
        .select('*')
        .or('status.is.null,status.not.in.(confirmed,discarded,archived,assigned)')
        .order('occurred_at', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(normalizeListLimit(limit, OPEN_STAGING_LIMIT))
      if (error) return readFailure(error)
      return {
        status: 'accepted',
        reason: 'loaded',
        rows: (data || []).map(row => mapStagingRow(row)),
      }
    } catch (error) {
      return readFailure(error)
    }
  }

  async function listProcessed({ limit = PROCESSED_STAGING_LIMIT } = {}) {
    try {
      const { data, error } = await client.from('staging_records')
        .select('*')
        .in('status', ['archived', 'discarded'])
        .order('resolved_at', { ascending: false, nullsFirst: false })
        .order('created_at', { ascending: false })
        .limit(normalizeListLimit(limit, PROCESSED_STAGING_LIMIT))
      if (error) return readFailure(error)
      return {
        status: 'accepted',
        reason: 'loaded',
        rows: (data || []).map(row => mapStagingRow(row, { processed: true })),
      }
    } catch (error) {
      return readFailure(error)
    }
  }

  return { retry, archive, discard, listOpen, listProcessed }
}
