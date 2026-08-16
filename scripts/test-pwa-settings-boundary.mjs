import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const files = {
  store: new URL('../src/composables/useStore.js', import.meta.url),
  settings: new URL('../src/components/pages/PageSettings.vue', import.meta.url),
  vision: new URL('../src/components/pages/PageAiVisionSettings.vue', import.meta.url),
  welcome: new URL('../src/components/ModalWelcome.vue', import.meta.url),
  auth: new URL('../src/components/pages/AuthPage.vue', import.meta.url),
  feature: new URL('../src/features/settings/createSettingsState.js', import.meta.url),
}

test('PWA-008 useStore remains the compatibility surface for settings', async () => {
  const store = await readFile(files.store, 'utf8')

  assert.match(store, /createSettingsState\(\{/)
  assert.match(store, /settingsState,[\s\S]*toggleSetting,[\s\S]*setSetting,[\s\S]*setRetention,[\s\S]*loadUserSettings/)
})

test('PWA-009 settings consumers no longer query user_configs directly', async () => {
  const [settings, vision, welcome, auth] = await Promise.all([
    readFile(files.settings, 'utf8'),
    readFile(files.vision, 'utf8'),
    readFile(files.welcome, 'utf8'),
    readFile(files.auth, 'utf8'),
  ])

  assert.doesNotMatch(settings, /\.from\(['"]user_configs['"]\)/)
  assert.doesNotMatch(vision, /lib\/supabase|\.from\(['"]user_configs['"]\)/)
  assert.doesNotMatch(welcome, /lib\/supabase|\.from\(['"]user_configs['"]\)/)
  assert.doesNotMatch(auth, /lib\/supabase|\.from\(['"]user_configs['"]\)/)
})

test('PWA-013 immediate image cleanup is gated by a successful retention save', async () => {
  const settings = await readFile(files.settings, 'utf8')
  const saveIndex = settings.indexOf('await store.setRetention(')
  const successGuardIndex = settings.indexOf('if (!retentionResult?.ok) return', saveIndex)
  const cleanupIndex = settings.indexOf("action: 'cleanup_all_images'", saveIndex)

  assert.ok(saveIndex >= 0, 'retention must be persisted first')
  assert.ok(successGuardIndex > saveIndex, 'failed retention saves must exit explicitly')
  assert.ok(cleanupIndex > successGuardIndex, 'cleanup may run only after the success guard')
})

test('PWA-014 feature does not reproduce server consent or privacy cleanup rules', async () => {
  const feature = await readFile(files.feature, 'utf8')

  assert.doesNotMatch(feature, /consent_at|withdrawn_at|expression_shadow_runs|delete\s+from/i)
  assert.doesNotMatch(feature, /\bfetch\b|SUPABASE|lib\/supabase/i)
})
