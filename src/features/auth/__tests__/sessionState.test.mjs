import test from 'node:test'
import assert from 'node:assert/strict'
import { createSessionState } from '../createSessionState.js'

function deferred() {
  let resolve
  let reject
  const promise = new Promise((res, rej) => { resolve = res; reject = rej })
  return { promise, resolve, reject }
}

function createHarness({ loadData = async () => {} } = {}) {
  const identity = { id: '', email: '', loggedIn: false }
  const calls = []
  const session = createSessionState({
    getCurrentUserId: () => identity.id,
    setIdentity(user) {
      identity.id = user.id
      identity.email = user.email || ''
      identity.loggedIn = true
      calls.push(['identity', user.id])
    },
    clearIdentity() {
      identity.id = ''
      identity.email = ''
      identity.loggedIn = false
      calls.push(['clear'])
    },
    resetUserData: () => calls.push(['reset']),
    navigateHome: () => calls.push(['home']),
    loadData: async () => {
      calls.push(['load'])
      return loadData()
    },
  })
  return { identity, calls, session }
}

test('PWA-019 getSession and SIGNED_IN for one user trigger only one initial load', async () => {
  const harness = createHarness()

  await harness.session.applySession({ user: { id: 'user-1', email: 'a@example.com' } })
  await harness.session.handleAuthEvent('SIGNED_IN', { user: { id: 'user-1', email: 'a@example.com' } })
  await harness.session.handleAuthEvent('TOKEN_REFRESHED', { user: { id: 'user-1', email: 'a@example.com' } })

  assert.equal(harness.calls.filter(([kind]) => kind === 'load').length, 1)
  assert.equal(harness.identity.id, 'user-1')
})

test('PWA-020 switching users invalidates the previous session load', async () => {
  const firstLoad = deferred()
  let loadCount = 0
  const harness = createHarness({
    loadData: () => (++loadCount === 1 ? firstLoad.promise : Promise.resolve()),
  })

  const oldSession = harness.session.applySession({ user: { id: 'user-a' } })
  const newSession = harness.session.applySession({ user: { id: 'user-b' } })
  await newSession
  firstLoad.resolve()

  assert.equal((await oldSession).stale, true)
  assert.equal(harness.identity.id, 'user-b')
  assert.equal(harness.calls.filter(([kind]) => kind === 'reset').length, 1)
})

test('PWA-021 signing out invalidates an in-flight load and clears state immediately', async () => {
  const pendingLoad = deferred()
  const harness = createHarness({ loadData: () => pendingLoad.promise })

  const signedIn = harness.session.applySession({ user: { id: 'user-1' } })
  const signedOut = harness.session.handleAuthEvent('SIGNED_OUT', null)
  assert.equal(harness.identity.loggedIn, false)
  pendingLoad.resolve()

  assert.equal((await signedIn).stale, true)
  assert.equal((await signedOut).ok, true)
})
