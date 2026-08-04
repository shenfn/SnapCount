import assert from 'node:assert/strict'
import { getAccountSections, getDistribution, getRecentRecords } from '../src/adapters/domain/walletAdapter.js'
import { shouldAdoptSnapshotAsOpeningBalance } from '../src/adapters/domain/accountAdapter.js'

function storeFor(payload) {
  return {
    accounts: { value: [] },
    dataRecords: { value: [{
      id: 'snapshot-1',
      domainKey: 'wallet',
      occurredAt: '2026-08-04T00:00:00Z',
      createdAt: '2026-08-04T00:00:00Z',
      title: '测试钱包',
      summary: '账户余额快照',
      payload,
    }] },
  }
}

const nonZeroPayload = {
  record_kind: 'cash_snapshot',
  account_name: '测试钱包',
  snapshot_balance: 123.45,
}
assert.equal(getDistribution(storeFor(nonZeroPayload))[0].value, 123.45)
assert.equal(getRecentRecords(storeFor(nonZeroPayload))[0].value, '余额 ¥123.45')

const zeroPayload = {
  record_kind: 'cash_snapshot',
  account_name: '空账户',
  snapshot_balance: 0,
}
assert.equal(getDistribution(storeFor(zeroPayload))[0].value, 0)
assert.equal(getRecentRecords(storeFor(zeroPayload))[0].value, '余额 ¥0.00')

const emptyAccount = { initialBalance: 0, currentBalance: 0 }
assert.equal(shouldAdoptSnapshotAsOpeningBalance(emptyAccount, 0, 123.45), true)
assert.equal(shouldAdoptSnapshotAsOpeningBalance(emptyAccount, 0, 0), true)
assert.equal(shouldAdoptSnapshotAsOpeningBalance(emptyAccount, 1, 123.45), false)
assert.equal(shouldAdoptSnapshotAsOpeningBalance({ initialBalance: 10, currentBalance: 10 }, 0, 123.45), false)
assert.equal(shouldAdoptSnapshotAsOpeningBalance({ initial_balance: 0, current_balance: 0 }, 0, 88), true)

const accountSections = getAccountSections({
  accounts: { value: [{
    id: 'account-1',
    name: '微信余额',
    type: 'wallet_balance',
    currentBalance: 88,
    snapshotBalance: 88,
    snapshotAt: '2026-08-04T08:00:00Z',
    isArchived: false,
  }] },
})
assert.equal(accountSections[0].items[0].value, '¥88.00')
assert.equal(accountSections[0].items[0].snapshot, '最近快照 2026-08-04 · ¥88.00')

console.log('wallet snapshot amount contract: ok')
