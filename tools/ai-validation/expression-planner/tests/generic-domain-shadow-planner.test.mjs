import test from 'node:test'
import assert from 'node:assert/strict'
import { build } from 'esbuild'
import { parseFiniteNumber } from '../lib/generic-domain-candidates.mjs'

const bundle = await build({ entryPoints: ['supabase/functions/ingest-receipt/expression-shadow-planner.ts'], bundle: true, platform: 'node', format: 'esm', write: false })
const { buildExpressionShadowPlan, buildGenericExpressionShadowPlan } = await import('data:text/javascript;base64,' + Buffer.from(bundle.outputFiles[0].text).toString('base64'))

function walletRecord({
  id,
  occurredAt,
  balance,
  linkedAccountId = 'account-1',
  kind = 'asset',
  accountName = '微信余额',
  snapshotAt = null,
  payload = {},
}) {
  return {
    id,
    occurred_at: occurredAt,
    linked_account_id: linkedAccountId,
    account_snapshot_kind: kind,
    snapshot_balance: balance,
    snapshot_at: snapshotAt,
    payload: {
      account_name: accountName,
      record_kind: kind === 'liability' ? 'liability_snapshot' : 'cash_snapshot',
      ...payload,
    },
  }
}

function candidate(plan, semanticKey) {
  return plan.candidates.find(item => item.claim.semantic_key === semanticKey)
}

test('strict numeric parsing rejects missing and non-numeric values but preserves zero', () => {
  for (const value of [null, undefined, '', '  ', true, false, {}, [], NaN, Infinity, 'not-a-number']) {
    assert.equal(parseFiniteNumber(value), null)
  }
  assert.equal(parseFiniteNumber(0), 0)
  assert.equal(parseFiniteNumber('0'), 0)
  assert.equal(parseFiniteNumber(' 12.50 '), 12.5)
})

test('income planner recognizes fixed notification coverage and keeps richer plans for details', () => {
  const records = [
    { id: 'i1', occurred_at: '2026-07-01T12:00:00+08:00', amount: 1000, source_name: '项目款' },
    { id: 'i2', occurred_at: '2026-07-13T12:00:00+08:00', amount: 500, source_name: '项目款' },
  ]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'income', records, currentRecordId: 'i2' })
  assert.equal(plan.status, 'auto_planned')
  assert.equal(plan.domain_key, 'income')
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_month_total_count'))
  assert.ok(plan.candidates.some(item => item.claim.semantic_key === 'income_source_month_pattern'))
  assert.equal(plan.shortcut_plan.silent, true)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('sleep planner creates a personal median comparison from history', () => {
  const records = [6, 7, 7.5, 8, 5.5, 6.5, 7, 8.5].map((hours, index) => ({
    id: 's' + index, occurred_at: `2026-07-${String(index + 1).padStart(2, '0')}T08:00:00+08:00`, payload: { sleep_hours: hours },
  }))
  records.push({ id: 'current', occurred_at: '2026-07-13T08:00:00+08:00', payload: { sleep_hours: 5 } })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records, currentRecordId: 'current' })
  const comparison = plan.candidates.find(item => item.claim.semantic_key === 'sleep_vs_personal_median')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.sample_count, 8)
  assert.ok(plan.plan_summary.record_detail.selected_count >= 1)
})

test('sleep baseline only uses records known before the current record', () => {
  const records = [6, 7, 8].map((hours, index) => ({
    id: `past-${index}`,
    created_at: `2026-07-0${index + 1}T09:00:00+08:00`,
    occurred_at: `2026-07-0${index + 1}T08:00:00+08:00`,
    payload: { sleep_hours: hours },
  }))
  records.push({
    id: 'current-causal', created_at: '2026-07-05T09:00:00+08:00', occurred_at: '2026-07-05T08:00:00+08:00',
    payload: { sleep_hours: 5 },
  })
  records.push({
    id: 'future-record', created_at: '2026-07-06T09:00:00+08:00', occurred_at: '2026-07-06T08:00:00+08:00',
    payload: { sleep_hours: 12 },
  })

  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records, currentRecordId: 'current-causal' })
  const comparison = candidate(plan, 'sleep_vs_personal_median')
  assert.equal(comparison.claim.structured_value.sample_count, 3)
  assert.equal(comparison.claim.structured_value.median, 7)
})

test('sleep baseline folds exact duplicate rows for the same sleep event', () => {
  function sleepEvent(id, day, hours, createdAt) {
    return {
      id,
      created_at: createdAt,
      occurred_at: `2026-07-${day}T08:00:00+08:00`,
      payload: {
        sleep_hours: hours,
        sleep_minutes: hours * 60,
        sleep_start_at: `2026-07-${day}T01:00:00+08:00`,
        wake_at: `2026-07-${day}T08:00:00+08:00`,
        deep_sleep_minutes: 120,
        light_sleep_minutes: hours * 60 - 160,
        rem_minutes: 40,
      },
    }
  }
  const records = [
    sleepEvent('event-a', '01', 6, '2026-07-01T08:05:00+08:00'),
    sleepEvent('event-a-duplicate', '01', 6, '2026-07-01T08:06:00+08:00'),
    sleepEvent('event-b', '02', 7, '2026-07-02T08:05:00+08:00'),
    sleepEvent('event-c', '03', 8, '2026-07-03T08:05:00+08:00'),
    sleepEvent('current-dedup', '05', 5, '2026-07-05T08:05:00+08:00'),
  ]

  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records, currentRecordId: 'current-dedup' })
  const comparison = candidate(plan, 'sleep_vs_personal_median')
  assert.equal(comparison.claim.structured_value.sample_count, 3)
  assert.equal(comparison.claim.structured_value.median, 7)
})

test('sleep planner falls back to sleep_minutes when sleep_hours is null', () => {
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'sleep',
    records: [{ id: 'sleep-current-null-hours', occurred_at: '2026-07-14T08:00:00+08:00', payload: { sleep_hours: null, sleep_minutes: 390 } }],
    currentRecordId: 'sleep-current-null-hours',
  })
  assert.equal(candidate(plan, 'sleep_current_metric').claim.structured_value.value, 6.5)
})

test('food planner reads the production total_calorie_kcal field', () => {
  const records = [{
    id: 'food-current',
    occurred_at: '2026-07-14T19:00:00+08:00',
    payload: { total_calorie_kcal: 638, meal_type: 'dinner' },
  }]
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records, currentRecordId: 'food-current' })
  const fact = plan.candidates.find(item => item.claim.semantic_key === 'food_current_metric')
  assert.ok(fact)
  assert.equal(fact.claim.structured_value.value, 638)
  assert.equal(fact.claim.structured_value.unit, '千卡')
})

test('food planner keeps meal and dish context when calories are missing', () => {
  const current = {
    id: 'food-context-only',
    occurred_at: '2026-07-14T08:31:00+08:00',
    payload: { meal_type: 'breakfast', dishes: [{ name: '全麦面包' }] },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records: [current], currentRecordId: current.id })
  const context = candidate(plan, 'food_record_context')

  assert.ok(context)
  assert.equal(candidate(plan, 'food_current_metric'), undefined)
  assert.equal(context.claim.structured_value.meal_type, 'breakfast')
  assert.deepEqual(context.claim.structured_value.dish_names, ['全麦面包'])
  assert.equal(context.numbers[0].value, 1)
  assert.equal(plan.shortcut_plan.silent, true)
  assert.equal(plan.plan_summary.record_detail.selected[0].semantic_key, 'food_record_context')
})

test('food planner exposes time, meal, dish, and composition facts', () => {
  const history = [1, 2, 3].map(index => ({
    id: `food-history-${index}`,
    occurred_at: `2026-07-${String(index).padStart(2, '0')}T19:00:00+08:00`,
    payload: { total_calorie_kcal: 600 + index, meal_type: 'dinner', dishes: [{ name: '鸡腿饭', protein_g: 25, carb_g: 50, fat_g: 18 }] },
  }))
  const current = {
    id: 'food-rich-current',
    occurred_at: '2026-07-14T19:00:00+08:00',
    payload: {
      total_calorie_kcal: 638,
      meal_type: 'dinner',
      dishes: [{ name: '鸡腿饭', protein_g: 25, carb_g: 50, fat_g: 18 }],
    },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'food', records: [...history, current], currentRecordId: current.id })
  assert.ok(candidate(plan, 'food_record_context'))
  assert.ok(candidate(plan, 'food_composition'))
  assert.ok(candidate(plan, 'food_meal_vs_personal_median'))
  assert.equal(candidate(plan, 'food_composition').dimension, 'record_composition')
})

test('food planner uses a sufficiently supported meal profile', () => {
  const current = { id: 'food-profile-current', occurred_at: '2026-07-14T19:00:00+08:00', payload: { total_calorie_kcal: 638, meal_type: 'dinner' } }
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'food', records: [current], currentRecordId: current.id,
    domainProfile: { meal_baseline: { dinner: { n: 11, median_kcal: 750 } } },
  })
  const comparison = candidate(plan, 'food_meal_vs_personal_median')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.median, 750)
  assert.equal(comparison.claim.structured_value.baseline_source, 'domain_profile')
})

test('sleep planner exposes timing, quality, and partial stage facts', () => {
  const history = [1, 2, 3].map(index => ({
    id: `sleep-history-${index}`,
    occurred_at: `2026-07-${String(index).padStart(2, '0')}T08:00:00+08:00`,
    payload: { sleep_hours: 7, quality_score: 80 },
  }))
  const current = {
    id: 'sleep-rich-current',
    occurred_at: '2026-07-14T08:00:00+08:00',
    payload: {
      sleep_hours: 7.18,
      quality_score: 82,
      sleep_start_at: '2026-07-14T01:10:00+08:00',
      wake_at: '2026-07-14T08:20:00+08:00',
      deep_sleep_minutes: 90,
      light_sleep_minutes: 240,
      rem_minutes: null,
    },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records: [...history, current], currentRecordId: current.id })
  assert.ok(candidate(plan, 'sleep_timing'))
  assert.ok(candidate(plan, 'sleep_quality_current'))
  const stages = candidate(plan, 'sleep_stage_composition')
  assert.ok(stages)
  assert.equal(stages.claim.structured_value.rem_minutes, null)
  assert.equal(stages.quality.data_coverage, 2 / 3)
})

test('sleep planner keeps timing context when total duration is missing', () => {
  const current = {
    id: 'sleep-timing-only',
    occurred_at: '2026-07-14T08:20:00+08:00',
    payload: { sleep_start_at: '2026-07-14T01:10:00+08:00', wake_at: '2026-07-14T08:20:00+08:00' },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records: [current], currentRecordId: current.id })

  assert.ok(candidate(plan, 'sleep_timing'))
  assert.equal(candidate(plan, 'sleep_current_metric'), undefined)
  assert.equal(plan.shortcut_plan.silent, true)
  assert.equal(plan.plan_summary.record_detail.selected[0].semantic_key, 'sleep_timing')
})

test('sleep timing keeps only observed clock values when one endpoint is missing', () => {
  const current = {
    id: 'sleep-start-only',
    occurred_at: '2026-07-14T08:20:00+08:00',
    payload: { sleep_start_at: '2026-07-14T01:10:00+08:00' },
  }
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'sleep', records: [current], currentRecordId: current.id })
  const timing = candidate(plan, 'sleep_timing')

  assert.ok(timing)
  assert.equal(timing.numbers.length, 1)
  assert.equal(timing.numbers[0].meaning, 'sleep_start_clock_minutes')
  assert.equal(timing.numbers[0].value, 70)
  assert.equal(timing.quality.data_coverage, 0.5)
  assert.match(timing.claim.canonical_text, /醒来 未知/)
})

test('sleep planner compares timing with a sufficiently supported chronotype profile', () => {
  const current = {
    id: 'sleep-profile-current',
    occurred_at: '2026-07-14T08:00:00+08:00',
    payload: { sleep_hours: 7, sleep_start_at: '2026-07-14T02:00:00+08:00', wake_at: '2026-07-14T08:00:00+08:00' },
  }
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'sleep', records: [current], currentRecordId: current.id,
    domainProfile: { chronotype: { typical_sleep_start: '00:40', typical_wake: '07:30', n: 12 } },
  })
  const timing = candidate(plan, 'sleep_timing_vs_typical')
  assert.ok(timing)
  assert.equal(timing.claim.structured_value.sleep_start_delta_minutes, 80)
  assert.equal(timing.claim.structured_value.wake_delta_minutes, 30)
})

test('expense planner normalizes legacy category aliases without changing raw records', () => {
  const plan = buildExpressionShadowPlan({
    transactions: [{
      id: 'expense-current', transaction_date: '2026-07-14', transaction_time: '18:00:00',
      amount: 30, merchant_name: '社区药房', category: '医疗', status: 'done',
    }],
    currentRecordId: 'expense-current',
  })
  assert.equal(plan.current_record.category, 'health')
})

test('expense planner skips null or blank amounts but keeps an explicit zero', () => {
  const missing = buildExpressionShadowPlan({
    transactions: [{ id: 'expense-null', transaction_date: '2026-07-14', amount: null, merchant_name: '测试商户', status: 'done' }],
    currentRecordId: 'expense-null',
  })
  assert.equal(missing.status, 'skipped')

  const zero = buildExpressionShadowPlan({
    transactions: [{ id: 'expense-zero', transaction_date: '2026-07-14', amount: 0, merchant_name: '测试商户', status: 'done' }],
    currentRecordId: 'expense-zero',
  })
  assert.equal(zero.status, 'auto_planned')
  assert.equal(zero.current_record.amount, 0)
})

test('wallet snapshot_balance has precedence and explicit zero is a valid current fact', () => {
  const plan = buildGenericExpressionShadowPlan({
    domainKey: 'wallet',
    records: [{
      ...walletRecord({ id: 'wallet-zero', occurredAt: '2026-07-14T08:00:00+08:00', balance: '0' }),
      payload: { account_name: '微信余额', record_kind: 'cash_snapshot', amount: 9 },
    }],
    currentRecordId: 'wallet-zero',
  })
  const fact = candidate(plan, 'wallet_current_metric')
  assert.ok(fact)
  assert.equal(fact.claim.structured_value.value, 0)
  assert.equal(fact.claim.structured_value.amount_source, 'snapshot_balance')
  assert.equal(fact.claim.structured_value.amount_conflict, true)
  assert.equal(candidate(plan, 'wallet_vs_personal_median'), undefined)
})

test('wallet amount conflicts retain the current fact but block change comparisons', () => {
  const current = {
    ...walletRecord({ id: 'wallet-conflict-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100 }),
    payload: { account_name: '微信余额', record_kind: 'cash_snapshot', amount: 99 },
  }
  const previous = walletRecord({ id: 'wallet-conflict-previous', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80 })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_current_metric').claim.structured_value.amount_conflict, true)
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
})

test('wallet comparison requires the same linked account, kind, user, and strictly earlier time', () => {
  const previous = walletRecord({ id: 'wallet-previous', occurredAt: '2026-07-13T08:00:00+08:00', balance: 227.03 })
  const current = walletRecord({ id: 'wallet-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 242.68 })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  const comparison = candidate(plan, 'wallet_change_previous')
  assert.ok(comparison)
  assert.equal(comparison.claim.structured_value.delta, 15.65)
  assert.equal(comparison.claim.structured_value.previous_account_name, '微信余额')
  assert.equal(comparison.claim.structured_value.previous_linked_account_id, 'account-1')
  assert.match(comparison.claim.canonical_text, /账户余额/)
})

test('wallet comparison blocks different linked ids even when account names match', () => {
  const previous = walletRecord({ id: 'wallet-other-account', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80, linkedAccountId: 'account-2' })
  const current = walletRecord({ id: 'wallet-current-account', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, linkedAccountId: 'account-1' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
})

test('wallet comparison blocks conflicting account names on the same linked id', () => {
  const previous = walletRecord({ id: 'wallet-name-a', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80, accountName: '微信余额' })
  const current = walletRecord({ id: 'wallet-name-b', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, accountName: '支付宝余额' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
})

test('wallet comparison blocks asset and liability cross-kind comparisons', () => {
  const previous = walletRecord({ id: 'wallet-asset', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80, kind: 'asset' })
  const current = walletRecord({ id: 'wallet-liability', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, kind: 'liability' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
})

test('wallet comparison does not fall back when only one record has a linked id', () => {
  const previous = walletRecord({ id: 'wallet-name-only', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80, linkedAccountId: null })
  const current = walletRecord({ id: 'wallet-linked', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, linkedAccountId: 'account-1' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
})

test('wallet comparison allows exact specific account-name fallback when both ids are missing', () => {
  const previous = walletRecord({ id: 'wallet-fallback-previous', occurredAt: '2026-07-13T08:00:00+08:00', balance: 80, linkedAccountId: null })
  const current = walletRecord({ id: 'wallet-fallback-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, linkedAccountId: null })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.ok(candidate(plan, 'wallet_change_previous'))
})

test('wallet comparison blocks same-timestamp snapshots and future snapshots', () => {
  const sameTimestampPlan = buildGenericExpressionShadowPlan({
    domainKey: 'wallet',
    records: [
      walletRecord({ id: 'wallet-same-time-previous', occurredAt: '2026-07-14T08:00:00+08:00', balance: 80 }),
      walletRecord({ id: 'wallet-same-time-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100 }),
    ],
    currentRecordId: 'wallet-same-time-current',
  })
  assert.equal(candidate(sameTimestampPlan, 'wallet_change_previous'), undefined)

  const futurePlan = buildGenericExpressionShadowPlan({
    domainKey: 'wallet',
    records: [
      walletRecord({ id: 'wallet-future-previous', occurredAt: '2026-07-13T08:00:00+08:00', snapshotAt: '2026-07-15T08:00:00+08:00', balance: 80 }),
      walletRecord({ id: 'wallet-future-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100 }),
    ],
    currentRecordId: 'wallet-future-current',
  })
  assert.equal(candidate(futurePlan, 'wallet_change_previous'), undefined)
})

test('wallet liability wording describes outstanding amount change without inferring repayment', () => {
  const previous = walletRecord({ id: 'liability-previous', occurredAt: '2026-07-13T08:00:00+08:00', balance: 120, kind: 'liability', accountName: '花呗待还' })
  const current = walletRecord({ id: 'liability-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 100, kind: 'liability', accountName: '花呗待还' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  const comparison = candidate(plan, 'wallet_change_previous')
  assert.ok(comparison)
  assert.match(comparison.claim.canonical_text, /待还金额/)
  assert.doesNotMatch(comparison.claim.canonical_text, /还款|偿还|还清|消费|支出/)
})

test('wallet does not emit a change candidate when the rounded balance delta is zero', () => {
  const previous = walletRecord({ id: 'wallet-zero-delta-previous', occurredAt: '2026-07-13T08:00:00+08:00', balance: 18.79, kind: 'liability', accountName: '抖音月付' })
  const current = walletRecord({ id: 'wallet-zero-delta-current', occurredAt: '2026-07-14T08:00:00+08:00', balance: 18.79, kind: 'liability', accountName: '抖音月付' })
  const plan = buildGenericExpressionShadowPlan({ domainKey: 'wallet', records: [previous, current], currentRecordId: current.id })
  assert.equal(candidate(plan, 'wallet_change_previous'), undefined)
  assert.ok(candidate(plan, 'wallet_current_metric'))
})
