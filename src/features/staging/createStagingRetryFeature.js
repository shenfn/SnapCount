const MAX_RETRY_COUNT = 3

function messageOf(error) {
  return error?.message || String(error || '中转重试失败')
}

export function createStagingRetryFeature({ repository, getCurrentUserId }) {
  if (!repository?.retry) throw new Error('中转重试缺少 Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('中转重试缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function canRetry(record) {
    return Number(record?.retryCount || 0) < MAX_RETRY_COUNT
  }

  function retry(record) {
    const recordId = String(record?.id || '').trim()
    if (!recordId) return Promise.resolve({ status: 'failed', reason: 'missing_record_id', recordStillVisible: true })

    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) return Promise.resolve({ status: 'failed', reason: 'unauthenticated', recordId, recordStillVisible: true })

    // 这是非权威的 UX 预检，服务端仍必须拒绝超过上限的请求。
    if (!canRetry(record)) {
      return Promise.resolve({
        status: 'rejected',
        reason: 'retry_limit_exceeded',
        recordId,
        recordStillVisible: true,
        localPreflight: true,
      })
    }

    if (requests.has(recordId)) return requests.get(recordId)
    const expectedGeneration = generation
    const previousRetryCount = Number(record.retryCount || 0)
    const request = (async () => {
      try {
        const result = await repository.retry(recordId)
        if (generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId) {
          return { status: 'stale', reason: 'session_changed', recordId, recordStillVisible: true }
        }
        if (result.status === 'failed' && result.attempted) {
          return { ...result, nextRetryCount: previousRetryCount + 1 }
        }
        return result
      } catch (error) {
        if (generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId) {
          return { status: 'stale', reason: 'session_changed', recordId, recordStillVisible: true }
        }
        return {
          status: 'failed',
          reason: 'client_error',
          recordId,
          recordStillVisible: true,
          error: messageOf(error),
        }
      } finally {
        if (requests.get(recordId) === request) requests.delete(recordId)
      }
    })()
    requests.set(recordId, request)
    return request
  }

  return { reset, canRetry, retry }
}
