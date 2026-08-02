import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'

const result = await build({
  entryPoints: ['supabase/functions/ingest-receipt/voice-memory.ts'],
  bundle: true,
  platform: 'node',
  format: 'esm',
  write: false,
})
const moduleUrl = 'data:text/javascript;base64,' + Buffer.from(result.outputFiles[0].text).toString('base64')
const { selectRelevantVoiceMemories, validateVoiceSemantics } = await import(moduleUrl)

test('selects merchant purpose memory across spacing aliases', () => {
  const memory = {
    long_term: [
      {
        key: 'merchant_context:example_api_hub',
        content: 'Example API Hub 是开发模型 API 中转站。',
        evidence: { merchant_aliases: ['Example API Hub', 'ExampleAPIHub'] },
      },
      { key: 'merchant:other', content: '其他商户记忆', evidence: { merchant: '其他商户' } },
    ],
  }
  assert.deepEqual(
    selectRelevantVoiceMemories(memory, 'ExampleAPIHub'),
    ['Example API Hub 是开发模型 API 中转站。'],
  )
})

test('does not leak unrelated merchant memories', () => {
  const memory = {
    long_term: [
      { key: 'merchant:coffee', content: '咖啡店用于工作会面。', evidence: { merchant: '咖啡店' } },
    ],
  }
  assert.deepEqual(selectRelevantVoiceMemories(memory, 'Example API Hub'), [])
})

test('merchant repeat rejects judgmental interpretation', () => {
  const result = validateVoiceSemantics(
    ['merchant_repeat'],
    ['这种高频小额支出，往往藏着被忽略的生活惯性。', '建议审视必要性。'],
  )
  assert.equal(result.ok, false)
  assert.equal(result.violations.length, 2)
})

test('merchant repeat allows neutral precise facts', () => {
  const result = validateVoiceSemantics(
    ['merchant_repeat'],
    ['中转站额度补上了。', '本周第4次充值，近90天均价11.97元。'],
  )
  assert.deepEqual(result, { ok: true, violations: [] })
})
