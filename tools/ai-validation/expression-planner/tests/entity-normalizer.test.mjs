import test from 'node:test'
import assert from 'node:assert/strict'
import {
  compileMerchantAliases,
  normalizeEntityText,
  resolveMerchant,
  summarizeMerchantObservation,
} from '../lib/entity-normalizer.mjs'

const aliases = compileMerchantAliases({
  merchants: [{
    entity_id: 'merchant_example_api_hub',
    canonical_name: 'Example API Hub',
    aliases: ['ExampleAPIHub'],
  }],
})

test('normalizes merchant whitespace', () => {
  assert.equal(normalizeEntityText(' Example API Hub '), 'exampleapihub')
})

test('resolves aliases to one entity', () => {
  assert.equal(resolveMerchant('ExampleAPIHub', aliases).entity_id, 'merchant_example_api_hub')
  assert.equal(resolveMerchant('Example API Hub', aliases).entity_id, 'merchant_example_api_hub')
})

test('keeps raw aliases while separating entity and alias novelty', () => {
  const configured = compileMerchantAliases({
    merchants: [{
      entity_id: 'merchant_example',
      canonical_name: '示例商店',
      aliases: ['示例科技有限公司'],
    }],
  })
  const prior = resolveMerchant('示例商店', configured)
  const current = resolveMerchant('示例科技有限公司', configured)
  const observation = summarizeMerchantObservation(current, [prior])

  assert.equal(observation.entity_first_seen, false)
  assert.equal(observation.alias_first_seen, true)
  assert.deepEqual(observation.observed_aliases, ['示例商店', '示例科技有限公司'])
})

test('marks a genuinely new merchant entity', () => {
  const current = resolveMerchant('第一次出现的商店', aliases)
  const observation = summarizeMerchantObservation(current, [])
  assert.equal(observation.entity_first_seen, true)
  assert.equal(observation.alias_first_seen, true)
})
