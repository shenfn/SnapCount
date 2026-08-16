function normalizeId(value) {
  return String(value || '').trim()
}

function messageOf(error) {
  return error?.message || String(error || '账户操作失败')
}

function stale() {
  return { status: 'stale', reason: 'session_changed', account: null }
}

function conflict() {
  return { status: 'conflict', reason: 'account_command_conflict', account: null }
}

function signatureOf(operation, command) {
  return JSON.stringify({
    operation,
    accountId: normalizeId(command?.accountId) || null,
    commandKey: normalizeId(command?.commandKey) || null,
    name: command?.name || '',
    type: command?.type || '',
    institution: command?.institution || null,
    last4: command?.last4 || null,
    initialBalance: command?.initialBalance == null ? 0 : Number(command.initialBalance),
    billDay: command?.billDay == null ? null : Number(command.billDay),
    paymentDueDay: command?.paymentDueDay == null ? null : Number(command.paymentDueDay),
    autoDebitAccountId: normalizeId(command?.autoDebitAccountId) || null,
    autoConfirmRepayment: !!command?.autoConfirmRepayment,
    isDefaultExpense: !!command?.isDefaultExpense,
    isDefaultIncome: !!command?.isDefaultIncome,
    archived: !!command?.archived,
  })
}

export function createAccountManagementFeature({ repository, getCurrentUserId }) {
  if (!repository?.saveAccount || !repository?.setAccountArchived) throw new Error('账户管理缺少 Account Repository')
  if (typeof getCurrentUserId !== 'function') throw new Error('账户管理缺少用户状态读取器')

  const requests = new Map()
  let generation = 0

  function reset() {
    generation += 1
    requests.clear()
  }

  function isStale(expectedGeneration, userId) {
    return generation !== expectedGeneration || normalizeId(getCurrentUserId()) !== userId
  }

  function requestKey(operation, command, userId) {
    const accountId = normalizeId(command?.accountId)
    if (accountId) return `${userId}:account:${accountId}`
    return `${userId}:create:${normalizeId(command?.commandKey)}`
  }

  function execute(operation, command = {}, hooks = {}) {
    const userId = normalizeId(getCurrentUserId())
    if (!userId) return Promise.resolve({ status: 'failed', reason: 'unauthenticated', account: null })

    const accountId = normalizeId(command.accountId)
    if ((operation === 'save' && !normalizeId(command.name)) || (operation === 'archive' && !accountId)) {
      return Promise.resolve({ status: 'failed', reason: 'invalid_input', account: null })
    }
    if (operation === 'save' && !accountId && !normalizeId(command.commandKey)) {
      return Promise.resolve({ status: 'failed', reason: 'invalid_input', account: null })
    }

    const key = requestKey(operation, command, userId)
    const signature = signatureOf(operation, command)
    const active = requests.get(key)
    if (active) return active.signature === signature ? active.promise : Promise.resolve(conflict())

    const expectedGeneration = generation
    const token = Symbol(key)
    const transport = operation === 'save'
      ? repository.saveAccount
      : repository.setAccountArchived
    const promise = (async () => {
      try {
        const result = await Promise.resolve().then(() => transport(command))
        if (isStale(expectedGeneration, userId)) return stale()
        if (result?.status !== 'accepted' || !result.account?.id) return result?.status ? result : { status: 'failed', reason: 'invalid_response', account: null }

        if (typeof hooks.onAccepted === 'function') {
          try {
            await hooks.onAccepted(result.account, { userId, operation, accountId: result.account.id })
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        if (isStale(expectedGeneration, userId)) return stale()

        let refreshStatus = 'not_requested'
        if (typeof hooks.refresh === 'function') {
          try {
            const refreshResult = await hooks.refresh(result.account, { userId, operation, accountId: result.account.id })
            if (isStale(expectedGeneration, userId)) return stale()
            if (refreshResult?.status === 'failed') {
              return { ...result, refreshStatus: 'failed', refreshError: refreshResult.error || refreshResult.reason || '账户列表刷新失败' }
            }
            refreshStatus = 'ok'
          } catch (error) {
            if (isStale(expectedGeneration, userId)) return stale()
            return { ...result, refreshStatus: 'failed', refreshError: messageOf(error) }
          }
        }
        return { ...result, refreshStatus }
      } catch (error) {
        if (isStale(expectedGeneration, userId)) return stale()
        return { status: 'failed', reason: 'client_error', account: null, error: messageOf(error) }
      } finally {
        if (requests.get(key)?.token === token) requests.delete(key)
      }
    })()
    requests.set(key, { signature, promise, token })
    return promise
  }

  return {
    reset,
    save: (command, hooks) => execute('save', command, hooks),
    setArchived: (command, hooks) => execute('archive', command, hooks),
  }
}
