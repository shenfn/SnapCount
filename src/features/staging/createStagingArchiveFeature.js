const FINANCE_DOMAINS = new Set(['expense', 'income'])

function messageOf(error) {
  return error?.message || String(error || '中转归档失败')
}

function validAmount(value) {
  const amount = Number(value)
  return Number.isFinite(amount) && amount > 0
}

export function createStagingArchiveFeature({ repository, getCurrentUserId }) {
  if (!repository?.archive) throw new Error('中转归档缺少 Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('中转归档缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function archive(record, domainKey, options = {}) {
    const recordId = String(record?.id || '').trim()
    const normalizedDomain = String(domainKey || '').trim()
    if (!recordId) {
      return Promise.resolve({ status: 'rejected', reason: 'missing_record_id', recordStillVisible: true })
    }
    if (!normalizedDomain) {
      return Promise.resolve({ status: 'rejected', reason: 'missing_domain', recordId, recordStillVisible: true })
    }

    const userId = String(getCurrentUserId() || '').trim()
    if (!userId) {
      return Promise.resolve({ status: 'rejected', reason: 'unauthenticated', recordId, recordStillVisible: true })
    }

    const payload = options.payload && typeof options.payload === 'object' ? options.payload : {}
    const amount = options.amount ?? payload.amount
    if (FINANCE_DOMAINS.has(normalizedDomain) && !validAmount(amount)) {
      return Promise.resolve({
        status: 'rejected',
        reason: 'missing_amount',
        recordId,
        recordStillVisible: true,
        requiresManualCompletion: true,
      })
    }

    const requestKey = `${recordId}:${normalizedDomain}`
    if (requests.has(requestKey)) return requests.get(requestKey)
    const expectedGeneration = generation
    const request = (async () => {
      try {
        const result = await repository.archive({
          stagingId: recordId,
          domainKey: normalizedDomain,
          amount: amount ?? null,
          title: options.title ?? payload.title ?? null,
          platform: options.platform ?? payload.platform ?? null,
          category: options.category ?? payload.category ?? null,
          paymentMethod: options.paymentMethod ?? payload.payment_method ?? null,
          incomeCategory: options.incomeCategory ?? payload.income_category ?? null,
          recordDate: options.recordDate ?? payload.record_date ?? payload.transaction_date ?? payload.income_date ?? null,
          recordTime: options.recordTime ?? payload.record_time ?? payload.transaction_time ?? null,
          occurredAt: options.occurredAt ?? payload.occurred_at ?? payload.order_finished_at ?? null,
          summary: options.summary ?? null,
          payload,
          accountId: options.accountId ?? payload.account_id ?? null,
        })
        if (generation !== expectedGeneration || String(getCurrentUserId() || '').trim() !== userId) {
          return { status: 'stale', reason: 'session_changed', recordId, recordStillVisible: true }
        }

        if (result.status !== 'accepted') return result

        let refreshStatus = 'not_requested'
        if (typeof options.afterAccepted === 'function') {
          try {
            await options.afterAccepted(result)
            refreshStatus = 'ok'
          } catch (error) {
            refreshStatus = 'failed'
            return {
              ...result,
              refreshStatus,
              refreshError: messageOf(error),
              recordStillVisible: false,
            }
          }
        }
        return { ...result, refreshStatus }
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
        if (requests.get(requestKey) === request) requests.delete(requestKey)
      }
    })()
    requests.set(requestKey, request)
    return request
  }

  return { reset, archive }
}
