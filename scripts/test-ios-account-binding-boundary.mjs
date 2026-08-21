import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const repositoryPath = 'ios/SnapCount/Repositories/UnboundRecordRepository.swift'
const useCasePath = 'ios/SnapCount/Features/Accounts/AccountBindingUseCase.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const modelPath = 'ios/SnapCount/Models/NativeUnboundRecord.swift'
const testsPath = 'ios/SnapCountTests/AccountBindingUseCaseTests.swift'

test('A4-IOS-007A-G behavior scenarios are represented by XCTest', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['007A', '007B', '007C', '007D', '007E', '007F', '007G']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})

test('A4-IOS-007 use case owns binding orchestration without transport dependencies', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/import\s+SwiftUI|import\s+Supabase/u.test(source), false, 'use case must not import UI or Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  for (const marker of ['inFlight', 'expectedResetGeneration', 'transaction: .accepted', 'transaction: .stale', 'refresh']) {
    assert.ok(source.includes(marker), `missing binding orchestration marker: ${marker}`)
  }
  assert.ok(source.includes('UnboundRecordRepositoryProtocol'), 'use case must depend on narrow repository protocol')
})

test('A4-IOS-007F repository returns structured accepted identity', async () => {
  const source = await readFile(repositoryPath, 'utf8')
  assert.match(source, /func\s+bind\([\s\S]*\)\s+async\s+throws\s*->\s*NativeAccountBindingResult/u, 'binding transport must return structured result')
  assert.ok(source.includes('NativeAccountBindingResult'), 'accepted result type is missing')
  assert.ok(source.includes('save_transaction_with_account'), 'expense RPC mapping disappeared')
  assert.ok(source.includes('save_income_with_account'), 'income RPC mapping disappeared')
})

test('A4-IOS-007C/D/E AppState is only a compatibility projection', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const start = source.indexOf('func bindUnboundRecord(')
  assert.notEqual(start, -1, 'single binding public entry is missing')
  const end = source.indexOf('func loadWalletSnapshots()', start)
  const block = source.slice(start, end)
  assert.ok(block.includes('AccountBindingUseCase'), 'AppState adapter is missing')
  assert.equal(/unboundRecordRepository\.bind\(/u.test(block), false, 'AppState still owns binding transport')
  assert.equal(/for candidate in candidates/u.test(block), false, 'AppState still owns batch orchestration')
})

test('A4-IOS-007G recommendation and read boundaries remain outside binding use case', async () => {
  const [useCase, model] = await Promise.all([
    readFile(useCasePath, 'utf8'),
    readFile(modelPath, 'utf8')
  ])
  assert.equal(/NativeAccountRecommendationEngine|func\s+fetch\(/u.test(useCase), false, 'binding use case absorbed recommendation or reads')
  assert.ok(model.includes('NativeAccountRecommendationEngine'), 'recommendation engine moved out of its pure model boundary')
})
