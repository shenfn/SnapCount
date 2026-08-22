import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Inbox/StagingLifecycleUseCase.swift'
const repositoryPath = 'ios/SnapCount/Repositories/InboxRepository.swift'
const transportPath = 'ios/SnapCount/Services/NativeDataService.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/StagingLifecycleUseCaseTests.swift'

test('A4-IOS-008A-H behavior scenarios are represented by XCTest', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['008A', '008B', '008C', '008D', '008E', '008F', '008G', '008H']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})

test('A4-IOS-008 use case owns lifecycle orchestration without transport dependencies', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/import\s+SwiftUI|import\s+Supabase/u.test(source), false, 'use case must not import UI or Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  for (const marker of ['inFlight', 'expectedResetGeneration', '.accepted', '.stale', 'refresh']) {
    assert.ok(source.includes(marker), `missing lifecycle orchestration marker: ${marker}`)
  }
  assert.ok(source.includes('StagingLifecycleRepositoryProtocol'), 'use case must depend on narrow repository protocol')
})

test('A4-IOS-008 repository returns structured discard/retry/archive facts', async () => {
  const [source, transport] = await Promise.all([
    readFile(repositoryPath, 'utf8'),
    readFile(transportPath, 'utf8')
  ])
  assert.match(source, /func\s+discard\([\s\S]*\)\s+async\s+throws\s*->\s*NativeStagingDiscardResult/u)
  assert.match(source, /func\s+retry\([\s\S]*\)\s+async\s+throws\s*->\s*NativeStagingRetryResult/u)
  assert.match(source, /func\s+archive\([\s\S]*\)\s+async\s+throws\s*->\s*NativeStagingArchiveResult/u)
  const combined = `${source}\n${transport}`
  for (const marker of ['discard_staging_record', 'archive_staging_record', 'ingest-receipt', 'idempotent_retry', 'cleanup_queued']) {
    assert.ok(combined.includes(marker), `missing transport fact marker: ${marker}`)
  }
})

test('A4-IOS-008 AppState is only a compatibility projection', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const start = source.indexOf('func discardStagingRecord(')
  const end = source.indexOf('func resolveStagingImageURL', start)
  assert.notEqual(start, -1, 'staging lifecycle public entry is missing')
  assert.notEqual(end, -1, 'staging lifecycle block boundary is missing')
  const block = source.slice(start, end)
  assert.ok(block.includes('StagingLifecycleUseCase'), 'AppState adapter is missing')
  assert.equal(/inboxRepository\.(discard|retry|archive)\(/u.test(block), false, 'AppState still owns lifecycle transport')
  assert.equal(/refreshDashboardAfterInboxMutation/u.test(block), false, 'AppState still owns lifecycle refresh scheduling')
})

test('A4-IOS-008 keeps pending confirmation, repayment and record reads outside lifecycle use case', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/confirmPending|confirmStagingRepayment|fetchDetail|NativeDataService/u.test(source), false)
})
