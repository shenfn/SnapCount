function messageOf(error) {
  return error?.message || String(error || '财务记录保存失败')
}

export function createFinanceSaveFeature({ repository, getCurrentUserId }) {
  if (!repository?.saveExpense || !repository?.saveIncome) throw new Error('财务保存缺少 Record Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('财务保存缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId
  }

  function save(kind, input = {}, options = {}) {
    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) return Promise.resolve({ status: 'rejected', reason: 'unauthenticated', kind })

    const recordId = String(input.id || '').trim()
    const requestKey = `${userId}:${kind}:${recordId || 'create'}`
    if (requests.has(requestKey)) return requests.get(requestKey)

    const expectedGeneration = generation
    const repositorySave = kind === 'expense' ? repository.saveExpense : repository.saveIncome
    const request = (async () => {
      try {
        const result = await repositorySave(input)
        if (isStale(expectedGeneration, userId)) {
          return { status: 'stale', reason: 'session_changed', kind, record: null }
        }
        if (result.status !== 'accepted') return result

        if (typeof options.onAccepted === 'function') {
          try {
            await options.onAccepted(result, { userId })
          } catch (error) {
            return {
              ...result,
              refreshStatus: 'failed',
              refreshError: messageOf(error),
            }
          }
        }
        if (isStale(expectedGeneration, userId)) {
          return { status: 'stale', reason: 'session_changed', kind, record: null }
        }

        let refreshStatus = 'not_requested'
        if (typeof options.refresh === 'function') {
          try {
            await options.refresh(result, { userId })
            if (isStale(expectedGeneration, userId)) {
              return { status: 'stale', reason: 'session_changed', kind, record: null }
            }
            refreshStatus = 'ok'
          } catch (error) {
            if (isStale(expectedGeneration, userId)) {
              return { status: 'stale', reason: 'session_changed', kind, record: null }
            }
            refreshStatus = 'failed'
            return {
              ...result,
              refreshStatus,
              refreshError: messageOf(error),
            }
          }
        }
        return { ...result, refreshStatus }
      } catch (error) {
        if (isStale(expectedGeneration, userId)) {
          return { status: 'stale', reason: 'session_changed', kind, record: null }
        }
        return {
          status: 'failed',
          reason: 'client_error',
          kind,
          record: null,
          error: messageOf(error),
        }
      } finally {
        if (requests.get(requestKey) === request) requests.delete(requestKey)
      }
    })()
    requests.set(requestKey, request)
    return request
  }

  return {
    reset,
    saveExpense: (input, options) => save('expense', input, options),
    saveIncome: (input, options) => save('income', input, options),
  }
}
