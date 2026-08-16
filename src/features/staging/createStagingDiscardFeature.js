function messageOf(error) {
  return error?.message || String(error || '中转丢弃失败')
}

export function createStagingDiscardFeature({ repository, getCurrentUserId }) {
  if (!repository?.discard) throw new Error('中转丢弃缺少 Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('中转丢弃缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function discard(record, reason = 'user_discarded', options = {}) {
    const recordId = String(record?.id || '').trim()
    if (!recordId) {
      return Promise.resolve({ status: 'rejected', reason: 'missing_record_id', recordStillVisible: true })
    }

    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) {
      return Promise.resolve({ status: 'rejected', reason: 'unauthenticated', recordId, recordStillVisible: true })
    }

    if (requests.has(recordId)) return requests.get(recordId)
    const expectedGeneration = generation
    const request = (async () => {
      try {
        const result = await repository.discard({
          stagingId: recordId,
          reason: String(reason || 'user_discarded').trim() || 'user_discarded',
        })
        if (generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId) {
          return { status: 'stale', reason: 'session_changed', recordId, recordStillVisible: true }
        }
        if (result.status !== 'accepted') return result

        let convergenceStatus = 'not_requested'
        if (typeof options.afterAccepted === 'function') {
          try {
            await options.afterAccepted(result)
            convergenceStatus = 'ok'
          } catch (error) {
            return {
              ...result,
              convergenceStatus: 'failed',
              convergenceError: messageOf(error),
              recordStillVisible: false,
            }
          }
        }
        return { ...result, convergenceStatus }
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

  return { reset, discard }
}
