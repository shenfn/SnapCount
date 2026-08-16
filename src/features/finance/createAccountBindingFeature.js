function messageOf(error) {
  return error?.message || String(error || '账户补绑失败')
}

function cleanOptional(value) {
  return value && value !== '?' ? value : null
}

function transactionTimeOf(value) {
  if (!value) return null
  return value.length === 5 ? `${value}:00` : value
}

export function buildAccountBindingInput(kind, record = {}, accountId) {
  if (kind === 'income') {
    return {
      id: record.id,
      category: record.cat || 'other',
      sourceName: record.source || '收入',
      amount: Number(record.amount || 0),
      incomeDate: record.dateRaw || null,
      occurredAt: record.occurredAt || null,
      note: record.note || null,
      source: record.sourceType || null,
      imageUrl: record.image_path || record.image_url || null,
      imageHash: null,
      companionMessage: record.companionMessage || null,
      accountId,
    }
  }

  return {
    id: record.id,
    amount: Number(record.amount || 0),
    merchantName: record.name || '支出',
    platform: cleanOptional(record.platform),
    category: cleanOptional(record.cat),
    paymentMethod: cleanOptional(record.payment),
    transactionDate: record.dateRaw || null,
    transactionTime: transactionTimeOf(record.time),
    occurredAt: record.occurredAt || null,
    note: record.note || null,
    isLargeTransport: record.cat === 'transport' && Number(record.amount || 0) >= 200,
    transportType: record.transport_type || null,
    source: record.source || null,
    imageUrl: record.image_path || record.image_url || null,
    imageHash: record.image_hash || null,
    companionMessage: record.companionMessage || null,
    accountId,
  }
}

export function createAccountBindingFeature({ repository, getCurrentUserId }) {
  if (!repository?.saveExpense || !repository?.saveIncome) throw new Error('账户补绑缺少 Record Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('账户补绑缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId
  }

  function stale(kind) {
    return { status: 'stale', reason: 'session_changed', kind, record: null }
  }

  function bind(kind, record = {}, accountId, options = {}) {
    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) return Promise.resolve({ status: 'rejected', reason: 'unauthenticated', kind, record: null })
    if (!['expense', 'income'].includes(kind) || !record?.id || !accountId) {
      return Promise.resolve({ status: 'rejected', reason: 'invalid_input', kind, record: null })
    }

    const recordKey = `${userId}:${kind}:${record.id}`
    const normalizedAccountId = String(accountId)
    const active = requests.get(recordKey)
    if (active) {
      if (active.accountId === normalizedAccountId) return active.promise
      return Promise.resolve({ status: 'rejected', reason: 'binding_conflict', kind, record: null })
    }

    const expectedGeneration = generation
    const repositorySave = kind === 'expense' ? repository.saveExpense : repository.saveIncome
    const request = (async () => {
      try {
        const result = await repositorySave(buildAccountBindingInput(kind, record, accountId))
        if (isStale(expectedGeneration, userId)) return stale(kind)
        if (result.status !== 'accepted') return result

        if (typeof options.onAccepted === 'function') {
          try {
            await options.onAccepted(result, { userId, kind, recordId: record.id, accountId })
          } catch (error) {
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        if (isStale(expectedGeneration, userId)) return stale(kind)

        let refreshStatus = 'not_requested'
        if (typeof options.refresh === 'function') {
          try {
            await options.refresh(result, { userId, kind, recordId: record.id, accountId })
            if (isStale(expectedGeneration, userId)) return stale(kind)
            refreshStatus = 'ok'
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale(kind)
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        return { ...result, refreshStatus }
      } catch (error) {
        if (isStale(expectedGeneration, userId)) return stale(kind)
        return { status: 'failed', reason: 'client_error', kind, record: null, error: messageOf(error) }
      } finally {
        if (requests.get(recordKey)?.promise === request) requests.delete(recordKey)
      }
    })()
    requests.set(recordKey, { accountId: normalizedAccountId, promise: request })
    return request
  }

  function bindBatch(items = [], options = {}) {
    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) return Promise.resolve({ status: 'rejected', reason: 'unauthenticated', items: [], successCount: 0, failedCount: 0 })
    if (!Array.isArray(items) || items.length === 0) {
      return Promise.resolve({ status: 'rejected', reason: 'invalid_input', items: [], successCount: 0, failedCount: 0 })
    }
    const expectedGeneration = generation

    return (async () => {
      const results = []
      for (const item of items) {
        if (isStale(expectedGeneration, userId)) {
          return { status: 'stale', reason: 'session_changed', items: results, successCount: 0, failedCount: 0 }
        }
        const result = await bind(item.kind, item.record, item.accountId, {
          onAccepted: typeof options.onAccepted === 'function'
            ? (accepted, meta) => options.onAccepted(accepted, item, meta)
            : undefined,
        })
        if (result.status === 'stale' || isStale(expectedGeneration, userId)) {
          return { status: 'stale', reason: 'session_changed', items: results, successCount: 0, failedCount: 0 }
        }
        results.push({ ...result, input: item })
      }

      const successCount = results.filter(result => result.status === 'accepted').length
      const failedCount = results.length - successCount
      let status = successCount === 0 ? 'failed' : (failedCount > 0 ? 'partial' : 'accepted')
      let refreshStatus = 'not_requested'
      let refreshError

      if (successCount > 0 && typeof options.refresh === 'function') {
        try {
          await options.refresh({ status, items: results, successCount, failedCount }, { userId })
          if (isStale(expectedGeneration, userId)) {
            return { status: 'stale', reason: 'session_changed', items: results, successCount: 0, failedCount: 0 }
          }
          refreshStatus = 'ok'
        } catch (error) {
          if (isStale(expectedGeneration, userId)) {
            return { status: 'stale', reason: 'session_changed', items: results, successCount: 0, failedCount: 0 }
          }
          refreshStatus = 'failed'
          refreshError = messageOf(error)
        }
      }

      return { status, reason: status === 'failed' ? 'all_failed' : 'bound', items: results, successCount, failedCount, refreshStatus, refreshError }
    })()
  }

  return { reset, bind, bindBatch }
}
