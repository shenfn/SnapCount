import test from 'node:test'
import assert from 'node:assert/strict'
import { createSettingsState } from '../createSettingsState.js'

function deferred() {
  let resolve
  let reject
  const promise = new Promise((res, rej) => { resolve = res; reject = rej })
  return { promise, resolve, reject }
}

function createRepository({ load, save } = {}) {
  const calls = []
  return {
    calls,
    async load(userId) {
      calls.push(['load', userId])
      return load ? load(userId) : { data: null, legacy: false }
    },
    async save(userId, patch) {
      calls.push(['save', userId, patch])
      return save ? save(userId, patch) : null
    },
  }
}

test('PWA-009 one load hydrates the shared normalized settings snapshot', async () => {
  const repository = createRepository({
    load: async () => ({
      legacy: false,
      data: {
        ai_logs_enabled: true,
        upload_token: 'token-1',
        screenshot_vision_primary: 'qwen',
        qwen_photo_model: 'qwen3.7-plus',
        companion_memory_strength: 'bold',
      },
    }),
  })
  const feature = createSettingsState({ repository })

  const result = await feature.load('user-1')

  assert.equal(result.ok, true)
  assert.equal(feature.settingsState.aiLogsEnabled, true)
  assert.equal(feature.settingsState.uploadToken, 'token-1')
  assert.equal(feature.settingsState.screenshotVisionPrimary, 'qwen')
  assert.equal(feature.settingsState.qwenPhotoModel, 'qwen3.7-plus')
  assert.equal(feature.settingsState.companionMemoryStrength, 'bold')
})

test('PWA-010 reset prevents an old user load from writing into the next session', async () => {
  const firstLoad = deferred()
  const repository = createRepository({ load: () => firstLoad.promise })
  const feature = createSettingsState({ repository })

  const pending = feature.load('user-old')
  feature.reset()
  firstLoad.resolve({ data: { ai_logs_enabled: true }, legacy: false })

  assert.equal((await pending).stale, true)
  assert.equal(feature.settingsState.aiLogsEnabled, false)
  assert.equal(feature.settingsState.uploadToken, '')
})

test('PWA-010 an older forced load cannot overwrite the newest same-user snapshot', async () => {
  const firstLoad = deferred()
  const secondLoad = deferred()
  let loadCount = 0
  const repository = createRepository({
    load: () => (++loadCount === 1 ? firstLoad.promise : secondLoad.promise),
  })
  const feature = createSettingsState({ repository })

  const oldRequest = feature.load('user-1')
  const newRequest = feature.load('user-1', { force: true })
  secondLoad.resolve({ data: { companion_persona: 'minimal' }, legacy: false })
  assert.equal((await newRequest).ok, true)
  firstLoad.resolve({ data: { companion_persona: 'warm' }, legacy: false })

  assert.equal((await oldRequest).stale, true)
  assert.equal(feature.settingsState.companionPersona, 'minimal')
})

test('PWA-011 an old failed update cannot roll back a newer value', async () => {
  const first = deferred()
  const second = deferred()
  let saveCount = 0
  const repository = createRepository({
    save: () => (++saveCount === 1 ? first.promise : second.promise),
  })
  const feature = createSettingsState({ repository })

  const oldUpdate = feature.update('user-1', 'companionPersona', 'warm')
  const newUpdate = feature.update('user-1', 'companionPersona', 'minimal')
  second.resolve(null)
  assert.equal((await newUpdate).ok, true)
  first.reject(new Error('旧请求失败'))

  assert.equal((await oldUpdate).ok, false)
  assert.equal(feature.settingsState.companionPersona, 'minimal')
})

test('PWA-013 retention failure restores both fields and returns an explicit failure', async () => {
  const repository = createRepository({ save: async () => { throw new Error('保存失败') } })
  const feature = createSettingsState({ repository })
  feature.settingsState.keepSourceImages = true
  feature.settingsState.imageRetentionDays = -1

  const result = await feature.updateMany('user-1', {
    keepSourceImages: false,
    imageRetentionDays: 7,
  })

  assert.equal(result.ok, false)
  assert.match(result.error.message, /保存失败/)
  assert.equal(feature.settingsState.keepSourceImages, true)
  assert.equal(feature.settingsState.imageRetentionDays, -1)
})

test('PWA-011 non-allowlisted client keys never reach the repository', async () => {
  const repository = createRepository()
  const feature = createSettingsState({ repository })

  const result = await feature.update('user-1', 'monthlyQuota', 999)

  assert.equal(result.ok, false)
  assert.match(result.error.message, /不允许更新配置字段/)
  assert.equal(repository.calls.length, 0)
})
