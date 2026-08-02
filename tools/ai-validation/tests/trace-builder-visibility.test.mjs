import test from 'node:test'
import assert from 'node:assert/strict'
import { buildActualSurfaceOutputs } from '../lib/trace-builder.mjs'

test('only marks an actual shortcut payload as user-visible', () => {
  const outputs = buildActualSurfaceOutputs({ notification: '💸 已记账\n今日已花 45 元（4 笔）' })
  assert.equal(outputs.length, 1)
  assert.equal(outputs[0].output_type, 'ios_shortcut_notification')
  assert.equal(outputs[0].delivery_state, 'returned_to_shortcut')
})

test('does not invent visibility without a rendered notification', () => {
  assert.deepEqual(buildActualSurfaceOutputs({ notification: null }), [])
})
