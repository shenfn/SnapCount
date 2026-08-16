export function createSessionState({
  getCurrentUserId,
  setIdentity,
  clearIdentity,
  resetUserData,
  navigateHome,
  loadData,
}) {
  if (![getCurrentUserId, setIdentity, clearIdentity, resetUserData, navigateHome, loadData]
    .every(value => typeof value === 'function')) {
    throw new Error('会话状态缺少必要依赖')
  }

  let activeUserId = String(getCurrentUserId() || '')
  let generation = 0

  async function applySession(session) {
    const user = session?.user
    const userId = String(user?.id || '').trim()
    if (!userId) return { ok: false, anonymous: true }

    const sameUser = activeUserId === userId && String(getCurrentUserId() || '') === userId
    if (sameUser) {
      setIdentity(user)
      return { ok: true, duplicate: true }
    }

    const switchingUser = Boolean(activeUserId && activeUserId !== userId)
    generation += 1
    const expectedGeneration = generation
    if (switchingUser) resetUserData()
    activeUserId = userId
    setIdentity(user)
    navigateHome()

    try {
      const loadResult = await loadData()
      if (generation !== expectedGeneration || activeUserId !== userId) {
        return { ok: false, stale: true }
      }
      if (loadResult?.ok === false) {
        return {
          ok: false,
          dataLoadFailed: !loadResult.stale,
          stale: Boolean(loadResult.stale),
          error: loadResult.error,
        }
      }
      return { ok: true, userId }
    } catch (error) {
      if (generation !== expectedGeneration || activeUserId !== userId) {
        return { ok: false, stale: true, error }
      }
      return { ok: false, dataLoadFailed: true, error }
    }
  }

  function signOut() {
    generation += 1
    activeUserId = ''
    resetUserData()
    clearIdentity()
    navigateHome()
    return { ok: true }
  }

  function handleAuthEvent(event, session) {
    if (event === 'SIGNED_OUT') return Promise.resolve(signOut())
    if (session?.user) return applySession(session)
    return Promise.resolve({ ok: true, ignored: true })
  }

  return { applySession, handleAuthEvent, signOut }
}
