import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..')
const inbox = await readFile(path.join(root, 'ios/SnapCount/Features/Inbox/InboxView.swift'), 'utf8')
const appState = await readFile(path.join(root, 'ios/SnapCount/App/AppState.swift'), 'utf8')

test('REC-016 pending bills use the inbox inline editor instead of a record navigation destination', () => {
  assert.match(inbox, /InboxPendingExpenseEditor/)
  assert.doesNotMatch(inbox, /if let pending = item\.pendingExpense \{\s*NavigationLink\(value: NativeInboxRoute\.record/)
  assert.match(appState, /func openPendingExpense[\s\S]{0,300}NativeInboxRoute\.category\(filter: \.pendingExpense\)/)
  assert.doesNotMatch(appState, /func openPendingExpense[\s\S]{0,300}NativeInboxRoute\.record\(/)
})
