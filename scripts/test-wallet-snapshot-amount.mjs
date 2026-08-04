import assert from 'node:assert/strict'
import { getDistribution, getRecentRecords } from '../src/adapters/domain/walletAdapter.js'

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

console.log('wallet snapshot amount contract: ok')
