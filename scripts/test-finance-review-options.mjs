import assert from 'node:assert/strict'
import {
  buildAdaptiveFinanceOptions,
  normalizeFinanceOptionValue,
} from '../src/domains/financeReviewOptions.js'

const starterPlatforms = buildAdaptiveFinanceOptions({ kind: 'platform' })
assert.equal(starterPlatforms.some(item => item.hot), false, 'starter suggestions must not be marked as user favorites')

const unknownCurrent = buildAdaptiveFinanceOptions({
  kind: 'platform',
  currentValue: '盒马',
  limit: 4,
})
assert.equal(unknownCurrent[0]?.val, '盒马', 'the current recognized value must remain selectable')

const unconfirmedHistory = buildAdaptiveFinanceOptions({
  kind: 'payment',
  transactions: [
    { payment: '云闪付', createdAt: '2026-07-21T10:00:00Z' },
    { payment: '云闪付', createdAt: '2026-07-20T10:00:00Z' },
    { payment: '微信支付', createdAt: '2026-07-19T10:00:00Z' },
  ],
})
assert.equal(
  unconfirmedHistory.some(item => item.val === '云闪付'),
  false,
  'unconfirmed transaction history must not become durable personal vocabulary',
)

const persistedVocabulary = buildAdaptiveFinanceOptions({
  kind: 'payment',
  vocabulary: [{
    kind: 'payment',
    displayName: 'Apple Pay',
    usageCount: 6,
    lastUsedAt: '2026-07-21T11:00:00Z',
    status: 'active',
  }],
})
assert.equal(persistedVocabulary[0]?.val, 'Apple Pay')
assert.equal(persistedVocabulary[0]?.hot, true)

const categories = buildAdaptiveFinanceOptions({
  kind: 'category',
  currentValue: 'health',
})
assert.equal(categories[0]?.val, '健康')
assert.ok(categories.some(item => item.val === '教育'), 'the shared category taxonomy must include education')

assert.equal(normalizeFinanceOptionValue('payment', '花呗（先用后付）'), '先用后付')
assert.equal(normalizeFinanceOptionValue('category', '交通'), '出行')
assert.equal(normalizeFinanceOptionValue('category', '咖啡'), '', 'unknown values must not fragment primary categories')
assert.equal(normalizeFinanceOptionValue('platform', '  Costco  '), 'Costco')

console.log('Finance review options validated.')
