import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const repositoryPath = 'ios/SnapCount/Repositories/AccountRepository.swift'
const useCasePath = 'ios/SnapCount/Features/Accounts/AccountManagementActionUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/AccountManagementActionUseCaseTests.swift'

test('A4-IOS-004 repository writes through canonical account RPCs', async () => {
  const source = await readFile(repositoryPath, 'utf8')

  assert.ok(source.includes('save_account'), 'missing save_account RPC')
  assert.ok(source.includes('set_account_archived'), 'missing set_account_archived RPC')
  assert.equal(/remoteClient\.(post|patch|upsert)\(/u.test(source), false, 'account management REST write remains')
  assert.equal(source.includes('unsetOtherDefaults'), false, 'client-side default cleanup remains')
})

test('A4-IOS-004 use case stays independent from UI and transport clients', async () => {
  const source = await readFile(useCasePath, 'utf8')

  assert.equal(/import\s+SwiftUI/u.test(source), false, 'use case must not import SwiftUI')
  assert.equal(/import\s+Supabase/u.test(source), false, 'use case must not import Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  assert.ok(source.includes('AccountManagementRepositoryProtocol'), 'narrow repository dependency is missing')
})

test('A4-IOS-004 owns command reuse, conflict, stale and refresh layering', async () => {
  const source = await readFile(useCasePath, 'utf8')

  for (const marker of [
    'inFlight',
    'accountCommandConflict',
    'expectedResetGeneration',
    'applyAccepted',
    'refresh: .failed',
    'transaction: .accepted',
  ]) {
    assert.ok(source.includes(marker), `missing orchestration marker: ${marker}`)
  }
})

test('A4-IOS-004 AppState delegates account writes and invalidates on reset', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const saveStart = source.indexOf('func saveAccount')
  const archiveStart = source.indexOf('func setAccountArchived')
  const nextBlock = source.indexOf('func ', archiveStart + 1)
  assert.notEqual(saveStart, -1, 'save public entry is missing')
  assert.notEqual(archiveStart, -1, 'archive public entry is missing')
  const actionBlock = source.slice(saveStart, nextBlock === -1 ? undefined : nextBlock)

  assert.ok(actionBlock.includes('AccountManagementActionUseCase'), 'AppState use case adapter is missing')
  assert.equal(/accountRepository\.(save|setArchived)\(/u.test(actionBlock), false, 'AppState still writes directly through repository')
  assert.ok(source.includes('accountManagementActionUseCase?.reset()'), 'user reset does not invalidate account action')
})

test('A4-IOS-004A-H are represented by XCTest behavior cases', async () => {
  const source = await readFile(testsPath, 'utf8')

  for (const scenario of ['004A', '004B', '004C', '004D', '004E', '004F', '004G', '004H']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})
