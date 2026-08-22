import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Records/RecordDetailImageUseCase.swift'
const repositoryPath = 'ios/SnapCount/Repositories/RecordRepository.swift'
const servicePath = 'ios/SnapCount/Services/NativeDataService.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/RecordDetailImageUseCaseTests.swift'

test('A4-IOS-011A-G scenarios are represented by XCTest', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['011A', '011B', '011C', '011D', '011E', '011F', '011G']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})

test('A4-IOS-011 use case owns hydration orchestration without transport dependencies', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/import\s+SwiftUI|import\s+Supabase/u.test(source), false)
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false)
  for (const marker of ['inFlight', 'reset', '.hydrated', '.stale', 'notNeeded']) {
    assert.ok(source.includes(marker), `missing image hydration marker: ${marker}`)
  }
  assert.ok(source.includes('NativeRecordDetailImageRepositoryProtocol'))
})

test('A4-IOS-011 repository remains the signed-image transport boundary', async () => {
  const [repository, service] = await Promise.all([
    readFile(repositoryPath, 'utf8'),
    readFile(servicePath, 'utf8')
  ])
  assert.match(repository, /func\s+hydrateDetailImage\(/u)
  assert.match(service, /hydrateRecordDetailImage\(/u)
  assert.equal(/RecordDetailImageUseCase|signedURLMap|receipt-images/u.test(repository), false)
})

test('A4-IOS-011 AppState is only a compatibility projection', async () => {
  const source = await readFile(appStatePath, 'utf8')
  assert.ok(source.includes('hydrateRecordDetailImageIfNeeded'))
  assert.equal(source.includes('recordDetailImageUseCase'), false, 'red baseline unexpectedly has use case wiring')
  assert.match(source, /recordRepository\.hydrateDetailImage\(/u)
})

test('A4-IOS-011 use case does not absorb detail reads or expression feedback', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/fetchDetail|prepareRecordExpressionPlan|submitRecordFeedback|NativeDataService/u.test(source), false)
})

console.log('iOS record detail image boundary checks passed')
