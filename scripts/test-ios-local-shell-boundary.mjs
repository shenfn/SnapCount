import test from 'node:test'
import assert from 'node:assert/strict'
import { access, readFile } from 'node:fs/promises'

const rootPath = 'ios/SnapCount/Features/Root/RootView.swift'
const recordsPath = 'ios/SnapCount/Features/Records/RecordsView.swift'
const localSettingsPath = 'ios/SnapCount/Features/Settings/LocalSettingsView.swift'

test('LOCAL-002UIA1-2 signed-out root uses a two-tab local shell', async () => {
  await access(localSettingsPath)
  const source = await readFile(rootPath, 'utf8')

  assert.match(source, /else if appState\.isSignedIn\s*\{\s*cloudTabRoot\s*\}\s*else\s*\{\s*localTabRoot\s*\}/u)
  assert.doesNotMatch(source, /else\s*\{\s*LoginView\(\)\s*\}/u)

  const localStart = source.indexOf('private var localTabRoot')
  const cloudStart = source.indexOf('private var cloudTabRoot')
  assert.ok(localStart >= 0 && cloudStart > localStart, 'local and cloud tab roots must be explicit')
  const localRoot = source.slice(localStart, cloudStart)
  assert.match(localRoot, /RecordsView\(\)/u)
  assert.match(localRoot, /LocalSettingsView\(\)/u)
  assert.doesNotMatch(localRoot, /TodayView|InboxView|InsightsView|\bSettingsView\(/u)
})

test('LOCAL-002UIA4 local records do not navigate to or prefetch remote details', async () => {
  const source = await readFile(recordsPath, 'utf8')
  assert.match(source, /if appState\.isSignedIn\s*\{[\s\S]*NavigationLink/u)
  assert.match(source, /guard appState\.isSignedIn else \{ return \}[\s\S]*prefetchRecordDetails/u)
})

test('LOCAL-002UIA7 local settings has no remote settings load', async () => {
  const source = await readFile(localSettingsPath, 'utf8')
  assert.match(source, /仅保存在此 iPhone/u)
  assert.match(source, /云同步尚未开启/u)
  assert.doesNotMatch(source, /loadUserSettings|signIn\(|LoginView/u)
})

test('LOCAL-002 UIA keeps local record creation hidden until UIB', async () => {
  const source = await readFile(recordsPath, 'utf8')
  const toolbarStart = source.indexOf('.toolbar {')
  const destinationStart = source.indexOf('.navigationDestination', toolbarStart)
  assert.ok(toolbarStart >= 0 && destinationStart > toolbarStart, 'records toolbar boundary missing')
  const toolbar = source.slice(toolbarStart, destinationStart)
  assert.match(toolbar, /if appState\.isSignedIn/u)
  assert.match(toolbar, /showManualRecordSheet = true/u)
})

console.log('iOS LOCAL-002-UIA local shell boundary checks passed')
