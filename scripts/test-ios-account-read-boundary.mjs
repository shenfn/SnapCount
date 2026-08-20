import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const repositoryPath = 'ios/SnapCount/Repositories/AccountRepository.swift'
const useCasePath = 'ios/SnapCount/Features/Accounts/AccountReadPreparationUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/AccountReadPreparationUseCaseTests.swift'

test('A4-IOS-005 repository keeps repayment preparation explicit', async () => {
  const source = await readFile(repositoryPath, 'utf8')
  assert.ok(source.includes('ensureRepaymentCycles'), 'missing explicit preparation method')
  const fetchDetailStart = source.lastIndexOf('func fetchDetail(')
  const fetchDetailEnd = source.indexOf('func fetchOpenRepaymentCycles(', fetchDetailStart)
  const fetchDetail = source.slice(fetchDetailStart, fetchDetailEnd)
  assert.equal(fetchDetail.includes('ensureRepaymentCycles'), false, 'fetchDetail hides write preparation')
})

test('A4-IOS-005 preparation use case owns reuse, stale and failure layering', async () => {
  const source = await readFile(useCasePath, 'utf8')
  for (const marker of ['inFlight', 'expectedResetGeneration', 'transaction: .accepted', 'transaction: .failed', 'transaction: .stale']) {
    assert.ok(source.includes(marker), `missing preparation marker: ${marker}`)
  }
  assert.equal(/import\s+SwiftUI/u.test(source), false, 'use case must not import SwiftUI')
  assert.equal(/URLSession|SupabaseRemoteClient/u.test(source), false, 'use case must not own transport')
  assert.ok(source.includes('AccountReadPreparationRepositoryProtocol'), 'narrow repository dependency is missing')
})

test('A4-IOS-005 AppState no longer silently discards preparation failure', async () => {
  const source = await readFile(appStatePath, 'utf8')
  assert.ok(source.includes('AccountReadPreparationUseCase'), 'AppState adapter is missing')
  assert.equal(/try\?\s+await\s+accountRepository\.ensureRepaymentCycles/u.test(source), false, 'prepare failure is still silently discarded')
  assert.ok(source.includes('onFailure("还款计划准备失败：'), 'prepare failure is not projected separately')
  assert.ok(source.includes('self?.inboxFinanceMessage = message'), 'inbox preparation failure is projected to the wrong surface')
})

test('A4-IOS-005D detail reads preserve independent section failures', async () => {
  const source = await readFile(repositoryPath, 'utf8')
  assert.ok(source.includes('AccountDetailSectionResult'), 'detail section result is missing')
  assert.ok(source.includes('loadErrors: errors'), 'detail section errors are no longer preserved')
})

test('A4-IOS-005F account repository does not absorb wallet source reads', async () => {
  const source = await readFile(repositoryPath, 'utf8')
  assert.equal(/rest\/v1\/data_records|resolveImageURL|WalletSnapshotRepository/u.test(source), false, 'account repository absorbed wallet/record reads')
})

test('A4-IOS-005G screenshot repayment remains outside preparation use case', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/confirmStagingRepayment|NativeRepaymentCandidateEngine|InboxRepository/u.test(source), false, 'screenshot repayment leaked into preparation use case')
})

test('A4-IOS-005A-G behavior scenarios are represented by XCTest and source checks', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['005A', '005B', '005C', '005D', '005E']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})
