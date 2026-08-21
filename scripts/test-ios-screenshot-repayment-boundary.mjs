import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Accounts/ScreenshotRepaymentUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const inboxRepositoryPath = 'ios/SnapCount/Repositories/InboxRepository.swift'
const testsPath = 'ios/SnapCountTests/ScreenshotRepaymentUseCaseTests.swift'

test('A4-IOS-006 use case stays independent from UI and transport clients', async () => {
  const source = await readFile(useCasePath, 'utf8')

  assert.equal(/import\s+SwiftUI/u.test(source), false, 'use case must not import SwiftUI')
  assert.equal(/import\s+Supabase/u.test(source), false, 'use case must not import Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  assert.ok(source.includes('ScreenshotRepaymentRepositoryProtocol'), 'narrow repository protocol is missing')
})

test('A4-IOS-006 owns command reuse, conflict, stale and refresh layering', async () => {
  const source = await readFile(useCasePath, 'utf8')

  for (const marker of [
    'inFlight',
    'screenshotRepaymentConflict',
    'expectedResetGeneration',
    'onAccepted',
    'refresh',
    'transaction: .accepted',
  ]) {
    assert.ok(source.includes(marker), `missing orchestration marker: ${marker}`)
  }
})

test('A4-IOS-006 AppState delegates screenshot repayment and repository owns transport', async () => {
  const [appState, repository] = await Promise.all([
    readFile(appStatePath, 'utf8'),
    readFile(inboxRepositoryPath, 'utf8'),
  ])
  const start = appState.indexOf('func confirmStagingRepayment')
  assert.notEqual(start, -1, 'screenshot repayment public entry is missing')
  const end = appState.indexOf('private func refreshAfterRepayment', start)
  const block = appState.slice(start, end)
  assert.ok(block.includes('ScreenshotRepaymentUseCase'), 'AppState adapter is missing')
  assert.equal(/inboxRepository\.confirmStagingRepayment\(/u.test(block), false, 'AppState still owns screenshot RPC transport')
  assert.match(repository, /func confirmStagingRepayment[\s\S]*->\s*NativeRepaymentCycle/u, 'repository must return canonical cycle')
})

test('A4-IOS-006 behavior scenarios are represented by XCTest', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['006B', '006C', '006D', '006E', '006F']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})
