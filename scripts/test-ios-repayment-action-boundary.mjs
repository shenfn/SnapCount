import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Accounts/RepaymentActionUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/RepaymentActionUseCaseTests.swift'

test('A4-IOS-003 use case stays independent from UI and transport clients', async () => {
  const source = await readFile(useCasePath, 'utf8')

  assert.equal(/import\s+SwiftUI/u.test(source), false, 'use case must not import SwiftUI')
  assert.equal(/import\s+Supabase/u.test(source), false, 'use case must not import Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  assert.ok(source.includes('AccountRepositoryProtocol'), 'repository protocol dependency is missing')
})

test('A4-IOS-003 owns command reuse, conflict, stale and refresh layering', async () => {
  const source = await readFile(useCasePath, 'utf8')

  for (const marker of [
    'inFlight',
    'repaymentConflict',
    'expectedResetGeneration',
    'applyAccepted',
    'refresh: .failed',
    'transaction: .accepted',
  ]) {
    assert.ok(source.includes(marker), `missing orchestration marker: ${marker}`)
  }
})

test('A4-IOS-003 AppState delegates manual repayment writes', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const start = source.indexOf('func confirmRepayment')
  const end = source.indexOf('func loadInboxRepaymentCandidates', start)
  assert.notEqual(start, -1, 'confirm public entry is missing')
  assert.notEqual(end, -1, 'manual repayment block end is missing')
  const actionBlock = source.slice(start, end)

  assert.ok(actionBlock.includes('performRepaymentAction'), 'AppState does not delegate to action use case')
  assert.ok(actionBlock.includes('resolvedRepaymentActionUseCase'), 'AppState use case adapter is missing')
  assert.equal(/accountRepository\.(confirmRepayment|revokePayment)\(/u.test(actionBlock), false, 'AppState still writes directly through repository')
  assert.ok(source.includes('repaymentActionUseCase?.reset()'), 'user reset does not invalidate repayment action')
})

test('A4-IOS-003A-F are represented by XCTest behavior cases', async () => {
  const source = await readFile(testsPath, 'utf8')

  for (const scenario of ['003A', '003B', '003C', '003D', '003E', '003F']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})
