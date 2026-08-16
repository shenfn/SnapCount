function messageOf(error) {
  return error?.message || String(error || '账户还款失败')
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

function confirmSignature(command) {
  return JSON.stringify({
    operation: 'confirm',
    cycleId: normalizeId(command.cycleId),
    accountId: normalizeId(command.accountId),
    paidAmount: Number(command.paidAmount),
    debitAccountId: normalizeId(command.debitAccountId) || null,
    status: command.status || null,
    note: command.note || null,
  })
}

function revokeSignature(command) {
  return JSON.stringify({
    operation: 'revoke',
    paymentId: normalizeId(command.paymentId),
    cycleId: normalizeId(command.cycleId),
    accountId: normalizeId(command.accountId),
    reason: command.reason || null,
  })
}

export function createRepaymentFeature({ repository, getCurrentUserId, now = () => new Date() }) {
  if (!repository?.confirmRepayment || !repository?.revokePayment) throw new Error('账户还款缺少 Account Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('账户还款缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || normalizeId(getCurrentUserId()) !== userId
  }

  function execute(operation, command, options = {}) {
    const userId = normalizeId(getCurrentUserId())
    if (!userId) return Promise.resolve(rejected('unauthenticated'))

    const cycleId = normalizeId(command?.cycleId)
    const accountId = normalizeId(command?.accountId)
    const isConfirm = operation === 'confirm'
    const paidAmount = Number(command?.paidAmount)
    const paymentId = normalizeId(command?.paymentId)
    if (!cycleId || !accountId || (isConfirm ? (!Number.isFinite(paidAmount) || paidAmount <= 0) : !paymentId)) {
      return Promise.resolve(rejected('invalid_input'))
    }

    const requestKey = `${userId}:${cycleId}`
    const signature = isConfirm ? confirmSignature(command) : revokeSignature(command)
    const active = requests.get(requestKey)
    if (active) {
      if (active.signature === signature) return active.promise
      return Promise.resolve(rejected('repayment_conflict'))
    }

    const expectedGeneration = generation
    const token = Symbol(requestKey)
    const transportCommand = isConfirm
      ? { ...command, paidAmount, paidAt: command.paidAt || now().toISOString() }
      : command
    const repositoryCall = isConfirm ? repository.confirmRepayment : repository.revokePayment
    const promise = (async () => {
      try {
        const result = await Promise.resolve().then(() => repositoryCall(transportCommand))
        if (isStale(expectedGeneration, userId)) return stale()
        if (result.status !== 'accepted') return result

        if (typeof options.onAccepted === 'function') {
          try {
            await options.onAccepted(result, { userId, operation, cycleId, accountId })
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        if (isStale(expectedGeneration, userId)) return stale()

        let refreshStatus = 'not_requested'
        if (typeof options.refresh === 'function') {
          try {
            await options.refresh(result, { userId, operation, cycleId, accountId })
            if (isStale(expectedGeneration, userId)) return stale()
            refreshStatus = 'ok'
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        return { ...result, refreshStatus }
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

  return {
    reset,
    confirm: (command, options) => execute('confirm', command, options),
    revoke: (command, options) => execute('revoke', command, options),
  }
}
