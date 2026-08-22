import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const useCasePath = 'ios/SnapCount/Features/Inbox/PendingConfirmationUseCase.swift'
const repositoryPath = 'ios/SnapCount/Repositories/InboxRepository.swift'
const transportPath = 'ios/SnapCount/Services/NativeDataService.swift'
const appStatePath = 'ios/SnapCount/App/AppState.swift'
const testsPath = 'ios/SnapCountTests/PendingConfirmationUseCaseTests.swift'

test('A4-IOS-009A-H scenarios are represented by XCTest', async () => {
  const source = await readFile(testsPath, 'utf8')
  for (const scenario of ['009A', '009B', '009C', '009D', '009E', '009F', '009G', '009H']) {
    assert.ok(source.includes(`testA4IOS${scenario}`), `missing XCTest scenario A4-IOS-${scenario}`)
  }
})

test('A4-IOS-009 use case owns confirmation orchestration without transport dependencies', async () => {
  const source = await readFile(useCasePath, 'utf8')
  assert.equal(/import\s+SwiftUI|import\s+Supabase/u.test(source), false, 'use case must not import UI or Supabase')
  assert.equal(/SupabaseRemoteClient|URLRequest|URLSession/u.test(source), false, 'use case must not own transport')
  for (const marker of ['inFlight', 'reset', '.accepted', '.stale', 'refresh']) {
    assert.ok(source.includes(marker), `missing confirmation orchestration marker: ${marker}`)
  }
  assert.ok(source.includes('PendingConfirmationRepositoryProtocol'), 'use case must depend on narrow repository protocol')
})

test('A4-IOS-009 repository returns structured confirmation facts', async () => {
  const [source, transport] = await Promise.all([
    readFile(repositoryPath, 'utf8'),
    readFile(transportPath, 'utf8')
  ])
  assert.match(source, /func\s+confirmPending[\s\S]*async\s+throws\s*->\s*NativePendingConfirmationResult/u)
  const combined = `${source}\n${transport}`
  for (const marker of ['confirm_pending_transaction_with_account', 'record_type', 'idempotent_retry', 'p_pending_id', 'p_entry_type']) {
    assert.ok(combined.includes(marker), `missing confirmation transport fact marker: ${marker}`)
  }
})

test('A4-IOS-009 AppState is only a compatibility projection', async () => {
  const source = await readFile(appStatePath, 'utf8')
  const start = source.indexOf('func confirmPendingRecord(')
  const end = source.indexOf('func submitRecordFeedback(', start)
  assert.notEqual(start, -1, 'pending confirmation public entry is missing')
  assert.notEqual(end, -1, 'pending confirmation block boundary is missing')
  const block = source.slice(start, end)
  assert.ok(block.includes('PendingConfirmationUseCase'), 'AppState adapter is missing')
  assert.equal(/inboxRepository\.confirmPending\(/u.test(block), false, 'AppState still owns confirmation transport')
  assert.equal(/confirm_pending_transaction_with_account/u.test(block), false, 'AppState repeats RPC state machine')
})

test('A4-IOS-009 reset is connected and non-target boundaries remain outside the use case', async () => {
  const [useCase, appState] = await Promise.all([
    readFile(useCasePath, 'utf8'),
    readFile(appStatePath, 'utf8')
  ])
  assert.equal(/saveRecordDetail|deleteRecord|submitRecordFeedback|confirmStagingRepayment|NativeDataService/u.test(useCase), false)
  assert.match(appState, /pendingConfirmationUseCase\?\.reset\(\)/u)
})
