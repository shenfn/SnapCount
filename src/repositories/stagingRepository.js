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
      targetReference: data.target_reference || null,
      idempotentRetry: data.idempotent_retry === true,
      recordStillVisible: false,
      payload: data,
    }
  }

  return { retry, archive }
}
