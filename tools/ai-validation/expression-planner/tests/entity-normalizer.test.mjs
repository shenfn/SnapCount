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

test('EXP-001 resolves one high-confidence administrative and legal-name variant to its historical entity', () => {
  const emptyAliases = compileMerchantAliases({ merchants: [] })
  const prior = resolveMerchant('晨光网络科技工作室', emptyAliases)
  const current = resolveMerchant('示例区晨光网络科技工作室（个体工商户）', emptyAliases)
  const observation = summarizeMerchantObservation(current, [prior])

  assert.equal(observation.entity_id, prior.entity_id)
  assert.equal(observation.entity_first_seen, false)
  assert.equal(observation.alias_first_seen, true)
  assert.equal(observation.resolution, 'historical_legal_variant')
  assert.equal(observation.match_basis, 'administrative_prefix_and_legal_suffix')
  assert.equal(observation.historical_record_count, 1)
  assert.equal(observation.total_record_count, 2)
  assert.deepEqual(observation.observed_aliases, [
    '晨光网络科技工作室',
    '示例区晨光网络科技工作室(个体工商户)',
  ])
})

test('EXP-001 suppresses first occurrence without merging when historical entity ownership is ambiguous', () => {
  const emptyAliases = compileMerchantAliases({ merchants: [] })
  const prior = resolveMerchant('晨光网络科技工作室', emptyAliases)
  const current = resolveMerchant('示例区晨光网络科技工作室（个体工商户）', emptyAliases)
  const observation = summarizeMerchantObservation(current, [
    { ...prior, entity_id: 'merchant-history-a' },
    { ...prior, entity_id: 'merchant-history-b' },
  ])

  assert.equal(observation.entity_id, current.entity_id)
  assert.equal(observation.entity_first_seen, null)
  assert.equal(observation.resolution, 'historical_variant_ambiguous')
  assert.equal(observation.match_basis, 'multiple_historical_entities')
  assert.equal(observation.historical_record_count, 0)
  assert.equal(observation.total_record_count, 1)
})

test('EXP-001 does not merge a longer marketing name whose extra prefix is not administrative', () => {
  const emptyAliases = compileMerchantAliases({ merchants: [] })
  const prior = resolveMerchant('晨光网络科技工作室', emptyAliases)
  const current = resolveMerchant('超级晨光网络科技工作室', emptyAliases)
  const observation = summarizeMerchantObservation(current, [prior])

  assert.equal(observation.entity_id, current.entity_id)
  assert.equal(observation.entity_first_seen, true)
  assert.equal(observation.resolution, 'normalized_fallback')
  assert.equal(observation.historical_record_count, 0)
})
