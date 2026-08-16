function normalizeId(value) {
  return String(value || '').trim()
}

function messageOf(error, fallback = '账户详情读取失败') {
  return error?.message || String(error || fallback)
}

function idleSection(data, applicable = true) {
  return { status: 'idle', data, error: null, applicable }
}

function initialSections() {
  return {
    entries: idleSection([]),
    payments: idleSection([]),
    repaymentCycles: idleSection([]),
    sourceSnapshot: idleSection(null, false),
  }
}

function loadingSections(account) {
  const sourceApplicable = account?.sourceRecordTable === 'data_records' && !!account?.sourceRecordId
  const liabilityApplicable = ['credit_card', 'credit_line'].includes(account?.type)
  return {
    entries: { status: 'loading', data: [], error: null, applicable: true },
    payments: liabilityApplicable
      ? { status: 'loading', data: [], error: null, applicable: true }
      : { status: 'accepted', data: [], error: null, applicable: false },
    repaymentCycles: liabilityApplicable
      ? { status: 'loading', data: [], error: null, applicable: true }
      : { status: 'accepted', data: [], error: null, applicable: false },
    sourceSnapshot: sourceApplicable
      ? { status: 'loading', data: null, error: null, applicable: true }
      : { status: 'accepted', data: null, error: null, applicable: false },
  }
}

function failedSection(error, data, applicable = true) {
  return { status: 'failed', data, error: messageOf(error), applicable }
}

async function settle(call, kind = 'rows') {
  try {
    const result = await call()
    const data = kind === 'data' ? (result?.data ?? null) : (result?.rows || [])
    if (result?.status === 'accepted') {
      return {
        status: 'accepted',
        data,
        error: null,
        applicable: result.applicable !== false,
      }
    }
    if (result?.status === 'unavailable') {
      return {
        status: 'unavailable',
        data,
        error: result.error || '当前分区暂不可用',
        applicable: result.applicable !== false,
      }
    }
    return failedSection(result?.error || result?.reason, data, result?.applicable !== false)
  } catch (error) {
    return failedSection(error, kind === 'data' ? null : [])
  }
}

function summarize(sections) {
  const applicable = Object.values(sections).filter(section => section.applicable !== false)
  const successes = applicable.filter(section => section.status === 'accepted').length
  const failures = applicable.length - successes
  if (!failures) return 'accepted'
  if (successes) return 'partial'
  return 'failed'
}

function staleResult() {
  return { status: 'stale', reason: 'identity_changed', sections: null }
}

export function createAccountDetailFeature({
  accountRepository,
  loadSourceSnapshot,
  getCurrentUserId,
  onStateChange = () => {},
}) {
  if (!accountRepository?.listAccountEntries
    || !accountRepository?.listAccountPayments
    || !accountRepository?.listRepaymentCycles
    || !accountRepository?.ensureRepaymentCycles) {
    throw new Error('账户详情缺少 Account Repository')
  }
  if (typeof loadSourceSnapshot !== 'function') throw new Error('账户详情缺少来源快照读取器')
  if (typeof getCurrentUserId !== 'function') throw new Error('账户详情缺少用户状态读取器')

  const requests = new Map()
  let generation = 0
  let currentIdentityKey = ''
  let state = {
    status: 'idle',
    identity: null,
    sections: initialSections(),
    error: null,
  }

  function publish(nextState) {
    state = nextState
    onStateChange(state)
  }

  function getState() {
    return state
  }

  function reset() {
    generation += 1
    currentIdentityKey = ''
    requests.clear()
    publish({ status: 'idle', identity: null, sections: initialSections(), error: null })
  }

  function isStale(identityKey, expectedGeneration, userId) {
    return currentIdentityKey !== identityKey
      || generation !== expectedGeneration
      || normalizeId(getCurrentUserId()) !== userId
  }

  function load(account, options = {}) {
    const userId = normalizeId(getCurrentUserId())
    const accountId = normalizeId(account?.id)
    if (!userId || !accountId) {
      return Promise.resolve({ status: 'failed', reason: 'invalid_identity', sections: initialSections() })
    }

    const expectedGeneration = generation
    const identityKey = `${expectedGeneration}:${userId}:${accountId}`
    const active = requests.get(identityKey)
    if (active) return active

    currentIdentityKey = identityKey
    const identity = { userId, accountId, generation: expectedGeneration }
    publish({ status: 'loading', identity, sections: loadingSections(account), error: null })

    const promise = (async () => {
      const liabilityApplicable = ['credit_card', 'credit_line'].includes(account.type)
      const cyclesPromise = liabilityApplicable ? (async () => {
        let ensureResult = { status: 'accepted', reason: 'not_requested' }
        if (options.ensureCycles) {
          ensureResult = await accountRepository.ensureRepaymentCycles({ cycleMonth: options.cycleMonth })
        }
        const section = await settle(() => accountRepository.listRepaymentCycles({ accountId, limit: 80 }))
        if (ensureResult.status !== 'accepted') {
          return failedSection(ensureResult.error || ensureResult.reason, section.data)
        }
        return section
      })() : Promise.resolve({ status: 'accepted', data: [], error: null, applicable: false })

      const sourceApplicable = account.sourceRecordTable === 'data_records' && !!account.sourceRecordId
      const [entries, payments, repaymentCycles, sourceSnapshot] = await Promise.all([
        settle(() => accountRepository.listAccountEntries({ accountId, limit: 50 })),
        liabilityApplicable
          ? settle(() => accountRepository.listAccountPayments({ accountId, limit: 30 }))
          : Promise.resolve({ status: 'accepted', data: [], error: null, applicable: false }),
        cyclesPromise,
        sourceApplicable
          ? settle(() => loadSourceSnapshot(account), 'data')
          : Promise.resolve({ status: 'accepted', data: null, error: null, applicable: false }),
      ])

      if (isStale(identityKey, expectedGeneration, userId)) return staleResult()

      const sections = { entries, payments, repaymentCycles, sourceSnapshot }
      const status = summarize(sections)
      const result = { status, reason: status === 'accepted' ? 'loaded' : status, accountId, sections }
      publish({ status, identity, sections, error: status === 'failed' ? '账户详情读取失败' : null })
      return result
    })().finally(() => {
      if (requests.get(identityKey) === promise) requests.delete(identityKey)
    })

    requests.set(identityKey, promise)
    return promise
  }

  return { load, refresh: load, reset, getState }
}
