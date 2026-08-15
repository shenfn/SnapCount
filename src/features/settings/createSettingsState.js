import {
  createDefaultSettingsState,
  normalizeSettingsRow,
  prepareSettingsPatch,
} from './settingsConfig.js'

export function createSettingsState({
  repository,
  state = createDefaultSettingsState(),
}) {
  if (!repository?.load || !repository?.save) throw new Error('设置状态缺少 Repository')

  const settingsState = state
  const loadRequests = new Map()
  const fieldRevisions = new Map()
  let activeUserId = ''
  let generation = 0
  let stateRevision = 0
  let loadRevision = 0

  function replaceState(next) {
    Object.assign(settingsState, createDefaultSettingsState(), next)
  }

  function reset() {
    generation += 1
    stateRevision += 1
    loadRevision += 1
    activeUserId = ''
    loadRequests.clear()
    fieldRevisions.clear()
    replaceState(createDefaultSettingsState())
  }

  function activate(userId) {
    const normalizedUserId = String(userId || '').trim()
    if (!normalizedUserId) return ''
    if (activeUserId && activeUserId !== normalizedUserId) reset()
    activeUserId = normalizedUserId
    return normalizedUserId
  }

  function isCurrent(userId, expectedGeneration) {
    return activeUserId === userId && generation === expectedGeneration
  }

  function load(userId, { force = false } = {}) {
    const normalizedUserId = activate(userId)
    if (!normalizedUserId) {
      reset()
      return Promise.resolve({ ok: true, data: settingsState, anonymous: true })
    }
    if (!force && loadRequests.has(normalizedUserId)) return loadRequests.get(normalizedUserId)

    const expectedGeneration = generation
    const expectedStateRevision = stateRevision
    const expectedLoadRevision = ++loadRevision
    settingsState.settingsLoading = true
    settingsState.settingsError = ''
    const request = (async () => {
      try {
        const result = await repository.load(normalizedUserId)
        if (!isCurrent(normalizedUserId, expectedGeneration)
          || loadRevision !== expectedLoadRevision
          || stateRevision !== expectedStateRevision) return { ok: false, stale: true }
        replaceState(normalizeSettingsRow(result.data || {}, { legacy: result.legacy }))
        return { ok: true, data: settingsState, legacy: result.legacy }
      } catch (error) {
        if (!isCurrent(normalizedUserId, expectedGeneration)
          || loadRevision !== expectedLoadRevision
          || stateRevision !== expectedStateRevision) return { ok: false, stale: true, error }
        settingsState.settingsLoading = false
        settingsState.settingsError = error?.message || String(error)
        return { ok: false, error }
      }
    })()
    loadRequests.set(normalizedUserId, request)
    request.finally(() => {
      if (loadRequests.get(normalizedUserId) === request) loadRequests.delete(normalizedUserId)
    }).catch(() => {})
    return request
  }

  function updateMany(userId, clientPatch) {
    const normalizedUserId = activate(userId)
    if (!normalizedUserId) {
      return Promise.resolve({ ok: false, error: new Error('请先登录') })
    }

    let prepared
    try {
      prepared = prepareSettingsPatch(clientPatch)
    } catch (error) {
      return Promise.resolve({ ok: false, error })
    }

    const keys = Object.keys(prepared.statePatch)
    const previous = Object.fromEntries(keys.map(key => [key, settingsState[key]]))
    const revisions = {}
    for (const key of keys) {
      const revision = (fieldRevisions.get(key) || 0) + 1
      fieldRevisions.set(key, revision)
      revisions[key] = revision
    }
    const expectedGeneration = generation
    stateRevision += 1
    Object.assign(settingsState, prepared.statePatch)
    settingsState.settingsError = ''

    return (async () => {
      try {
        await repository.save(normalizedUserId, prepared.databasePatch)
        if (!isCurrent(normalizedUserId, expectedGeneration)) return { ok: false, stale: true }
        return { ok: true, data: settingsState }
      } catch (error) {
        if (isCurrent(normalizedUserId, expectedGeneration)) {
          for (const key of keys) {
            if (fieldRevisions.get(key) === revisions[key]
              && Object.is(settingsState[key], prepared.statePatch[key])) {
              settingsState[key] = previous[key]
            }
          }
          settingsState.settingsError = error?.message || String(error)
        }
        return { ok: false, error }
      }
    })()
  }

  function update(userId, key, value) {
    return updateMany(userId, { [key]: value })
  }

  return {
    settingsState,
    load,
    reset,
    update,
    updateMany,
  }
}
