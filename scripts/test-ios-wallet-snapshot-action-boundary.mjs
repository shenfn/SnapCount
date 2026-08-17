import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Accounts/WalletSnapshotActionUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/WalletSnapshotActionUseCaseTests.swift'

test('A4-IOS-002 use case stays independent from UI and transport clients', async () => {
  const source = await readFile(useCasePath, 'utf8')

  assert.equal(/import\s+SwiftUI/u.test(source), false, 'use case must not import SwiftUI')
  assert.equal(/import\s+Supabase/u.test(source), false, 'use case must not import Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  assert.ok(/WalletSnapshotRepositoryProtocol/u.test(source), 'repository protocol dependency is missing')
})

test('A4-IOS-002 owns command deduplication, conflict, stale and refresh layering', async () => {
  const source = await readFile(useCasePath, 'utf8')

  for (const marker of [
    'inFlight',
    'walletSnapshotConflict',
    'expectedResetGeneration',
    'sessionChanged',
    'refresh: .failed',
    'transaction: .accepted',
  ]) {
    assert.ok(source.includes(marker), `missing orchestration marker: ${marker}`)
  }
})

test('A4-IOS-002 AppState public entries delegate instead of writing through repository', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const start = source.indexOf('func createAccountFromWalletSnapshot')
  const end = source.indexOf('func openUnboundRecord', start)
  assert.notEqual(start, -1, 'create public entry is missing')
  assert.notEqual(end, -1, 'wallet action block end is missing')
  const actionBlock = source.slice(start, end)

  assert.ok(actionBlock.includes('performWalletSnapshotAction'), 'AppState does not delegate to action use case')
  assert.ok(actionBlock.includes('resolvedWalletSnapshotActionUseCase'), 'AppState use case adapter is missing')
  assert.equal(/walletSnapshotRepository\.(createAccount|link)\(/u.test(actionBlock), false, 'AppState still writes directly through repository')
  assert.ok(source.includes('walletSnapshotActionUseCase?.reset()'), 'user reset does not invalidate in-flight action')
})

test('A4-IOS-002A-F are represented by XCTest behavior cases', async () => {
  const source = await readFile(testsPath, 'utf8')

  for (const scenario of ['002A', '002B', '002C', '002D', '002E', '002F']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})
