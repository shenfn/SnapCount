import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const files = {
  app: new URL('../src/App.vue', import.meta.url),
  authPage: new URL('../src/components/pages/AuthPage.vue', import.meta.url),
  store: new URL('../src/composables/useStore.js', import.meta.url),
  feature: new URL('../src/features/auth/createSessionState.js', import.meta.url),
}

test('PWA-018 App owns auth events and AuthPage does not write session state', async () => {
  const [app, authPage] = await Promise.all([
    readFile(files.app, 'utf8'),
    readFile(files.authPage, 'utf8'),
  ])

  assert.match(app, /store\.initializeAuth\(\)/)
  assert.match(app, /authUnsubscribe\?\.\(\)/)
  assert.doesNotMatch(authPage, /lib\/supabase|\.from\(['"]user_configs['"]\)/)
  assert.doesNotMatch(authPage, /currentUserId\.value\s*=|currentUserEmail\.value\s*=|isLoggedIn\.value\s*=|store\.loadData\(/)
  assert.doesNotMatch(authPage, /setTimeout\(|submit\(attempt|return submit\(/)
  assert.match(authPage, /store\.signIn\(|store\.signUp\(/)
})

test('PWA-020 loadData guards main writes by run and user identity', async () => {
  const store = await readFile(files.store, 'utf8')
  const promiseIndex = store.indexOf('] = await Promise.all([')
  const guardIndex = store.indexOf('if (!isCurrentDataLoad()) return', promiseIndex)
  const firstWriteIndex = store.indexOf('bills.value =', promiseIndex)

  assert.ok(promiseIndex >= 0, 'main data query batch must remain visible')
  assert.ok(guardIndex > promiseIndex, 'main query results need a stale-session guard')
  assert.ok(firstWriteIndex > guardIndex, 'guard must run before the first main state write')
  assert.match(store, /const expectedUserId = currentUserId\.value/)
  assert.match(store, /runId === loadDataRunId\s*&&\s*currentUserId\.value === expectedUserId/)
  assert.match(store, /function resetUserData\(\)[\s\S]*loadDataRunId \+= 1/)
})

test('PWA-025 auth feature remains free of Supabase, Vue and settings rules', async () => {
  const feature = await readFile(files.feature, 'utf8')

  assert.doesNotMatch(feature, /lib\/supabase|SUPABASE|\bfetch\b|from ['"]vue['"]/)
  assert.doesNotMatch(feature, /user_configs|settingsState|consent_at|terms_version|privacy_version/)
})

test('PWA-021 session reset clears account, insight and signed-image user state', async () => {
  const store = await readFile(files.store, 'utf8')
  const resetStart = store.indexOf('function resetUserData()')
  const resetEnd = store.indexOf('\n  function isActionPending', resetStart)
  const reset = store.slice(resetStart, resetEnd)

  assert.match(reset, /accounts\.value = \[\]/)
  assert.match(reset, /selectedAccountEntries\.value = \[\]/)
  assert.match(reset, /unboundRecords\.value = \{ expenses: \[\], incomes: \[\] \}/)
  assert.match(reset, /dailySummary\.value = \[\]/)
  assert.match(reset, /aiInsight\.value = null/)
  assert.match(reset, /signedImageUrlCache\.clear\(\)/)
})
