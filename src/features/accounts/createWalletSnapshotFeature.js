function normalizeId(value) {
  return String(value || '').trim()
}

function messageOf(error) {
  return error?.message || String(error || '钱包快照处理失败')
}

function stale() {
  return { status: 'stale', reason: 'session_changed', account: null, cycle: null, payment: null }
}

function rejected(reason) {
  return { status: 'rejected', reason, account: null, cycle: null, payment: null }
}

export function createWalletSnapshotFeature({ repository, getCurrentUserId }) {
  if (!repository?.applyWalletSnapshot) throw new Error('钱包快照缺少 Account Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('钱包快照缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || normalizeId(getCurrentUserId()) !== userId
  }

  function apply(command = {}, hooks = {}) {
    const userId = normalizeId(getCurrentUserId())
    if (!userId) return Promise.resolve(rejected('unauthenticated'))

    const operation = command.operation === 'link' ? 'link' : command.operation === 'create' ? 'create' : ''
    const recordId = normalizeId(command.recordId)
    const accountId = normalizeId(command.accountId)
    if (!operation || !recordId || (operation === 'link' && !accountId)) {
      return Promise.resolve(rejected('invalid_input'))
    }

    const key = `${userId}:${recordId}`
    const signature = JSON.stringify({ operation, accountId: operation === 'link' ? accountId : null })
    const active = requests.get(key)
    if (active) {
      if (active.signature === signature) return active.promise
      return Promise.resolve({ status: 'conflict', reason: 'wallet_snapshot_conflict', account: null, cycle: null, payment: null })
    }

    const expectedGeneration = generation
    const token = Symbol(key)
    const promise = (async () => {
      try {
        const result = await repository.applyWalletSnapshot({
          recordId,
          accountId: operation === 'link' ? accountId : null,
        })
        if (isStale(expectedGeneration, userId)) return stale()
        if (result?.status !== 'accepted') return result?.status ? result : rejected('invalid_response')

        let convergenceError = null
        if (typeof hooks.onAccepted === 'function') {
          try {
            await hooks.onAccepted(result, { userId, operation, recordId, accountId: result.linkedAccountId })
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            convergenceError = messageOf(error)
          }
        }
        if (isStale(expectedGeneration, userId)) return stale()

        let refreshStatus = 'not_requested'
        let refreshError = convergenceError
        if (typeof hooks.refresh === 'function') {
          try {
            await hooks.refresh(result, { userId, operation, recordId, accountId: result.linkedAccountId })
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
        return { status: 'failed', reason: 'client_error', account: null, cycle: null, payment: null, error: messageOf(error) }
      } finally {
        if (requests.get(key)?.token === token) requests.delete(key)
      }
    })()
    requests.set(key, { signature, promise, token })
    return promise
  }

  return { reset, apply }
}
