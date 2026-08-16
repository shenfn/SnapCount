function messageOf(error) {
  return error?.message || String(error || '截图还款确认失败')
}

function stale() {
  return { status: 'stale', reason: 'session_changed', cycle: null }
}

function rejected(reason) {
  return { status: 'rejected', reason, cycle: null }
}

function normalizeId(value) {
  return String(value || '').trim()
}

export function createScreenshotRepaymentFeature({ repository, getCurrentUserId, now = () => new Date() }) {
  if (!repository?.confirmStagingRepayment) throw new Error('截图还款缺少 Account Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('截图还款缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || normalizeId(getCurrentUserId()) !== userId
  }

  function confirm(command = {}, options = {}) {
    const userId = normalizeId(getCurrentUserId())
    if (!userId) return Promise.resolve(rejected('unauthenticated'))
    const stagingId = normalizeId(command.stagingId)
    const cycleId = normalizeId(command.cycleId)
    const paidAmount = Number(command.paidAmount)
    if (!stagingId || !cycleId || !Number.isFinite(paidAmount) || paidAmount <= 0) {
      return Promise.resolve(rejected('invalid_input'))
    }

    const requestKey = `${userId}:${stagingId}`
    const signature = JSON.stringify({ stagingId, cycleId, paidAmount, debitAccountId: normalizeId(command.debitAccountId) || null })
    const active = requests.get(requestKey)
    if (active) {
      if (active.signature === signature) return active.promise
      return Promise.resolve(rejected('screenshot_repayment_conflict'))
    }

    const expectedGeneration = generation
    const token = Symbol(requestKey)
    const promise = (async () => {
      try {
        const result = await repository.confirmStagingRepayment({
          ...command,
          stagingId,
          cycleId,
          paidAmount,
          paidAt: command.paidAt || now().toISOString(),
        })
        if (isStale(expectedGeneration, userId)) return stale()
        if (result.status !== 'accepted') return result

        let convergenceError = null
        if (typeof options.onAccepted === 'function') {
          try {
            await options.onAccepted(result)
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            convergenceError = messageOf(error)
          }
        }
        if (isStale(expectedGeneration, userId)) return stale()
        let refreshStatus = 'not_requested'
        let refreshError = convergenceError
        if (typeof options.refresh === 'function') {
          try {
            await options.refresh(result)
            if (isStale(expectedGeneration, userId)) return stale()
            refreshStatus = convergenceError ? 'failed' : 'ok'
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            refreshStatus = 'failed'
            refreshError = [convergenceError, messageOf(error)].filter(Boolean).join('；')
          }
        }
        if (convergenceError && refreshStatus === 'not_requested') refreshStatus = 'failed'
        return refreshError ? { ...result, refreshStatus, refreshError } : { ...result, refreshStatus }
      } catch (error) {
        if (isStale(expectedGeneration, userId)) return stale()
        return { status: 'failed', reason: 'client_error', cycle: null, error: messageOf(error) }
      } finally {
        if (requests.get(requestKey)?.token === token) requests.delete(requestKey)
      }
    })()
    requests.set(requestKey, { signature, promise, token })
    return promise
  }

  return { reset, confirm }
}
