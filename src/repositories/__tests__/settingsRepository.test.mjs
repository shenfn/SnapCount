import test from 'node:test'
import assert from 'node:assert/strict'
import { createSettingsRepository } from '../settingsRepository.js'

function createClient({ reads = [], writeError = null } = {}) {
  const selects = []
  const upserts = []
  return {
    selects,
    upserts,
    from(table) {
      assert.equal(table, 'user_configs')
      return {
        select(fields) {
          selects.push(fields)
          return {
            eq(column, userId) {
              assert.equal(column, 'user_id')
              return {
                async maybeSingle() {
                  const next = reads.shift() || { data: null, error: null }
                  return { ...next, userId }
                },
              }
            },
          }
        },
        async upsert(patch, options) {
          upserts.push({ patch, options })
          return { data: null, error: writeError }
        },
      }
    },
  }
}

test('PWA-012 repository falls back once when modern vision columns are missing', async () => {
  const client = createClient({
    reads: [
      { data: null, error: { code: '42703', message: 'column qwen_photo_model does not exist' } },
      { data: { vision_primary: 'qwen', companion_persona: 'warm' }, error: null },
    ],
  })
  const repository = createSettingsRepository({ client })

  const result = await repository.load('user-1')

  assert.equal(result.legacy, true)
  assert.equal(result.data.vision_primary, 'qwen')
  assert.equal(client.selects.length, 2)
  assert.match(client.selects[0], /qwen_photo_model/)
  assert.doesNotMatch(client.selects[1], /qwen_photo_model/)
})

test('PWA-012 repository does not disguise unrelated read failures as legacy schema', async () => {
  const repository = createSettingsRepository({
    client: createClient({ reads: [{ data: null, error: { code: '42501', message: 'permission denied' } }] }),
  })

  await assert.rejects(repository.load('user-1'), /permission denied/)
})

test('PWA-011 repository rejects non-allowlisted updates before transport', async () => {
  const client = createClient()
  const repository = createSettingsRepository({ client })

  await assert.rejects(
    repository.save('user-1', { monthly_quota: 999 }),
    /不允许更新配置字段/,
  )
  assert.equal(client.upserts.length, 0)
})

test('PWA-011 repository persists allowed fields with a transport timestamp', async () => {
  const client = createClient()
  const repository = createSettingsRepository({
    client,
    now: () => new Date('2026-08-16T00:00:00.000Z'),
  })

  await repository.save('user-1', {
    companion_persona: 'warm',
    expression_improvement_enabled: true,
  })

  assert.deepEqual(client.upserts, [{
    patch: {
      user_id: 'user-1',
      companion_persona: 'warm',
      expression_improvement_enabled: true,
      updated_at: '2026-08-16T00:00:00.000Z',
    },
    options: { onConflict: 'user_id' },
  }])
})
