import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

test('IOS-V2-SHELL-003A zero or failed candidate count must not block Inbox recovery', async () => {
  const source = await readFile('ios/SnapCount/Features/Root/MainShellView.swift', 'utf8')
  const start = source.indexOf('private var shellBottomBar: some View')
  const end = source.indexOf('Spacer()', start)
  assert.ok(start >= 0 && end > start, 'Inbox entry boundary must exist')
  const entry = source.slice(start, end)
  assert.match(entry, /presentedOverlay\s*=\s*\.inbox/u, 'Inbox must remain reachable from the shell')
  assert.doesNotMatch(entry, /\.disabled\(/u, 'Zero count also occurs after a read failure; Inbox must stay available for retry')
  assert.match(entry, /if appState\.dashboard\.pendingCount > 0/u, 'Only the badge should be hidden for zero candidates')
})
