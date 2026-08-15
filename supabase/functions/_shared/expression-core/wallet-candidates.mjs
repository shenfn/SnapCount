import { candidate, num, textValue } from './generic-domain-shared.mjs'

function rawRecordValue(record, key) {
  if (record && record[key] !== null && record[key] !== undefined) return record[key]
  return record?.payload?.[key]
}

function hasRawValue(value) {
  return value !== null
    && value !== undefined
    && !(typeof value === 'string' && !value.trim())
}

function walletAmountState(record) {
  const sources = [
    ['snapshot_balance', record?.snapshot_balance],
    ['payload.snapshot_balance', record?.payload?.snapshot_balance],
    ['payload.amount', record?.payload?.amount],
    ['amount', record?.amount],
    ['payload.balance', record?.payload?.balance],
    ['balance', record?.balance],
    ['payload.wallet_amount', record?.payload?.wallet_amount],
    ['wallet_amount', record?.wallet_amount],
    ['payload.liability_amount', record?.payload?.liability_amount],
    ['liability_amount', record?.liability_amount],
  ].filter(([, value]) => hasRawValue(value))
  const parsed = sources.map(([source, raw]) => ({ source, raw, value: num(raw) }))
  const valid = parsed.filter(item => item.value !== null)
  const first = valid[0]?.value ?? null
  const conflict = parsed.some(item => item.value === null)
    || valid.some(item => item.value !== first)
  return { value: first, source: valid[0]?.source ?? null, conflict }
}

function normalizeWalletKind(value) {
  const normalized = textValue(value)?.toLowerCase()
  if (normalized === 'asset' || normalized === 'cash_snapshot') return 'asset'
  if (normalized === 'liability' || normalized === 'liability_snapshot') return 'liability'
  return null
}

function walletKindState(record) {
  const sources = [
    ['account_snapshot_kind', record?.account_snapshot_kind],
    ['payload.account_snapshot_kind', record?.payload?.account_snapshot_kind],
    ['record_kind', record?.record_kind],
    ['payload.record_kind', record?.payload?.record_kind],
  ].filter(([, value]) => hasRawValue(value))
  const parsed = sources.map(([source, raw]) => ({ source, raw, kind: normalizeWalletKind(raw) }))
  const valid = parsed.filter(item => item.kind !== null)
  const uniqueKinds = [...new Set(valid.map(item => item.kind))]
  const conflict = parsed.some(item => item.kind === null) || uniqueKinds.length > 1
  return { kind: valid[0]?.kind ?? null, source: valid[0]?.source ?? null, conflict }
}

function normalizeAccountName(value) {
  return textValue(value)?.toLocaleLowerCase().replace(/\s+/g, ' ') ?? null
}

function walletIdentityState(record) {
  const linkedAccountId = textValue(rawRecordValue(record, 'linked_account_id'))
  const accountName = normalizeAccountName(
    rawRecordValue(record, 'account_name') ?? record?.title,
  )
  const genericNames = new Set(['账户', '未知账户', '余额', '钱包', '银行卡'])
  return {
    linkedAccountId,
    accountName,
    accountNameSpecific: Boolean(accountName && accountName.length >= 2 && !genericNames.has(accountName)),
  }
}

function walletSnapshotTime(record) {
  const snapshotRaw = rawRecordValue(record, 'snapshot_at')
  const raw = hasRawValue(snapshotRaw) ? snapshotRaw : record?.occurred_at
  const value = new Date(raw ?? '').getTime()
  return Number.isFinite(value) ? value : null
}

function walletMetric(record) {
  const amount = walletAmountState(record)
  if (amount.value === null) return null
  const kind = walletKindState(record)
  const identity = walletIdentityState(record)
  return {
    value: amount.value,
    label: kind.kind === 'liability' ? '待还金额' : kind.kind === 'asset' ? '账户余额' : '账户金额',
    unit: '元',
    wallet: {
      amountSource: amount.source,
      amountConflict: amount.conflict,
      kind: kind.kind,
      kindSource: kind.source,
      kindConflict: kind.conflict,
      identity,
      snapshotAt: rawRecordValue(record, 'snapshot_at') ?? record?.occurred_at ?? null,
    },
  }
}

function walletComparisonAllowed(current, previous, currentMetric, previousMetric) {
  const currentUser = textValue(current?.user_id)
  const previousUser = textValue(previous?.user_id)
  if (currentUser || previousUser) {
    if (!currentUser || !previousUser || currentUser !== previousUser) return false
  }
  const currentWallet = currentMetric.wallet
  const previousWallet = previousMetric.wallet
  if (currentWallet.amountConflict || previousWallet.amountConflict) return false
  if (currentWallet.kindConflict || previousWallet.kindConflict) return false
  if (!currentWallet.kind || currentWallet.kind !== previousWallet.kind) return false

  const currentIdentity = currentWallet.identity
  const previousIdentity = previousWallet.identity
  if (currentIdentity.accountName && previousIdentity.accountName
    && currentIdentity.accountName !== previousIdentity.accountName) return false
  if (currentIdentity.linkedAccountId || previousIdentity.linkedAccountId) {
    if (!currentIdentity.linkedAccountId || !previousIdentity.linkedAccountId
      || currentIdentity.linkedAccountId !== previousIdentity.linkedAccountId) return false
  } else if (!currentIdentity.accountNameSpecific || !previousIdentity.accountNameSpecific
    || currentIdentity.accountName !== previousIdentity.accountName) {
    return false
  }

  const currentTime = walletSnapshotTime(current)
  const previousTime = walletSnapshotTime(previous)
  return currentTime !== null && previousTime !== null && previousTime < currentTime
}

export function generateWalletCandidates(current, records) {
  const currentMetric = walletMetric(current)
  if (!currentMetric) return []
  const output = [candidate({
    id: `fact:wallet:${current.id}`,
    domainKey: 'wallet',
    semanticKey: 'wallet_current_metric',
    subtype: 'observed',
    dimension: 'current_fact',
    value: {
      domain_key: 'wallet',
      value: currentMetric.value,
      unit: currentMetric.unit,
      occurred_at: current.occurred_at,
      account_name: currentMetric.wallet.identity.accountName,
      linked_account_id: currentMetric.wallet.identity.linkedAccountId,
      account_snapshot_kind: currentMetric.wallet.kind,
      snapshot_at: currentMetric.wallet.snapshotAt,
      amount_source: currentMetric.wallet.amountSource,
      amount_conflict: currentMetric.wallet.amountConflict,
      kind_conflict: currentMetric.wallet.kindConflict,
    },
    text: `本次${currentMetric.label}为 ${currentMetric.value} ${currentMetric.unit}`,
    records: [current],
    numbers: [{ value: currentMetric.value, meaning: 'current_wallet_metric', derivation: 'source_record.metric' }],
  })]

  const previous = records
    .filter(record => record.id !== current.id)
    .map(record => ({ record, metric: walletMetric(record) }))
    .filter(item => item.metric)
    .filter(item => walletComparisonAllowed(current, item.record, currentMetric, item.metric))
    .sort((a, b) => walletSnapshotTime(b.record) - walletSnapshotTime(a.record))[0]
  if (!previous) return output
  const delta = Math.round((currentMetric.value - previous.metric.value) * 100) / 100
  if (delta === 0) return output
  const amountLabel = currentMetric.wallet.kind === 'liability' ? '待还金额' : '账户余额'
  const deltaText = delta > 0 ? `+${delta}` : String(delta)
  output.push(candidate({
    id: `comparison:wallet:previous:${current.id}`,
    domainKey: 'wallet',
    semanticKey: 'wallet_change_previous',
    claimType: 'comparison',
    dimension: 'state_change',
    value: {
      current: currentMetric.value,
      previous: previous.metric.value,
      delta,
      unit: '元',
      account_snapshot_kind: currentMetric.wallet.kind,
      account_name: currentMetric.wallet.identity.accountName,
      linked_account_id: currentMetric.wallet.identity.linkedAccountId,
      previous_account_name: previous.metric.wallet.identity.accountName,
      previous_linked_account_id: previous.metric.wallet.identity.linkedAccountId,
    },
    text: `${currentMetric.wallet.identity.accountName ? `「${currentMetric.wallet.identity.accountName}」` : ''}${amountLabel}较上次变化 ${deltaText} 元，当前 ${currentMetric.value} 元`,
    records: [current, previous.record],
    numbers: [
      { value: delta, meaning: 'wallet_delta_amount', derivation: 'current_wallet_amount - previous_wallet_amount' },
      { value: currentMetric.value, meaning: 'current_wallet_amount', derivation: 'source_record.wallet_amount' },
      { value: previous.metric.value, meaning: 'previous_wallet_amount', derivation: 'previous_record.wallet_amount' },
    ],
    confidence: 0.9,
  }))
  return output
}
