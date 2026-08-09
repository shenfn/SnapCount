import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const root = path.resolve(here, '../../../..')

async function source(relativePath) {
  return readFile(path.join(root, relativePath), 'utf8')
}

test('EXP-006 iOS keeps Voice and Planner feedback in separate slots across both detail surfaces', async () => {
  const [service, appState, records, inbox] = await Promise.all([
    source('ios/SnapCount/Services/NativeDataService.swift'),
    source('ios/SnapCount/App/AppState.swift'),
    source('ios/SnapCount/Features/Records/RecordsView.swift'),
    source('ios/SnapCount/Features/Inbox/InboxView.swift'),
  ])

  assert.match(service, /var legacyAiFeedback: NativeAIFeedback\?/)
  assert.match(service, /var plannerAiFeedback: NativeAIFeedback\?/)
  assert.match(appState, /synchronizeAIFeedbackSlots/)
  assert.match(appState, /plannerAiFeedback = preview\.feedback/)
  assert.match(records, /supportingFeedback:/)
  assert.match(records, /interactionFeedback:/)
  assert.match(inbox, /supportingFeedback:/)
  assert.match(inbox, /interactionFeedback:/)
})
