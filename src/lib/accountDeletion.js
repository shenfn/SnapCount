const RECEIPT_STORAGE_KEY = 'jiezi.account-deletion-receipt.v1'
const DELETION_STATES = new Set(['none', 'requested', 'cleaning', 'deleting', 'completed', 'failed'])
const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
const SUPPORT_REFERENCE_PATTERN = /^DEL-[0-9A-F]{12}$/
const ISO_TIMESTAMP_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/

function optionalString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null
}

function normalizeTimestamp(value) {
  const normalized = optionalString(value)
  if (!normalized || !ISO_TIMESTAMP_PATTERN.test(normalized)) return null
  return Number.isNaN(Date.parse(normalized)) ? null : normalized
}

function resolveStorage(storage) {
  if (storage !== undefined) return storage
  try {
    return globalThis.localStorage || null
  } catch {
    return null
  }
}

export function normalizeAccountDeletionResult(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return null
  const deletionStatus = optionalString(value.deletion_status)
  if (!deletionStatus || !DELETION_STATES.has(deletionStatus)) return null
  if (deletionStatus === 'none') {
    if (optionalString(value.status) !== 'none') return null
    return {
      status: 'none',
      deletionStatus,
      requestId: null,
      requestedAt: null,
      completedAt: null,
      estimatedCompletionAt: null,
      supportReference: null,
      retryable: false,
      message: optionalString(value.message) || '当前没有账户删除请求',
    }
  }

  const requestId = optionalString(value.request_id)
  const requestedAt = normalizeTimestamp(value.requested_at)
  const estimatedCompletionAt = normalizeTimestamp(value.estimated_completion_at)
  const supportReference = optionalString(value.support_reference)
  const completedAt = value.completed_at == null ? null : normalizeTimestamp(value.completed_at)
  const completed = deletionStatus === 'completed'
  const expectedEnvelope = completed ? 'deleted' : 'deletion_pending'
  if (!requestId || !UUID_PATTERN.test(requestId) || !requestedAt || !estimatedCompletionAt) return null
  if (!supportReference || !SUPPORT_REFERENCE_PATTERN.test(supportReference)) return null
  if (optionalString(value.status) !== expectedEnvelope) return null
  if (completed ? !completedAt || value.retryable !== false : completedAt || value.retryable !== true) return null

  return {
    status: expectedEnvelope,
    deletionStatus,
    requestId,
    requestedAt,
    completedAt,
    estimatedCompletionAt,
    supportReference,
    retryable: value.retryable,
    message: optionalString(value.message) || '账户删除请求已受理，通常在 24 小时内完成',
  }
}

export function isAcceptedAccountDeletion(result) {
  if (!result || result.deletionStatus === 'none') return false
  return Boolean(normalizeAccountDeletionResult({
    status: result.status,
    deletion_status: result.deletionStatus,
    request_id: result.requestId,
    requested_at: result.requestedAt,
    completed_at: result.completedAt,
    estimated_completion_at: result.estimatedCompletionAt,
    support_reference: result.supportReference,
    retryable: result.retryable,
    message: result.message,
  }))
}

export function saveAccountDeletionReceipt(result, storage) {
  const target = resolveStorage(storage)
  if (!isAcceptedAccountDeletion(result)) throw new Error('账户删除回执格式无效')
  if (!target) throw new Error('本机存储不可用，尚未退出登录')
  const receipt = { ...result, savedAt: new Date().toISOString() }
  target.setItem(RECEIPT_STORAGE_KEY, JSON.stringify(receipt))
  const restored = loadAccountDeletionReceipt(target)
  if (
    restored?.requestId !== receipt.requestId
      || restored?.supportReference !== receipt.supportReference
      || restored?.savedAt !== receipt.savedAt
  ) {
    throw new Error('账户删除回执未能保存到本机，尚未退出登录')
  }
  return receipt
}

export function loadAccountDeletionReceipt(storage) {
  const target = resolveStorage(storage)
  if (!target) return null
  try {
    const raw = JSON.parse(target.getItem(RECEIPT_STORAGE_KEY) || 'null')
    const normalized = normalizeAccountDeletionResult({
      status: raw?.status,
      deletion_status: raw?.deletionStatus,
      request_id: raw?.requestId,
      requested_at: raw?.requestedAt,
      completed_at: raw?.completedAt,
      estimated_completion_at: raw?.estimatedCompletionAt,
      support_reference: raw?.supportReference,
      retryable: raw?.retryable,
      message: raw?.message,
    })
    return normalized ? { ...normalized, savedAt: optionalString(raw?.savedAt) } : null
  } catch {
    return null
  }
}

export function clearAccountDeletionReceipt(storage) {
  try {
    resolveStorage(storage)?.removeItem(RECEIPT_STORAGE_KEY)
  } catch {
    // A receipt that cannot be removed should remain visible on the next load.
  }
}

async function currentSession(client) {
  const { data, error } = await client.auth.getSession()
  if (error) throw error
  const session = data?.session || null
  if (!session?.access_token || !session?.user?.id) throw new Error('登录会话已失效，请重新登录')
  return session
}

async function callDeletionAction({ action, session, functionUrl, anonKey, fetchImpl }) {
  const response = await fetchImpl(functionUrl, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${session.access_token}`,
      apikey: anonKey,
    },
    body: JSON.stringify({ action }),
  })
  const payload = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(payload?.error || `账户服务返回 ${response.status}`)
  const result = normalizeAccountDeletionResult(payload)
  if (!result) throw new Error('账户删除回执格式无效')
  return result
}

export async function requestAccountDeletion({ client, functionUrl, anonKey, fetchImpl = globalThis.fetch }) {
  const session = await currentSession(client)
  try {
    const result = await callDeletionAction({
      action: 'delete_account', session, functionUrl, anonKey, fetchImpl,
    })
    if (!isAcceptedAccountDeletion(result)) throw new Error('账户删除请求未被受理')
    return result
  } catch (requestError) {
    try {
      const status = await callDeletionAction({
        action: 'get_account_deletion_status', session, functionUrl, anonKey, fetchImpl,
      })
      if (isAcceptedAccountDeletion(status)) return status
    } catch {
      // The original request may have reached the server. Repeating it is safe
      // because delete_account returns the same active request.
    }
    const error = new Error('暂时无法确认删除请求结果。请重试，重复提交不会重置处理进度')
    error.cause = requestError
    throw error
  }
}
