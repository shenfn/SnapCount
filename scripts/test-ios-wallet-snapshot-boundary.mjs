import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const repositoryPath = 'ios/SnapCount/Repositories/WalletSnapshotRepository.swift'
const modelPath = 'ios/SnapCount/Models/NativeWalletSnapshot.swift'

test('A4-IOS-001/002 repository writes through the canonical wallet snapshot RPC', async () => {
  const source = await readFile(repositoryPath, 'utf8')

  assert.ok(/name:\s*"apply_wallet_snapshot"/u.test(source), 'missing canonical wallet snapshot RPC')
  assert.ok(source.includes('"p_record_id"'), 'missing p_record_id RPC parameter')
  assert.ok(source.includes('"p_account_id"'), 'missing p_account_id RPC parameter')
})

test('A4-IOS-001/002 repository does not retain the old multi-step wallet write path', async () => {
  const source = await readFile(repositoryPath, 'utf8')

  assert.equal(/create_account_entry_for_record/u.test(source), false, 'legacy account entry helper remains')
  assert.equal(/upsertRepaymentCycle/u.test(source), false, 'client-side repayment upsert remains')
  assert.equal(/remoteClient\.(post|patch|upsert)\(/u.test(source), false, 'multi-step REST write remains')
})

test('A4-IOS-003/004 repository source names every canonical outcome', async () => {
  const source = [
    await readFile(repositoryPath, 'utf8'),
    await readFile(modelPath, 'utf8'),
  ].join('\n')

  for (const outcome of ['created', 'linked', 'replayed', 'needs_confirmation']) {
    assert.ok(source.includes(outcome), `missing canonical outcome: ${outcome}`)
  }
  assert.ok(/review_required/u.test(source), 'missing review_required mapping')
  assert.ok(/balance_changed/u.test(source), 'missing balance_changed mapping')
})

test('A4-IOS-005/006 repository exposes invalid response and stable wallet errors', async () => {
  const source = [
    await readFile(repositoryPath, 'utf8'),
    await readFile(modelPath, 'utf8'),
  ].join('\n')

  assert.ok(/invalid_response/u.test(source), 'missing invalid_response mapping')
  for (const reason of [
    'wallet_snapshot_not_found',
    'account_kind_mismatch',
    'snapshot_link_conflict',
    'repayment_evidence_conflict',
  ]) {
    assert.ok(new RegExp(reason, 'u').test(source), `missing stable error mapping: ${reason}`)
  }
})
